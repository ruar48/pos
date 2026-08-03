import { Head, router } from '@inertiajs/react';
import {
    AlertTriangle,
    ArrowLeft,
    Boxes,
    Download,
    ExternalLink,
    Layers,
    Loader2,
    Maximize2,
    Minimize2,
    Package,
    Pencil,
    Plus,
    Save,
    Search,
    Tag,
    Trash2,
    Upload,
    X,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent, type ReactNode, type RefObject } from 'react';
import { toast } from 'sonner';
import { PageHeader } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from '@/components/ui/select';
import {
    categoryIconOptions,
    resolveCategoryIcon,
    suggestCategoryIconKey,
} from '@/lib/category-icons';
import {
    createCategory,
    deleteProduct,
    exportProducts,
    fetchCategories,
    fetchProductsPage,
    importProducts,
    saveProduct,
    updateCategory,
    type PosCategory,
    type PosProduct,
    type ProductInput,
} from '@/lib/items-api';
import { cn } from '@/lib/utils';
import { dashboard } from '@/routes';

const ALL = '__all__';

function toNumber(value: number | string | null | undefined): number {
    if (value === null || value === undefined || value === '') return 0;
    const n = typeof value === 'number' ? value : parseFloat(value);
    return Number.isFinite(n) ? n : 0;
}

