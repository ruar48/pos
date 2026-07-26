const BUSINESS_DAY_RESET_HOUR = 5;

function pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
}

export function toIsoDate(date: Date): string {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function currentBusinessDate(
    now = new Date(),
    resetHour = BUSINESS_DAY_RESET_HOUR,
): string {
    const moment = new Date(now);
    if (moment.getHours() < resetHour) {
        moment.setDate(moment.getDate() - 1);
    }
    return toIsoDate(moment);
}

export function isCurrentBusinessDate(
    date: string,
    now = new Date(),
    resetHour = BUSINESS_DAY_RESET_HOUR,
): boolean {
    return date === currentBusinessDate(now, resetHour);
}

export function businessDayResetLabel(
    resetHour = BUSINESS_DAY_RESET_HOUR,
): string {
    const hour = resetHour % 12 || 12;
    const suffix = resetHour < 12 ? 'AM' : 'PM';
    return `${hour}:00 ${suffix}`;
}
