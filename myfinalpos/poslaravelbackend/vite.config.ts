import inertia from '@inertiajs/vite';
import { wayfinder } from '@laravel/vite-plugin-wayfinder';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import laravel from 'laravel-vite-plugin';
import { bunny } from 'laravel-vite-plugin/fonts';
import { defineConfig, loadEnv } from 'vite';

export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, process.cwd(), '');
    const devServerUrl =
        env.VITE_DEV_SERVER_URL?.replace(/\/$/, '') ??
        'http://127.0.0.1:5173';

    return {
        server: {
            // Listen on all interfaces for tablets/other PCs.
            host: '0.0.0.0',
            port: 5173,
            strictPort: true,
            // Do not set server.origin — it breaks CORS when Laravel runs on :8000.
            cors: {
                origin: [
                    'http://127.0.0.1:8000',
                    'http://localhost:8000',
                    'http://10.179.102.85:8000',
                ],
            },
            hmr: {
                host: new URL(devServerUrl).hostname,
            },
        },
        plugins: [
            laravel({
            input: ['resources/css/app.css', 'resources/js/app.tsx'],
            refresh: true,
            fonts: [
                bunny('Plus Jakarta Sans', {
                    weights: [400, 500, 600, 700],
                }),
            ],
            }),
            inertia(),
            react({
                babel: {
                    plugins: ['babel-plugin-react-compiler'],
                },
            }),
            tailwindcss(),
            wayfinder({
                formVariants: true,
            }),
        ],
    };
});
