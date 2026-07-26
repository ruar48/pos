import { Link } from '@inertiajs/react';
import { Sprout } from 'lucide-react';
import { BrandLogo } from '@/components/brand-logo';
import { BRAND } from '@/lib/brand';
import { home } from '@/routes';
import type { AuthLayoutProps } from '@/types';

export default function AuthSimpleLayout({
    children,
    title,
    description,
}: AuthLayoutProps) {
    return (
        <div className="relative flex min-h-svh flex-col items-center justify-center overflow-hidden p-6 md:p-10">
            <div
                className="pointer-events-none absolute inset-0"
                style={{
                    background:
                        'radial-gradient(ellipse 70% 50% at 50% -10%, oklch(0.55 0.12 155 / 0.12), transparent), radial-gradient(ellipse 50% 40% at 100% 80%, oklch(0.78 0.11 85 / 0.08), transparent), oklch(0.97 0.018 155)',
                }}
            />

            <div className="relative w-full max-w-md">
                <div className="agri-card overflow-hidden p-8 shadow-lg sm:p-10">
                    <div className="mb-8 flex flex-col items-center gap-4 text-center">
                        <Link
                            href={home()}
                            className="group transition-transform duration-200 hover:scale-[1.02]"
                        >
                            <BrandLogo
                                size="lg"
                                subtitle={BRAND.posSubtitle}
                                className="flex-col items-center text-center"
                                nameClassName="text-foreground"
                                subtitleClassName="text-muted-foreground uppercase tracking-wide"
                            />
                        </Link>

                        <div className="space-y-1.5">
                            <h1 className="text-xl font-bold text-foreground">
                                {title}
                            </h1>
                            <p className="text-sm leading-relaxed text-muted-foreground">
                                {description}
                            </p>
                        </div>
                    </div>

                    {children}

                    <div className="mt-8 flex items-center justify-center gap-2 border-t border-border/50 pt-6 text-xs text-muted-foreground">
                        <Sprout className="size-3.5 text-agri-leaf" />
                        <span>{BRAND.tagline}</span>
                    </div>
                </div>
            </div>
        </div>
    );
}
