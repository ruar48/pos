const GENERIC =
    'Something went wrong. Please try again or contact support.';

const TECHNICAL_PATTERNS = [
    /SQLSTATE/i,
    /General error:\s*\d+/i,
    /Connection:\s*mysql/i,
    /Host:\s*[\d.]+/i,
    /Port:\s*\d+/i,
    /Database:\s*\w+/i,
    /\bSQL:\s/i,
    /INSERT INTO/i,
    /UPDATE\s+`/i,
    /SELECT\s+/i,
    /PDOException/i,
    /QueryException/i,
    /doesn't have a default value/i,
    /Duplicate entry/i,
    /foreign key constraint/i,
    /\.php on line \d+/i,
];

function isTechnicalApiError(message: string): boolean {
    return TECHNICAL_PATTERNS.some((pattern) => pattern.test(message));
}

function friendlyApiErrorMessage(message: string): string {
    if (/doesn't have a default value|1364/i.test(message)) {
        return 'We could not complete this action. Please ask your administrator to check the server database setup.';
    }
    if (/Duplicate entry/i.test(message)) {
        return 'This record already exists. Please refresh and try again.';
    }
    if (/foreign key constraint/i.test(message)) {
        return 'Related data is missing or was removed. Please refresh and try again.';
    }
    if (/SQLSTATE|Connection:\s*mysql|INSERT INTO|UPDATE `/i.test(message)) {
        return 'We could not save your changes. Please try again or contact support.';
    }
    return GENERIC;
}

export function cleanApiErrorMessage(raw: string): string {
    let message = raw.trim();
    if (message.startsWith('Exception:')) {
        message = message.slice('Exception:'.length).trim();
    }
    for (const prefix of [
        'Server error: ',
        'Failed to load transaction report: ',
        'Could not save image: ',
    ]) {
        if (message.startsWith(prefix)) {
            message = message.slice(prefix.length).trim();
        }
    }
    message = message
        .replace(/<[^>]*>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();

    if (isTechnicalApiError(message)) {
        return friendlyApiErrorMessage(message);
    }

    if (message.length > 160) {
        message = `${message.slice(0, 160)}...`;
    }

    return message || GENERIC;
}
