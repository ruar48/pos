import { Head, router } from '@inertiajs/react';
import { useEffect } from 'react';
import { dashboard } from '@/routes';

export default function VerifyEmail() {
    useEffect(() => {
        router.visit(dashboard());
    }, []);

    return (
        <>
            <Head title="Verify email" />
            <p className="text-sm text-muted-foreground">
                Email verification is not required for POS accounts.
            </p>
        </>
    );
}
