import type { ReactNode } from 'react';

export default function AppWallLayout({ children }: { children: ReactNode }) {
    return (
        <div className="live-monitor-wall min-h-svh bg-background text-foreground">
            {children}
        </div>
    );
}
