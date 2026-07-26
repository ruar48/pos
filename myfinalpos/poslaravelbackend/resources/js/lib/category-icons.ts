import {
    Boxes,
    Bug,
    Droplets,
    Flower2,
    PawPrint,
    Recycle,
    Shapes,
    Shield,
    Sprout,
    Stethoscope,
    Tractor,
    Trees,
    Wheat,
    Wrench,
    type LucideIcon,
} from 'lucide-react';

export type CategoryIconOption = {
    key: string;
    label: string;
    icon: LucideIcon;
};

/**
 * Keys mirror the Flutter app's category_icons.dart so a category icon saved
 * on the web renders correctly on the tablet, and vice versa.
 */
export const categoryIconOptions: CategoryIconOption[] = [
    { key: 'eco', label: 'Seeds', icon: Sprout },
    { key: 'grass', label: 'Crops', icon: Sprout },
    { key: 'compost', label: 'Fertilizer', icon: Recycle },
    { key: 'shield', label: 'Protection', icon: Shield },
    { key: 'pest_control', label: 'Pesticide', icon: Bug },
    { key: 'pets', label: 'Animal Feed', icon: PawPrint },
    { key: 'build', label: 'Tools', icon: Wrench },
    { key: 'agriculture', label: 'Farm', icon: Tractor },
    { key: 'water_drop', label: 'Irrigation', icon: Droplets },
    { key: 'local_florist', label: 'Plants', icon: Flower2 },
    { key: 'inventory_2', label: 'Supplies', icon: Boxes },
    { key: 'medical_services', label: 'Veterinary', icon: Stethoscope },
    { key: 'grain', label: 'Grain', icon: Wheat },
    { key: 'park', label: 'Organic', icon: Trees },
    { key: 'category', label: 'General', icon: Shapes },
];

export function suggestCategoryIconKey(name: string): string {
    const n = name.trim().toLowerCase();
    if (n === '') return 'category';

    if (n.includes('seedling') || n.includes('nursery') || n.includes('plant'))
        return 'local_florist';
    if (n.includes('seed')) return 'eco';
    if (n.includes('fertil') || n.includes('compost')) return 'compost';
    if (
        n.includes('pestic') ||
        n.includes('herb') ||
        n.includes('fungic') ||
        n.includes('insect')
    )
        return 'shield';
    if (
        n.includes('feed') ||
        n.includes('animal') ||
        n.includes('livestock') ||
        n.includes('poultry') ||
        n.includes('broiler') ||
        n.includes('layer')
    )
        return 'pets';
    if (
        n.includes('tool') ||
        n.includes('equipment') ||
        n.includes('machinery') ||
        n.includes('tractor')
    )
        return 'build';
    if (
        n.includes('irrig') ||
        n.includes('water') ||
        n.includes('drip') ||
        n.includes('sprinkler')
    )
        return 'water_drop';
    if (
        n.includes('harvest') ||
        n.includes('crate') ||
        n.includes('sack') ||
        n.includes('supply') ||
        n.includes('supplies')
    )
        return 'inventory_2';
    if (n.includes('vet') || n.includes('medic')) return 'medical_services';
    if (n.includes('grain') || n.includes('rice') || n.includes('corn'))
        return 'grain';
    if (n.includes('organic')) return 'park';

    return 'category';
}

export function categoryIconOptionForKey(key: string): CategoryIconOption {
    return (
        categoryIconOptions.find((o) => o.key === key) ??
        categoryIconOptions[categoryIconOptions.length - 1]
    );
}

export function resolveCategoryIcon(
    iconKey?: string | null,
    categoryName?: string | null,
): LucideIcon {
    const key =
        iconKey && iconKey.trim() !== ''
            ? iconKey.trim()
            : suggestCategoryIconKey(categoryName ?? '');
    return categoryIconOptionForKey(key).icon;
}
