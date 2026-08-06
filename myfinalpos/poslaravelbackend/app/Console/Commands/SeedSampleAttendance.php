<?php

namespace App\Console\Commands;

use Database\Seeders\StaffAttendanceSeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class SeedSampleAttendance extends Command
{
    protected $signature = 'attendance:sample {--clear : Remove sample attendance rows only}';

    protected $description = 'Load demo attendance for the past 7 days so you can review the Staff board and Payroll report without live clock-ins';

    public function handle(): int
    {
        if (! Schema::hasTable('staff_attendance')) {
            $this->error('staff_attendance table missing. Run: php artisan migrate');

            return self::FAILURE;
        }

        if ($this->option('clear')) {
            $deleted = DB::table('staff_attendance')
                ->where('notes', '[Sample]')
                ->delete();
            $this->info("Removed {$deleted} sample attendance row(s).");

            return self::SUCCESS;
        }

        $this->call('db:seed', [
            '--class' => StaffAttendanceSeeder::class,
            '--force' => true,
        ]);

        return self::SUCCESS;
    }
}
