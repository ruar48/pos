<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call([
            PosDatabaseSeeder::class,
            PosDemoDataSeeder::class,
            ReportAccuracySeeder::class,
            StaffAttendanceSeeder::class,
        ]);
    }
}
