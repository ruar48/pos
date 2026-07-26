import { Head, router } from '@inertiajs/react';
import { useEffect } from 'react';
import { login } from '@/routes';

export default function TwoFactorChallenge() {
    useEffect(() => {
        router.visit(login());
    }, []);

    return (
        <>
            <Head title="Two-factor challenge" />
            <p className="text-sm text-muted-foreground">
                Two-factor authentication is disabled for this POS.
            </p>
        </>
    );
}
