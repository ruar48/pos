<?php

namespace Database\Seeders;

use Carbon\Carbon;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class StaffAttendanceSeeder extends Seeder
{
    private const TZ = 'Asia/Manila';

    private const SAMPLE_TAG = '[Sample]';

    public function run(): void
    {
        if (! Schema::hasTable('staff_attendance')) {
            $this->command?->warn('Run migrations first.');

            return;
        }

        $this->ensureDemoStaff();

        DB::table('staff_attendance')
            ->where('notes', self::SAMPLE_TAG)
            ->delete();

        $branch = DB::table('branches')->where('id', 1)->first();
        $lat = (float) ($branch->latitude ?? 15.0319);
        $lng = (float) ($branch->longitude ?? 120.6895);

        $users = $this->resolveUsers();
        if ($users === []) {
            $this->command?->warn('No staff users found. Run php artisan db:seed --class=PosDatabaseSeeder first.');

            return;
        }

        $today = Carbon::today(self::TZ);

        // Scenario 3 — Present: morning + afternoon (Ricardo)
        if (isset($users['ricardo'])) {
            $this->seedDay($users['ricardo'], $lat, $lng, $today, [
                ['clock_in', 8, 5],
                ['clock_out', 11, 45],
                ['clock_in', 13, 5],
                ['clock_out', 16, 35],
            ], 'Full day — daily Present');
        }

        // Scenario 2 — Half-day: morning Present, afternoon Absent (Ana)
        if (isset($users['ana'])) {
            $this->seedDay($users['ana'], $lat, $lng, $today, [
                ['clock_in', 8, 10],
                ['clock_out', 11, 50],
            ], 'Morning only — daily Half-day (PM absent after cutoff)');
        }

        // Scenario 1 — Half-day: morning Absent, afternoon Present (Pedro)
        if (isset($users['pedro'])) {
            $this->seedDay($users['pedro'], $lat, $lng, $today, [
                ['clock_in', 13, 10],
                ['clock_out', 16, 40],
            ], 'Afternoon only — daily Half-day (AM absent)');
        }

        // Scenario 4 — Absent: no punches today (Maria)
        // (intentionally empty)

        $this->command?->newLine();
        $this->command?->info('Sample attendance loaded for TODAY ('.$today->format('Y-m-d').').');
        $this->command?->table(
            ['Staff', 'Expected today'],
            [
                ['Ricardo Santos', 'AM Present · PM Present · Daily Present'],
                ['Ana Reyes', 'AM Present · PM Absent · Daily Half-day'],
                ['Pedro Santos', 'AM Absent · PM Present · Daily Half-day'],
                ['Maria Cruz', 'AM Absent · PM Absent · Daily Absent'],
            ],
        );
        $this->command?->line('Open POS → Staff → Attendance → Daily board (today’s date).');
        $this->command?->line('Re-run: php artisan attendance:sample');
        $this->command?->line('Clear samples: php artisan attendance:sample --clear');
    }

    private function ensureDemoStaff(): void
    {
        DB::table('branches')->updateOrInsert(
            ['id' => 1],
            [
                'name' => 'Green Farm Mart — San Fernando',
                'latitude' => 15.0319000,
                'longitude' => 120.6895000,
            ],
        );

        $passwordHash = password_hash('password', PASSWORD_BCRYPT);

        DB::table('users')->updateOrInsert(
            ['email' => 'demo+absent@no-login.local'],
            [
                'full_name' => 'Maria Cruz',
                'username' => 'maria_cruz',
                'password_hash' => $passwordHash,
                'role' => 'labor',
                'status' => 1,
                'branch_id' => 1,
                'email_verified_at' => now(),
                'created_at' => now(),
            ],
        );
    }

    /**
     * @return array<string, int>
     */
    private function resolveUsers(): array
    {
        $map = [];
        $rows = DB::table('users')
            ->whereIn('email', [
                'admin@agriculture.local',
                'cashier@agriculture.local',
                'labor+pedro@no-login.local',
                'demo+absent@no-login.local',
            ])
            ->get(['id', 'email']);

        foreach ($rows as $row) {
            $key = match ((string) $row->email) {
                'admin@agriculture.local' => 'ricardo',
                'cashier@agriculture.local' => 'ana',
                'labor+pedro@no-login.local' => 'pedro',
                'demo+absent@no-login.local' => 'maria',
                default => null,
            };
            if ($key !== null) {
                $map[$key] = (int) $row->id;
            }
        }

        return $map;
    }

    /**
     * @param  list<array{0: string, 1: int, 2: int}>  $punches
     */
    private function seedDay(
        int $userId,
        float $lat,
        float $lng,
        Carbon $day,
        array $punches,
        string $scenarioNote,
    ): void {
        foreach ($punches as [$type, $hour, $minute]) {
            $local = $day->copy()->setTime($hour, $minute, 0);

            DB::table('staff_attendance')->insert([
                'user_id' => $userId,
                'branch_id' => 1,
                'event_type' => $type,
                'latitude' => $lat,
                'longitude' => $lng,
                'accuracy_meters' => 10,
                'distance_from_branch_km' => 0.05,
                'within_geofence' => 1,
                'face_verified' => null,
                'device_info' => 'Sample data — '.$scenarioNote,
                'notes' => self::SAMPLE_TAG,
                'created_at' => $local->copy()->timezone('UTC'),
            ]);
        }
    }
}