function formatMoney(value: number | string | null | undefined): string {
    return toNumber(value).toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

type ItemTableRow = {
    key: string;
    index: number;
    product: PosProduct;
    isPending?: boolean;
};

function buildItemTableRows(products: PosProduct[]): ItemTableRow[] {
    return products.map((product, index) => ({
        key: `${product.id}`,
        index: index + 1,
        product,
    }));
}

function tableRowPrice(row: ItemTableRow): number {
    return toNumber(row.product.price);
}

function tableRowCost(row: ItemTableRow): number | null {
    const raw = row.product.cost_price;
    if (raw === null || raw === undefined || raw === '') {
        return null;
    }
    return toNumber(raw);
}

function tableRowDeal(row: ItemTableRow): string {
    return row.product.deal?.trim() ?? '';
}

function tableRowOption(row: ItemTableRow): string {
    return row.product.option?.trim() ?? '';
}

function tableRowStock(row: ItemTableRow): number {
    return toNumber(row.product.stock);
}

function tableRowReorder(row: ItemTableRow): number {
    return toNumber(row.product.reorder_level) || 5;
}

function productToPayload(product: PosProduct): ProductInput {
    return {
        id: product.id,
        name: product.name,
        option: product.option?.trim() || null,
        category: product.category_name,
        price: toNumber(product.price),
        cost_price:
            product.cost_price === null ||
            product.cost_price === undefined ||
            product.cost_price === ''
                ? null
                : toNumber(product.cost_price),
        deal: product.deal?.trim() || null,
        stock: toNumber(product.stock),
        reorder_level: toNumber(product.reorder_level) || 5,
        description: product.description?.trim() || undefined,
    };
}

function mergeProductWithPendingEdits(
    product: PosProduct,
    edits?: Partial<ProductInput>,
): PosProduct {
    if (!edits) {
        return product;
    }

    return {
        ...product,
        category_name: edits.category ?? product.category_name,
        name: edits.name ?? product.name,
        option: edits.option !== undefined ? edits.option : product.option,
        price: edits.price ?? product.price,
        cost_price:
            edits.cost_price !== undefined
                ? edits.cost_price
                : product.cost_price,
        deal: edits.deal !== undefined ? edits.deal : product.deal,
        stock: edits.stock ?? product.stock,
        reorder_level: edits.reorder_level ?? product.reorder_level,
        description: edits.description ?? product.description,
    };
}

function applyInlineFieldToPayload(
    payload: ProductInput,
    field: InlineField,
    rawValue: InlineValue,
): Partial<ProductInput> {
    if (field === 'category' && typeof rawValue === 'string') {
        const category = rawValue.trim();
        if (category === '') {
            throw new Error('Category is required');
        }
        return { category };
    }

    if (field === 'name' && typeof rawValue === 'string') {
        const name = rawValue.trim();
        if (name === '') {
            throw new Error('Product name is required');
        }
        return { name };
    }

    if (field === 'option' && typeof rawValue === 'string') {
        const option = rawValue.trim();
        if (option.length > 120) {
            throw new Error('Option must be 120 characters or less');
        }
        return { option: option === '' ? null : option };
    }

    if (
        field === 'price' &&
        rawValue !== null &&
        typeof rawValue === 'number'
    ) {
        if (rawValue < 0) {
            throw new Error('Price cannot be negative');
        }
        return { price: rawValue };
    }

    if (field === 'cost_price') {
        const cost = rawValue as number | null;
        if (cost !== null && cost < 0) {
            throw new Error('Cost cannot be negative');
        }
        return { cost_price: cost };
    }

    if (field === 'deal' && typeof rawValue === 'string') {
        const deal = rawValue.trim();
        if (deal.length > DEAL_MAX_LENGTH) {
            throw new Error(
                `Deal must be ${DEAL_MAX_LENGTH} characters or less`,
            );
        }
        return { deal: deal === '' ? null : deal };
    }

    if (
        field === 'stock' &&
        rawValue !== null &&
        typeof rawValue === 'number'
    ) {
        if (rawValue < 0) {
            throw new Error('Stock cannot be negative');
        }
        return { stock: rawValue };
    }

    return {};
}

function applyInlineFieldToDraft(
    draft: NewProductDraft,
    field: InlineField,
    rawValue: InlineValue,
): NewProductDraft {
    if (field === 'category' && typeof rawValue === 'string') {
        const category = rawValue.trim();
        if (category === '') {
            throw new Error('Category is required');
        }
        return { ...draft, category };
    }

    if (field === 'name' && typeof rawValue === 'string') {
        const name = rawValue.trim();
        if (name === '') {
            throw new Error('Product name is required');
        }
        return { ...draft, name };
    }

    if (field === 'option' && typeof rawValue === 'string') {
        const option = rawValue.trim();
        if (option.length > 120) {
            throw new Error('Option must be 120 characters or less');
        }
        return { ...draft, option };
    }

    if (
        field === 'price' &&
        rawValue !== null &&
        typeof rawValue === 'number'
    ) {
        if (rawValue < 0) {
            throw new Error('Price cannot be negative');
        }
        return { ...draft, price: String(rawValue) };
    }

    if (field === 'cost_price') {
        if (rawValue === null) {
            return { ...draft, cost_price: '' };
        }
        if (typeof rawValue === 'number' && rawValue < 0) {
            throw new Error('Cost cannot be negative');
        }
        return {
            ...draft,
            cost_price:
                rawValue === null || rawValue === undefined
                    ? ''
                    : String(rawValue),
        };
    }

    if (field === 'deal' && typeof rawValue === 'string') {
        const deal = rawValue.trim();
        if (deal.length > DEAL_MAX_LENGTH) {
            throw new Error(
                `Deal must be ${DEAL_MAX_LENGTH} characters or less`,
            );
        }
        return { ...draft, deal };
    }

    if (
        field === 'stock' &&
        rawValue !== null &&
        typeof rawValue === 'number'
    ) {
        if (rawValue < 0) {
            throw new Error('Stock cannot be negative');
        }
        return { ...draft, stock: String(Math.trunc(rawValue)) };
    }

    return draft;
}

function parsePendingCreateIndex(rowKey: string): number | null {
    if (!rowKey.startsWith('pending-')) {
        return null;
    }
    const index = Number.parseInt(rowKey.slice('pending-'.length), 10);
    return Number.isFinite(index) ? index : null;
}

function draftToProductInput(draft: NewProductDraft): ProductInput {
    const name = draft.name.trim();
    const category = draft.category.trim();

    const priceResult = parseSpreadsheetDecimal(draft.price, {
        allowEmpty: true,
        label: 'Price',
    });
    if (!priceResult.ok) {
        throw new Error(priceResult.message);
    }
    const price = priceResult.value ?? 0;

    const costResult = parseSpreadsheetDecimal(draft.cost_price, {
        allowEmpty: true,
        label: 'Cost',
    });
    if (!costResult.ok) {
        throw new Error(costResult.message);
    }
    const cost = costResult.value;

    const stockResult = parseSpreadsheetInteger(draft.stock, {
        label: 'Stock',
    });
    if (!stockResult.ok) {
        throw new Error(stockResult.message);
    }
    const stock = stockResult.value;

    const deal = draft.deal.trim() === '' ? null : draft.deal.trim();
    if (deal !== null && deal.length > DEAL_MAX_LENGTH) {
        throw new Error(`Deal must be ${DEAL_MAX_LENGTH} characters or less`);
    }

    return {
        name,
        option: draft.option.trim() === '' ? null : draft.option.trim(),
        category,
        price,
        cost_price: cost !== null && Number.isFinite(cost) ? cost : null,
        deal,
        stock: Number.isFinite(stock) ? stock : 0,
        reorder_level: 5,
    };
}

function pendingDraftToDisplayProduct(
    draft: NewProductDraft,
    tempId: number,
): PosProduct {
    let payload: ProductInput;
    try {
        payload = draftToProductInput(draft);
    } catch {
        payload = {
            name: draft.name.trim() || 'New item',
            category: draft.category.trim() || '',
            price: 0,
            stock: 0,
            reorder_level: 5,
        };
    }

    return {
        id: tempId,
        category_id: 0,
        category_name: payload.category,
        name: payload.name,
        option: payload.option ?? null,
        price: payload.price,
        cost_price: payload.cost_price ?? null,
        deal: payload.deal ?? null,
        stock: payload.stock ?? 0,
        reorder_level: payload.reorder_level ?? 5,
    };
}

type InlineField =
    | 'category'
    | 'name'
    | 'option'
    | 'price'
    | 'cost_price'
    | 'deal'
    | 'stock';

type InlineValue = string | number | null;

const SPREADSHEET_INPUT = cn(
    'h-full w-full min-w-0 border-0 bg-transparent px-1.5 py-1 text-sm outline-none',
    'focus:bg-white focus:ring-2 focus:ring-blue-500 focus:ring-inset',
    'disabled:cursor-wait disabled:opacity-50',
);
const SPREADSHEET_INPUT_INVALID =
    'bg-red-50 ring-2 ring-red-400 ring-inset focus:ring-red-400';

const DEAL_MAX_LENGTH = 500;

const SPREADSHEET_CELL = 'border border-gray-300 p-0 align-middle bg-white';
const SPREADSHEET_HEADER =
    'border border-gray-300 bg-gray-50 px-1.5 py-1 text-left text-xs font-semibold text-gray-600';
const SPREADSHEET_ROW_NUM =
    'border border-gray-300 bg-gray-100 px-1 py-1 text-center text-xs tabular-nums text-gray-500 select-none';
const SPREADSHEET_NEW_ROW = 'bg-emerald-50/50';
const SPREADSHEET_TOOLBAR =
    'flex flex-col gap-3 border border-gray-300 bg-gray-50 p-2 lg:flex-row lg:items-center lg:justify-between';

type ProductFormState = {
    id?: number;
    name: string;
    category: string;
    price: string;
    cost_price: string;
    deal: string;
    stock: string;
    reorder_level: string;
    description: string;
};

const emptyForm = (category = ''): ProductFormState => ({
    name: '',
    category,
    price: '',
    cost_price: '',
    deal: '',
    stock: '',
    reorder_level: '5',
    description: '',
});

type NewProductDraft = {
    category: string;
    name: string;
    option: string;
    price: string;
    cost_price: string;
    deal: string;
    stock: string;
};

function defaultNewProductCategory(
    categories: PosCategory[],
    activeCategory: string,
): string {
    if (activeCategory !== ALL) {
        return activeCategory;
    }
    return categories[0]?.name ?? '';
}

function emptyNewProductDraft(category = ''): NewProductDraft {
    return {
        category,
        name: '',
        option: '',
        price: '',
        cost_price: '',
        deal: '',
        stock: '',
    };
}

function newProductDraftHasData(draft: NewProductDraft): boolean {
    return (
        draft.name.trim() !== '' ||
        draft.option.trim() !== '' ||
        draft.price.trim() !== '' ||
        draft.cost_price.trim() !== '' ||
        draft.stock.trim() !== ''
    );
}

type NewProductBlurField =
    | 'category'
    | 'name'
    | 'option'
    | 'price'
    | 'cost_price'
    | 'deal'
    | 'stock';

function shouldCommitNewProductOnBlur(
    draft: NewProductDraft,
    field: NewProductBlurField,
): boolean {
    if (field === 'price' || field === 'cost_price' || field === 'deal') {
        return true;
    }

    if (field === 'stock') {
        return (
            draft.price.trim() !== '' ||
            draft.cost_price.trim() !== '' ||
            draft.stock.trim() !== ''
        );
    }

    return false;
}

function findMatchingProduct(
    products: PosProduct[],
    name: string,
    category: string,
): PosProduct | undefined {
    const normalizedName = name.trim().toLowerCase();
    const normalizedCategory = category.trim();

    return products.find(
        (product) =>
            product.name.trim().toLowerCase() === normalizedName &&
            product.category_name === normalizedCategory,
    );
}

const ITEMS_SHEET_PATH = '/pos/items/sheet';

function downloadCsv(filename: string, header: string[], rows: (string | number)[][]) {
    const escape = (v: string | number) => {
        const s = String(v);
        return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const lines = [
        header.join(','),
        ...rows.map((row) => row.map(escape).join(',')),
    ];
    const blob = new Blob([lines.join('\n')], {
        type: 'text/csv;charset=utf-8;',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

const ITEMS_PER_PAGE = 100;

export function ItemsCatalogView({ standalone = false }: { standalone?: boolean }) {
    const [categories, setCategories] = useState<PosCategory[]>([]);
    const [products, setProducts] = useState<PosProduct[]>([]);
    const [loading, setLoading] = useState(true);
    const [refreshing, setRefreshing] = useState(false);
    const [loadError, setLoadError] = useState<string | null>(null);

    const [page, setPage] = useState(1);
    const [hasMore, setHasMore] = useState(false);
    const [loadingMore, setLoadingMore] = useState(false);
    const [catalogTotal, setCatalogTotal] = useState(0);
    const [filteredTotal, setFilteredTotal] = useState(0);
    const [lowStockTotal, setLowStockTotal] = useState(0);
    const [categoryCounts, setCategoryCounts] = useState<
        Record<string, number>
    >({});

    const [search, setSearch] = useState('');
    const [activeCategory, setActiveCategory] = useState<string>(ALL);

    const [categoryDialogOpen, setCategoryDialogOpen] = useState(false);
    const [categoryManageDialogOpen, setCategoryManageDialogOpen] =
        useState(false);
    const [editingCategory, setEditingCategory] = useState<PosCategory | null>(
        null,
    );
    const [categoryName, setCategoryName] = useState('');
    const [categoryDescription, setCategoryDescription] = useState('');
    const [categoryIconKey, setCategoryIconKey] = useState('category');
    const [categoryIconTouched, setCategoryIconTouched] = useState(false);
    const [savingCategory, setSavingCategory] = useState(false);

    const [productDialogOpen, setProductDialogOpen] = useState(false);
    const [form, setForm] = useState<ProductFormState>(emptyForm());
    const [savingProduct, setSavingProduct] = useState(false);

    const [detailsProduct, setDetailsProduct] = useState<PosProduct | null>(
        null,
    );
    const [pendingEdits, setPendingEdits] = useState<
        Map<number, Partial<ProductInput>>
    >(() => new Map());
    const [pendingCreates, setPendingCreates] = useState<NewProductDraft[]>(
        [],
    );
    const [savingAll, setSavingAll] = useState(false);
    const [leavePromptOpen, setLeavePromptOpen] = useState(false);
    const pendingLeaveActionRef = useRef<(() => void) | null>(null);
    const allowNavigationRef = useRef(false);
    const [newProductDraft, setNewProductDraft] = useState<NewProductDraft>(
        emptyNewProductDraft(),
    );
    const [importDialogOpen, setImportDialogOpen] = useState(false);
    const [exportingProducts, setExportingProducts] = useState(false);
    const [importingProducts, setImportingProducts] = useState(false);
    const importFileRef = useRef<HTMLInputElement>(null);
    const [deleteTarget, setDeleteTarget] = useState<PosProduct | null>(null);
    const [deletingProduct, setDeletingProduct] = useState(false);
    const newRowItemRef = useRef<HTMLInputElement>(null);
    const spreadsheetRootRef = useRef<HTMLDivElement>(null);
    const tableScrollRef = useRef<HTMLDivElement>(null);
    const [browserFullscreen, setBrowserFullscreen] = useState(false);

    const categoryIconByName = useMemo(() => {
        const map = new Map<string, string>();
        categories.forEach((c) => map.set(c.name, c.icon ?? ''));
        return map;
    }, [categories]);

    async function loadData(options?: {
        search?: string;
        category?: string;
        resetPending?: boolean;
    }) {
        const hasLocalData = categories.length > 0 || products.length > 0;
        const searchTerm = options?.search ?? search;
        const category = options?.category ?? activeCategory;

        if (!hasLocalData) {
            setLoading(true);
        } else {
            setRefreshing(true);
        }
        setLoadError(null);

        try {
            const [catRes, prodRes] = await Promise.all([
                fetchCategories(),
                fetchProductsPage({
                    page: 1,
                    perPage: ITEMS_PER_PAGE,
                    search: searchTerm,
                    category: category === ALL ? undefined : category,
                }),
            ]);
            setCategories(catRes.data ?? []);
            setProducts(prodRes.data ?? []);
            setPage(1);
            setHasMore(prodRes.meta?.has_more ?? false);
            setFilteredTotal(prodRes.meta?.total ?? (prodRes.data?.length ?? 0));
            setCatalogTotal(prodRes.meta?.catalog_total ?? 0);
            setLowStockTotal(prodRes.meta?.low_stock_total ?? 0);
            setCategoryCounts(prodRes.meta?.category_counts ?? {});
            if (options?.resetPending !== false) {
                setPendingEdits(new Map());
                setPendingCreates([]);
            }
        } catch (error) {
            if (!hasLocalData) {
                setLoadError(
                    error instanceof Error
                        ? error.message
                        : 'Failed to load items',
                );
            }
        } finally {
            setLoading(false);
            setRefreshing(false);
        }
    }

    const loadMore = useCallback(async () => {
        if (loadingMore || !hasMore) {
            return;
        }
        setLoadingMore(true);
        try {
            const nextPage = page + 1;
            const res = await fetchProductsPage({
                page: nextPage,
                perPage: ITEMS_PER_PAGE,
                search,
                category: activeCategory === ALL ? undefined : activeCategory,
            });
            setProducts((current) => [...current, ...(res.data ?? [])]);
            setPage(nextPage);
            setHasMore(res.meta?.has_more ?? false);
        } catch (error) {
            toast.error(
                error instanceof Error
                    ? error.message
                    : 'Failed to load more items',
            );
        } finally {
            setLoadingMore(false);
        }
    }, [activeCategory, hasMore, loadingMore, page, search]);

    const loadMoreSentinelRef = useRef<HTMLTableRowElement>(null);
    useEffect(() => {
        const sentinel = loadMoreSentinelRef.current;
        if (!sentinel) {
            return;
        }
        const observer = new IntersectionObserver(
            (entries) => {
                if (entries[0]?.isIntersecting) {
                    void loadMore();
                }
            },
            { rootMargin: '600px' },
        );
        observer.observe(sentinel);
        return () => observer.disconnect();
    }, [loadMore]);

    const didMountRef = useRef(false);
    useEffect(() => {
        if (!didMountRef.current) {
            didMountRef.current = true;
            return;
        }
        const timeout = setTimeout(() => {
            void loadData({
                search,
                category: activeCategory,
                resetPending: false,
            });
        }, 300);
        return () => clearTimeout(timeout);
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [search, activeCategory]);

    useEffect(() => {
        void loadData();
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        const preset = defaultNewProductCategory(categories, activeCategory);
        setNewProductDraft((current) => {
            if (newProductDraftHasData(current)) {
                return current;
            }
            return { ...current, category: preset };
        });
    }, [activeCategory, categories]);

    const focusNewProductRow = useCallback(() => {
        const target = newRowItemRef.current;
        if (!target) {
            return;
        }
        target.focus({ preventScroll: true });
    }, []);

    const hasUnsavedChanges =
        pendingEdits.size > 0 ||
        pendingCreates.length > 0 ||
        newProductDraftHasData(newProductDraft);

    const discardAllChanges = useCallback(() => {
        setPendingEdits(new Map());
        setPendingCreates([]);
        setNewProductDraft(
            emptyNewProductDraft(
                defaultNewProductCategory(categories, activeCategory),
            ),
        );
    }, [activeCategory, categories]);

    const requestLeave = useCallback(
        (action: () => void) => {
            if (!hasUnsavedChanges) {
                action();
                return;
            }
            pendingLeaveActionRef.current = action;
            setLeavePromptOpen(true);
        },
        [hasUnsavedChanges],
    );

    const closeLeavePrompt = useCallback(() => {
        pendingLeaveActionRef.current = null;
        setLeavePromptOpen(false);
    }, []);

    const runPendingLeaveAction = useCallback(() => {
        const action = pendingLeaveActionRef.current;
        pendingLeaveActionRef.current = null;
        setLeavePromptOpen(false);
        if (action) {
            allowNavigationRef.current = true;
            action();
        }
    }, []);

    const saveAllChanges = useCallback(async () => {
        if (savingAll) {
            return false;
        }

        const createPayloads: ProductInput[] = [];
        for (const draft of [
            ...pendingCreates,
            ...(newProductDraftHasData(newProductDraft)
                ? [newProductDraft]
                : []),
        ]) {
            const name = draft.name.trim();
            const category = draft.category.trim();
            if (name === '' || category === '') {
                toast.error('Complete the new row (category and name) before saving');
                return false;
            }
            try {
                createPayloads.push(draftToProductInput(draft));
            } catch (error) {
                toast.error(
                    error instanceof Error
                        ? error.message
                        : 'Invalid new product row',
                );
                return false;
            }
        }

        setSavingAll(true);
        try {
            let nextProducts = [...products];

            for (const [productId, edits] of pendingEdits) {
                const base = products.find((product) => product.id === productId);
                if (!base) {
                    continue;
                }
                const merged = mergeProductWithPendingEdits(base, edits);
                const payload = { ...productToPayload(merged), ...edits, id: productId };
                const res = await saveProduct(payload);
                nextProducts = nextProducts.map((product) =>
                    product.id === productId ? res.data : product,
                );
            }

            for (const payload of createPayloads) {
                const existing = findMatchingProduct(
                    nextProducts,
                    payload.name,
                    payload.category,
                );
                if (existing) {
                    throw new Error(
                        `"${payload.name}" already exists in ${payload.category}`,
                    );
                }
                const res = await saveProduct(payload);
                nextProducts = [...nextProducts, res.data];
            }

            setProducts(nextProducts);
            setPendingEdits(new Map());
            setPendingCreates([]);
            setNewProductDraft(
                emptyNewProductDraft(
                    defaultNewProductCategory(categories, activeCategory),
                ),
            );
            toast.success('All changes saved');
            return true;
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : 'Failed to save changes',
            );
            return false;
        } finally {
            setSavingAll(false);
        }
    }, [
        activeCategory,
        categories,
        newProductDraft,
        pendingCreates,
        pendingEdits,
        products,
        savingAll,
    ]);

    const handleSaveAndLeave = useCallback(async () => {
        const saved = await saveAllChanges();
        if (!saved) {
            return;
        }
        runPendingLeaveAction();
    }, [runPendingLeaveAction, saveAllChanges]);

    const handleDiscardAndLeave = useCallback(() => {
        discardAllChanges();
        runPendingLeaveAction();
    }, [discardAllChanges, runPendingLeaveAction]);

    const unsavedEditCount = pendingEdits.size;
    const unsavedCreateCount =
        pendingCreates.length +
        (newProductDraftHasData(newProductDraft) ? 1 : 0);

    useEffect(() => {
        const handleBeforeUnload = (event: BeforeUnloadEvent) => {
            if (!hasUnsavedChanges) {
                return;
            }
            event.preventDefault();
            event.returnValue = '';
        };

        window.addEventListener('beforeunload', handleBeforeUnload);
        return () => {
            window.removeEventListener('beforeunload', handleBeforeUnload);
        };
    }, [hasUnsavedChanges]);

    useEffect(() => {
        return router.on('before', (event) => {
            if (allowNavigationRef.current) {
                allowNavigationRef.current = false;
                return;
            }
            if (!hasUnsavedChanges) {
                return;
            }
            event.preventDefault();
            const visit = event.detail.visit;
            pendingLeaveActionRef.current = () => {
                router.visit(visit.url, visit);
            };
            setLeavePromptOpen(true);
        });
    }, [hasUnsavedChanges]);

    const displayProducts = useMemo(
        () =>
            products.map((product) =>
                mergeProductWithPendingEdits(
                    product,
                    pendingEdits.get(product.id),
                ),
            ),
        [pendingEdits, products],
    );

    const filteredProducts = useMemo(() => {
        const term = search.trim().toLowerCase();
        return displayProducts.filter((p) => {
            const matchesCategory =
                activeCategory === ALL || p.category_name === activeCategory;
            const matchesSearch =
                term === '' || p.name.toLowerCase().includes(term);
            return matchesCategory && matchesSearch;
        });
    }, [displayProducts, search, activeCategory]);

    const tableRows = useMemo(() => {
        const productRows = buildItemTableRows(filteredProducts).map((row) => ({
            ...row,
            isPending: pendingEdits.has(row.product.id),
        }));
        const stagedCreates = pendingCreates
            .map((draft, createIndex) => ({ draft, createIndex }))
            .filter(({ draft }) => {
                if (activeCategory === ALL) {
                    return true;
                }
                return draft.category.trim() === activeCategory;
            })
            .map(({ draft, createIndex }, displayIndex) => ({
                key: `pending-${createIndex}`,
                index: productRows.length + displayIndex + 1,
                product: pendingDraftToDisplayProduct(draft, -(createIndex + 1)),
                isPending: true as const,
            }));

        return [...productRows, ...stagedCreates];
    }, [activeCategory, filteredProducts, pendingCreates, pendingEdits]);

    const toggleBrowserFullscreen = useCallback(async () => {
        const root = spreadsheetRootRef.current;
        if (!root) {
            return;
        }

        try {
            if (document.fullscreenElement) {
                await document.exitFullscreen();
            } else {
                await root.requestFullscreen();
            }
        } catch {
            toast.error('Fullscreen is not available in this browser');
        }
    }, []);

    useEffect(() => {
        const handleFullscreenChange = () => {
            setBrowserFullscreen(document.fullscreenElement !== null);
        };

        document.addEventListener('fullscreenchange', handleFullscreenChange);
        return () => {
            document.removeEventListener(
                'fullscreenchange',
                handleFullscreenChange,
            );
        };
    }, []);

    const openItemsSheetTab = useCallback(() => {
        requestLeave(() => {
            window.open(ITEMS_SHEET_PATH, '_blank', 'noopener,noreferrer');
        });
    }, [requestLeave]);

    const categoryNames = useMemo(
        () => categories.map((category) => category.name),
        [categories],
    );

    const stageInlineField = useCallback(
        async (row: ItemTableRow, field: InlineField, rawValue: InlineValue) => {
            const createIndex = parsePendingCreateIndex(row.key);

            try {
                if (createIndex !== null) {
                    setPendingCreates((current) => {
                        const draft = current[createIndex];
                        if (!draft) {
                            return current;
                        }
                        const next = [...current];
                        next[createIndex] = applyInlineFieldToDraft(
                            draft,
                            field,
                            rawValue,
                        );
                        return next;
                    });
                    return;
                }

                const pending = pendingEdits.get(row.product.id);
                const merged = mergeProductWithPendingEdits(row.product, pending);
                const payload = productToPayload(merged);
                const patch = applyInlineFieldToPayload(
                    payload,
                    field,
                    rawValue,
                );

                setPendingEdits((current) => {
                    const next = new Map(current);
                    next.set(row.product.id, {
                        ...(next.get(row.product.id) ?? {}),
                        ...patch,
                    });
                    return next;
                });
            } catch (error) {
                toast.error(
                    error instanceof Error
                        ? error.message
                        : 'Invalid value',
                );
                throw error;
            }
        },
        [pendingEdits],
    );

    const stageNewProduct = useCallback(
        async (draft: NewProductDraft) => {
            const name = draft.name.trim();
            const category = draft.category.trim();

            if (name === '' || category === '') {
                return false;
            }

            if (categories.length === 0) {
                toast.error('Add a category first');
                return false;
            }

            try {
                draftToProductInput(draft);
            } catch (error) {
                toast.error(
                    error instanceof Error
                        ? error.message
                        : 'Invalid new product row',
                );
                return false;
            }

            const existing = findMatchingProduct(displayProducts, name, category);
            if (existing) {
                toast.error('This item already exists');
                return false;
            }

            const duplicatePending = pendingCreates.some(
                (item) =>
                    item.name.trim().toLowerCase() === name.toLowerCase() &&
                    item.category.trim() === category,
            );
            if (duplicatePending) {
                toast.error('This item is already in unsaved rows');
                return false;
            }

            setPendingCreates((current) => [...current, { ...draft }]);
            const preset = defaultNewProductCategory(categories, activeCategory);
            setNewProductDraft(emptyNewProductDraft(preset));
            window.requestAnimationFrame(() => {
                newRowItemRef.current?.focus();
            });
            return true;
        },
        [activeCategory, categories, displayProducts, pendingCreates],
    );

    const tryCommitNewProduct = useCallback(async () => {
        if (savingAll) {
            return;
        }
        const name = newProductDraft.name.trim();
        const category = newProductDraft.category.trim();
        if (name === '' || category === '') {
            return;
        }

        const existing = findMatchingProduct(displayProducts, name, category);
        if (existing) {
            return;
        }

        const hasPricing =
            newProductDraft.price.trim() !== '' ||
            newProductDraft.stock.trim() !== '' ||
            newProductDraft.cost_price.trim() !== '';
        if (!hasPricing) {
            return;
        }

        if (
            isInvalidDecimalDraft(newProductDraft.price, true) ||
            isInvalidDecimalDraft(newProductDraft.cost_price, true) ||
            isInvalidIntegerDraft(newProductDraft.stock) ||
            newProductDraft.deal.trim().length > DEAL_MAX_LENGTH
        ) {
            return;
        }

        await stageNewProduct(newProductDraft);
    }, [displayProducts, newProductDraft, savingAll, stageNewProduct]);

    async function handleExportProducts() {
        setExportingProducts(true);
        try {
            const response = await exportProducts();
            const headers = response.headers ?? [];
            const rows = (response.rows ?? []).map((row) =>
                headers.map((header) => row[header] ?? ''),
            );
            downloadCsv(
                `items-${new Date().toISOString().slice(0, 10)}.csv`,
                headers,
                rows,
            );
            toast.success('Items exported');
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : 'Export failed',
            );
        } finally {
            setExportingProducts(false);
        }
    }

    const openImportDialog = useCallback(() => {
        requestLeave(() => {
            setImportDialogOpen(true);
        });
    }, [requestLeave]);

    function requestDeleteRow(row: ItemTableRow) {
        const createIndex = parsePendingCreateIndex(row.key);
        if (createIndex !== null) {
            setPendingCreates((current) =>
                current.filter((_, index) => index !== createIndex),
            );
            return;
        }

        if (row.product.id > 0) {
            setDeleteTarget(row.product);
        }
    }

    async function confirmDeleteProduct() {
        if (!deleteTarget) {
            return;
        }

        setDeletingProduct(true);
        try {
            await deleteProduct(deleteTarget.id);
            setPendingEdits((current) => {
                const next = new Map(current);
                next.delete(deleteTarget.id);
                return next;
            });
            setProducts((current) =>
                current.filter((product) => product.id !== deleteTarget.id),
            );
            if (detailsProduct?.id === deleteTarget.id) {
                setDetailsProduct(null);
            }
            setDeleteTarget(null);
            toast.success('Product removed');
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : 'Delete failed',
            );
        } finally {
            setDeletingProduct(false);
        }
    }

    async function handleImportFile(file: File) {
        setImportingProducts(true);
        const loadingToast = toast.loading(
            'Importing products… large files may take up to a minute.',
        );
        try {
            const result = await importProducts(file);
            toast.success(result.message ?? 'Import complete', {
                id: loadingToast,
            });
            if (result.data?.errors?.length) {
                toast.warning(
                    `${result.data.errors.length} row issue(s) — check server response`,
                );
            }
            setImportDialogOpen(false);
            await loadData();
        } catch (error) {
            toast.error(
                error instanceof Error ? error.message : 'Import failed',
                { id: loadingToast },
            );
        } finally {
            setImportingProducts(false);
            if (importFileRef.current) {
                importFileRef.current.value = '';
            }
        }
    }

    function openAddProduct() {
        focusNewProductRow();
    }

    function openEditProduct(product: PosProduct) {
        setForm({
            id: product.id,
            name: product.name,
            category: product.category_name,
            price: String(toNumber(product.price)),
            cost_price:
                product.cost_price === null || product.cost_price === undefined
                    ? ''
                    : String(toNumber(product.cost_price)),
            deal: product.deal?.trim() ?? '',
            stock:
                product.stock === null || product.stock === undefined
                    ? ''
                    : String(toNumber(product.stock)),
            reorder_level: String(toNumber(product.reorder_level) || 5),
            description: product.description ?? '',
        });
        setProductDialogOpen(true);
    }

    function openEditFromDetails(product: PosProduct) {
        setDetailsProduct(null);
        openEditProduct(product);
    }

    function openAddCategory() {
        setEditingCategory(null);
        setCategoryName('');
        setCategoryDescription('');
        setCategoryIconKey('category');
        setCategoryIconTouched(false);
        setCategoryDialogOpen(true);
    }

    function openEditCategory(category: PosCategory) {
        setEditingCategory(category);
        setCategoryName(category.name);
        setCategoryDescription(category.description ?? '');
        setCategoryIconKey(category.icon ?? suggestCategoryIconKey(category.name));
        setCategoryIconTouched(true);
        setCategoryManageDialogOpen(false);
        setCategoryDialogOpen(true);
    }

    async function handleSaveCategory() {
        const name = categoryName.trim();
        if (name === '') {
            toast.error('Category name is required');
            return;
        }
        setSavingCategory(true);
        const previousName = editingCategory?.name ?? null;
        const isEdit = editingCategory !== null;
        try {
            const payload = {
                name,
                description: categoryDescription.trim() || undefined,
                icon: categoryIconKey,
            };
            const res = editingCategory
                ? await updateCategory({
                      id: editingCategory.id,
                      ...payload,
                  })
                : await createCategory(payload);
            toast.success(res.message ?? 'Category saved');
            setCategoryName('');
            setCategoryDescription('');
            setEditingCategory(null);
            setCategoryDialogOpen(false);
            await loadData();
            if (res.data?.name) {
                if (previousName !== null && activeCategory === previousName) {
                    setActiveCategory(res.data.name);
                } else if (!isEdit) {
                    setActiveCategory(res.data.name);
                }
            }
        } catch (error) {
            toast.error(
                error instanceof Error
                    ? error.message
                    : 'Failed to save category',
            );
        } finally {
            setSavingCategory(false);
        }
    }

    async function handleSaveProduct() {
        const name = form.name.trim();
        const category = form.category.trim();

        if (name === '') {
            toast.error('Product name is required');
            return;
        }
        if (category === '') {
            toast.error('Please choose a category');
            return;
        }

        const productPrice = parseFloat(form.price);
        if (!Number.isFinite(productPrice) || productPrice < 0) {
            toast.error('Enter a valid price');
            return;
        }

        const payload: ProductInput = {
            id: form.id,
            name,
            category,
            price: productPrice,
            cost_price:
                form.cost_price.trim() === ''
                    ? null
                    : parseFloat(form.cost_price),
            deal: form.deal.trim() === '' ? null : form.deal.trim(),
            stock:
                form.stock.trim() === '' ? 0 : parseInt(form.stock, 10),
            reorder_level:
                form.reorder_level.trim() === ''
                    ? 5
                    : parseInt(form.reorder_level, 10),
            description: form.description.trim() || undefined,
        };

        setSavingProduct(true);
        try {
            const res = await saveProduct(payload);
            toast.success(
                res.message ?? (form.id ? 'Product updated' : 'Product saved'),
            );
            setProductDialogOpen(false);
            await loadData();
        } catch (error) {
            toast.error(
                error instanceof Error
                    ? error.message
                    : 'Failed to save product',
            );
        } finally {
            setSavingProduct(false);
        }
    }

    const scrollLayout = standalone || browserFullscreen;

    return (
        <>
            <Head title={standalone ? 'Items Spreadsheet' : 'Items'} />
            <div
                ref={spreadsheetRootRef}
                className={cn(
                    scrollLayout
                        ? cn(
                              'flex h-full flex-col overflow-hidden bg-white text-gray-900',
                              '[&_.agri-stat-card]:border-gray-300 [&_.agri-stat-card]:bg-white [&_.agri-stat-card]:text-gray-900',
                              '[&_.agri-stat-label]:text-gray-500',
                              '[&_.text-foreground]:text-gray-900',
                              '[&_.text-muted-foreground]:text-gray-600',
                          )
                        : 'agri-page-container',
                    standalone && 'h-svh',
                    'fullscreen:flex fullscreen:h-full fullscreen:flex-col fullscreen:overflow-hidden fullscreen:bg-white fullscreen:text-gray-900',
                )}
            >
                {standalone ? (
                    <div className="flex shrink-0 items-center justify-between gap-3 border-b border-gray-300 bg-gray-50 px-3 py-2">
                        <div className="flex min-w-0 items-center gap-3">
                            <button
                                type="button"
                                onClick={() =>
                                    requestLeave(() => {
                                        allowNavigationRef.current = true;
                                        router.visit('/pos/items');
                                    })
                                }
                                className="inline-flex items-center gap-1 text-xs text-gray-600 hover:text-gray-900"
                            >
                                <ArrowLeft className="size-3.5" />
                                Items
                            </button>
                            <span className="text-sm font-semibold text-gray-900">
                                Spreadsheet
                            </span>
                            <span className="hidden text-xs text-gray-500 sm:inline">
                                {catalogTotal} products · {categories.length}{' '}
                                categories
                            </span>
                        </div>
                        <div className="flex flex-wrap items-center justify-end gap-2">
                            <Button
                                type="button"
                                variant="outline"
                                size="sm"
                                className="h-8 rounded-sm border-gray-300 bg-white px-3 text-xs shadow-none"
                                onClick={() => void toggleBrowserFullscreen()}
                            >
                                {browserFullscreen ? (
                                    <Minimize2 className="size-3.5" />
                                ) : (
                                    <Maximize2 className="size-3.5" />
                                )}
                                {browserFullscreen ? 'Exit fullscreen' : 'Fullscreen'}
                            </Button>
                        </div>
                    </div>
                ) : (
                    <PageHeader
                        badge="Products"
                        title="Items & Categories"
                        description="Edit cells in the spreadsheet below; changes stay on this page until you click Save. Export CSV first if you want a backup, or import Excel/CSV for bulk updates."
                        className={scrollLayout ? 'shrink-0' : undefined}
                    />
                )}

                {!standalone ? (
                    <div
                        className={cn(
                            'grid grid-cols-2 gap-4 lg:grid-cols-4 lg:gap-5',
                            scrollLayout && 'shrink-0',
                        )}
                    >
                        <div className="agri-stat-card">
                            <div className="mb-3 flex items-center justify-between gap-2">
                                <span className="agri-stat-label">Products</span>
                                <div className="agri-icon-box">
                                    <Package className="size-4" />
                                </div>
                            </div>
                            <p className="agri-stat-value mt-auto">
                                {catalogTotal}
                            </p>
                        </div>
                        <div className="agri-stat-card">
                            <div className="mb-3 flex items-center justify-between gap-2">
                                <span className="agri-stat-label">
                                    Categories
                                </span>
                                <div className="agri-icon-box">
                                    <Layers className="size-4" />
                                </div>
                            </div>
                            <p className="agri-stat-value mt-auto">
                                {categories.length}
                            </p>
                        </div>
                        <div className="agri-stat-card">
                            <div className="mb-3 flex items-center justify-between gap-2">
                                <span className="agri-stat-label">Low stock</span>
                                <div className="agri-icon-box">
                                    <AlertTriangle className="size-4" />
                                </div>
                            </div>
                            <p
                                className={`agri-stat-value mt-auto ${
                                    lowStockTotal > 0 ? 'text-destructive' : ''
                                }`}
                            >
                                {lowStockTotal}
                            </p>
                        </div>
                        <div className="agri-stat-card">
                            <div className="mb-3 flex items-center justify-between gap-2">
                                <span className="agri-stat-label">Showing</span>
                                <div className="agri-icon-box">
                                    <Boxes className="size-4" />
                                </div>
                            </div>
                            <p className="agri-stat-value mt-auto">
                                {tableRows.length}
                            </p>
                        </div>
                    </div>
                ) : null}

                <div
                    className={cn(
                        'flex flex-col gap-2',
                        scrollLayout &&
                            'min-h-0 flex-1 overflow-hidden bg-white fullscreen:min-h-0 fullscreen:flex-1 fullscreen:overflow-hidden fullscreen:bg-white',
                        standalone && 'p-2',
                    )}
                >
                <div
                    className={cn(
                        SPREADSHEET_TOOLBAR,
                        scrollLayout && 'shrink-0',
                    )}
                >
                    <div className="relative w-full lg:max-w-sm">
                        <Search className="absolute top-1/2 left-2 size-4 -translate-y-1/2 text-gray-500" />
                        <input
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            placeholder="Search by name"
                            className={cn(
                                SPREADSHEET_INPUT,
                                'h-8 border border-gray-300 bg-white pl-8 text-left focus:ring-1',
                            )}
                        />
                    </div>
                    <div className="flex flex-wrap items-center gap-2">
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            className="h-8 rounded-sm border-gray-300 bg-white px-3 text-xs shadow-none"
                            onClick={openAddCategory}
                        >
                            <Tag className="size-3.5" />
                            Add Category
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            className="h-8 rounded-sm border-gray-300 bg-white px-3 text-xs shadow-none"
                            onClick={() => setCategoryManageDialogOpen(true)}
                            disabled={categories.length === 0}
                        >
                            <Pencil className="size-3.5" />
                            Manage Categories
                        </Button>
                        {hasUnsavedChanges ? (
                            <>
                                <Button
                                    type="button"
                                    size="sm"
                                    className="h-8 rounded-sm px-3 text-xs shadow-none"
                                    disabled={savingAll}
                                    onClick={() => void saveAllChanges()}
                                >
                                    {savingAll ? (
                                        <Loader2 className="size-3.5 animate-spin" />
                                    ) : (
                                        <Save className="size-3.5" />
                                    )}
                                    Save changes
                                </Button>
                                <Button
                                    type="button"
                                    variant="outline"
                                    size="sm"
                                    className="h-8 rounded-sm border-gray-300 bg-white px-3 text-xs shadow-none"
                                    disabled={savingAll}
                                    onClick={discardAllChanges}
                                >
                                    <X className="size-3.5" />
                                    Discard
                                </Button>
                            </>
                        ) : null}
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            className="h-8 rounded-sm border-gray-300 bg-white px-3 text-xs shadow-none"
                            disabled={exportingProducts}
                            onClick={() => void handleExportProducts()}
                        >
                            {exportingProducts ? (
                                <Loader2 className="size-3.5 animate-spin" />
                            ) : (
                                <Download className="size-3.5" />
                            )}
                            Export CSV
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            className="h-8 rounded-sm border-gray-300 bg-white px-3 text-xs shadow-none"
                            onClick={openImportDialog}
                        >
                            <Upload className="size-3.5" />
                            Import file
                        </Button>
                        <Button
                            type="button"
                            size="sm"
                            className="h-8 rounded-sm border border-gray-300 bg-white px-3 text-xs text-gray-700 shadow-none hover:bg-gray-100"
                            variant="outline"
                            onClick={openAddProduct}
                        >
                            <Plus className="size-3.5" />
                            New row
                        </Button>
                        {!standalone ? (
                            <>
                                <Button
                                    type="button"
                                    size="sm"
                                    className="h-8 rounded-sm border border-gray-300 bg-white px-3 text-xs text-gray-700 shadow-none hover:bg-gray-100"
                                    variant="outline"
                                    onClick={openItemsSheetTab}
                                >
                                    <ExternalLink className="size-3.5" />
                                    Open sheet tab
                                </Button>
                                <Button
                                    type="button"
                                    size="sm"
                                    className="h-8 rounded-sm border border-gray-300 bg-white px-3 text-xs text-gray-700 shadow-none hover:bg-gray-100"
                                    variant="outline"
                                    onClick={() => void toggleBrowserFullscreen()}
                                >
                                    {browserFullscreen ? (
                                        <Minimize2 className="size-3.5" />
                                    ) : (
                                        <Maximize2 className="size-3.5" />
                                    )}
                                    Fullscreen
                                </Button>
                            </>
                        ) : null}
                    </div>
                </div>
                {hasUnsavedChanges ? (
                    <div
                        className={cn(
                            'flex flex-wrap items-center justify-between gap-2 border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-950',
                            scrollLayout && 'shrink-0',
                        )}
                    >
                        <div className="flex items-center gap-2">
                            <AlertTriangle className="size-3.5 shrink-0 text-amber-600" />
                            <span>
                                Unsaved changes —{' '}
                                {unsavedEditCount > 0
                                    ? `${unsavedEditCount} edited row${unsavedEditCount === 1 ? '' : 's'}`
                                    : null}
                                {unsavedEditCount > 0 && unsavedCreateCount > 0
                                    ? ', '
                                    : null}
                                {unsavedCreateCount > 0
                                    ? `${unsavedCreateCount} new row${unsavedCreateCount === 1 ? '' : 's'}`
                                    : null}
                                . Click Save changes to persist, or Export CSV
                                for a backup.
                            </span>
                        </div>
                    </div>
                ) : null}
                {/* Category filter chips */}
                <div
                    className={cn(
                        'flex flex-wrap gap-2',
                        scrollLayout && 'shrink-0',
                    )}
                >
                    <CategoryChip
                        label="All"
                        count={catalogTotal}
                        active={activeCategory === ALL}
                        onClick={() => setActiveCategory(ALL)}
                    />
                    {categories.map((cat) => {
                        const Icon = resolveCategoryIcon(cat.icon, cat.name);
                        return (
                            <CategoryChip
                                key={cat.id}
                                label={cat.name}
                                count={categoryCounts[cat.name] ?? 0}
                                active={activeCategory === cat.name}
                                onClick={() => setActiveCategory(cat.name)}
                                icon={<Icon className="size-3.5" />}
                            />
                        );
                    })}
                </div>

                {/* Content */}
                {loading ? (
                    <div className="agri-card flex items-center justify-center gap-3 p-12 text-muted-foreground">
                        <Loader2 className="size-5 animate-spin" />
                        Loading items...
                    </div>
                ) : loadError ? (
                    <div className="agri-card flex flex-col items-center gap-3 p-12 text-center">
                        <AlertTriangle className="size-8 text-destructive" />
                        <p className="font-medium text-destructive">
                            {loadError}
                        </p>
                        <Button
                            variant="outline"
                            className="rounded-xl"
                            onClick={() => void loadData()}
                        >
                            Try again
                        </Button>
                    </div>
                ) : (
                    <>
                        {refreshing && (
                            <div className="mb-2 flex items-center gap-2 text-xs text-muted-foreground">
                                <Loader2 className="size-3.5 animate-spin" />
                                Updating items…
                            </div>
                        )}
                    <div
                        ref={tableScrollRef}
                        className={cn(
                            'overflow-auto border border-gray-300 bg-white',
                            scrollLayout
                                ? 'min-h-0 flex-1 fullscreen:min-h-0 fullscreen:flex-1 fullscreen:overflow-auto'
                                : 'max-h-[70vh]',
                        )}
                    >
                        {products.length === 0 &&
                        (search.trim() !== '' || activeCategory !== ALL) ? (
                            <p className="border-b border-gray-300 bg-amber-50 px-3 py-1.5 text-xs text-amber-900">
                                No products match your current filter. Clear
                                search or choose another category.
                            </p>
                        ) : null}
                        {products.length > 0 && filteredProducts.length === 0 ? (
                            <p className="border-b border-gray-300 bg-amber-50 px-3 py-1.5 text-xs text-amber-900">
                                No products match your current filter. Clear
                                search or choose another category.
                            </p>
                        ) : null}
                        {categories.length === 0 ? (
                            <p className="border-b border-gray-300 bg-amber-50 px-3 py-1.5 text-xs text-amber-900">
                                Add a category first, then type in the blank row
                                below to add products.
                            </p>
                        ) : null}
                        <table className="w-full min-w-[52rem] border-collapse font-sans text-sm">
                            <thead>
                                <tr>
                                    <th
                                        className={cn(
                                            SPREADSHEET_HEADER,
                                            'w-10 text-center',
                                        )}
                                    >
                                        #
                                    </th>
                                    <th className={SPREADSHEET_HEADER}>
                                        Category
                                    </th>
                                    <th className={SPREADSHEET_HEADER}>Item</th>
                                    <th className={SPREADSHEET_HEADER}>
                                        Option
                                    </th>
                                    <th
                                        className={cn(
                                            SPREADSHEET_HEADER,
                                            'text-right',
                                        )}
                                    >
                                        Price
                                    </th>
                                    <th
                                        className={cn(
                                            SPREADSHEET_HEADER,
                                            'text-right',
                                        )}
                                    >
                                        Cost
                                    </th>
                                    <th className={SPREADSHEET_HEADER}>
                                        Deal
                                    </th>
                                    <th
                                        className={cn(
                                            SPREADSHEET_HEADER,
                                            'text-right',
                                        )}
                                    >
                                        Stock
                                    </th>
                                    <th
                                        className={cn(
                                            SPREADSHEET_HEADER,
                                            'w-12 text-center',
                                        )}
                                    >
                                        <span className="sr-only">Delete</span>
                                    </th>
                                </tr>
                            </thead>
                            <tbody>
                                {tableRows.map((row) => {
                                    const low =
                                        tableRowStock(row) <=
                                        tableRowReorder(row);
                                    const cost = tableRowCost(row);
                                    const saving = savingAll;
                                    const cellRow = row.index;

                                    return (
                                        <tr
                                            key={row.key}
                                            className={
                                                row.isPending
                                                    ? 'bg-amber-50'
                                                    : undefined
                                            }
                                        >
                                            <td className={SPREADSHEET_ROW_NUM}>
                                                {row.index}
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetSelectCell
                                                    value={
                                                        row.product.category_name
                                                    }
                                                    options={categoryNames}
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={1}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'category',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetTextCell
                                                    value={row.product.name}
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={2}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'name',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetTextCell
                                                    value={tableRowOption(row)}
                                                    allowEmpty
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={3}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'option',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetNumberCell
                                                    value={tableRowPrice(row)}
                                                    decimals={2}
                                                    label="Price"
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={4}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'price',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetNumberCell
                                                    value={cost}
                                                    decimals={2}
                                                    allowEmpty
                                                    label="Cost"
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={5}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'cost_price',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetTextCell
                                                    value={tableRowDeal(row)}
                                                    allowEmpty
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={6}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'deal',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td className={SPREADSHEET_CELL}>
                                                <SpreadsheetIntegerCell
                                                    value={tableRowStock(row)}
                                                    low={low}
                                                    saving={saving}
                                                    dataRow={cellRow}
                                                    dataCol={7}
                                                    onCommit={(value) =>
                                                        stageInlineField(
                                                            row,
                                                            'stock',
                                                            value,
                                                        )
                                                    }
                                                />
                                            </td>
                                            <td
                                                className={cn(
                                                    SPREADSHEET_CELL,
                                                    'text-center',
                                                )}
                                            >
                                                <button
                                                    type="button"
                                                    title={
                                                        row.key.startsWith(
                                                            'pending-',
                                                        )
                                                            ? 'Remove unsaved row'
                                                            : 'Delete product'
                                                    }
                                                    disabled={saving}
                                                    className="inline-flex size-7 items-center justify-center rounded-sm text-gray-400 transition-colors hover:bg-red-50 hover:text-destructive disabled:cursor-not-allowed disabled:opacity-50"
                                                    onClick={() =>
                                                        requestDeleteRow(row)
                                                    }
                                                >
                                                    <Trash2 className="size-3.5" />
                                                </button>
                                            </td>
                                        </tr>
                                    );
                                })}
                                <NewProductSpreadsheetRow
                                    draft={newProductDraft}
                                    saving={savingAll}
                                    rowIndex={tableRows.length + 1}
                                    categoryNames={categoryNames}
                                    itemInputRef={newRowItemRef}
                                    onDraftChange={(patch) =>
                                        setNewProductDraft((current) => ({
                                            ...current,
                                            ...patch,
                                        }))
                                    }
                                    onTryCommit={tryCommitNewProduct}
                                    onFocusRow={focusNewProductRow}
                                />
                                {hasMore && !loadingMore ? (
                                    <tr ref={loadMoreSentinelRef}>
                                        <td colSpan={9} className="p-0">
                                            <button
                                                type="button"
                                                onClick={() => void loadMore()}
                                                className="w-full border-t border-gray-200 bg-gray-50 px-3 py-2 text-center text-xs font-medium text-gray-600 hover:bg-gray-100"
                                            >
                                                Load 100 more ({products.length}
                                                /{filteredTotal})
                                            </button>
                                        </td>
                                    </tr>
                                ) : null}
                                {loadingMore ? (
                                    <tr>
                                        <td
                                            colSpan={9}
                                            className="border border-gray-300 px-3 py-2 text-center text-xs text-muted-foreground"
                                        >
                                            <span className="inline-flex items-center gap-2">
                                                <Loader2 className="size-3.5 animate-spin" />
                                                Loading more items…
                                            </span>
                                        </td>
                                    </tr>
                                ) : null}
                            </tbody>
                            <tfoot>
                                <tr className="bg-gray-50 font-semibold">
                                    <td
                                        className="border border-gray-300 px-1.5 py-1 text-gray-700"
                                        colSpan={8}
                                    >
                                        {tableRows.length} product row
                                        {tableRows.length === 1 ? '' : 's'}
                                    </td>
                                    <td className="border border-gray-300 px-1.5 py-1 text-right tabular-nums text-gray-700">
                                        {tableRows.reduce(
                                            (sum, row) =>
                                                sum + tableRowStock(row),
                                            0,
                                        )}
                                    </td>
                                </tr>
                            </tfoot>
                        </table>
                    </div>
                    </>
                )}
                </div>
            </div>

            {/* Product Details Dialog */}
            <ProductDetailsDialog
                product={detailsProduct}
                categoryIcon={
                    detailsProduct
                        ? resolveCategoryIcon(
                              categoryIconByName.get(
                                  detailsProduct.category_name,
                              ),
                              detailsProduct.category_name,
                          )
                        : undefined
                }
                onOpenChange={(open) => {
                    if (!open) setDetailsProduct(null);
                }}
                onEdit={openEditFromDetails}
            />

            {/* Add / Edit Category Dialog */}
            <Dialog
                open={categoryDialogOpen}
                onOpenChange={(open) => {
                    setCategoryDialogOpen(open);
                    if (!open) {
                        setEditingCategory(null);
                    }
                }}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>
                            {editingCategory ? 'Edit Category' : 'Add Category'}
                        </DialogTitle>
                        <DialogDescription>
                            {editingCategory
                                ? 'Fix the name, description, or icon for this category. Products in this group keep their items.'
                                : 'Group your products — e.g. Seeds, Fertilizers, Fresh Produce.'}
                        </DialogDescription>
                    </DialogHeader>
                    <div className="flex flex-col gap-4 py-2">
                        <div className="grid gap-2">
                            <Label htmlFor="cat-name">Category name</Label>
                            <Input
                                id="cat-name"
                                value={categoryName}
                                onChange={(e) => {
                                    const value = e.target.value;
                                    setCategoryName(value);
                                    if (!categoryIconTouched) {
                                        setCategoryIconKey(
                                            suggestCategoryIconKey(value),
                                        );
                                    }
                                }}
                                placeholder="e.g. Seeds"
                                autoFocus
                            />
                        </div>
                        <div className="grid gap-2">
                            <Label htmlFor="cat-desc">
                                Description (optional)
                            </Label>
                            <Input
                                id="cat-desc"
                                value={categoryDescription}
                                onChange={(e) =>
                                    setCategoryDescription(e.target.value)
                                }
                                placeholder="Short description"
                            />
                        </div>
                        <div className="grid gap-2">
                            <Label>Icon</Label>
                            <div className="grid grid-cols-5 gap-2 sm:grid-cols-8">
                                {categoryIconOptions.map((option) => {
                                    const Icon = option.icon;
                                    const selected =
                                        categoryIconKey === option.key;
                                    return (
                                        <button
                                            key={option.key}
                                            type="button"
                                            title={option.label}
                                            onClick={() => {
                                                setCategoryIconKey(option.key);
                                                setCategoryIconTouched(true);
                                            }}
                                            className={`flex aspect-square items-center justify-center rounded-xl border transition-colors ${
                                                selected
                                                    ? 'border-primary bg-primary/10 text-primary'
                                                    : 'border-border bg-card text-muted-foreground hover:border-primary/40 hover:text-foreground'
                                            }`}
                                        >
                                            <Icon className="size-5" />
                                        </button>
                                    );
                                })}
                            </div>
                        </div>
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setCategoryDialogOpen(false)}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => void handleSaveCategory()}
                            disabled={savingCategory}
                        >
                            {savingCategory && (
                                <Loader2 className="size-4 animate-spin" />
                            )}
                            {editingCategory ? 'Save Changes' : 'Save Category'}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={categoryManageDialogOpen}
                onOpenChange={setCategoryManageDialogOpen}
            >
                <DialogContent className="max-h-[85vh] overflow-y-auto sm:max-w-lg">
                    <DialogHeader>
                        <DialogTitle>Manage Categories</DialogTitle>
                        <DialogDescription>
                            Rename a category if you made a typo, or update its
                            icon and description.
                        </DialogDescription>
                    </DialogHeader>
                    <div className="flex flex-col gap-2 py-2">
                        {categories.map((cat) => {
                            const Icon = resolveCategoryIcon(cat.icon, cat.name);
                            const count = products.filter(
                                (product) => product.category_name === cat.name,
                            ).length;
                            return (
                                <div
                                    key={cat.id}
                                    className="flex items-center gap-3 rounded-xl border border-border bg-card px-3 py-2.5"
                                >
                                    <div className="flex size-9 shrink-0 items-center justify-center rounded-lg bg-primary/10 text-primary">
                                        <Icon className="size-4" />
                                    </div>
                                    <div className="min-w-0 flex-1">
                                        <p className="truncate font-medium text-foreground">
                                            {cat.name}
                                        </p>
                                        <p className="text-xs text-muted-foreground">
                                            {count} item{count === 1 ? '' : 's'}
                                            {cat.description
                                                ? ` · ${cat.description}`
                                                : ''}
                                        </p>
                                    </div>
                                    <Button
                                        type="button"
                                        variant="outline"
                                        size="sm"
                                        className="shrink-0"
                                        onClick={() => openEditCategory(cat)}
                                    >
                                        <Pencil className="size-3.5" />
                                        Edit
                                    </Button>
                                </div>
                            );
                        })}
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setCategoryManageDialogOpen(false)}
                        >
                            Close
                        </Button>
                        <Button
                            onClick={() => {
                                setCategoryManageDialogOpen(false);
                                openAddCategory();
                            }}
                        >
                            <Plus className="size-4" />
                            Add Category
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            {/* Add/Edit Product Dialog */}
            <Dialog open={productDialogOpen} onOpenChange={setProductDialogOpen}>
                <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-2xl">
                    <DialogHeader>
                        <DialogTitle>
                            {form.id ? 'Edit Product' : 'Add Product'}
                        </DialogTitle>
                        <DialogDescription>
                            {form.id
                                ? 'Update the product details.'
                                : 'Create a product. New categories are created automatically if needed.'}
                        </DialogDescription>
                    </DialogHeader>

                    <div className="grid gap-4 py-1">
                        <div className="grid gap-4">
                            <div className="grid gap-2">
                                <Label htmlFor="p-name">Product name</Label>
                                <Input
                                    id="p-name"
                                    value={form.name}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            name: e.target.value,
                                        }))
                                    }
                                    placeholder="e.g. Tomato Seeds"
                                    autoFocus
                                />
                            </div>

                            <div className="grid gap-2">
                                <Label>Category</Label>
                                {categories.length > 0 ? (
                                    <Select
                                        value={form.category || undefined}
                                        onValueChange={(value) =>
                                            setForm((f) => ({
                                                ...f,
                                                category: value,
                                            }))
                                        }
                                    >
                                        <SelectTrigger className="w-full">
                                            <SelectValue placeholder="Choose a category" />
                                        </SelectTrigger>
                                        <SelectContent>
                                            {categories.map((cat) => (
                                                <SelectItem
                                                    key={cat.id}
                                                    value={cat.name}
                                                >
                                                    {cat.name}
                                                </SelectItem>
                                            ))}
                                        </SelectContent>
                                    </Select>
                                ) : (
                                    <Input
                                        value={form.category}
                                        onChange={(e) =>
                                            setForm((f) => ({
                                                ...f,
                                                category: e.target.value,
                                            }))
                                        }
                                        placeholder="Type a category name"
                                    />
                                )}
                            </div>
                        </div>

                        <div className="grid gap-4 sm:grid-cols-2">
                            <div className="grid gap-2">
                                <Label htmlFor="p-price">Price (₱)</Label>
                                <Input
                                    id="p-price"
                                    type="number"
                                    inputMode="decimal"
                                    min="0"
                                    step="0.01"
                                    value={form.price}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            price: e.target.value,
                                        }))
                                    }
                                    placeholder="0.00"
                                />
                            </div>
                            <div className="grid gap-2">
                                <Label htmlFor="p-cost">
                                    Cost price (optional)
                                </Label>
                                <Input
                                    id="p-cost"
                                    type="number"
                                    inputMode="decimal"
                                    min="0"
                                    step="0.01"
                                    value={form.cost_price}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            cost_price: e.target.value,
                                        }))
                                    }
                                    placeholder="0.00"
                                />
                            </div>
                        </div>

                        <div className="grid gap-4 sm:grid-cols-2">
                            <div className="grid gap-2">
                                <Label htmlFor="p-stock">Stock</Label>
                                <Input
                                    id="p-stock"
                                    type="number"
                                    inputMode="numeric"
                                    min="0"
                                    value={form.stock}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            stock: e.target.value,
                                        }))
                                    }
                                    placeholder="0"
                                />
                            </div>
                            <div className="grid gap-2">
                                <Label htmlFor="p-reorder">Reorder at</Label>
                                <Input
                                    id="p-reorder"
                                    type="number"
                                    inputMode="numeric"
                                    min="0"
                                    value={form.reorder_level}
                                    onChange={(e) =>
                                        setForm((f) => ({
                                            ...f,
                                            reorder_level: e.target.value,
                                        }))
                                    }
                                    placeholder="5"
                                />
                            </div>
                        </div>

                        <div className="grid gap-2">
                            <Label htmlFor="p-deal">Deal (optional)</Label>
                            <Input
                                id="p-deal"
                                value={form.deal}
                                onChange={(e) =>
                                    setForm((f) => ({
                                        ...f,
                                        deal: e.target.value,
                                    }))
                                }
                                placeholder="Promo text shown at POS"
                            />
                        </div>

                        <div className="grid gap-2">
                            <Label htmlFor="p-desc">
                                Description (optional)
                            </Label>
                            <Input
                                id="p-desc"
                                value={form.description}
                                onChange={(e) =>
                                    setForm((f) => ({
                                        ...f,
                                        description: e.target.value,
                                    }))
                                }
                                placeholder="Short description"
                            />
                        </div>
                    </div>

                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setProductDialogOpen(false)}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => void handleSaveProduct()}
                            disabled={savingProduct}
                        >
                            {savingProduct && (
                                <Loader2 className="size-4 animate-spin" />
                            )}
                            {form.id ? 'Update Product' : 'Save Product'}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog open={importDialogOpen} onOpenChange={setImportDialogOpen}>
                <DialogContent className="sm:max-w-md">
                    <DialogHeader>
                        <DialogTitle>Import products from Excel or CSV</DialogTitle>
                        <DialogDescription>
                            Upload your existing inventory spreadsheet (.xlsx,
                            .xls, or .csv). Works with your legacy file
                            (Category, Item, Option, Price, Cost, Morning
                            Inventory) or a system export backup (id, category,
                            item, option, price, cost_price, deal, stock,
                            reorder_level). Category numbers like &quot;01
                            CHEMICALS&quot; are saved as words only. Extra
                            columns are ignored.
                        </DialogDescription>
                    </DialogHeader>
                    <div className="flex flex-col gap-3 py-2">
                        <Button
                            type="button"
                            variant="outline"
                            disabled={exportingProducts}
                            onClick={() => void handleExportProducts()}
                        >
                            {exportingProducts ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                <Download className="size-4" />
                            )}
                            Download backup (CSV)
                        </Button>
                        <input
                            ref={importFileRef}
                            type="file"
                            accept=".csv,.xlsx,.xls,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/vnd.ms-excel"
                            className="hidden"
                            onChange={(event) => {
                                const file = event.target.files?.[0];
                                if (file) {
                                    void handleImportFile(file);
                                }
                            }}
                        />
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setImportDialogOpen(false)}
                        >
                            Cancel
                        </Button>
                        <Button
                            disabled={importingProducts}
                            onClick={() => importFileRef.current?.click()}
                        >
                            {importingProducts && (
                                <Loader2 className="size-4 animate-spin" />
                            )}
                            Choose Excel or CSV file
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={deleteTarget !== null}
                onOpenChange={(open) => {
                    if (!open && !deletingProduct) {
                        setDeleteTarget(null);
                    }
                }}
            >
                <DialogContent className="sm:max-w-md">
                    <DialogHeader className="items-center text-center sm:items-center sm:text-center">
                        <div className="mb-1 flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
                            <Trash2 className="size-5" />
                        </div>
                        <DialogTitle>Delete product?</DialogTitle>
                        <DialogDescription className="text-center">
                            {deleteTarget
                                ? `Remove "${deleteTarget.name}" from your catalog? It will disappear from POS and items, but past sales records are kept.`
                                : null}
                        </DialogDescription>
                    </DialogHeader>
                    <DialogFooter className="gap-2 sm:justify-center">
                        <Button
                            variant="outline"
                            onClick={() => setDeleteTarget(null)}
                            disabled={deletingProduct}
                        >
                            Cancel
                        </Button>
                        <Button
                            variant="destructive"
                            onClick={() => void confirmDeleteProduct()}
                            disabled={deletingProduct}
                        >
                            {deletingProduct ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                'Delete'
                            )}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={leavePromptOpen}
                onOpenChange={(open) => {
                    if (!open) {
                        closeLeavePrompt();
                    }
                }}
            >
                <DialogContent className="sm:max-w-md">
                    <DialogHeader>
                        <DialogTitle>Unsaved changes</DialogTitle>
                        <DialogDescription>
                            You have unsaved spreadsheet edits. Save them before
                            leaving, discard them, or stay on this page.
                        </DialogDescription>
                    </DialogHeader>
                    <DialogFooter className="gap-2 sm:gap-0">
                        <Button
                            type="button"
                            variant="outline"
                            disabled={savingAll}
                            onClick={closeLeavePrompt}
                        >
                            Cancel
                        </Button>
                        <Button
                            type="button"
                            variant="outline"
                            disabled={savingAll}
                            onClick={handleDiscardAndLeave}
                        >
                            Discard & leave
                        </Button>
                        <Button
                            type="button"
                            disabled={savingAll}
                            onClick={() => void handleSaveAndLeave()}
                        >
                            {savingAll ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                <Save className="size-4" />
                            )}
                            Save & leave
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        </>
    );
}

