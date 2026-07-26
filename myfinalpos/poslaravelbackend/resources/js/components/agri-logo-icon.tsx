import type { SVGAttributes } from 'react';

export default function AgriLogoIcon(props: SVGAttributes<SVGElement>) {
    return (
        <svg
            {...props}
            viewBox="0 0 32 32"
            fill="none"
            xmlns="http://www.w3.org/2000/svg"
        >
            <path
                d="M16 4C16 4 10 8 10 14C10 17.3137 12.6863 20 16 20C19.3137 20 22 17.3137 22 14C22 8 16 4 16 4Z"
                fill="currentColor"
                fillOpacity="0.9"
            />
            <path
                d="M16 20V28"
                stroke="currentColor"
                strokeWidth="2.5"
                strokeLinecap="round"
            />
            <path
                d="M12 24H20"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
            />
            <path
                d="M8 12C6 14 5 16.5 5 19"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeOpacity="0.6"
            />
            <path
                d="M24 12C26 14 27 16.5 27 19"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeOpacity="0.6"
            />
        </svg>
    );
}
