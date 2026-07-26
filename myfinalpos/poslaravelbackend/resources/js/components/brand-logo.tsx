import { useState } from 'react';
import AppLogoIcon from '@/components/app-logo-icon';
import { BRAND } from '@/lib/brand';
import { cn } from '@/lib/utils';

type BrandLogoProps = {
    className?: string;
    imageClassName?: string;
    iconClassName?: string;
    markClassName?: string;
    showText?: boolean;
    nameClassName?: string;
    subtitleClassName?: string;
    subtitle?: string;
    size?: 'sm' | 'md' | 'lg';
    tone?: 'default' | 'on-dark';
};

const sizeMap = {
    sm: {
        box: 'size-10',
        icon: 'size-5',
        name: 'text-sm',
        sub: 'text-[11px]',
        gap: 'gap-2.5',
    },
    md: {
        box: 'size-11',
        icon: 'size-5',
        name: 'text-base',
        sub: 'text-xs',
        gap: 'gap-3',
    },
    lg: {
        box: 'size-16',
        icon: 'size-8',
        name: 'text-xl',
        sub: 'text-sm',
        gap: 'gap-3.5',
    },
} as const;

export function BrandLogo({
    className,
    imageClassName,
    iconClassName,
    markClassName,
    showText = true,
    nameClassName,
    subtitleClassName,
    subtitle = BRAND.tagline,
    size = 'md',
    tone = 'default',
}: BrandLogoProps) {
    const [imageFailed, setImageFailed] = useState(false);
    const dims = sizeMap[size];
    const showImage = !imageFailed;

    const imageMarkClasses =
        tone === 'on-dark'
            ? 'border-sidebar-border/50 bg-white shadow-sm'
            : 'border-border/60 bg-white shadow-sm';

    return (
        <div
            className={cn(
                'flex min-w-0 items-center',
                dims.gap,
                className,
            )}
        >
            <div
                className={cn(
                    'flex shrink-0 items-center justify-center overflow-hidden rounded-xl',
                    dims.box,
                    showImage
                        ? cn('border p-1', imageMarkClasses)
                        : 'bg-primary text-primary-foreground shadow-sm',
                    markClassName,
                )}
            >
                {showImage ? (
                    <img
                        src={BRAND.logoPath}
                        alt={BRAND.shortName}
                        className={cn(
                            'size-full object-contain',
                            imageClassName,
                        )}
                        onError={() => setImageFailed(true)}
                    />
                ) : (
                    <AppLogoIcon className={cn(dims.icon, iconClassName)} />
                )}
            </div>
            {showText && (
                <div className="min-w-0 leading-tight">
                    <span
                        className={cn(
                            'block truncate font-bold tracking-tight',
                            dims.name,
                            nameClassName,
                        )}
                    >
                        {BRAND.shortName}
                    </span>
                    {subtitle ? (
                        <span
                            className={cn(
                                'block truncate text-muted-foreground',
                                dims.sub,
                                subtitleClassName,
                            )}
                        >
                            {subtitle}
                        </span>
                    ) : null}
                </div>
            )}
        </div>
    );
}
