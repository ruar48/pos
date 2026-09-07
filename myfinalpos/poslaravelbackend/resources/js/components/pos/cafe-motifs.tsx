/**
 * Line-art café motifs used as faint decoration on dashboard tiles, empty
 * states and chart backdrops.
 *
 * They are ornament, never information: every one is `aria-hidden`, inherits
 * `currentColor`, and is drawn in strokes light enough to sit behind text
 * without competing with it. Nothing here reads or reports data.
 */

type MotifProps = {
    className?: string;
    size?: number;
};

export type CafeMotifName =
    | 'cup'
    | 'croissant'
    | 'cake'
    | 'cookie'
    | 'leaf'
    | 'wheat'
    | 'bag'
    | 'monitor'
    | 'beans'
    | 'receipt';

function svgProps(size: number, className?: string) {
    return {
        width: size,
        height: size,
        viewBox: '0 0 64 64',
        fill: 'none',
        stroke: 'currentColor',
        strokeWidth: 1.6,
        strokeLinecap: 'round' as const,
        strokeLinejoin: 'round' as const,
        className,
        'aria-hidden': true,
        focusable: false,
    };
}

function CupMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M12 26h30v12a13 13 0 0 1-13 13h-4a13 13 0 0 1-13-13z" />
            <path d="M42 30h4a7 7 0 0 1 0 14h-4" />
            <path d="M8 55h42" />
            <path d="M22 18c0-3 3-3 3-6M31 18c0-3 3-3 3-6" />
        </svg>
    );
}

function CroissantMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M8 42c6-18 22-30 40-30 4 0 7 3 7 7 0 18-14 32-32 32-4 0-7-3-7-4z" />
            <path d="M20 38c4-8 10-14 18-17M27 45c4-9 11-16 20-19" />
        </svg>
    );
}

function CakeMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M10 52V32l22-12 22 12v20z" />
            <path d="M10 40l22 10 22-10M10 32l22 10 22-10" />
            <path d="M32 20V8" />
            <circle cx="32" cy="6" r="2.5" />
        </svg>
    );
}

function CookieMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <circle cx="32" cy="32" r="22" />
            <circle cx="25" cy="25" r="2.5" />
            <circle cx="39" cy="28" r="2.5" />
            <circle cx="30" cy="39" r="2.5" />
            <circle cx="41" cy="40" r="2" />
        </svg>
    );
}

function LeafMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M32 56C32 30 40 14 56 8c2 22-8 40-24 44z" />
            <path d="M32 56C24 38 18 28 8 24c-1 16 8 28 24 32z" />
            <path d="M32 56V34" />
        </svg>
    );
}

function WheatMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M32 56V22" />
            <path d="M32 24c-8-2-12-8-12-14 7 0 12 4 12 10zM32 24c8-2 12-8 12-14-7 0-12 4-12 10z" />
            <path d="M32 38c-8-2-12-8-12-14 7 0 12 4 12 10zM32 38c8-2 12-8 12-14-7 0-12 4-12 10z" />
        </svg>
    );
}

function BagMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M13 20h38l-4 34H17z" />
            <path d="M23 20v-4a9 9 0 0 1 18 0v4" />
        </svg>
    );
}

function MonitorMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <rect x="7" y="13" width="50" height="32" rx="3" />
            <path d="M25 53h14M32 45v8" />
            <path d="M16 36l8-9 6 6 8-11 10 14" />
        </svg>
    );
}

function BeansMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <ellipse cx="24" cy="26" rx="11" ry="15" transform="rotate(-25 24 26)" />
            <path d="M19 15c4 7 4 15 0 22" transform="rotate(-25 24 26)" />
            <ellipse cx="41" cy="41" rx="9" ry="13" transform="rotate(20 41 41)" />
            <path d="M37 31c3 6 3 13 0 19" transform="rotate(20 41 41)" />
        </svg>
    );
}

function ReceiptMotif({ className, size = 64 }: MotifProps) {
    return (
        <svg {...svgProps(size, className)}>
            <path d="M15 6h34v52l-6-4-6 4-5-4-6 4-6-4-5 4z" />
            <path d="M23 20h18M23 30h18M23 40h11" />
        </svg>
    );
}

const MOTIFS: Record<
    CafeMotifName,
    (props: MotifProps) => React.ReactElement
> = {
    cup: CupMotif,
    croissant: CroissantMotif,
    cake: CakeMotif,
    cookie: CookieMotif,
    leaf: LeafMotif,
    wheat: WheatMotif,
    bag: BagMotif,
    monitor: MonitorMotif,
    beans: BeansMotif,
    receipt: ReceiptMotif,
};

export function CafeMotif({
    name,
    className,
    size = 64,
}: {
    name: CafeMotifName;
} & MotifProps) {
    const Motif = MOTIFS[name];
    return <Motif className={className} size={size} />;
}

/**
 * Larger cup-and-foliage vignette for empty states and chart backdrops.
 */
export function CafeVignette({ className }: { className?: string }) {
    return (
        <svg
            viewBox="0 0 220 150"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
            strokeLinejoin="round"
            className={className}
            aria-hidden
            focusable={false}
        >
            {/* cup */}
            <path d="M66 64h58v24a26 26 0 0 1-26 26h-6a26 26 0 0 1-26-26z" />
            <path d="M124 72h9a13 13 0 0 1 0 26h-9" />
            <path d="M52 120h86" />
            {/* saucer */}
            <path d="M62 120c0 6 16 10 33 10s33-4 33-10" />
            {/* foliage left */}
            <path d="M52 116c-14-6-24-18-27-32 15 1 27 10 31 24" />
            <path d="M44 112c-10-10-13-24-9-36 11 7 16 20 14 33" />
            {/* foliage right */}
            <path d="M140 118c14-4 26-15 31-29-15-1-28 7-33 21" />
            <path d="M150 112c11-9 15-23 12-35-11 6-18 19-17 32" />
            {/* steam */}
            <path d="M84 50c0-8 8-8 8-16M104 50c0-8 8-8 8-16" />
        </svg>
    );
}
