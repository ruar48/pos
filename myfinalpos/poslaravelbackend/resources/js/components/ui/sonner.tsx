import { useFlashToast } from '@/hooks/use-flash-toast';
import { useAppearance } from '@/hooks/use-appearance';
import { Toaster as Sonner, type ToasterProps } from 'sonner';

function Toaster({ ...props }: ToasterProps) {
    const { appearance } = useAppearance();

    useFlashToast();

    return (
        <Sonner
            theme={appearance}
            className="toaster group"
            position="top-right"
            richColors
            toastOptions={{
                classNames: {
                    toast: 'agri-toast',
                },
            }}
            style={
                {
                    '--normal-bg': 'var(--popover)',
                    '--normal-text': 'var(--popover-foreground)',
                    '--normal-border': 'var(--border)',
                    '--success-bg': 'var(--agri-toast-success)',
                    '--success-border': 'var(--agri-toast-success)',
                    '--success-text': 'var(--agri-toast-foreground)',
                    '--error-bg': 'var(--agri-toast-error)',
                    '--error-border': 'var(--agri-toast-error)',
                    '--error-text': 'var(--agri-toast-foreground)',
                    '--warning-bg': 'var(--agri-toast-warning)',
                    '--warning-border': 'var(--agri-toast-warning)',
                    '--warning-text': 'var(--agri-toast-foreground)',
                    '--info-bg': 'var(--agri-toast-info)',
                    '--info-border': 'var(--agri-toast-info)',
                    '--info-text': 'var(--agri-toast-foreground)',
                } as React.CSSProperties
            }
            {...props}
        />
    );
}

export { Toaster };
