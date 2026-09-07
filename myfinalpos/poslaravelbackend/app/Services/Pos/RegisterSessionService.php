<?php

namespace App\Services\Pos;

use App\Support\BusinessDay;
use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Register shifts: one open session per terminal at a time.
 *
 * A session is what an X or Z reading covers. Orders are stamped with the open
 * session's id at checkout, which is how a reading knows which sales belong to
 * it — before this, orders carried no terminal at all.
 */
class RegisterSessionService
{
    /**
     * The open session for a terminal, or null when the shift is closed.
     *
     * Pass lock: true inside a transaction when the caller is about to close
     * the session, so two Z readings cannot race.
     */
    public function openSessionFor(string $terminalId, bool $lock = false): ?object
    {
        $query = DB::table('pos_register_sessions')
            ->where('terminal_id', $terminalId)
            ->where('status', 'open')
            ->orderByDesc('id');

        if ($lock) {
            $query->lockForUpdate();
        }

        return $query->first();
    }

    /**
     * Opens a shift. Refuses when one is already open — closing it is a Z
     * reading, which is deliberate and irreversible, so it never happens as a
     * side effect of opening.
     */
    public function open(
        string $terminalId,
        ?int $cashierUserId,
        float $openingCash = 0,
        ?int $branchId = null,
    ): object {
        return DB::transaction(function () use (
            $terminalId,
            $cashierUserId,
            $openingCash,
            $branchId,
        ) {
            $existing = $this->openSessionFor($terminalId, lock: true);
            if ($existing !== null) {
                throw new RuntimeException(
                    'This terminal already has an open shift. Take a Z reading to close it first.',
                );
            }

            $this->countersFor($terminalId);

            $id = DB::table('pos_register_sessions')->insertGetId([
                'terminal_id' => $terminalId,
                'branch_id' => $branchId,
                'cashier_user_id' => $cashierUserId,
                'business_date' => BusinessDay::currentDate(),
                'opening_cash' => $openingCash,
                'opened_at' => now(),
                'status' => 'open',
                'created_at' => now(),
                'updated_at' => now(),
            ]);

            return DB::table('pos_register_sessions')->find($id);
        });
    }

    /**
     * The counter row for a terminal, created on first use.
     *
     * These are the figures BIR requires to be monotonic, so the row is only
     * ever updated by a Z reading.
     */
    public function countersFor(string $terminalId, bool $lock = false): object
    {
        $fetch = function () use ($terminalId, $lock) {
            $query = DB::table('pos_terminal_counters')
                ->where('terminal_id', $terminalId);

            if ($lock) {
                $query->lockForUpdate();
            }

            return $query->first();
        };

        $row = $fetch();
        if ($row !== null) {
            return $row;
        }

        DB::table('pos_terminal_counters')->insertOrIgnore([
            'terminal_id' => $terminalId,
            'grand_total_accumulated' => 0,
            'z_counter' => 0,
            'reset_counter' => 0,
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $row = $fetch();
        if ($row === null) {
            throw new RuntimeException(
                'Could not initialise counters for terminal ' . $terminalId,
            );
        }

        return $row;
    }

    /**
     * Session id to stamp on a new order, or null when no shift is open.
     *
     * Checkout stays possible with no open shift — refusing sales because a
     * cashier forgot to open one would be worse than a sale that lands outside
     * a reading — but such a sale will not appear on any X or Z.
     */
    public function currentSessionId(string $terminalId): ?int
    {
        $session = $this->openSessionFor($terminalId);

        return $session === null ? null : (int) $session->id;
    }
}
