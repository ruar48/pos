import { Head, router } from '@inertiajs/react';
import { useEffect } from 'react';
import { login } from '@/routes';

export default function Register() {
    useEffect(() => {
        router.visit(login());
    }, []);

    return (
        <>
            <Head title="Register" />
            <p className="text-sm text-muted-foreground">
                Registration is disabled. Redirecting to login...
            </p>
        </>
    );
}
