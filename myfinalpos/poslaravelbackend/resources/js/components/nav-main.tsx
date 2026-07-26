import { Link } from '@inertiajs/react';
import {
    SidebarGroup,
    SidebarGroupLabel,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from '@/components/ui/sidebar';
import {
    Tooltip,
    TooltipContent,
    TooltipTrigger,
} from '@/components/ui/tooltip';
import { useCurrentUrl } from '@/hooks/use-current-url';
import { cn } from '@/lib/utils';
import type { NavItem } from '@/types';

type Props = {
    items?: NavItem[];
    label?: string;
};

export function NavMain({ items = [], label = 'Menu' }: Props) {
    const { isCurrentUrl, isCurrentOrParentUrl } = useCurrentUrl();

    return (
        <SidebarGroup className="min-w-0 px-1 py-0">
            <SidebarGroupLabel className="text-sidebar-foreground/50 text-[10px] font-semibold tracking-widest uppercase">
                {label}
            </SidebarGroupLabel>
            <SidebarMenu>
                {items.map((item) => {
                    const isActive = item.href
                        ? item.title === 'Settings'
                            ? isCurrentOrParentUrl(item.href)
                            : isCurrentUrl(item.href)
                        : false;

                    if (item.disabled || !item.href) {
                        return (
                            <SidebarMenuItem key={item.title}>
                                <Tooltip>
                                    <TooltipTrigger asChild>
                                        <SidebarMenuButton
                                            disabled
                                            className="cursor-not-allowed opacity-40"
                                        >
                                            {item.icon && (
                                                <item.icon className="size-4 shrink-0" />
                                            )}
                                            <span className="min-w-0 flex-1 truncate">
                                                {item.title}
                                            </span>
                                            {item.badge && (
                                                <span className="agri-sidebar-badge shrink-0">
                                                    {item.badge}
                                                </span>
                                            )}
                                        </SidebarMenuButton>
                                    </TooltipTrigger>
                                    <TooltipContent side="right">
                                        Coming soon
                                    </TooltipContent>
                                </Tooltip>
                            </SidebarMenuItem>
                        );
                    }

                    return (
                        <SidebarMenuItem key={item.title}>
                            <SidebarMenuButton
                                asChild
                                isActive={isActive}
                                tooltip={{ children: item.title }}
                                className={cn(
                                    'transition-colors duration-150',
                                    isActive && 'agri-sidebar-nav-active',
                                )}
                            >
                                <Link href={item.href} prefetch>
                                    {item.icon && (
                                        <item.icon className="size-4 shrink-0" />
                                    )}
                                    <span className="min-w-0 flex-1 truncate">
                                        {item.title}
                                    </span>
                                    {item.badge && (
                                        <span className="agri-sidebar-badge shrink-0">
                                            {item.badge}
                                        </span>
                                    )}
                                </Link>
                            </SidebarMenuButton>
                        </SidebarMenuItem>
                    );
                })}
            </SidebarMenu>
        </SidebarGroup>
    );
}
