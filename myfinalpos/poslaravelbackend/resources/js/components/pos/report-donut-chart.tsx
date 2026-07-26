import { useMemo } from 'react';
import { cn } from '@/lib/utils';

export type DonutSlice = {
    label: string;
    value: number;
    hint?: string;
};

const SLICE_COLORS = [
    '#0f766e',
    '#14b8a6',
    '#2dd4bf',
    '#5eead4',
    '#059669',
    '#34d399',
    '#f97316',
    '#fb923c',
    '#fdba74',
    '#64748b',
];

function polarToCartesian(
    cx: number,
    cy: number,
    radius: number,
    angleInDegrees: number,
) {
    const angleInRadians = ((angleInDegrees - 90) * Math.PI) / 180;
    return {
        x: cx + radius * Math.cos(angleInRadians),
        y: cy + radius * Math.sin(angleInRadians),
    };
}

function describeArc(
    cx: number,
    cy: number,
    radius: number,
    startAngle: number,
    endAngle: number,
) {
    const start = polarToCartesian(cx, cy, radius, endAngle);
    const end = polarToCartesian(cx, cy, radius, startAngle);
    const largeArcFlag = endAngle - startAngle <= 180 ? '0' : '1';

    return [
        'M',
        start.x,
        start.y,
        'A',
        radius,
        radius,
        0,
        largeArcFlag,
        0,
        end.x,
        end.y,
        'L',
        cx,
        cy,
        'Z',
    ].join(' ');
}

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

export function ReportDonutChart({
    title,
    subtitle,
    slices,
    valueFormatter = (value) => `₱${formatMoney(value)}`,
    className,
    maxLegendItems = 6,
}: {
    title: string;
    subtitle?: string;
    slices: DonutSlice[];
    valueFormatter?: (value: number, slice: DonutSlice) => string;
    className?: string;
    maxLegendItems?: number;
}) {
    const total = useMemo(
        () => slices.reduce((sum, slice) => sum + slice.value, 0),
        [slices],
    );

    const arcs = useMemo(() => {
        if (total <= 0) {
            return [];
        }

        let cursor = 0;
        return slices.map((slice, index) => {
            const angle = (slice.value / total) * 360;
            const start = cursor;
            const end = cursor + angle;
            cursor = end;

            return {
                ...slice,
                color: SLICE_COLORS[index % SLICE_COLORS.length],
                path:
                    angle >= 359.99
                        ? null
                        : describeArc(50, 50, 38, start, end),
                fullCircle: angle >= 359.99,
            };
        });
    }, [slices, total]);

    const legend = slices.slice(0, maxLegendItems);
    const hiddenCount = Math.max(slices.length - legend.length, 0);

    return (
        <div className={cn('agri-card flex h-full flex-col p-5', className)}>
            <div className="mb-4">
                <h3 className="text-base font-semibold text-teal-800">{title}</h3>
                {subtitle && (
                    <p className="mt-0.5 text-xs text-muted-foreground">{subtitle}</p>
                )}
            </div>

            {total <= 0 ? (
                <p className="text-sm text-muted-foreground">No data for this period.</p>
            ) : (
                <div className="flex flex-1 flex-col gap-4 lg:flex-row lg:items-center">
                    <div className="mx-auto shrink-0">
                        <svg viewBox="0 0 100 100" className="size-40">
                            {arcs.map((arc) =>
                                arc.fullCircle ? (
                                    <circle
                                        key={arc.label}
                                        cx="50"
                                        cy="50"
                                        r="38"
                                        fill={arc.color}
                                    />
                                ) : (
                                    <path
                                        key={arc.label}
                                        d={arc.path ?? ''}
                                        fill={arc.color}
                                    />
                                ),
                            )}
                            <circle cx="50" cy="50" r="22" fill="white" />
                        </svg>
                    </div>

                    <ul className="min-h-0 flex-1 space-y-2 overflow-y-auto pr-1">
                        {legend.map((slice, index) => (
                            <li
                                key={slice.label}
                                className="flex items-start justify-between gap-3 text-sm"
                            >
                                <div className="flex min-w-0 items-start gap-2">
                                    <span
                                        className="mt-1 size-2.5 shrink-0 rounded-full"
                                        style={{
                                            backgroundColor:
                                                SLICE_COLORS[
                                                    index % SLICE_COLORS.length
                                                ],
                                        }}
                                    />
                                    <div className="min-w-0">
                                        <p className="truncate font-medium text-foreground">
                                            {slice.label}
                                        </p>
                                        {slice.hint && (
                                            <p className="text-xs text-muted-foreground">
                                                {slice.hint}
                                            </p>
                                        )}
                                    </div>
                                </div>
                                <p className="shrink-0 font-semibold tabular-nums text-foreground">
                                    {valueFormatter(slice.value, slice)}
                                </p>
                            </li>
                        ))}
                        {hiddenCount > 0 && (
                            <li className="text-xs text-muted-foreground">
                                +{hiddenCount} more
                            </li>
                        )}
                    </ul>
                </div>
            )}
        </div>
    );
}
