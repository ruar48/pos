import { cleanApiErrorMessage } from '@/lib/api-error-message';

type LaravelJsonResponse<T = Record<string, unknown>> = {
    success: boolean;
    message?: string;
} & T;

function readXsrfToken(): string {
    const match = document.cookie.match(/XSRF-TOKEN=([^;]+)/);
    return match ? decodeURIComponent(match[1]) : '';
}

export async function laravelFetch<T = Record<string, unknown>>(
    url: string,
    init?: RequestInit,
): Promise<LaravelJsonResponse<T>> {
    const response = await fetch(url, {
        credentials: 'same-origin',
        headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
            'X-XSRF-TOKEN': readXsrfToken(),
            ...(init?.headers ?? {}),
        },
        ...init,
    });

    const raw = await response.text();
    let body: LaravelJsonResponse<T>;

    try {
        body = JSON.parse(raw) as LaravelJsonResponse<T>;
    } catch {
        const snippet = raw.replace(/\s+/g, ' ').slice(0, 120);
        throw new Error(
            response.ok
                ? 'Server returned an invalid response.'
                : `Request failed (${response.status})${snippet ? `: ${snippet}` : ''}`,
        );
    }

    if (body.success === false) {
        throw new Error(
            cleanApiErrorMessage(
                body.message ?? `Request failed (${response.status})`,
            ),
        );
    }

    if (!response.ok) {
        throw new Error(
            cleanApiErrorMessage(
                body.message ?? `Request failed (${response.status})`,
            ),
        );
    }

    return body;
}
