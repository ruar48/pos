import { useMemo, useState } from 'react';
import { cn } from '@/lib/utils';

export type HourlyHeatmapData = {
    days: string[];
    day_labels: string[];
    hours: number[];
    hour_labels: string[];
    cells: {
        date: string;
        hour: number;
        units: number;
        amount: number;
    }[];
};

type HeatmapMode = 'units' | 'price';

function formatCellValue(value: number, mode: HeatmapMode): string {
    if (value <= 0) {
        return '0';
    }
    if (mode === 'price') {
        return value.toLocaleString(undefined, {
            maximumFractionDigits: 0,
        });
    }
    return Number.isInteger(value)
        ? value.toLocaleString()
        : value.toLocaleString(undefined, { maximumFractionDigits: 1 });
}

function heatColor(ratio: number): string {
    if (ratio <= 0) {
        return '#475569';
    }
    if (ratio < 0.2) {
        return '#fdba74';
    }
    if (ratio < 0.4) {
        return '#fb923c';
    }
    if (ratio < 0.6) {
        return '#f59e0b';
    }
    if (ratio < 0.8) {
        return '#34d399';
    }
    return '#0f766e';
}

export function ReportHourlyHeatmap({
    data,
    rangeLabel,
    className,
}: {
    data: HourlyHeatmapData;
    rangeLabel: string;
    className?: string;
}) {
    const [mode, setMode] = useState<HeatmapMode>('units');

    const cellMap = useMemo(() => {
        const map = new Map<string, (typeof data.cells)[number]>();
        data.cells.forEach((cell) => {
            map.set(`${cell.date}|${cell.hour}`, cell);
        });
        return map;
    }, [data.cells]);

    const maxValue = useMemo(() => {
        const values = data.cells.map((cell) =>
            mode === 'units' ? cell.units : cell.amount,
        );
        return Math.max(...values, 1);
    }, [data.cells, mode]);

    return (
        <div className={cn('agri-card p-5', className)}>
            <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                <div>
                    <h3 className="text-base font-semibold text-teal-800">
                        Units Sold by Hour
                    </h3>
                    <p className="mt-0.5 text-xs text-muted-foreground">{rangeLabel}</p>
                </div>
                <div className="inline-flex rounded-lg border border-border bg-secondary/30 p-0.5">
                    <button
                        type="button"
                        onClick={() => setMode('units')}
                        className={cn(
                            'rounded-md px-3 py-1 text-xs font-semibold transition-colors',
                            mode === 'units'
                                ? 'bg-white text-teal-800 shadow-sm'
                                : 'text-muted-foreground hover:text-foreground',
                        )}
                    >
                        Unit
                    </button>
                    <button
                        type="button"
                        onClick={() => setMode('price')}
                        className={cn(
                            'rounded-md px-3 py-1 text-xs font-semibold transition-colors',
                            mode === 'price'
                                ? 'bg-white text-teal-800 shadow-sm'
                                : 'text-muted-foreground hover:text-foreground',
                        )}
                    >
                        Price
                    </button>
                </div>
            </div>

            <div className="overflow-x-auto">
                <div className="min-w-[720px]">
                    <div
                        className="grid gap-1"
                        style={{
                            gridTemplateColumns: `4.5rem repeat(${data.hours.length}, minmax(2rem, 1fr))`,
                        }}
                    >
                        <div />
                        {data.hour_labels.map((label) => (
                            <div
                                key={label}
                                className="truncate text-center text-[10px] font-medium text-muted-foreground"
                            >
                                {label}
                            </div>
                        ))}

                        {data.days.map((day, dayIndex) => (
                            <div key={day} className="contents">
                                <div className="flex items-center pr-2 text-xs font-medium text-foreground">
                                    {data.day_labels[dayIndex] ?? day}
                                </div>
                                {data.hours.map((hour) => {
                                    const cell = cellMap.get(`${day}|${hour}`);
                                    const value = cell
                                        ? mode === 'units'
                                            ? cell.units
                                            : cell.amount
                                        : 0;
                                    const ratio = value / maxValue;
                                    const color = heatColor(ratio);

                                    return (
                                        <div
                                            key={`${day}-${hour}`}
                                            className="flex aspect-square min-h-8 items-center justify-center rounded-full text-[10px] font-semibold tabular-nums text-white"
                                            style={{ backgroundColor: color }}
                                            title={`${data.day_labels[dayIndex] ?? day} ${data.hour_labels[hour] ?? hour}: ${formatCellValue(value, mode)}`}
                                        >
                                            {formatCellValue(value, mode)}
                                        </div>
                                    );
                                })}
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            <div className="mt-4 flex items-center gap-2 text-[10px] text-muted-foreground">
                <span>Low</span>
                <div className="flex h-2 flex-1 overflow-hidden rounded-full">
                    <div className="flex-1 bg-slate-600" />
                    <div className="flex-1 bg-orange-300" />
                    <div className="flex-1 bg-orange-400" />
                    <div className="flex-1 bg-amber-500" />
                    <div className="flex-1 bg-emerald-400" />
                    <div className="flex-1 bg-teal-700" />
                </div>
                <span>High</span>
            </div>
        </div>
    );
}
