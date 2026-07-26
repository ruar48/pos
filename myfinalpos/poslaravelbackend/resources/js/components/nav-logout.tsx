import { Link, router } from '@inertiajs/react';
import { LogOut } from 'lucide-react';
import {
    SidebarMenu,
    SidebarMenuButton,
    SidebarMenuItem,
} from '@/components/ui/sidebar';
import { useMobileNavigation } from '@/hooks/use-mobile-navigation';
import { logout } from '@/routes';

export function NavLogout() {
    const cleanup = useMobileNavigation();

    const handleLogout = () => {
        cleanup();
        router.flushAll();
    };

    return (
        <SidebarMenu>
            <SidebarMenuItem>
                <SidebarMenuButton
                    asChild
                    tooltip={{ children: 'Log out' }}
                    className="text-sidebar-foreground/70 hover:bg-destructive/15 hover:text-red-200"
                >
                    <Link
                        href={logout()}
                        as="button"
                        onClick={handleLogout}
                        data-test="sidebar-logout-button"
                    >
                        <LogOut className="size-4" />
                        <span>Log out</span>
                    </Link>
                </SidebarMenuButton>
            </SidebarMenuItem>
        </SidebarMenu>
    );
}