function CategoryChip({
    label,
    count,
    active,
    onClick,
    icon,
}: {
    label: string;
    count: number;
    active: boolean;
    onClick: () => void;
    icon?: React.ReactNode;
}) {
    return (
        <button
            type="button"
            onClick={onClick}
            className={`inline-flex items-center gap-2 rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors ${
                active
                    ? 'border-primary bg-primary text-primary-foreground'
                    : 'border-border bg-card text-muted-foreground hover:border-primary/40 hover:text-foreground'
            }`}
        >
            {icon}
            {label}
            <span
                className={`rounded-full px-1.5 text-xs ${
                    active
                        ? 'bg-primary-foreground/20'
                        : 'bg-secondary text-secondary-foreground'
                }`}
            >
                {count}
            </span>
        </button>
    );
}

function DetailRow({
    label,
    value,
}: {
    label: string;
    value: ReactNode;
}) {
    return (
        <div className="flex flex-col gap-0.5">
            <span className="text-[11px] font-semibold tracking-wider text-muted-foreground uppercase">
                {label}
            </span>
            <span className="text-sm font-medium text-foreground">{value}</span>
        </div>
    );
}

function ProductDetailsDialog({
    product,
    categoryIcon: CategoryIcon,
    onOpenChange,
    onEdit,
}: {
    product: PosProduct | null;
    categoryIcon?: LucideIcon;
    onOpenChange: (open: boolean) => void;
    onEdit: (product: PosProduct) => void;
}) {
    if (!product) return null;

    const Icon = CategoryIcon;
    const price = toNumber(product.price);
    const cost =
        product.cost_price === null || product.cost_price === undefined
            ? null
            : toNumber(product.cost_price);
    const margin = cost === null ? null : price - cost;
    const stock = toNumber(product.stock);
    const reorder = toNumber(product.reorder_level);
    const low = stock <= reorder;

    return (
        <Dialog open={product !== null} onOpenChange={onOpenChange}>
            <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-lg">
                <DialogHeader>
                    <DialogTitle>{product.name}</DialogTitle>
                    <DialogDescription>
                        <span className="inline-flex items-center gap-1.5">
                            {Icon && <Icon className="size-3.5" />}
                            {product.category_name}
                        </span>
                    </DialogDescription>
                </DialogHeader>

                <div className="grid gap-5 py-1">
                    <div className="flex items-end justify-between gap-3">
                        <div>
                            <p className="text-2xl font-bold text-primary">
                                ₱{formatMoney(price)}
                            </p>
                        </div>
                        <span
                            className={`inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold ${
                                low
                                    ? 'bg-destructive/10 text-destructive'
                                    : 'bg-primary/10 text-primary'
                            }`}
                        >
                            {stock} in stock
                        </span>
                    </div>

                    <div className="grid grid-cols-2 gap-4 rounded-xl border border-border/60 bg-secondary/30 p-4">
                        {product.option?.trim() && (
                            <DetailRow label="Option" value={product.option} />
                        )}
                        {cost !== null && (
                            <DetailRow
                                label="Cost price"
                                value={`₱${formatMoney(cost)}`}
                            />
                        )}
                        {margin !== null && (
                            <DetailRow
                                label="Margin"
                                value={`₱${formatMoney(margin)}`}
                            />
                        )}
                        <DetailRow label="Stock" value={`${stock}`} />
                        <DetailRow label="Reorder at" value={`${reorder}`} />
                        {product.deal?.trim() && (
                            <DetailRow label="Deal" value={product.deal} />
                        )}
                    </div>

                    {product.description && (
                        <div className="flex flex-col gap-1">
                            <span className="text-[11px] font-semibold tracking-wider text-muted-foreground uppercase">
                                Description
                            </span>
                            <p className="text-sm leading-relaxed text-foreground">
                                {product.description}
                            </p>
                        </div>
                    )}
                </div>

                <DialogFooter>
                    <Button
                        variant="outline"
                        onClick={() => onOpenChange(false)}
                    >
                        Close
                    </Button>
                    <Button onClick={() => onEdit(product)}>
                        <Pencil className="size-4" />
                        Edit Product
                    </Button>
                </DialogFooter>
            </DialogContent>
        </Dialog>
    );
}

