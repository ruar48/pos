<?php

namespace App\Services\Pos;

use PhpOffice\PhpSpreadsheet\Spreadsheet;
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

        $spreadsheet = new Spreadsheet();
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
     * @param  list<string>  $headers
     * @param  list<list<mixed>>  $rows
     */
    private function writeTable(
        \PhpOffice\PhpSpreadsheet\Worksheet\Worksheet $sheet,
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
