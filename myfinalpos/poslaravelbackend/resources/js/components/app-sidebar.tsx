import { Link } from '@inertiajs/react';
import {
    ArrowLeftRight,
    BarChart3,
    Banknote,
    Gift,
    Home,
    LayoutGrid,
    Lock,
    MonitorSmartphone,
    Package,
    Tag,
    Users,
    Wallet,
    Warehouse,
} from 'lucide-react';
import AppLogo from '@/components/app-logo';
import { NavLogout } from '@/components/nav-logout';
import { NavMain } from '@/components/nav-main';
import {
    Sidebar,
    SidebarContent,
    SidebarFooter,
    SidebarHeader,
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
    SidebarSeparator,
} from '@/components/ui/sidebar';
import { dashboard } from '@/routes';
import { edit as editProfile } from '@/routes/profile';
import type { NavItem } from '@/types';

const mainNavItems: NavItem[] = [
    {
        title: 'Dashboard',
        href: dashboard(),
        icon: LayoutGrid,
    },
    {
        title: 'Live POS Monitor',
        href: '/pos',
        icon: MonitorSmartphone,
    },
];

const operationsNavItems: NavItem[] = [
    {
        title: 'Transactions',
        href: '/pos/transactions',
        icon: ArrowLeftRight,
    },
    {
        title: 'Reports',
        href: '/pos/reports',
        icon: BarChart3,
    },
    {
        title: 'Items',
        href: '/pos/items',
        icon: Package,
    },
    {
        title: 'Inventory',
        href: '/pos/inventory',
        icon: Warehouse,
    },
    {
        title: 'Promotions',
        href: '/pos/promotions',
        icon: Tag,
    },
];

const managementNavItems: NavItem[] = [
    {
        title: 'Staff',
        href: '/pos/staff',
        icon: Users,
    },
    {
        title: 'Payroll',
        href: '/pos/payroll',
        icon: Banknote,
    },
    {
        title: 'Loyalty & Customers',
        href: '/pos/loyalty',
        icon: Gift,
    },
    {
        title: 'Cash Drawer',
        href: '/pos/cash-drawer',
        icon: Wallet,
    },
];

const footerNavItems: NavItem[] = [
    {
        title: 'Settings',
        href: editProfile(),
        icon: Lock,
    },
];

export function AppSidebar() {
    return (
        <Sidebar
            collapsible="icon"
            variant="sidebar"
            className="overflow-hidden border-r border-sidebar-border/50"
        >
            <SidebarHeader className="border-b border-sidebar-border/40 px-2 py-4">
                <SidebarMenu>
                    <SidebarMenuItem>
                        <SidebarMenuButton
                            size="lg"
                            asChild
                            className="hover:bg-sidebar-accent/60"
                        >
                            <Link href={dashboard()} prefetch>
                                <AppLogo />
                            </Link>
                        </SidebarMenuButton>
                    </SidebarMenuItem>
                </SidebarMenu>
            </SidebarHeader>

            <SidebarContent className="min-w-0 gap-0 overflow-x-hidden py-3">
                <NavMain items={mainNavItems} label="Overview" />
                <SidebarSeparator className="my-2 bg-sidebar-border/40" />
                <NavMain items={operationsNavItems} label="Operations" />
                <SidebarSeparator className="my-2 bg-sidebar-border/40" />
                <NavMain items={managementNavItems} label="Management" />
            </SidebarContent>

            <SidebarFooter className="min-w-0 overflow-x-hidden border-t border-sidebar-border/40 px-1 py-3">
                <NavMain items={footerNavItems} label="System" />
                <div className="mt-1 px-1">
                    <NavLogout />
                </div>
            </SidebarFooter>
        </Sidebar>
    );
}
