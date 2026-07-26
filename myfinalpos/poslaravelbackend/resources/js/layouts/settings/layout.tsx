import { Link } from '@inertiajs/react';
import type { PropsWithChildren } from 'react';
import { Shield, Store, User } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Separator } from '@/components/ui/separator';
import { useCurrentUrl } from '@/hooks/use-current-url';
import { cn, toUrl } from '@/lib/utils';
import { edit } from '@/routes/profile';
import { edit as editSecurity } from '@/routes/security';
import type { NavItem } from '@/types';

const sidebarNavItems: NavItem[] = [
    {
        title: 'Store',
        href: '/settings/store',
        icon: Store,
    },
    {
        title: 'Profile',
        href: edit(),
        icon: User,
    },
    {
        title: 'Security',
        href: editSecurity(),
        icon: Shield,
    },
];

export default function SettingsLayout({ children }: PropsWithChildren) {
    const { isCurrentOrParentUrl } = useCurrentUrl();

    return (
        <div className="agri-page-container">
            <div className="mb-8">
                <h1 className="text-2xl font-bold tracking-tight text-foreground md:text-3xl">
                    Store Settings
                </h1>
                <p className="mt-2 max-w-xl text-sm text-muted-foreground">
                    Manage your profile and security preferences for this
                    register.
                </p>
            </div>

            <div className="flex flex-col gap-8 lg:flex-row lg:gap-12">
                    <aside className="w-full shrink-0 lg:w-52">
                        <nav
                            className="agri-card flex flex-row gap-1 p-1.5 lg:flex-col"
                            aria-label="Settings"
                        >
                            {sidebarNavItems.map((item, index) => (
                                <Button
                                    key={`${toUrl(item.href)}-${index}`}
                                    size="sm"
                                    variant="ghost"
                                    asChild
                                    className={cn(
                                        'h-10 flex-1 justify-start gap-2 rounded-xl px-3 font-medium lg:flex-none lg:w-full',
                                        isCurrentOrParentUrl(item.href!) &&
                                            'bg-primary/10 text-primary hover:bg-primary/15 hover:text-primary',
                                    )}
                                >
                                    <Link href={item.href!}>
                                        {item.icon && (
                                            <item.icon className="size-4" />
                                        )}
                                        {item.title}
                                    </Link>
                                </Button>
                            ))}
                        </nav>
                    </aside>

                    <Separator className="lg:hidden" />

                    <div className="min-w-0 flex-1">
                        <section className="agri-card p-6 md:p-8">
                            {children}
                        </section>
                    </div>
            </div>
        </div>
    );
}
