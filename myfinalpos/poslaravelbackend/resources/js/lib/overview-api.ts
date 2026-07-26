import { laravelFetch } from '@/lib/laravel-fetch';
import { health } from '@/routes/pos';

export async function fetchAppHealth() {
    return laravelFetch<{
        database?: string;
        database_connected?: boolean;
        database_error?: string | null;
    }>(health.url());
}
