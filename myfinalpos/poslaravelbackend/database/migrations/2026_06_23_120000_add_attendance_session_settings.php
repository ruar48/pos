<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (! Schema::hasTable('app_settings')) {
            return;
        }

        Schema::table('app_settings', function (Blueprint $table) {
            $columns = [
                'attendance_morning_accept_start' => '06:30',
                'attendance_morning_official_start' => '08:00',
                'attendance_morning_grace_end' => '08:15',
                'attendance_morning_late_start' => '08:16',
                'attendance_morning_cutoff' => '09:00',
                'attendance_break_out_start' => '11:00',
                'attendance_break_out_end' => '12:00',
                'attendance_afternoon_accept_start' => '12:50',
                'attendance_afternoon_on_time_end' => '13:30',
                'attendance_afternoon_late_start' => '13:31',
                'attendance_afternoon_cutoff' => '14:00',
                'attendance_timeout_start' => '16:30',
            ];

            foreach ($columns as $name => $default) {
                if (! Schema::hasColumn('app_settings', $name)) {
                    $table->string($name, 5)->default($default);
                }
            }
        });

        if (! Schema::hasColumn('app_settings', 'attendance_morning_accept_start')) {
            return;
        }

        $row = DB::table('app_settings')->orderBy('id')->first();
        if ($row === null) {
            return;
        }

        $officialStart = $row->attendance_start_time ?? '08:00';
        $graceMinutes = (int) ($row->attendance_grace_minutes ?? 15);
        $graceEnd = \Illuminate\Support\Carbon::createFromFormat('H:i', $officialStart)
            ->addMinutes($graceMinutes)
            ->format('H:i');
        $lateStart = \Illuminate\Support\Carbon::createFromFormat('H:i', $graceEnd)
            ->addMinute()
            ->format('H:i');

        DB::table('app_settings')->where('id', $row->id)->update([
            'attendance_morning_official_start' => $officialStart,
            'attendance_morning_grace_end' => $graceEnd,
            'attendance_morning_late_start' => $lateStart,
            'attendance_morning_cutoff' => $row->attendance_morning_absent_after_time ?? '09:00',
            'attendance_break_out_end' => $row->attendance_lunch_out_time ?? '12:00',
            'attendance_afternoon_on_time_end' => $row->attendance_afternoon_in_time ?? '13:30',
            'attendance_timeout_start' => $row->attendance_day_end_time ?? '16:30',
        ]);
    }

    public function down(): void
    {
        if (! Schema::hasTable('app_settings')) {
            return;
        }

        Schema::table('app_settings', function (Blueprint $table) {
            foreach ([
                'attendance_morning_accept_start',
                'attendance_morning_official_start',
                'attendance_morning_grace_end',
                'attendance_morning_late_start',
                'attendance_morning_cutoff',
                'attendance_break_out_start',
                'attendance_break_out_end',
                'attendance_afternoon_accept_start',
                'attendance_afternoon_on_time_end',
                'attendance_afternoon_late_start',
                'attendance_afternoon_cutoff',
                'attendance_timeout_start',
            ] as $column) {
                if (Schema::hasColumn('app_settings', $column)) {
                    $table->dropColumn($column);
                }
            }
        });
    }
};
