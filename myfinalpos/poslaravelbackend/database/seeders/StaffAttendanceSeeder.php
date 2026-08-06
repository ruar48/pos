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

        // A full week (today + the 6 days before it) so the Payroll report
        // has enough spread to sanity-check date-range filtering, break-time
        // deduction, and the missing-time-out handling all at once.

        // Day -6: everyone present, ordinary full/half days.
        $this->seedWeekday($users, $lat, $lng, $today->copy()->subDays(6), [
            'ricardo' => [['clock_in', 8, 2], ['clock_out', 11, 58], ['clock_in', 13, 1], ['clock_out', 17, 4]],
            'ana' => [['clock_in', 8, 12], ['clock_out', 12, 3], ['clock_in', 13, 9], ['clock_out', 16, 47]],
            'pedro' => [['clock_in', 13, 20], ['clock_out', 16, 55]],
            // Maria absent — intentionally no punches.
        ]);

        // Day -5: Ricardo takes a proper lunch break (tests break-minute
        // deduction from worked hours); Maria present for once.
        $this->seedWeekday($users, $lat, $lng, $today->copy()->subDays(5), [
            'ricardo' => [['clock_in', 8, 0], ['break_in', 12, 0], ['break_out', 12, 30], ['clock_out', 17, 0]],
            'ana' => [['clock_in', 8, 5], ['clock_out', 11, 50], ['clock_in', 12, 55], ['clock_out', 16, 40]],
            'maria' => [['clock_in', 8, 15], ['clock_out', 12, 0], ['clock_in', 13, 0], ['clock_out', 16, 30]],
            // Pedro absent.
        ]);

        // Day -4: everyone present, straightforward full days.
        $this->seedWeekday($users, $lat, $lng, $today->copy()->subDays(4), [
            'ricardo' => [['clock_in', 7, 58], ['clock_out', 12, 2], ['clock_in', 13, 0], ['clock_out', 17, 1]],
            'ana' => [['clock_in', 8, 0], ['clock_out', 11, 55], ['clock_in', 12, 58], ['clock_out', 16, 50]],
            'pedro' => [['clock_in', 8, 20], ['clock_out', 12, 10], ['clock_in', 13, 15], ['clock_out', 17, 5]],
            'maria' => [['clock_in', 8, 30], ['clock_out', 12, 0], ['clock_in', 13, 5], ['clock_out', 16, 20]],
        ]);

        // Day -3: Ricardo forgot to time out (real-world "emergency, walang
        // time out" scenario) — clock_in with no matching clock_out.
        // Exercises the fix that caps a past day's hours at end-of-day
        // instead of extrapolating to "now" and flags missing_time_out.
        $this->seedWeekday($users, $lat, $lng, $today->copy()->subDays(3), [
            'ricardo' => [['clock_in', 8, 4]],
            'ana' => [['clock_in', 8, 8], ['clock_out', 11, 52], ['clock_in', 13, 0], ['clock_out', 16, 45]],
            'pedro' => [['clock_in', 13, 25], ['clock_out', 17, 0]],
            // Maria absent.
        ]);

        // Day -2: everyone present again, mixed timings.
        $this->seedWeekday($users, $lat, $lng, $today->copy()->subDays(2), [
            'ricardo' => [['clock_in', 8, 1], ['clock_out', 12, 0], ['clock_in', 13, 3], ['clock_out', 17, 10]],
            'ana' => [['clock_in', 8, 15], ['clock_out', 12, 5], ['clock_in', 13, 1], ['clock_out', 16, 55]],
            'pedro' => [['clock_in', 8, 25], ['clock_out', 11, 50]],
            'maria' => [['clock_in', 13, 10], ['clock_out', 16, 35]],
        ]);

        // Day -1 (yesterday): Ricardo with a break again, others half-days.
        $this->seedWeekday($users, $lat, $lng, $today->copy()->subDays(1), [
            'ricardo' => [['clock_in', 7, 55], ['break_in', 12, 0], ['break_out', 12, 45], ['clock_out', 17, 2]],
            'ana' => [['clock_in', 8, 3], ['clock_out', 11, 58]],
            'pedro' => [['clock_in', 13, 12], ['clock_out', 16, 48]],
            // Maria absent.
        ]);

        // Day 0 — today: original 4-scenario demo, unchanged so the Daily
        // board keeps matching the existing walkthrough note below.
        $this->seedWeekday($users, $lat, $lng, $today, [
            'ricardo' => [['clock_in', 8, 5], ['clock_out', 11, 45], ['clock_in', 13, 5], ['clock_out', 16, 35]],
            'ana' => [['clock_in', 8, 10], ['clock_out', 11, 50]],
            'pedro' => [['clock_in', 13, 10], ['clock_out', 16, 40]],
            // Maria absent.
        ]);

        $this->command?->newLine();
        $this->command?->info(
            'Sample attendance loaded for the past 7 days ('
            .$today->copy()->subDays(6)->format('Y-m-d').' to '.$today->format('Y-m-d').').',
        );
        $this->command?->table(
            ['Staff', 'Notes'],
            [
                ['Ricardo Santos', 'Present most days · lunch break on 2 days · forgot to time out 3 days ago'],
                ['Ana Reyes', 'Present most days · a couple of half-days'],
                ['Pedro Santos', 'Present about half the week, various AM/PM patterns'],
                ['Maria Cruz', 'Present on 2 of the 7 days, absent the rest'],
            ],
        );
        $this->command?->line('Open POS admin → Staff → Payroll, set Start to '.$today->copy()->subDays(6)->format('m/d/Y').' and End to '.$today->format('m/d/Y').'.');
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
     * @param  array<string, int>  $users
     * @param  array<string, list<array{0: string, 1: int, 2: int}>>  $punchesByStaffKey
     */
    private function seedWeekday(
        array $users,
        float $lat,
        float $lng,
        Carbon $day,
        array $punchesByStaffKey,
    ): void {
        foreach ($punchesByStaffKey as $staffKey => $punches) {
            if (! isset($users[$staffKey]) || $punches === []) {
                continue;
            }

            $this->seedDay($users[$staffKey], $lat, $lng, $day, $punches);
        }
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
                'device_info' => 'Sample data — '.$day->format('Y-m-d'),
                'notes' => self::SAMPLE_TAG,
                'created_at' => $local->copy()->timezone('UTC'),
            ]);
        }
    }
}
