import { laravelFetch } from '@/lib/laravel-fetch';

export type ReceiptStore = {
    logo_text: string;
    logo_image_url: string | null;
    logo_image_base64: string | null;
    store_name: string;
    store_subtitle: string;
    address_line1: string;
    address_line2: string;
    tin: string;
    tax_status: string;
    pos_terminal_id: string;
    ptu_no: string;
    atp_no: string;
    atp_date_issued: string;
    series_range: string;
};

export type StoreBranch = {
    id: number;
    name: string;
    location: string | null;
    code: string | null;
};

export type StoreSettings = {
    tax_rate: number;
    auto_print_receipt: boolean;
    double_print_receipt: boolean;
    printer_host: string;
    printer_type: 'network' | 'bluetooth' | 'usb';
    printer_device: string;
    printer_port: number;
    allow_negative_stock: boolean;
    low_stock_email_enabled: boolean;
    low_stock_email_recipients: string;
    loyalty_enabled: boolean;
    loyalty_points_per_unit: number;
    loyalty_spend_unit: number;
    loyalty_redeem_points_per_peso: number;
    currency_symbol: string;
    receipt_store: ReceiptStore;
    default_branch_id: number;
    attendance_start_time: string;
    attendance_grace_minutes: number;
    attendance_lunch_out_time: string;
    attendance_afternoon_in_time: string;
    attendance_day_end_time: string;
    attendance_morning_absent_after_time: string;
    attendance_morning_accept_start: string;
    attendance_morning_official_start: string;
    attendance_morning_grace_end: string;
    attendance_morning_late_start: string;
    attendance_morning_cutoff: string;
    attendance_break_out_start: string;
    attendance_break_out_end: string;
    attendance_afternoon_accept_start: string;
    attendance_afternoon_on_time_end: string;
    attendance_afternoon_late_start: string;
    attendance_afternoon_cutoff: string;
    attendance_timeout_start: string;
};

export const DEFAULT_RECEIPT_STORE: ReceiptStore = {
    logo_text: '[ Farm & Tractor ]',
    logo_image_url: null,
    logo_image_base64: null,
    store_name: 'GREEN FARM MART',
    store_subtitle: 'AGRICULTURE RETAIL STORE',
    address_line1: 'Purok 3, Brgy. Sto. Rosario,',
    address_line2: 'Angeles City, Pampanga 2009',
    tin: '123-456-789-000',
    tax_status: 'NON-VAT REGISTERED',
    pos_terminal_id: 'POS-01',
    ptu_no: 'PTU-123456789',
    atp_no: 'ATP-987654321',
    atp_date_issued: '01/15/2026',
    series_range: '0000001 - 9999999',
};

export async function saveStoreSettings(
    input: Partial<StoreSettings>,
): Promise<StoreSettings> {
    const body = await laravelFetch<{
        settings: StoreSettings;
        message: string;
    }>('/settings/store', {
        method: 'PATCH',
        body: JSON.stringify(input),
    });

    return body.settings;
}
