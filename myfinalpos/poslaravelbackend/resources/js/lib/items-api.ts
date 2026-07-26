import { laravelFetch } from '@/lib/laravel-fetch';
import { categories, products } from '@/routes/pos/items';
import { store as storeCategory } from '@/routes/pos/items/categories';
import {
    exportMethod as exportProductsRoute,
    importMethod as importProductsRoute,
    store as storeProduct,
    update as updateProduct,
} from '@/routes/pos/items/products';

export type PosCategory = {
    id: number;
    name: string;
    icon?: string | null;
    description?: string | null;
};

export type PosProduct = {
    id: number;
    category_id: number;
    category_name: string;
    name: string;
    option?: string | null;
    description?: string | null;
    sku?: string | null;
    barcode?: string | null;
    price: number | string;
    cost_price?: number | string | null;
    deal?: string | null;
    stock?: number | string | null;
    reorder_level?: number | string | null;
    image_url?: string | null;
    status?: string | null;
    updated_at?: string | null;
};

export type ProductInput = {
    id?: number;
    name: string;
    option?: string | null;
    category: string;
    price: number;
    sku?: string;
    barcode?: string;
    cost_price?: number | null;
    deal?: string | null;
    stock?: number;
    reorder_level?: number;
    description?: string;
    image_url?: string;
    image_base64?: string;
    image_filename?: string;
    image_mime_type?: string;
};

export type ProductExportRow = Record<string, string | number | null>;

export type ItemsCatalogCache = {
    categories: PosCategory[];
    products: PosProduct[];
    savedAt: number;
};

let catalogCache: ItemsCatalogCache | null = null;
let catalogInFlight: Promise<ItemsCatalogCache> | null = null;

export function getItemsCatalogCache(): ItemsCatalogCache | null {
    return catalogCache;
}

export function setItemsCatalogCache(
    categoriesList: PosCategory[],
    productsList: PosProduct[],
): ItemsCatalogCache {
    catalogCache = {
        categories: categoriesList,
        products: productsList,
        savedAt: Date.now(),
    };
    return catalogCache;
}

export function clearItemsCatalogCache(): void {
    catalogCache = null;
    catalogInFlight = null;
}

export async function fetchCategories() {
    return laravelFetch<{ data: PosCategory[] }>(categories.url());
}

export async function createCategory(input: {
    name: string;
    description?: string;
    icon?: string;
}) {
    clearItemsCatalogCache();
    return laravelFetch<{ data: PosCategory }>(storeCategory.url(), {
        method: 'POST',
        body: JSON.stringify(input),
    });
}

export async function updateCategory(input: {
    id: number;
    name: string;
    description?: string;
    icon?: string;
}) {
    clearItemsCatalogCache();
    return laravelFetch<{ data: PosCategory; message?: string }>(
        storeCategory.url(),
        {
            method: 'PUT',
            body: JSON.stringify(input),
        },
    );
}

export async function fetchProducts() {
    return laravelFetch<{ data: PosProduct[] }>(products.url());
}

/** Load categories + products, with in-memory cache for fast revisits. */
export async function loadItemsCatalog(options?: {
    force?: boolean;
}): Promise<ItemsCatalogCache> {
    if (!options?.force && catalogCache) {
        return catalogCache;
    }

    if (!options?.force && catalogInFlight) {
        return catalogInFlight;
    }

    catalogInFlight = (async () => {
        const [catRes, prodRes] = await Promise.all([
            fetchCategories(),
            fetchProducts(),
        ]);
        return setItemsCatalogCache(catRes.data ?? [], prodRes.data ?? []);
    })();

    try {
        return await catalogInFlight;
    } finally {
        catalogInFlight = null;
    }
}

export async function saveProduct(input: ProductInput) {
    const isUpdate = typeof input.id === 'number' && input.id > 0;
    const route = isUpdate ? updateProduct : storeProduct;

    clearItemsCatalogCache();
    return laravelFetch<{ data: PosProduct; message?: string }>(route.url(), {
        method: isUpdate ? 'PUT' : 'POST',
        body: JSON.stringify(input),
    });
}

export async function deleteProduct(id: number) {
    clearItemsCatalogCache();
    return laravelFetch<{ message?: string }>(updateProduct.url(), {
        method: 'DELETE',
        body: JSON.stringify({ id }),
    });
}

export async function exportProducts() {
    return laravelFetch<{
        headers: string[];
        rows: ProductExportRow[];
    }>(exportProductsRoute.url());
}

export async function importProducts(file: File) {
    const formData = new FormData();
    formData.append('file', file);
    const match = document.cookie.match(/XSRF-TOKEN=([^;]+)/);
    const xsrf = match ? decodeURIComponent(match[1]) : '';

    const response = await fetch(importProductsRoute.url(), {
        method: 'POST',
        body: formData,
        credentials: 'same-origin',
        headers: {
            Accept: 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-XSRF-TOKEN': xsrf,
        },
    });

    const payload = (await response.json()) as {
        success?: boolean;
        message?: string;
        data?: {
            created: number;
            updated: number;
            skipped: number;
            errors: string[];
        };
    };

    if (!response.ok || !payload.success) {
        throw new Error(payload.message ?? 'Import failed');
    }

    clearItemsCatalogCache();
    return payload;
}