function focusSpreadsheetCell(cell: HTMLElement) {
    cell.focus({ preventScroll: true });
}

function navigateSpreadsheetCell(
    current: HTMLElement,
    direction: 'next' | 'prev' | 'up' | 'down',
) {
    const table = current.closest('table');
    if (!table) {
        return;
    }

    const cells = Array.from(
        table.querySelectorAll<HTMLElement>(
            '[data-spreadsheet-cell]:not(:disabled)',
        ),
    );
    const currentIndex = cells.indexOf(current);
    if (currentIndex === -1) {
        return;
    }

    if (direction === 'next') {
        const next = cells[currentIndex + 1];
        if (next) {
            focusSpreadsheetCell(next);
        }
        return;
    }

    if (direction === 'prev') {
        const prev = cells[currentIndex - 1];
        if (prev) {
            focusSpreadsheetCell(prev);
        }
        return;
    }

    const row = parseInt(current.dataset.row ?? '0', 10);
    const col = parseInt(current.dataset.col ?? '0', 10);
    const targetRow = direction === 'down' ? row + 1 : row - 1;

    const verticalMatch = cells
        .filter((cell) => {
            const cellRow = parseInt(cell.dataset.row ?? '0', 10);
            const cellCol = parseInt(cell.dataset.col ?? '0', 10);
            return cellCol === col && cellRow === targetRow;
        })
        .sort(
            (a, b) =>
                parseInt(a.dataset.row ?? '0', 10) -
                parseInt(b.dataset.row ?? '0', 10),
        )[0];

    if (verticalMatch) {
        focusSpreadsheetCell(verticalMatch);
        return;
    }

    const fallback = cells.filter((cell) => {
        const cellRow = parseInt(cell.dataset.row ?? '0', 10);
        const cellCol = parseInt(cell.dataset.col ?? '0', 10);
        if (cellCol !== col) {
            return false;
        }
        return direction === 'down' ? cellRow > row : cellRow < row;
    });

    fallback.sort((a, b) => {
        const aRow = parseInt(a.dataset.row ?? '0', 10);
        const bRow = parseInt(b.dataset.row ?? '0', 10);
        return direction === 'down' ? aRow - bRow : bRow - aRow;
    });

    const target = fallback[0];
    if (target) {
        focusSpreadsheetCell(target);
    }
}

function handleSpreadsheetKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.key === 'Enter') {
        event.preventDefault();
        navigateSpreadsheetCell(event.currentTarget, 'down');
        return;
    }

    if (event.key === 'Tab') {
        event.preventDefault();
        navigateSpreadsheetCell(
            event.currentTarget,
            event.shiftKey ? 'prev' : 'next',
        );
        return;
    }

    if (event.key === 'Escape') {
        event.preventDefault();
        event.currentTarget.blur();
    }
}

type SpreadsheetCellProps = {
    saving?: boolean;
    dataRow: number;
    dataCol: number;
};

function SpreadsheetTextCell({
    value,
    saving = false,
    dataRow,
    dataCol,
    disabled = false,
    allowEmpty = false,
    onCommit,
}: SpreadsheetCellProps & {
    value: string;
    disabled?: boolean;
    allowEmpty?: boolean;
    onCommit: (value: string) => Promise<void>;
}) {
    const [draft, setDraft] = useState(value);

    useEffect(() => {
        setDraft(value);
    }, [value]);

    async function commit() {
        const trimmed = draft.trim();
        if (trimmed === value.trim()) {
            return;
        }
        if (trimmed === '' && !allowEmpty) {
            toast.error('This field cannot be empty');
            setDraft(value);
            return;
        }
        if (trimmed.length > DEAL_MAX_LENGTH) {
            toast.error(`Deal must be ${DEAL_MAX_LENGTH} characters or less`);
            setDraft(value);
            return;
        }
        try {
            await onCommit(trimmed);
        } catch {
            setDraft(value);
        }
    }

    return (
        <input
            type="text"
            value={draft}
            disabled={disabled || saving}
            data-spreadsheet-cell=""
            data-row={dataRow}
            data-col={dataCol}
            maxLength={DEAL_MAX_LENGTH}
            className={cn(
                SPREADSHEET_INPUT,
                'text-left',
                draft.trim().length > DEAL_MAX_LENGTH && SPREADSHEET_INPUT_INVALID,
            )}
            onChange={(event) => setDraft(event.target.value)}
            onBlur={() => {
                void commit();
            }}
            onKeyDown={handleSpreadsheetKeyDown}
        />
    );
}

