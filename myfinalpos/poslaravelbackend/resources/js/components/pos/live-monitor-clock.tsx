import { CalendarDays, Clock } from 'lucide-react';
import type { LiveMonitorDensity } from '@/hooks/use-live-monitor-layout';
import { useLiveClock } from '@/hooks/use-live-clock';
import { cn } from '@/lib/utils';

type LiveMonitorClockProps = {
    density?: LiveMonitorDensity;
    wallMode?: boolean;
    variant?: 'chip' | 'standalone';
    className?: string;
};

export function LiveMonitorClock({
    density = 'desktop',
    wallMode = false,
    variant = 'chip',
    className,
}: LiveMonitorClockProps) {
    const { date, time } = useLiveClock();
    const isLarge = density === 'tv' || density === 'ultra';
    const isWallLarge = wallMode && isLarge;

    if (variant === 'chip') {
        return (
            <span
                className={cn(
                    'live-monitor-chip inline-flex items-center gap-1.5 rounded-full border border-border bg-background font-semibold text-foreground',
                    className,
                )}
            >
                <Clock className="live-monitor-chip-icon shrink-0 text-primary" />
                <span
                    className={cn(
                        'font-mono tabular-nums tracking-tight',
                        isWallLarge && 'text-base sm:text-lg',
                    )}
                >
                    {time}
                </span>
                <span
                    className="text-muted-foreground/50"
                    aria-hidden
                >
                    ·
                </span>
                <CalendarDays className="live-monitor-chip-icon shrink-0 text-primary/80" />
                <span
                    className={cn(
                        'font-normal text-muted-foreground',
                        isWallLarge && 'text-sm sm:text-base',
                    )}
                >
                    {date}
                </span>
            </span>
        );
    }

    return (
        <div
            className={cn(
                'inline-flex flex-col items-end rounded-xl border border-border/60 bg-background/80 px-3 py-2 text-right shadow-sm backdrop-blur-sm',
                wallMode && 'sm:px-4 sm:py-3',
                isWallLarge && 'px-5 py-4',
                className,
            )}
        >
            <div
                className={cn(
                    'inline-flex items-center gap-1.5 font-mono font-bold tabular-nums tracking-tight text-foreground',
                    density === 'phone' && 'text-base',
                    density === 'tablet' && 'text-lg',
                    density === 'desktop' && 'text-xl',
                    isWallLarge && 'text-3xl',
                    wallMode && !isLarge && 'text-xl sm:text-2xl',
                )}
            >
                <Clock
                    className={cn(
                        'shrink-0 text-primary',
                        density === 'phone' && 'size-4',
                        (density === 'tablet' || density === 'desktop') &&
                            'size-5',
                        isWallLarge && 'size-7',
                        wallMode && !isLarge && 'size-5',
                    )}
                />
                {time}
            </div>
            <div
                className={cn(
                    'mt-1 inline-flex items-center gap-1.5 text-muted-foreground',
                    density === 'phone' && 'text-[11px]',
                    density === 'tablet' && 'text-xs',
                    (density === 'desktop' || wallMode) && 'text-sm',
                    isWallLarge && 'text-base',
                )}
            >
                <CalendarDays
                    className={cn(
                        'shrink-0 text-primary/80',
                        density === 'phone' && 'size-3.5',
                        density !== 'phone' && 'size-4',
                        isWallLarge && 'size-5',
                    )}
                />
                <span>{date}</span>
            </div>
        </div>
    );
}
