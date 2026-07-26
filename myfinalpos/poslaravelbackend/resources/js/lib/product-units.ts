export type ProductUnitOption = {
    value: string;
    label: string;
};

/** Mirrors the Flutter app's product_units.dart so units stay compatible. */
export const productUnitOptions: ProductUnitOption[] = [
    { value: 'pc', label: 'Piece (pc)' },
    { value: 'kg', label: 'Kilo (kg)' },
    { value: 'g', label: 'Gram (g)' },
    { value: 'bag', label: 'Bag' },
    { value: 'sack', label: 'Sack' },
    { value: 'box', label: 'Box' },
    { value: 'bottle', label: 'Bottle' },
    { value: 'roll', label: 'Roll' },
    { value: 'tray', label: 'Tray' },
    { value: 'bundle', label: 'Bundle' },
    { value: 'liter', label: 'Liter (L)' },
    { value: 'ton', label: 'Ton' },
];

export function normalizeProductUnit(raw: string): string {
    const value = raw.trim().toLowerCase();
    switch (value) {
        case 'pcs':
        case 'piece':
        case 'pieces':
            return 'pc';
        case 'kilo':
        case 'kilogram':
        case 'kilograms':
            return 'kg';
        case 'gram':
        case 'grams':
            return 'g';
        case 'l':
        case 'litre':
        case 'litres':
        case 'liter':
            return 'liter';
        default:
            return value;
    }
}

export function parseProductUnits(raw?: string | null): string[] {
    if (!raw || raw.trim() === '') return ['pc'];
    const units = raw
        .split(',')
        .map(normalizeProductUnit)
        .filter((u) => u !== '');
    if (units.length === 0) return ['pc'];
    return Array.from(new Set(units));
}

export function encodeProductUnits(units: Iterable<string>): string {
    const normalized = Array.from(
        new Set(
            Array.from(units)
                .map(normalizeProductUnit)
                .filter((u) => u !== ''),
        ),
    );
    if (normalized.length === 0) return 'pc';
    normalized.sort();
    return normalized.join(',');
}

export function primaryProductUnit(raw?: string | null): string {
    return parseProductUnits(raw)[0];
}

export function productUnitLabel(value: string): string {
    const normalized = normalizeProductUnit(value);
    return (
        productUnitOptions.find((o) => o.value === normalized)?.label ??
        normalized
    );
}

export function displayProductUnits(raw?: string | null): string {
    return parseProductUnits(raw).join(', ');
}
