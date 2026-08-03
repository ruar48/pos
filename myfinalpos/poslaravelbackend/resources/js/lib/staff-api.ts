import { laravelFetch } from '@/lib/laravel-fetch';

export type StaffUser = {
    id: number;
    full_name: string;
    username: string;
    email: string;
    role: string;
    status: number;
    branch_id: number | null;
    branch_name: string | null;
    created_at: string | null;
};

export type AttendanceDayType = 'none' | 'in_progress' | 'half' | 'full';

export type AttendanceSchedule = {
    morning_accept_start: string;
    morning_official_start: string;
    morning_grace_end: string;
    morning_late_start: string;
    morning_cutoff: string;
    break_out_start: string;
    break_out_end: string;
    afternoon_accept_start: string;
    afternoon_on_time_end: string;
    afternoon_late_start: string;
    afternoon_cutoff: string;
    timeout_start: string;
    start_time: string;
    grace_minutes: number;
    late_after_time: string;
    lunch_out_time: string;
    lunch_out_start_time: string;
    afternoon_in_time: string;
    afternoon_in_start_time: string;
    afternoon_in_end_time: string;
    day_end_time: string;
    morning_absent_after_time: string;
    morning_in_end_time: string;
};

export type SessionStatus = 'present' | 'late' | 'absent' | 'not_in_yet';
export type DailyAttendanceStatus = 'present' | 'half_day' | 'absent' | 'in_progress';

export type PunctualityStatus =
    | 'present'
    | 'late'
    | 'absent'
    | 'not_in_yet'
    | 'morning_absent';

export type AttendanceRow = {
    user_id: number;
    full_name: string;
    role: string;
    branch_id: number | null;
    branch_name: string;
    clock_in_at: string | null;
    clock_out_at: string | null;
    morning_in_at: string | null;
    lunch_out_at: string | null;
    afternoon_in_at: string | null;
    day_out_at: string | null;
    morning_in_display?: string | null;
    lunch_out_display?: string | null;
    afternoon_in_display?: string | null;
    day_out_display?: string | null;
    clock_in_display?: string | null;
    clock_out_display?: string | null;
    punch_count: number;
    next_action: 'clock_in' | 'clock_out' | null;
    next_action_note?: string | null;
    day_complete: boolean;
    day_type: AttendanceDayType;
    total_minutes: number;
    total_hours_label: string;
    is_clocked_in: boolean;
    last_latitude: number | null;
    last_longitude: number | null;
    within_geofence: boolean | null;
    distance_km: number | null;
    punctuality_status: PunctualityStatus;
    is_late: boolean;
    minutes_from_start: number | null;
    minutes_late: number;
    expected_start_time: string;
    late_after_time: string;
    morning_absent_after_time: string;
    is_morning_absent: boolean;
    morning_session_status: SessionStatus;
    afternoon_session_status: SessionStatus;
    daily_status: DailyAttendanceStatus;
    morning_in_photo_url?: string | null;
    lunch_out_photo_url?: string | null;
    afternoon_in_photo_url?: string | null;
    day_out_photo_url?: string | null;
    is_on_break: boolean;
    break_start_at: string | null;
    break_end_at: string | null;
    break_start_display?: string | null;
    break_end_display?: string | null;
    break_start_photo_url?: string | null;
    break_end_photo_url?: string | null;
    total_break_minutes: number;
};

export type AttendancePunctualityRow = {
    user_id: number;
    full_name: string;
    role: string;
    branch_name: string;
    rank: number;
    days_tracked: number;
    days_present: number;
    days_half_day: number;
    days_late: number;
    days_absent: number;
};

export async function fetchStaffUsers() {
    return laravelFetch<{ data: StaffUser[] }>('/pos/staff/users');
}