function SpreadsheetSelectCell({
    value,
    options,
    saving = false,
    dataRow,
    dataCol,
    onCommit,
}: SpreadsheetCellProps & {
    value: string;
    options: string[];
    onCommit: (value: string) => Promise<void>;
}) {
    const [draft, setDraft] = useState(value);

    useEffect(() => {
        setDraft(value);
    }, [value]);

    async function commit(nextValue: string) {
        if (nextValue === value) {
            return;
        }
        try {
            await onCommit(nextValue);
        } catch {
            setDraft(value);
        }
    }

    return (
        <select
            value={draft}
            disabled={saving}
            data-spreadsheet-cell=""
            data-row={dataRow}
            data-col={dataCol}
            className={cn(
                SPREADSHEET_INPUT,
                'cursor-pointer text-left',
                saving && 'opacity-50',
            )}
            onChange={(event) => {
                const nextValue = event.target.value;
                setDraft(nextValue);
                void commit(nextValue);
            }}
            onKeyDown={handleSpreadsheetKeyDown}
        >
            {options.map((option) => (
                <option key={option} value={option}>
                    {option}
                </option>
            ))}
        </select>
    );
}

function parseInlineNumber(raw: string, allowEmpty: boolean): number | null {
    const trimmed = raw.trim();
    if (trimmed === '') {
        return allowEmpty ? null : 0;
    }
    const parsed = parseFloat(trimmed.replace(/,/g, ''));
    return Number.isFinite(parsed) ? parsed : null;
}

