/** Server stores MySQL datetimes without timezone — treat as UTC, display in PH time. */
const DISPLAY_TIMEZONE = 'Asia/Manila';

export function parseServerDateTime(
    value: string | null | undefined,
): Date | null {
    if (!value) return null;
    const trimmed = value.trim();
    if (!trimmed) return null;

    const normalized = trimmed.includes('T')
        ? trimmed
        : trimmed.replace(' ', 'T');
    const hasZone =
        normalized.endsWith('Z') || /[+-]\d{2}:\d{2}$/.test(normalized);
    const asUtc = hasZone ? normalized : `${normalized}Z`;
    const date = new Date(asUtc);

    return Number.isNaN(date.getTime()) ? null : date;
}

export function formatServerTime(value: string | null | undefined): string {
    const date = parseServerDateTime(value);
    if (!date) return '—';

    return date.toLocaleTimeString('en-PH', {
        hour: 'numeric',
        minute: '2-digit',
        timeZone: DISPLAY_TIMEZONE,
    });
}

export function formatServerDateTime(value: string | null | undefined): string {
    const date = parseServerDateTime(value);
    if (!date) return '—';

    return date.toLocaleString('en-PH', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        timeZone: DISPLAY_TIMEZONE,
    });
}