export async function saveStaffUser(input: {
    action: 'create' | 'update' | 'toggle' | 'reset_password';
    id?: number;
    full_name?: string;
    username?: string;
    email?: string;
    password?: string;
    role?: string;
    branch_id?: number | null;
}) {
    return laravelFetch<{ data?: StaffUser; message?: string }>('/pos/staff/users', {
        method: 'POST',
        body: JSON.stringify(input),
    });
}

export type AttendanceEventRow = {
    id: number;
    user_id: number;
    full_name: string;
    role: string;
    branch_name: string;
    event_type: 'clock_in' | 'clock_out' | string;
    recorded_at: string;
    device_info: string;
    within_geofence: boolean | null;
    distance_km: number | null;
};

export async function fetchAttendanceBoard(date: string, branchId?: number) {
    const params = new URLSearchParams({ date });
    if (branchId) params.set('branch_id', String(branchId));
    return laravelFetch<{
        date: string;
        schedule: AttendanceSchedule;
        rows: AttendanceRow[];
    }>(`/pos/staff/attendance?${params.toString()}`);
}

export async function fetchAttendancePunctualityReport(
    start: string,
    end: string,
    branchId?: number,
) {
    const params = new URLSearchParams({
        report: 'punctuality',
        start,
        end,
    });
    if (branchId) params.set('branch_id', String(branchId));
    return laravelFetch<{
        range: { start: string; end: string };
        schedule: AttendanceSchedule;
        rows: AttendancePunctualityRow[];
    }>(`/pos/staff/attendance?${params.toString()}`);
}

export async function fetchAttendanceEventLog(
    start: string,
    end: string,
    branchId?: number,
) {
    const params = new URLSearchParams({
        report: 'events',
        start,
        end,
    });
    if (branchId) params.set('branch_id', String(branchId));
    return laravelFetch<{
        range: { start: string; end: string };
        rows: AttendanceEventRow[];
    }>(`/pos/staff/attendance?${params.toString()}`);
}

export function attendanceExportUrl(
    start: string,
    end: string,
    branchId?: number,
): string {
    const params = new URLSearchParams({ start, end });
    if (branchId) params.set('branch_id', String(branchId));

    return `/pos/staff/attendance/export?${params.toString()}`;
}

export async function downloadAttendanceExport(
    start: string,
    end: string,
    branchId?: number,
): Promise<void> {
    const response = await fetch(attendanceExportUrl(start, end, branchId), {
        credentials: 'same-origin',
    });

    if (!response.ok) {
        let message = 'Export failed';
        try {
            const payload = (await response.json()) as { message?: string };
            if (payload.message) {
                message = payload.message;
            }
        } catch {
            // ignore
        }
        throw new Error(message);
    }

    const blob = await response.blob();
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = `attendance_${start}_to_${end}.xlsx`;
    anchor.click();
    URL.revokeObjectURL(url);
}

export async function clockStaffAttendance(input: {
    action: 'clock_in' | 'clock_out' | 'break_in' | 'break_out';
    user_id: number;
    branch_id?: number;
    face_verified?: boolean;
    photo_base64?: string;
    photo_mime?: string;
}) {
    return laravelFetch<{
        message: string;
        data: {
            status: AttendanceRow;
            is_late?: boolean;
            punctuality_status?: string;
        };
    }>('/pos/staff/attendance', {
        method: 'POST',
        body: JSON.stringify(input),
    });
}

export type AttendancePhotoStats = {
    file_count: number;
    total_bytes: number;
    total_mb: number;
    directory: string;
};

export async function fetchAttendancePhotoStats() {
    return laravelFetch<{ data: AttendancePhotoStats }>(
        '/pos/staff/attendance/photos',
    );
}

export async function purgeAttendancePhotos(input: {
    older_than_days?: number;
    all?: boolean;
}) {
    return laravelFetch<{
        message: string;
        data: {
            deleted_files: number;
            cleared_rows: number;
            freed_bytes: number;
            freed_mb: number;
        };
    }>('/pos/staff/attendance/photos/purge', {
        method: 'POST',
        body: JSON.stringify(input),
    });
}