type SpreadsheetParseResult<T> =
    | { ok: true; value: T }
    | { ok: false; message: string };

function parseSpreadsheetDecimal(
    raw: string,
    options: {
        allowEmpty?: boolean;
        label?: string;
        min?: number;
    } = {},
): SpreadsheetParseResult<number | null> {
    const { allowEmpty = false, label = 'Value', min = 0 } = options;
    const trimmed = raw.trim();

    if (trimmed === '') {
        if (allowEmpty) {
            return { ok: true, value: null };
        }
        return { ok: false, message: `${label} is required` };
    }

    const parsed = parseFloat(trimmed.replace(/,/g, ''));
    if (!Number.isFinite(parsed)) {
        return { ok: false, message: `Enter a valid ${label.toLowerCase()}` };
    }
    if (parsed < min) {
        return {
            ok: false,
            message:
                min === 0
                    ? `${label} cannot be negative`
                    : `${label} must be at least ${min}`,
        };
    }

    return { ok: true, value: parsed };
}

function parseSpreadsheetInteger(
    raw: string,
    options: { label?: string; allowEmpty?: boolean } = {},
): SpreadsheetParseResult<number> {
    const { label = 'Stock', allowEmpty = true } = options;
    const trimmed = raw.trim().replace(/,/g, '');

    if (trimmed === '') {
        return { ok: true, value: allowEmpty ? 0 : 0 };
    }

    if (!/^\d+$/.test(trimmed)) {
        return { ok: false, message: `${label} must be a whole number` };
    }

    const parsed = parseInt(trimmed, 10);
    if (!Number.isFinite(parsed) || parsed < 0) {
        return { ok: false, message: `Enter a valid ${label.toLowerCase()}` };
    }

    return { ok: true, value: parsed };
}

