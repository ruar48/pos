import { useEffect, useState } from 'react';

export type LiveMonitorDensity = 'phone' | 'tablet' | 'desktop' | 'tv' | 'ultra';

export type LiveMonitorLayout = {
    width: number;
    density: LiveMonitorDensity;
    columns: number;
    isPhone: boolean;
    isTablet: boolean;
    isDesktop: boolean;
    isTv: boolean;
    isCompactChrome: boolean;
};

const QUERIES = {
    phone: '(max-width: 639px)',
    tablet: '(min-width: 640px) and (max-width: 1023px)',
    desktop: '(min-width: 1024px) and (max-width: 1919px)',
    tv: '(min-width: 1920px) and (max-width: 2559px)',
    ultra: '(min-width: 2560px)',
} as const;

const DEFAULT_LAYOUT: LiveMonitorLayout = {
    width: 1280,
    density: 'desktop',
    columns: 3,
    isPhone: false,
    isTablet: false,
    isDesktop: true,
    isTv: false,
    isCompactChrome: false,
};

function computeLayout(width: number): LiveMonitorLayout {
    const isUltra = width >= 2560;
    const isTv = width >= 1920 && width < 2560;
    const isDesktop = width >= 1024 && width < 1920;
    const isTablet = width >= 640 && width < 1024;
    const isPhone = width < 640;

    let density: LiveMonitorDensity = 'desktop';
    let columns = 3;

    if (isUltra) {
        density = 'ultra';
        columns = 6;
    } else if (isTv) {
        density = 'tv';
        columns = 5;
    } else if (isDesktop) {
        density = 'desktop';
        columns = width >= 1536 ? 4 : 3;
    } else if (isTablet) {
        density = 'tablet';
        columns = 2;
    } else {
        density = 'phone';
        columns = 1;
    }

    return {
        width,
        density,
        columns,
        isPhone,
        isTablet,
        isDesktop,
        isTv: isTv || isUltra,
        isCompactChrome: isPhone || isTablet,
    };
}

function readLayout(): LiveMonitorLayout {
    if (typeof window === 'undefined') {
        return DEFAULT_LAYOUT;
    }

    return computeLayout(window.innerWidth);
}

function layoutsEqual(a: LiveMonitorLayout, b: LiveMonitorLayout): boolean {
    return (
        a.width === b.width &&
        a.density === b.density &&
        a.columns === b.columns &&
        a.isPhone === b.isPhone &&
        a.isTablet === b.isTablet &&
        a.isDesktop === b.isDesktop &&
        a.isTv === b.isTv &&
        a.isCompactChrome === b.isCompactChrome
    );
}

export function useLiveMonitorLayout(): LiveMonitorLayout {
    const [layout, setLayout] = useState<LiveMonitorLayout>(DEFAULT_LAYOUT);

    useEffect(() => {
        const update = () => {
            const next = readLayout();
            setLayout((current) =>
                layoutsEqual(current, next) ? current : next,
            );
        };

        update();

        const mediaLists = Object.values(QUERIES).map((query) =>
            window.matchMedia(query),
        );

        mediaLists.forEach((mql) => mql.addEventListener('change', update));
        window.addEventListener('resize', update);

        return () => {
            mediaLists.forEach((mql) =>
                mql.removeEventListener('change', update),
            );
            window.removeEventListener('resize', update);
        };
    }, []);

    return layout;
}
