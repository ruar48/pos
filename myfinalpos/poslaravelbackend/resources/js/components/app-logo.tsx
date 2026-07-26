import { BrandLogo } from '@/components/brand-logo';
import { BRAND } from '@/lib/brand';

export default function AppLogo() {
    return (
        <BrandLogo
            size="md"
            tone="on-dark"
            subtitle={BRAND.posSubtitle}
            nameClassName="text-sidebar-foreground"
            subtitleClassName="text-sidebar-foreground/60"
        />
    );
}