function isInvalidDecimalDraft(
    draft: string,
    allowEmpty: boolean,
    min = 0,
): boolean {
    const result = parseSpreadsheetDecimal(draft, { allowEmpty, min });
    return !result.ok;
}

function isInvalidIntegerDraft(draft: string): boolean {
    const trimmed = draft.trim().replace(/,/g, '');
    if (trimmed === '') {
        return false;
    }
    return !/^\d+$/.test(trimmed);
}

function decimalsEqual(
    a: number | null,
    b: number | null,
    decimals: number,
): boolean {
    if (a === null && b === null) {
        return true;
    }
    if (a === null || b === null) {
        return false;
    }
    return (
        Math.abs(a - b) < 10 ** -decimals ||
        a.toFixed(decimals) === b.toFixed(decimals)
    );
}

function SpreadsheetNumberCell({
    value,
    decimals,
    allowEmpty = false,
    label = 'Value',
    saving = false,
    dataRow,
    dataCol,
    onCommit,
}: SpreadsheetCellProps & {
    value: number | null;
    decimals: number;
    allowEmpty?: boolean;
    label?: string;
    onCommit: (value: number | null) => Promise<void>;
}) {
    const displayValue =
        value === null
            ? ''
            : value.toLocaleString(undefined, {
                  minimumFractionDigits: decimals,
                  maximumFractionDigits: decimals,
                  useGrouping: false,
              });
    const [draft, setDraft] = useState(displayValue);

    useEffect(() => {
        setDraft(displayValue);
    }, [displayValue]);

    const invalid = isInvalidDecimalDraft(draft, allowEmpty);

    async function commit() {
        const result = parseSpreadsheetDecimal(draft, { allowEmpty, label });
        if (!result.ok) {
            toast.error(result.message);
            setDraft(displayValue);
            return;
        }
        if (decimalsEqual(result.value, value, decimals)) {
            return;
        }
        try {
            await onCommit(result.value);
        } catch {
            setDraft(displayValue);
        }
    }

    return (
        <input
            type="text"
            inputMode="decimal"
            value={draft}
            disabled={saving}
            data-spreadsheet-cell=""
            data-row={dataRow}
            data-col={dataCol}
            className={cn(
                SPREADSHEET_INPUT,
                'text-right tabular-nums',
                invalid && SPREADSHEET_INPUT_INVALID,
            )}
            onChange={(event) => setDraft(event.target.value)}
            onBlur={() => {
                void commit();
            }}
            onKeyDown={handleSpreadsheetKeyDown}
        />
    );
}

function SpreadsheetIntegerCell({
    value,
    low = false,
    label = 'Stock',
    saving = false,
    dataRow,
    dataCol,
    onCommit,
}: SpreadsheetCellProps & {
    value: number;
    low?: boolean;
    label?: string;
    onCommit: (value: number) => Promise<void>;
}) {
    const [draft, setDraft] = useState(String(value));

    useEffect(() => {
        setDraft(String(value));
    }, [value]);

    const invalid = isInvalidIntegerDraft(draft);

    async function commit() {
        const result = parseSpreadsheetInteger(draft, { label });
        if (!result.ok) {
            toast.error(result.message);
            setDraft(String(value));
            return;
        }
        if (result.value === value) {
            return;
        }
        try {
            await onCommit(result.value);
        } catch {
            setDraft(String(value));
        }
    }

    return (
        <input
            type="text"
            inputMode="numeric"
            value={draft}
            disabled={saving}
            data-spreadsheet-cell=""
            data-row={dataRow}
            data-col={dataCol}
            className={cn(
                SPREADSHEET_INPUT,
                'text-right tabular-nums',
                low && !invalid && 'text-red-600',
                invalid && SPREADSHEET_INPUT_INVALID,
            )}
            onChange={(event) => setDraft(event.target.value)}
            onBlur={() => {
                void commit();
            }}
            onKeyDown={handleSpreadsheetKeyDown}
        />
    );
}

function NewProductSpreadsheetRow({
    draft,
    saving,
    rowIndex,
    categoryNames,
    itemInputRef,
    onDraftChange,
    onTryCommit,
    onFocusRow,
}: {
    draft: NewProductDraft;
    saving: boolean;
    rowIndex: number;
    categoryNames: string[];
    itemInputRef: RefObject<HTMLInputElement | null>;
    onDraftChange: (patch: Partial<NewProductDraft>) => void;
    onTryCommit: () => Promise<void>;
    onFocusRow: () => void;
}) {
    const hasCategories = categoryNames.length > 0;
    const placeholderClass = 'placeholder:text-gray-400';
    const priceInvalid = isInvalidDecimalDraft(draft.price, true);
    const costInvalid = isInvalidDecimalDraft(draft.cost_price, true);
    const stockInvalid = isInvalidIntegerDraft(draft.stock);
    const dealInvalid = draft.deal.trim().length > DEAL_MAX_LENGTH;

    function handleFieldBlur(field: NewProductBlurField) {
        if (!shouldCommitNewProductOnBlur(draft, field)) {
            return;
        }
        void onTryCommit();
    }

    return (
        <tr className={SPREADSHEET_NEW_ROW}>
            <td
                className={cn(
                    SPREADSHEET_ROW_NUM,
                    'cursor-pointer hover:bg-gray-200',
                )}
                title="Add new product"
                onClick={onFocusRow}
            >
                <Plus className="mx-auto size-3.5 text-emerald-700" />
            </td>
            <td className={SPREADSHEET_CELL}>
                {hasCategories ? (
                    <select
                        value={draft.category}
                        disabled={saving}
                        data-spreadsheet-cell=""
                        data-row={rowIndex}
                        data-col={1}
                        className={cn(
                            SPREADSHEET_INPUT,
                            'cursor-pointer text-left italic text-gray-600',
                            saving && 'opacity-50',
                        )}
                        onChange={(event) =>
                            onDraftChange({ category: event.target.value })
                        }
                        onBlur={() => handleFieldBlur('category')}
                        onKeyDown={handleSpreadsheetKeyDown}
                    >
                        {categoryNames.map((option) => (
                            <option key={option} value={option}>
                                {option}
                            </option>
                        ))}
                    </select>
                ) : (
                    <span className="block px-1.5 py-1 text-xs text-gray-400 italic">
                        Add category first
                    </span>
                )}
            </td>
            <td className={SPREADSHEET_CELL}>
                <input
                    ref={itemInputRef}
                    type="text"
                    value={draft.name}
                    disabled={saving || !hasCategories}
                    placeholder="New item name"
                    data-spreadsheet-cell=""
                    data-row={rowIndex}
                    data-col={2}
                    className={cn(
                        SPREADSHEET_INPUT,
                        'text-left italic text-gray-700',
                        placeholderClass,
                    )}
                    onChange={(event) =>
                        onDraftChange({ name: event.target.value })
                    }
                    onBlur={() => handleFieldBlur('name')}
                    onKeyDown={handleSpreadsheetKeyDown}
                />
            </td>
            <td className={SPREADSHEET_CELL}>
                <input
                    type="text"
                    value={draft.option}
                    disabled={saving || !hasCategories}
                    placeholder="Pack / unit"
                    maxLength={120}
                    data-spreadsheet-cell=""
                    data-row={rowIndex}
                    data-col={3}
                    className={cn(
                        SPREADSHEET_INPUT,
                        'text-left italic text-gray-700',
                        placeholderClass,
                    )}
                    onChange={(event) =>
                        onDraftChange({ option: event.target.value })
                    }
                    onBlur={() => handleFieldBlur('option')}
                    onKeyDown={handleSpreadsheetKeyDown}
                />
            </td>
            <td className={SPREADSHEET_CELL}>
                <input
                    type="text"
                    inputMode="decimal"
                    value={draft.price}
                    disabled={saving || !hasCategories}
                    placeholder="0.00"
                    data-spreadsheet-cell=""
                    data-row={rowIndex}
                    data-col={4}
                    className={cn(
                        SPREADSHEET_INPUT,
                        'text-right tabular-nums text-gray-700',
                        placeholderClass,
                        priceInvalid && SPREADSHEET_INPUT_INVALID,
                    )}
                    onChange={(event) =>
                        onDraftChange({ price: event.target.value })
                    }
                    onBlur={() => handleFieldBlur('price')}
                    onKeyDown={handleSpreadsheetKeyDown}
                />
            </td>
            <td className={SPREADSHEET_CELL}>
                <input
                    type="text"
                    inputMode="decimal"
                    value={draft.cost_price}
                    disabled={saving || !hasCategories}
                    placeholder="Cost"
                    data-spreadsheet-cell=""
                    data-row={rowIndex}
                    data-col={5}
                    className={cn(
                        SPREADSHEET_INPUT,
                        'text-right tabular-nums text-gray-700',
                        placeholderClass,
                        costInvalid && SPREADSHEET_INPUT_INVALID,
                    )}
                    onChange={(event) =>
                        onDraftChange({ cost_price: event.target.value })
                    }
                    onBlur={() => handleFieldBlur('cost_price')}
                    onKeyDown={handleSpreadsheetKeyDown}
                />
            </td>
            <td className={SPREADSHEET_CELL}>
                <input
                    type="text"
                    value={draft.deal}
                    disabled={saving || !hasCategories}
                    placeholder="Promo / note"
                    maxLength={DEAL_MAX_LENGTH}
                    data-spreadsheet-cell=""
                    data-row={rowIndex}
                    data-col={6}
                    className={cn(
                        SPREADSHEET_INPUT,
                        'text-left text-gray-700',
                        placeholderClass,
                        dealInvalid && SPREADSHEET_INPUT_INVALID,
                    )}
                    onChange={(event) =>
                        onDraftChange({ deal: event.target.value })
                    }
                    onBlur={() => handleFieldBlur('deal')}
                    onKeyDown={handleSpreadsheetKeyDown}
                />
            </td>
            <td className={SPREADSHEET_CELL}>
                <input
                    type="text"
                    inputMode="numeric"
                    value={draft.stock}
                    disabled={saving || !hasCategories}
                    placeholder="0"
                    data-spreadsheet-cell=""
                    data-row={rowIndex}
                    data-col={7}
                    className={cn(
                        SPREADSHEET_INPUT,
                        'text-right tabular-nums text-gray-700',
                        placeholderClass,
                        stockInvalid && SPREADSHEET_INPUT_INVALID,
                    )}
                    onChange={(event) =>
                        onDraftChange({ stock: event.target.value })
                    }
                    onBlur={() => handleFieldBlur('stock')}
                    onKeyDown={handleSpreadsheetKeyDown}
                />
            </td>
            <td className={SPREADSHEET_CELL} />
        </tr>
    );
}

ItemsPage.layout = {
    breadcrumbs: [
        { title: 'Dashboard', href: dashboard() },
        { title: 'Items', href: '/pos/items' },
    ],
};

export default function ItemsPage() {
    return <ItemsCatalogView />;
}
