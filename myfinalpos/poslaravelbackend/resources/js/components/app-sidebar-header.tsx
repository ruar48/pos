import { Breadcrumbs } from '@/components/breadcrumbs';
import { SidebarTrigger } from '@/components/ui/sidebar';

type BreadcrumbItemType = {
    title: string;
    href: string;
};

export function AppSidebarHeader({
    breadcrumbs = [],
}: {
    breadcrumbs?: BreadcrumbItemType[];
}) {
    return (
        <header className="sticky top-0 z-10 flex h-14 shrink-0 items-center gap-3 border-b border-border/40 bg-background/80 px-4 backdrop-blur-md transition-[width,height] ease-linear md:px-6">
            <SidebarTrigger className="-ml-1 text-muted-foreground hover:text-foreground" />
            {breadcrumbs.length > 0 && (
                <div className="hidden sm:block">
                    <Breadcrumbs breadcrumbs={breadcrumbs} />
                </div>
            )}
        </header>
    );
}
