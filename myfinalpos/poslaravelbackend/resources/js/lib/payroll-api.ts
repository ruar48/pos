import { laravelFetch } from '@/lib/laravel-fetch';

export type PayrollRow = {
    user_id: number;
    full_name: string;
    role: string;
    branch_name: string;
    break_minutes: number;
    break_hours_label: string;
    total_minutes: number;
    total_hours_label: string;
    hourly_rate: number;
    total_pay: number;
    has_missing_time_out: boolean;
    missing_time_out_dates: string[];
};

export async function fetchPayrollReport(
    start: string,
    end: string,
    branchId?: number,
) {
    const params = new URLSearchParams({ start, end });
    if (branchId) params.set('branch_id', String(branchId));

    return laravelFetch<{
        range: { start: string; end: string };
        rows: PayrollRow[];
    }>(`/pos/payroll/report?${params.toString()}`);
}

export async function savePayrollRate(input: {
    user_id: number;
    hourly_rate: number;
}) {
    return laravelFetch<{ success: boolean; message: string }>(
        '/pos/payroll/rate',
        {
            method: 'POST',
            body: JSON.stringify(input),
        },
    );
}
