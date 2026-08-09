<?php

namespace Tests\Unit;

use App\Services\Pos\AttendanceService;
use App\Services\Pos\PayrollService;
use Illuminate\Support\Facades\DB;
use Mockery;
use Tests\TestCase;

class PayrollServiceTest extends TestCase
{
    protected function tearDown(): void
    {
        Mockery::close();
        parent::tearDown();
    }

    public function test_open_clock_in_does_not_count_toward_hours_or_pay(): void
    {
        $date = now()->toDateString();

        $attendance = Mockery::mock(AttendanceService::class);
        $attendance->shouldReceive('dailyBoard')
            ->once()
            ->with($date, null)
            ->andReturn([
                [
                    'user_id' => 42,
                    'full_name' => 'Ana Reyes',
                    'role' => 'cashier',
                    'branch_name' => 'Main',
                    // Live duty span after just timing in — must not become payroll.
                    'total_minutes' => 125,
                    'total_break_minutes' => 0,
                    'is_clocked_in' => true,
                    'missing_time_out' => false,
                ],
            ]);

        $this->mockHourlyRates([42 => 80.0]);

        $service = new PayrollService($attendance);
        $rows = $service->report($date, $date);

        $this->assertCount(1, $rows);
        $this->assertSame(0, $rows[0]['total_minutes']);
        $this->assertSame('0 hour', $rows[0]['total_hours_label']);
        $this->assertSame(0.0, $rows[0]['total_pay']);
        $this->assertTrue($rows[0]['has_missing_time_out']);
        $this->assertSame([$date], $rows[0]['missing_time_out_dates']);
    }

    public function test_completed_shift_counts_toward_hours_and_pay(): void
    {
        $date = now()->toDateString();

        $attendance = Mockery::mock(AttendanceService::class);
        $attendance->shouldReceive('dailyBoard')
            ->once()
            ->with($date, null)
            ->andReturn([
                [
                    'user_id' => 7,
                    'full_name' => 'Ricardo Santos',
                    'role' => 'labor',
                    'branch_name' => 'Main',
                    'total_minutes' => 420,
                    'total_break_minutes' => 60,
                    'is_clocked_in' => false,
                    'missing_time_out' => false,
                ],
            ]);

        $this->mockHourlyRates([7 => 100.0]);

        $service = new PayrollService($attendance);
        $rows = $service->report($date, $date);

        $this->assertCount(1, $rows);
        $this->assertSame(420, $rows[0]['total_minutes']);
        $this->assertSame(700.0, $rows[0]['total_pay']);
        $this->assertFalse($rows[0]['has_missing_time_out']);
    }

    /**
     * @param  array<int, float>  $rates
     */
    private function mockHourlyRates(array $rates): void
    {
        $rows = [];
        foreach ($rates as $userId => $rate) {
            $rows[] = (object) [
                'id' => $userId,
                'hourly_rate' => $rate,
            ];
        }

        DB::shouldReceive('table')
            ->once()
            ->with('users')
            ->andReturnSelf();
        DB::shouldReceive('whereIn')
            ->once()
            ->with('id', Mockery::type('array'))
            ->andReturnSelf();
        DB::shouldReceive('select')
            ->once()
            ->with('id', 'hourly_rate')
            ->andReturnSelf();
        DB::shouldReceive('get')
            ->once()
            ->andReturn(collect($rows));
    }
}
