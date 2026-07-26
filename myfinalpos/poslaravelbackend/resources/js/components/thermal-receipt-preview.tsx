import { buildReceiptPreviewLines } from '@/lib/receipt-preview';
import type { ReceiptStore } from '@/lib/store-settings-api';

type Props = {
    store: ReceiptStore;
    currencySymbol: string;
    taxRate: number;
};

export function ThermalReceiptPreview({
    store,
    currencySymbol,
    taxRate,
}: Props) {
    const lines = buildReceiptPreviewLines(store, currencySymbol, taxRate);
    const logoSrc = store.logo_image_base64
        ? store.logo_image_base64.startsWith('data:')
            ? store.logo_image_base64
            : `data:image/png;base64,${store.logo_image_base64}`
        : store.logo_image_url;

    return (
        <div className="mx-auto w-full max-w-[280px] rounded-sm border border-border/80 bg-white px-3 py-4 shadow-sm">
            {logoSrc && (
                <div className="mb-2 flex justify-center">
                    <img
                        src={logoSrc}
                        alt="Store logo"
                        className="max-h-16 max-w-[120px] object-contain"
                    />
                </div>
            )}
            <pre className="whitespace-pre-wrap text-center font-mono text-[10px] leading-[1.35] text-neutral-900">
                {lines.join('\n')}
            </pre>
        </div>
    );
}
