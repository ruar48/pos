<?php

namespace App\Services\Pos;

use Carbon\CarbonImmutable;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Worksheet\Worksheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use Symfony\Component\HttpFoundation\StreamedResponse;

class AttendanceExportService
{
    public function __construct(
        private readonly AttendanceService $attendance,
    ) {}

    public function downloadResponse(string $startDate, string $endDate, ?int $branchId = null): StreamedResponse
    {
        $schedule = $this->attendance->schedule();
        $summaryRows = $this->attendance->punctualityReport($startDate, $endDate, $branchId);
        $eventRows = $this->attendance->eventLog($startDate, $endDate, $branchId);

        $spreadsheet = new Spreadsheet;
        $summarySheet = $spreadsheet->getActiveSheet();
        $summarySheet->setTitle('Summary');

        $summarySheet->setCellValue('A1', 'Attendance report');
        $summarySheet->setCellValue('A2', "Period: {$startDate} to {$endDate}");
        $summarySheet->setCellValue(
            'A3',
            sprintf(
                'Schedule: start %s, grace %d min, late after %s',
                $schedule['start_time'],
                $schedule['grace_minutes'],
                $schedule['late_after_time'],
            ),
        );

        $this->writeTable(
            $summarySheet,
            5,
            [
                'Rank',
                'Staff',
                'Role',
                'Present',
                'Half Day',
                'Late',
                'Absent',
            ],
            array_map(static fn (array $row) => [
                $row['rank'] ?? '',
                $row['full_name'] ?? '',
                $row['role'] ?? '',
                $row['days_present'] ?? 0,
                $row['days_half_day'] ?? 0,
                $row['days_late'] ?? 0,
                $row['days_absent'] ?? 0,
            ], $summaryRows),
        );

        $logSheet = $spreadsheet->createSheet();
        $logSheet->setTitle('Clock Log');
        $logSheet->setCellValue('A1', 'Clock in / out log');
        $logSheet->setCellValue('A2', "Period: {$startDate} to {$endDate}");

        $this->writeTable(
            $logSheet,
            4,
            [
                'Date & Time',
                'Staff',
                'Role',
                'Branch',
                'Event',
                'Source',
                'Within Geofence',
                'Distance (km)',
            ],
            array_map(static fn (array $row) => [
                $row['recorded_at'] ?? '',
                $row['full_name'] ?? '',
                $row['role'] ?? '',
                $row['branch_name'] ?? '',
                str_replace('_', ' ', (string) ($row['event_type'] ?? '')),
                $row['device_info'] ?? '',
                $row['within_geofence'] === null
                    ? ''
                    : ($row['within_geofence'] ? 'Yes' : 'No'),
                $row['distance_km'] ?? '',
            ], $eventRows),
        );

        // Payroll sheet - the flat one-row-per-staff-per-day layout the
        // client's payroll is keyed off: dates and times in their own
        // columns, and each duration split into an hours cell and a minutes
        // cell so the payroll sheet can total them without parsing a
        // "9h 03m" style label. Staff with no punches that day still get a
        // row (name only), so the roster lines up with the payroll roster.
        $payrollSheet = $spreadsheet->createSheet();
        $payrollSheet->setTitle('Payroll');

        $payroll = $this->payrollRows($startDate, $endDate, $branchId);
        $payrollHeaderRow = 1;

        $this->writeTable(
            $payrollSheet,
            $payrollHeaderRow,
            [
                'Staff',
                'In Date',
                'In Time',
                'Out Date',
                'Out time',
                'Total Duration Hours',
                'Total Duration Mins',
                'Break In Date',
                'Break In Time',
                'Break Out Date',
                'Break Out Time',
                'Total Break Duration Hours',
                'Total Break Duration Mins',
            ],
            $payroll['rows'],
        );

        // Bold the header and each day's date row so the day blocks are
        // pickable out at a glance when scrolling a long range.
        $payrollSheet->getStyle("A{$payrollHeaderRow}:M{$payrollHeaderRow}")
            ->getFont()
            ->setBold(true);

        foreach ($payroll['date_row_indexes'] as $index) {
            $sheetRow = $payrollHeaderRow + 1 + $index;
            $payrollSheet->getStyle("A{$sheetRow}")->getFont()->setBold(true);
        }

        // Open the workbook on Payroll rather than Summary - it's the sheet
        // the payroll run is done from, and it was otherwise the third tab
        // along, easy to miss.
        $spreadsheet->setActiveSheetIndexByName('Payroll');

        $filename = "attendance_{$startDate}_to_{$endDate}.xlsx";

        return new StreamedResponse(function () use ($spreadsheet) {
            $writer = new Xlsx($spreadsheet);
            $writer->save('php://output');
        }, 200, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'Content-Disposition' => 'attachment; filename="'.$filename.'"',
            'Cache-Control' => 'max-age=0',
        ]);
    }

    /**
     * One row per staff per day for the Payroll sheet, each day's block
     * introduced by a date row in the Staff column so a multi-day range
     * reads as dated sections stacked one after another instead of an
     * undivided run of names.
     *
     * @return array{rows: list<list<mixed>>, date_row_indexes: list<int>}
     */
    private function payrollRows(string $startDate, string $endDate, ?int $branchId): array
    {
        $rows = [];
        $dateRowIndexes = [];

        foreach ($this->attendance->rangeBoard($startDate, $endDate, $branchId) as $date => $dayRows) {
            if ($rows !== []) {
                // Blank spacer between one day's block and the next.
                $rows[] = [''];
            }

            $dateRowIndexes[] = count($rows);
            $rows[] = [$this->dateCell($this->moment($date))];

            foreach ($dayRows as $row) {
                $clockIn = $this->moment($row['clock_in_at'] ?? null);
                $clockOut = $this->moment($row['clock_out_at'] ?? null);
                $breakIn = $this->moment($row['break_start_at'] ?? null);
                $breakOut = $this->moment($row['break_end_at'] ?? null);
                $breakMinutes = max(0, (int) ($row['total_break_minutes'] ?? 0));

                // Worked duration is the raw in-to-out span less the break
                // that was actually punched, rather than the row's
                // total_minutes - that figure deducts a flat hour for lunch
                // whether or not a break was punched, so it wouldn't
                // reconcile against the break columns printed beside it.
                // A staff member still clocked in has no out time, so the
                // duration cells stay blank rather than counting a
                // half-finished shift.
                $workedMinutes = $clockIn !== null && $clockOut !== null
                    ? max(0, (int) $clockIn->diffInMinutes($clockOut) - $breakMinutes)
                    : null;

                $rows[] = [
                    $row['full_name'] ?? '',
                    $this->dateCell($clockIn),
                    $this->timeCell($clockIn),
                    $this->dateCell($clockOut),
                    $this->timeCell($clockOut),
                    $workedMinutes === null ? '' : intdiv($workedMinutes, 60),
                    $workedMinutes === null ? '' : $workedMinutes % 60,
                    $this->dateCell($breakIn),
                    $this->timeCell($breakIn),
                    $this->dateCell($breakOut),
                    $this->timeCell($breakOut),
                    $breakMinutes > 0 ? intdiv($breakMinutes, 60) : '',
                    $breakMinutes > 0 ? $breakMinutes % 60 : '',
                ];
            }
        }

        return ['rows' => $rows, 'date_row_indexes' => $dateRowIndexes];
    }

    /**
     * [AttendanceService] hands back ISO-8601 strings already shifted to the
     * display timezone, so parsing keeps the offset they carry - no second
     * conversion here.
     */
    private function moment(mixed $value): ?CarbonImmutable
    {
        if (! is_string($value) || trim($value) === '') {
            return null;
        }

        try {
            return CarbonImmutable::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }

    private function dateCell(?CarbonImmutable $at): string
    {
        return $at?->format('d/m/Y') ?? '';
    }

    private function timeCell(?CarbonImmutable $at): string
    {
        return $at?->format('g:i a') ?? '';
    }

    /**
     * @param  list<string>  $headers
     * @param  list<list<mixed>>  $rows
     */
    private function writeTable(
        Worksheet $sheet,
        int $headerRow,
        array $headers,
        array $rows,
    ): void {
        foreach ($headers as $columnIndex => $header) {
            $sheet->setCellValue([$columnIndex + 1, $headerRow], $header);
        }

        $dataRow = $headerRow + 1;
        foreach ($rows as $row) {
            foreach ($row as $columnIndex => $value) {
                $sheet->setCellValue([$columnIndex + 1, $dataRow], $value);
            }
            $dataRow++;
        }

        foreach (range(1, count($headers)) as $columnIndex) {
            $sheet->getColumnDimensionByColumn($columnIndex)->setAutoSize(true);
        }
    }
}
