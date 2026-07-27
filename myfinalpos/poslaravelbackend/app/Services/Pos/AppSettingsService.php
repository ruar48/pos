<?php

namespace App\Services\Pos;

use App\Support\AppSettingsRevision;
use App\Support\PosHelpers;
use Illuminate\Support\Facades\DB;

class AppSettingsService
{
    /**
     * @return array<string, mixed>
     */
    public function defaultReceiptStore(): array
    {
        return [
            'logo_text' => '[ Farm & Tractor ]',
            'logo_image_url' => null,
            'logo_image_base64' => null,
            'store_name' => 'GREEN FARM MART',
            'store_subtitle' => 'AGRICULTURE RETAIL STORE',
            'address_line1' => 'Purok 3, Brgy. Sto. Rosario,',
            'address_line2' => 'Angeles City, Pampanga 2009',
            'tin' => '123-456-789-000',
            'tax_status' => 'NON-VAT REGISTERED',
            'pos_terminal_id' => 'POS-01',
            'ptu_no' => 'PTU-123456789',
            'atp_no' => 'ATP-987654321',
            'atp_date_issued' => '01/15/2026',
            'series_range' => '0000001 - 9999999',
        ];
    }

    /**
     * @param  array<string, mixed>|null  $input
     * @return array<string, mixed>
     */
    public function normalizeReceiptStore(?array $input): array
    {
        $defaults = $this->defaultReceiptStore();
        $data = is_array($input) ? $input : [];

        $logoBase64 = trim((string) ($data['logo_image_base64'] ?? ''));
        if ($logoBase64 !== '' && strlen($logoBase64) > 700_000) {
            $logoBase64 = '';
        }

        $logoUrl = trim((string) ($data['logo_image_url'] ?? ''));

        return [
            'logo_text' => trim((string) ($data['logo_text'] ?? $defaults['logo_text'])) ?: $defaults['logo_text'],
            'logo_image_url' => $logoUrl !== '' ? $logoUrl : null,
            'logo_image_base64' => $logoBase64 !== '' ? $logoBase64 : null,
            'store_name' => trim((string) ($data['store_name'] ?? $defaults['store_name'])) ?: $defaults['store_name'],
            'store_subtitle' => trim((string) ($data['store_subtitle'] ?? $defaults['store_subtitle'])) ?: $defaults['store_subtitle'],
            'address_line1' => trim((string) ($data['address_line1'] ?? $defaults['address_line1'])) ?: $defaults['address_line1'],
            'address_line2' => trim((string) ($data['address_line2'] ?? $defaults['address_line2'])) ?: $defaults['address_line2'],
            'tin' => trim((string) ($data['tin'] ?? $defaults['tin'])) ?: $defaults['tin'],
            'tax_status' => trim((string) ($data['tax_status'] ?? $defaults['tax_status'])) ?: $defaults['tax_status'],
            'pos_terminal_id' => trim((string) ($data['pos_terminal_id'] ?? $defaults['pos_terminal_id'])) ?: $defaults['pos_terminal_id'],
            'ptu_no' => trim((string) ($data['ptu_no'] ?? $defaults['ptu_no'])) ?: $defaults['ptu_no'],
            'atp_no' => trim((string) ($data['atp_no'] ?? $defaults['atp_no'])) ?: $defaults['atp_no'],
            'atp_date_issued' => trim((string) ($data['atp_date_issued'] ?? $defaults['atp_date_issued'])) ?: $defaults['atp_date_issued'],
            'series_range' => trim((string) ($data['series_range'] ?? $defaults['series_range'])) ?: $defaults['series_range'],
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function read(): array
    {
        if (! PosHelpers::tableExists('app_settings')) {
            return $this->defaults();
        }

        $columns = [
            'tax_rate',
            'auto_print_receipt',
            'allow_negative_stock',
            'loyalty_enabled',
            'currency_symbol',
        ];

        if (PosHelpers::columnExists('app_settings', 'double_print_receipt')) {
            $columns[] = 'double_print_receipt';
        }

        if (PosHelpers::columnExists('app_settings', 'printer_host')) {
            $columns[] = 'printer_host';
        }
        if (PosHelpers::columnExists('app_settings', 'printer_type')) {
            $columns[] = 'printer_type';
        }
        if (PosHelpers::columnExists('app_settings', 'printer_device')) {
            $columns[] = 'printer_device';
        }
        if (PosHelpers::columnExists('app_settings', 'printer_port')) {
            $columns[] = 'printer_port';
        }
        if (PosHelpers::columnExists('app_settings', 'loyalty_points_per_unit')) {
            $columns[] = 'loyalty_points_per_unit';
        }
        if (PosHelpers::columnExists('app_settings', 'loyalty_spend_unit')) {
            $columns[] = 'loyalty_spend_unit';
        }
        if (PosHelpers::columnExists('app_settings', 'loyalty_redeem_points_per_peso')) {
            $columns[] = 'loyalty_redeem_points_per_peso';
        }
        if (PosHelpers::columnExists('app_settings', 'receipt_store_json')) {
            $columns[] = 'receipt_store_json';
        }
        if (PosHelpers::columnExists('app_settings', 'default_branch_id')) {
            $columns[] = 'default_branch_id';
        }
        if (PosHelpers::columnExists('app_settings', 'attendance_start_time')) {
            $columns[] = 'attendance_start_time';
        }
        if (PosHelpers::columnExists('app_settings', 'attendance_grace_minutes')) {
            $columns[] = 'attendance_grace_minutes';
        }
        if (PosHelpers::columnExists('app_settings', 'attendance_lunch_out_time')) {
            $columns[] = 'attendance_lunch_out_time';
        }
        if (PosHelpers::columnExists('app_settings', 'attendance_afternoon_in_time')) {
            $columns[] = 'attendance_afternoon_in_time';
        }
        if (PosHelpers::columnExists('app_settings', 'attendance_day_end_time')) {
            $columns[] = 'attendance_day_end_time';
        }
        if (PosHelpers::columnExists('app_settings', 'attendance_morning_absent_after_time')) {
            $columns[] = 'attendance_morning_absent_after_time';
        }
        foreach ($this->attendanceSessionColumns() as $column) {
            if (PosHelpers::columnExists('app_settings', $column)) {
                $columns[] = $column;
            }
        }
        if (PosHelpers::columnExists('app_settings', 'low_stock_email_enabled')) {
            $columns[] = 'low_stock_email_enabled';
        }
        if (PosHelpers::columnExists('app_settings', 'low_stock_email_recipients')) {
            $columns[] = 'low_stock_email_recipients';
        }
        if (PosHelpers::columnExists('app_settings', 'refund_pin_hash')) {
            $columns[] = 'refund_pin_hash';
        }

        $row = DB::selectOne(
            'SELECT '.implode(', ', $columns).' FROM app_settings ORDER BY id ASC LIMIT 1',
        );

        return $this->fromRow($row);
    }

    /**
     * @return array<string, mixed>
     */
    public function sync(?string $clientRevision = null): array
    {
        $revision = AppSettingsRevision::current();

        if (
            $clientRevision !== null
            && $clientRevision !== ''
            && hash_equals($revision, $clientRevision)
        ) {
            return [
                'revision' => $revision,
                'unchanged' => true,
            ];
        }

        return [
            'revision' => $revision,
            'unchanged' => false,
            'settings' => $this->read(),
        ];
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    public function save(array $input, int $actorUserId): array
    {
        if (! PosHelpers::tableExists('app_settings')) {
            throw new \RuntimeException('POS settings are not ready.');
        }

        $payload = [
            'tax_rate' => max(0.0, min(1.0, round((float) ($input['tax_rate'] ?? 0), 4))),
            'auto_print_receipt' => ! empty($input['auto_print_receipt']),
            'double_print_receipt' => ! empty($input['double_print_receipt']),
            'printer_host' => trim((string) ($input['printer_host'] ?? '')),
            'printer_type' => $this->normalizePrinterType($input['printer_type'] ?? 'network'),
            'printer_device' => trim((string) ($input['printer_device'] ?? '')),
            'printer_port' => max(1, min(65535, (int) ($input['printer_port'] ?? 9100))),
            'allow_negative_stock' => ! empty($input['allow_negative_stock']),
            'loyalty_enabled' => ! empty($input['loyalty_enabled']),
            'loyalty_points_per_unit' => max(0, (int) ($input['loyalty_points_per_unit'] ?? 50)),
            'loyalty_spend_unit' => max(0.01, round((float) ($input['loyalty_spend_unit'] ?? 1000), 2)),
            'loyalty_redeem_points_per_peso' => max(1, (int) ($input['loyalty_redeem_points_per_peso'] ?? 10)),
            'currency_symbol' => trim((string) ($input['currency_symbol'] ?? 'PHP')) ?: 'PHP',
        ];

        $hasLoyaltyColumns = PosHelpers::columnExists('app_settings', 'loyalty_points_per_unit')
            && PosHelpers::columnExists('app_settings', 'loyalty_spend_unit')
            && PosHelpers::columnExists('app_settings', 'loyalty_redeem_points_per_peso');

        if ($hasLoyaltyColumns) {
            DB::statement(
                'INSERT INTO app_settings
                    (id, tax_rate, auto_print_receipt, allow_negative_stock, loyalty_enabled, loyalty_points_per_unit, loyalty_spend_unit, loyalty_redeem_points_per_peso, currency_symbol, updated_by)
                 VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE
                    tax_rate = VALUES(tax_rate),
                    auto_print_receipt = VALUES(auto_print_receipt),
                    allow_negative_stock = VALUES(allow_negative_stock),
                    loyalty_enabled = VALUES(loyalty_enabled),
                    loyalty_points_per_unit = VALUES(loyalty_points_per_unit),
                    loyalty_spend_unit = VALUES(loyalty_spend_unit),
                    loyalty_redeem_points_per_peso = VALUES(loyalty_redeem_points_per_peso),
                    currency_symbol = VALUES(currency_symbol),
                    updated_by = VALUES(updated_by)',
                [
                    $payload['tax_rate'],
                    PosHelpers::boolToInt($payload['auto_print_receipt']),
                    PosHelpers::boolToInt($payload['allow_negative_stock']),
                    PosHelpers::boolToInt($payload['loyalty_enabled']),
                    $payload['loyalty_points_per_unit'],
                    $payload['loyalty_spend_unit'],
                    $payload['loyalty_redeem_points_per_peso'],
                    $payload['currency_symbol'],
                    $actorUserId,
                ],
            );
        } else {
            DB::statement(
                'INSERT INTO app_settings
                    (id, tax_rate, auto_print_receipt, allow_negative_stock, loyalty_enabled, currency_symbol, updated_by)
                 VALUES (1, ?, ?, ?, ?, ?, ?)
                 ON DUPLICATE KEY UPDATE
                    tax_rate = VALUES(tax_rate),
                    auto_print_receipt = VALUES(auto_print_receipt),
                    allow_negative_stock = VALUES(allow_negative_stock),
                    loyalty_enabled = VALUES(loyalty_enabled),
                    currency_symbol = VALUES(currency_symbol),
                    updated_by = VALUES(updated_by)',
                [
                    $payload['tax_rate'],
                    PosHelpers::boolToInt($payload['auto_print_receipt']),
                    PosHelpers::boolToInt($payload['allow_negative_stock']),
                    PosHelpers::boolToInt($payload['loyalty_enabled']),
                    $payload['currency_symbol'],
                    $actorUserId,
                ],
            );
        }

        if (PosHelpers::columnExists('app_settings', 'printer_host')) {
            DB::statement(
                'UPDATE app_settings SET printer_host = ?, updated_by = ? WHERE id = 1',
                [$payload['printer_host'], $actorUserId],
            );
        }

        if (PosHelpers::columnExists('app_settings', 'double_print_receipt')) {
            DB::table('app_settings')->where('id', 1)->update([
                'double_print_receipt' => PosHelpers::boolToInt($payload['double_print_receipt']),
                'updated_by' => $actorUserId,
            ]);
        }

        if (PosHelpers::columnExists('app_settings', 'printer_type')) {
            DB::table('app_settings')->where('id', 1)->update([
                'printer_type' => $payload['printer_type'],
                'printer_device' => $payload['printer_device'],
                'printer_port' => $payload['printer_port'],
                'updated_by' => $actorUserId,
            ]);
        }

        if (PosHelpers::columnExists('app_settings', 'receipt_store_json')) {
            $receiptStore = $this->normalizeReceiptStore(
                is_array($input['receipt_store'] ?? null) ? $input['receipt_store'] : null,
            );
            DB::table('app_settings')->where('id', 1)->update([
                'receipt_store_json' => json_encode($receiptStore, JSON_UNESCAPED_UNICODE),
                'updated_by' => $actorUserId,
            ]);
        }

        if (
            PosHelpers::columnExists('app_settings', 'default_branch_id')
            && array_key_exists('default_branch_id', $input)
        ) {
            $branchId = max(0, (int) $input['default_branch_id']);
            DB::table('app_settings')->where('id', 1)->update([
                'default_branch_id' => $branchId > 0 ? $branchId : null,
                'updated_by' => $actorUserId,
            ]);
        }

        if (PosHelpers::columnExists('app_settings', 'attendance_start_time')) {
            $startTime = $this->normalizeAttendanceTime(
                (string) ($input['attendance_start_time'] ?? '08:00'),
            );
            $grace = max(0, min(120, (int) ($input['attendance_grace_minutes'] ?? 15)));
            $attendanceUpdate = [
                'attendance_start_time' => $startTime,
                'attendance_grace_minutes' => $grace,
                'updated_by' => $actorUserId,
            ];
            if (PosHelpers::columnExists('app_settings', 'attendance_lunch_out_time')) {
                $attendanceUpdate['attendance_lunch_out_time'] = $this->normalizeAttendanceTime(
                    (string) ($input['attendance_lunch_out_time'] ?? '12:00'),
                );
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_afternoon_in_time')) {
                $attendanceUpdate['attendance_afternoon_in_time'] = $this->normalizeAttendanceTime(
                    (string) ($input['attendance_afternoon_in_time'] ?? '13:00'),
                );
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_day_end_time')) {
                $attendanceUpdate['attendance_day_end_time'] = $this->normalizeAttendanceTime(
                    (string) ($input['attendance_day_end_time'] ?? '17:00'),
                );
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_morning_absent_after_time')) {
                $attendanceUpdate['attendance_morning_absent_after_time'] = $this->normalizeAttendanceTime(
                    (string) ($input['attendance_morning_absent_after_time'] ?? $input['attendance_morning_cutoff'] ?? '09:00'),
                );
            }
            foreach ($this->attendanceSessionColumns() as $column) {
                if (PosHelpers::columnExists('app_settings', $column)) {
                    $defaults = $this->defaults();
                    $attendanceUpdate[$column] = $this->normalizeAttendanceTime(
                        (string) ($input[$column] ?? $defaults[$column] ?? '08:00'),
                    );
                }
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_morning_official_start')) {
                $attendanceUpdate['attendance_start_time'] = $attendanceUpdate['attendance_morning_official_start']
                    ?? $this->normalizeAttendanceTime((string) ($input['attendance_start_time'] ?? '08:00'));
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_break_out_end')) {
                $attendanceUpdate['attendance_lunch_out_time'] = $attendanceUpdate['attendance_break_out_end']
                    ?? $this->normalizeAttendanceTime((string) ($input['attendance_lunch_out_time'] ?? '12:00'));
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_afternoon_on_time_end')) {
                $attendanceUpdate['attendance_afternoon_in_time'] = $attendanceUpdate['attendance_afternoon_on_time_end']
                    ?? $this->normalizeAttendanceTime((string) ($input['attendance_afternoon_in_time'] ?? '13:30'));
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_timeout_start')) {
                $attendanceUpdate['attendance_day_end_time'] = $attendanceUpdate['attendance_timeout_start']
                    ?? $this->normalizeAttendanceTime((string) ($input['attendance_day_end_time'] ?? '16:30'));
            }
            if (PosHelpers::columnExists('app_settings', 'attendance_morning_cutoff')) {
                $attendanceUpdate['attendance_morning_absent_after_time'] = $attendanceUpdate['attendance_morning_cutoff']
                    ?? $attendanceUpdate['attendance_morning_absent_after_time'] ?? '09:00';
            }
            DB::table('app_settings')->where('id', 1)->update($attendanceUpdate);
        }

        if (PosHelpers::columnExists('app_settings', 'low_stock_email_enabled')) {
            DB::table('app_settings')->where('id', 1)->update([
                'low_stock_email_enabled' => PosHelpers::boolToInt(! empty($input['low_stock_email_enabled'])),
                'updated_by' => $actorUserId,
            ]);
        }

        if (PosHelpers::columnExists('app_settings', 'low_stock_email_recipients')) {
            $recipients = trim((string) ($input['low_stock_email_recipients'] ?? ''));
            if (strlen($recipients) > 500) {
                $recipients = substr($recipients, 0, 500);
            }
            DB::table('app_settings')->where('id', 1)->update([
                'low_stock_email_recipients' => $recipients,
                'updated_by' => $actorUserId,
            ]);
        }

        if (
            PosHelpers::columnExists('app_settings', 'refund_pin_hash')
            && array_key_exists('refund_pin', $input)
            && trim((string) $input['refund_pin']) !== ''
        ) {
            PosHelpers::requireAdminActor($actorUserId);
            $pin = trim((string) $input['refund_pin']);
            if (preg_match('/^\d{4,6}$/', $pin) !== 1) {
                throw new \RuntimeException('Refund PIN must be 4 to 6 digits.');
            }
            DB::table('app_settings')->where('id', 1)->update([
                'refund_pin_hash' => password_hash($pin, PASSWORD_DEFAULT),
                'updated_by' => $actorUserId,
            ]);
        }

        PosHelpers::insertAuditLog(
            $actorUserId,
            'update',
            'settings',
            'app_settings',
            1,
            'Application settings updated',
            $payload,
        );

        PosHelpers::insertUserTransaction(
            $actorUserId,
            'settings_save',
            'app_settings',
            1,
            0.0,
            'Application settings saved',
        );

        AppSettingsRevision::bump();

        return $this->read();
    }

    /**
     * @return array<string, mixed>
     */
    private function defaults(): array
    {
        $payload = [
            'tax_rate' => 0.0,
            'auto_print_receipt' => true,
            'double_print_receipt' => false,
            'printer_host' => '',
            'printer_type' => 'network',
            'printer_device' => '',
            'printer_port' => 9100,
            'allow_negative_stock' => false,
            'loyalty_enabled' => true,
            'loyalty_points_per_unit' => 50,
            'loyalty_spend_unit' => 1000.0,
            'loyalty_redeem_points_per_peso' => 10,
            'currency_symbol' => 'PHP',
            'receipt_store' => $this->defaultReceiptStore(),
            'default_branch_id' => 1,
            'attendance_start_time' => '08:00',
            'attendance_grace_minutes' => 15,
            'attendance_lunch_out_time' => '12:00',
            'attendance_afternoon_in_time' => '13:00',
            'attendance_day_end_time' => '17:00',
            'attendance_morning_absent_after_time' => '09:00',
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
            'low_stock_email_enabled' => true,
            'low_stock_email_recipients' => '',
            'has_refund_pin' => false,
        ];

        $payload['settings_revision'] = AppSettingsRevision::current();

        return $payload;
    }

    /**
     * @return array<string, mixed>
     */
    private function fromRow(?object $row): array
    {
        $defaults = $this->defaults();
        $data = (array) ($row ?? []);

        $receiptRaw = $data['receipt_store_json'] ?? null;
        $receiptDecoded = null;
        if (is_string($receiptRaw) && $receiptRaw !== '') {
            $receiptDecoded = json_decode($receiptRaw, true);
        } elseif (is_array($receiptRaw)) {
            $receiptDecoded = $receiptRaw;
        }

        $payload = [
            'tax_rate' => max(0.0, min(1.0, (float) ($data['tax_rate'] ?? $defaults['tax_rate']))),
            'auto_print_receipt' => ((int) ($data['auto_print_receipt'] ?? 1)) === 1,
            'double_print_receipt' => ((int) ($data['double_print_receipt'] ?? 0)) === 1,
            'printer_host' => trim((string) ($data['printer_host'] ?? $defaults['printer_host'])),
            'printer_type' => $this->normalizePrinterType($data['printer_type'] ?? $defaults['printer_type']),
            'printer_device' => trim((string) ($data['printer_device'] ?? $defaults['printer_device'])),
            'printer_port' => max(
                1,
                min(65535, (int) ($data['printer_port'] ?? $defaults['printer_port'])),
            ),
            'allow_negative_stock' => ((int) ($data['allow_negative_stock'] ?? 0)) === 1,
            'loyalty_enabled' => ((int) ($data['loyalty_enabled'] ?? 1)) === 1,
            'loyalty_points_per_unit' => max(0, (int) ($data['loyalty_points_per_unit'] ?? $defaults['loyalty_points_per_unit'])),
            'loyalty_spend_unit' => max(0.01, (float) ($data['loyalty_spend_unit'] ?? $defaults['loyalty_spend_unit'])),
            'loyalty_redeem_points_per_peso' => max(1, (int) ($data['loyalty_redeem_points_per_peso'] ?? $defaults['loyalty_redeem_points_per_peso'])),
            'currency_symbol' => (string) ($data['currency_symbol'] ?? $defaults['currency_symbol']),
            'receipt_store' => $this->normalizeReceiptStore(is_array($receiptDecoded) ? $receiptDecoded : null),
            'default_branch_id' => max(1, (int) ($data['default_branch_id'] ?? $defaults['default_branch_id'])),
            'attendance_start_time' => $this->normalizeAttendanceTime(
                (string) ($data['attendance_start_time'] ?? $defaults['attendance_start_time']),
            ),
            'attendance_grace_minutes' => max(
                0,
                min(120, (int) ($data['attendance_grace_minutes'] ?? $defaults['attendance_grace_minutes'])),
            ),
            'attendance_lunch_out_time' => $this->normalizeAttendanceTime(
                (string) ($data['attendance_lunch_out_time'] ?? $defaults['attendance_lunch_out_time']),
            ),
            'attendance_afternoon_in_time' => $this->normalizeAttendanceTime(
                (string) ($data['attendance_afternoon_in_time'] ?? $defaults['attendance_afternoon_in_time']),
            ),
            'attendance_day_end_time' => $this->normalizeAttendanceTime(
                (string) ($data['attendance_day_end_time'] ?? $defaults['attendance_day_end_time']),
            ),
            'attendance_morning_absent_after_time' => $this->normalizeAttendanceTime(
                (string) ($data['attendance_morning_absent_after_time'] ?? $defaults['attendance_morning_absent_after_time']),
            ),
            'low_stock_email_enabled' => ((int) ($data['low_stock_email_enabled'] ?? 1)) === 1,
            'low_stock_email_recipients' => trim(
                (string) ($data['low_stock_email_recipients'] ?? $defaults['low_stock_email_recipients']),
            ),
            'has_refund_pin' => trim((string) ($data['refund_pin_hash'] ?? '')) !== '',
        ];

        foreach ($this->attendanceSessionColumns() as $column) {
            $fallback = $defaults[$column] ?? '08:00';
            if ($column === 'attendance_morning_official_start' && empty($data[$column])) {
                $fallback = $payload['attendance_start_time'];
            }
            if ($column === 'attendance_break_out_end' && empty($data[$column])) {
                $fallback = $payload['attendance_lunch_out_time'];
            }
            if ($column === 'attendance_afternoon_on_time_end' && empty($data[$column])) {
                $fallback = $payload['attendance_afternoon_in_time'];
            }
            if ($column === 'attendance_timeout_start' && empty($data[$column])) {
                $fallback = $payload['attendance_day_end_time'];
            }
            if ($column === 'attendance_morning_cutoff' && empty($data[$column])) {
                $fallback = $payload['attendance_morning_absent_after_time'];
            }
            $payload[$column] = $this->normalizeAttendanceTime(
                (string) ($data[$column] ?? $fallback),
            );
        }

        $payload['settings_revision'] = AppSettingsRevision::current();

        return $payload;
    }

    /**
     * @return list<string>
     */
    private function attendanceSessionColumns(): array
    {
        return [
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
        ];
    }

    private function normalizeAttendanceTime(string $time): string
    {
        $time = trim($time);
        if (preg_match('/^(\d{1,2}):(\d{2})$/', $time, $matches) !== 1) {
            return '08:00';
        }

        $hour = max(0, min(23, (int) $matches[1]));
        $minute = max(0, min(59, (int) $matches[2]));

        return sprintf('%02d:%02d', $hour, $minute);
    }

    private function normalizePrinterType(mixed $type): string
    {
        $normalized = strtolower(trim((string) $type));

        return match ($normalized) {
            'bluetooth', 'bt' => 'bluetooth',
            'usb' => 'usb',
            default => 'network',
        };
    }
}
