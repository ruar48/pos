import { Head } from '@inertiajs/react';
import { LiveMonitorPanel } from '@/components/pos/live-monitor-panel';

export default function PosLiveWall() {
    return (
        <>
            <Head title="Live POS Wall" />
            <LiveMonitorPanel wallMode />
        </>
    );
}

PosLiveWall.layout = {
    breadcrumbs: [],
};
