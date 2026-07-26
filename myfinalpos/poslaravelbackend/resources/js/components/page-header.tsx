import type { ReactNode } from 'react';
import { cn } from '@/lib/utils';

type Props = {
    title: string;
    description?: string;
    badge?: string;
    actions?: ReactNode;
    className?: string;
};

export function PageHeader({
    title,
    description,
    badge,
    actions,
    className,
}: Props) {
    return (
        <div
            className={cn(
                'flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between',
                className,
            )}
        >
            <div className="space-y-1.5">
                {badge && (
                    <span className="inline-flex items-center rounded-full bg-primary/10 px-2.5 py-0.5 text-[11px] font-semibold tracking-wide text-primary uppercase">
                        {badge}
                    </span>
                )}
                <h1 className="text-2xl font-bold tracking-tight text-foreground">
                    {title}
                </h1>
                {description && (
                    <p className="max-w-3xl text-sm leading-relaxed text-muted-foreground">
                        {description}
                    </p>
                )}
            </div>
            {actions && (
                <div className="flex shrink-0 items-center gap-2">{actions}</div>
            )}
        </div>
    );
}
