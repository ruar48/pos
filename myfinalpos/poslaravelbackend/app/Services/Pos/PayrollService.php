<?php

namespace App\Services\Pos;

use App\Support\PosHelpers;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class PayrollService
{
    public function __construct(
        private readonly AttendanceService $attendance,
    ) {}

    /**
     * @return list<array<string, mixed>>
     */
    public function report(string $startDate, string $endDate, ?int $branchId = null): array
    {
        $start = Carbon::parse($startDate)->startOfDay();
        $end = Carbon::parse($endDate)->startOfDay();
        if ($end->lt($start)) {
            [$start, $end] = [$end, $start];
        }

        /** @var array<int, array<string, mixed>> $totals */
        $totals = [];

        for ($day = $start->copy(); $day->lte($end); $day->addDay()) {
            $date = $day->format('Y-m-d');

            foreach ($this->attendance->dailyBoard($date, $branchId) as $row) {
                $userId = (int) $row['user_id'];

                if (! isset($totals[$userId])) {
                    $totals[$userId] = [
                        'user_id' => $userId,
                        'full_name' => (string) $row['full_name'],
                        'role' => (string) $row['role'],
                        'branch_name' => (string) $row['branch_name'],
                        'total_minutes' => 0,
                        'break_minutes' => 0,
                        'has_missing_time_out' => false,
                        'missing_time_out_dates' => [],
                    ];
                }

                $totals[$userId]['total_minutes'] += (int) ($row['total_minutes'] ?? 0);
                $totals[$userId]['break_minutes'] += (int) ($row['total_break_minutes'] ?? 0);

                if (! empty($row['missing_time_out'])) {
                    $totals[$userId]['has_missing_time_out'] = true;
                    $totals[$userId]['missing_time_out_dates'][] = $date;
                }
            }
        }

        $rates = $this->hourlyRates(array_keys($totals));

        $rows = [];
        foreach ($totals as $userId => $totalRow) {
            $rate = $rates[$userId] ?? 0.0;
            $hours = $totalRow['total_minutes'] / 60;
            $totalPay = round($hours * $rate, 2);

            $rows[] = [
                'user_id' => $userId,
                'full_name' => $totalRow['full_name'],
                'role' => $totalRow['role'],
                'branch_name' => $totalRow['branch_name'],
                'break_minutes' => $totalRow['break_minutes'],
                'break_hours_label' => $this->formatDuration($totalRow['break_minutes']),
                'total_minutes' => $totalRow['total_minutes'],
                'total_hours_label' => $this->formatDuration($totalRow['total_minutes']),
                'hourly_rate' => $rate,
                'total_pay' => $totalPay,
                'has_missing_time_out' => $totalRow['has_missing_time_out'],
                'missing_time_out_dates' => $totalRow['missing_time_out_dates'],
            ];
        }

        usort($rows, static fn (array $a, array $b): int => strcmp((string) $a['full_name'], (string) $b['full_name']));

        return $rows;
    }

    public function updateHourlyRate(int $userId, float $rate, ?int $actorUserId): void
    {
        PosHelpers::requireManagementActor($actorUserId);

        if ($rate < 0) {
            throw new \RuntimeException('Hourly rate cannot be negative.');
        }

        $user = DB::selectOne('SELECT id FROM users WHERE id = ? LIMIT 1', [$userId]);
        if (! $user) {
            throw new \RuntimeException('Staff member not found');
        }

        DB::table('users')->where('id', $userId)->update(['hourly_rate' => $rate]);
    }

    /**
     * @param  list<int>  $userIds
     * @return array<int, float>
     */
    private function hourlyRates(array $userIds): array
    {
        if ($userIds === []) {
            return [];
        }

        $rows = DB::table('users')->whereIn('id', $userIds)->select('id', 'hourly_rate')->get();

        $result = [];
        foreach ($rows as $row) {
            $result[(int) $row->id] = (float) ($row->hourly_rate ?? 0);
        }

        return $result;
    }

    private function formatDuration(int $minutes): string
    {
        $safe = max(0, $minutes);
        $hours = intdiv($safe, 60);
        $mins = $safe % 60;

        if ($hours === 0 && $mins === 0) {
            return '0 hour';
        }

        if ($hours === 0) {
            return $mins === 1 ? '1 minute' : "{$mins} minutes";
        }

        if ($mins === 0) {
            return $hours === 1 ? '1 hour' : "{$hours} hours";
        }

        $hourLabel = $hours === 1 ? 'hour' : 'hours';
        $minLabel = $mins === 1 ? 'minute' : 'minutes';

        return "{$hours} {$hourLabel} {$mins} {$minLabel}";
    }
}
