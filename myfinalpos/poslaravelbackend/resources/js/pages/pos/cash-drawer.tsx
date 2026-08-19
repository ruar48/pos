import { Head, usePage } from '@inertiajs/react';
import {
    Banknote,
    Calendar,
    Download,
    Loader2,
    Lock,
    Pencil,
    Plus,
    Printer,
    RefreshCw,
    Trash2,
    Wallet,
    type LucideIcon,
} from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
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
import { formatServerDateTime } from '@/lib/datetime';
import {
    addCashAddition,
    addDrawerExpense,
    deleteCashAddition,
    deleteDrawerExpense,
    exportCashAdditions,
    exportDrawerExpenses,
    fetchCashDrawerSummary,
    isCashDrawerUnchanged,
    updateCashAddition,
    updateDrawerExpense,
    watchCashDrawer,
    updateStartingCash,
    verifyCashDrawerPin,
    type CashAddition,
    type CashDrawerData,
    type CashDrawerMutation,
    type DrawerExpense,
    type DrawerExpensePaymentType,
} from '@/lib/cash-drawer-api';
import { buildAllExpensesReceiptLines, buildCashAdditionReceiptLines, buildExpenseReceiptLines } from '@/lib/expense-receipt';
import {
    DEFAULT_RECEIPT_STORE,
    type ReceiptStore,
} from '@/lib/store-settings-api';
import { printThermalCopies } from '@/lib/thermal-print';
import { cn } from '@/lib/utils';
import {
    businessDayResetLabel,
    currentBusinessDate,
    isCurrentBusinessDate,
} from '@/lib/business-day';

function formatMoney(value: number): string {
    return value.toLocaleString(undefined, {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
    });
}

function peso(value: number): string {
    return `₱${formatMoney(value)}`;
}

function formatDateTime(value: string): string {
    return formatServerDateTime(value);
}

function downloadCsv(filename: string, header: string[], rows: (string | number)[][]) {
    const escape = (v: string | number) => {
        const s = String(v);
        return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    };
    const lines = [
        header.join(','),
        ...rows.map((row) => row.map(escape).join(',')),
    ];
    const blob = new Blob(['\uFEFF', lines.join('\n')], {
        type: 'text/csv;charset=utf-8;',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
}

function expensePaymentLabel(
    paymentType: DrawerExpensePaymentType,
): string {
    if (paymentType === 'gcash') return 'GCash';
    if (paymentType === 'bank') return 'Bank';
    return 'Cash';
}

function formatExpenseReferenceNo(
    businessDate: string,
    sequence: number,
): string {
    return `${businessDate}-${String(sequence).padStart(3, '0')}`;
}

function mergeDrawerMutation(
    current: CashDrawerData,
    mutation: CashDrawerMutation,
): CashDrawerData {
    let expenses = current.expenses;
    let cashAdditions = current.cash_additions;

    if (mutation.expense) {
        const existingIndex = expenses.findIndex(
            (row) => row.id === mutation.expense?.id,
        );
        if (existingIndex >= 0) {
            expenses = expenses.map((row, index) =>
                index === existingIndex ? mutation.expense! : row,
            );
        } else {
            expenses = [mutation.expense, ...expenses];
        }
    }

    if (mutation.deleted_expense_id) {
        expenses = expenses.filter(
            (row) => row.id !== mutation.deleted_expense_id,
        );
    }

    if (mutation.cash_addition) {
        const existingIndex = cashAdditions.findIndex(
            (row) => row.id === mutation.cash_addition?.id,
        );
        if (existingIndex >= 0) {
            cashAdditions = cashAdditions.map((row, index) =>
                index === existingIndex ? mutation.cash_addition! : row,
            );
        } else {
            cashAdditions = [mutation.cash_addition, ...cashAdditions];
        }
    }

    if (mutation.deleted_cash_addition_id) {
        cashAdditions = cashAdditions.filter(
            (row) => row.id !== mutation.deleted_cash_addition_id,
        );
    }

    return {
        ...current,
        business_date: mutation.business_date,
        session_id: mutation.session_id,
        revision: mutation.revision,
        summary: mutation.summary,
        range: mutation.range,
        expenses,
        cash_additions: cashAdditions,
    };
}

function applyOptimisticExpense(
    current: CashDrawerData,
    expense: DrawerExpense,
): CashDrawerData {
    return mergeDrawerMutation(current, {
        business_date: current.business_date,
        session_id: current.session_id,
        revision: current.revision,
        summary: current.summary,
        range: current.range,
        expense,
    });
}

function applyOptimisticCashAddition(
    current: CashDrawerData,
    addition: CashAddition,
): CashDrawerData {
    return mergeDrawerMutation(current, {
        business_date: current.business_date,
        session_id: current.session_id,
        revision: current.revision,
        summary: {
            ...current.summary,
            cash_added: current.summary.cash_added + addition.amount,
            cash_in_drawer: current.summary.cash_in_drawer + addition.amount,
        },
        range: current.range,
        cash_addition: addition,
    });
}

type ExpenseFilter = 'all' | DrawerExpensePaymentType;

type DeleteTarget =
    | { kind: 'expense'; item: DrawerExpense }
    | { kind: 'cash_addition'; item: CashAddition };

type ExpensePrintSettings = {
    currency_symbol: string;
    double_print_receipt: boolean;
    receipt_store: ReceiptStore;
};

type PageProps = {
    businessDayResetHour: number;
    hasCashDrawerPin: boolean;
    printSettings: ExpensePrintSettings;
};

function SummaryCard({
    label,
    value,
    tone,
    editable = false,
    onEdit,
}: {
    label: string;
    value: string;
    tone: 'green' | 'orange' | 'red' | 'teal';
    editable?: boolean;
    onEdit?: () => void;
}) {
    const toneClass = {
        green: 'border-emerald-500/30 bg-emerald-500/5',
        orange: 'border-amber-500/30 bg-amber-500/5',
        red: 'border-orange-500/30 bg-orange-500/5',
        teal: 'border-teal-500/30 bg-teal-500/5',
    }[tone];

    const valueClass = {
        green: 'text-emerald-700',
        orange: 'text-amber-700',
        red: 'text-orange-700',
        teal: 'text-teal-700',
    }[tone];

    return (
        <div className={cn('agri-stat-card relative border', toneClass)}>
            <div className="mb-2 flex items-start justify-between gap-2">
                <span className="agri-stat-label">{label}</span>
                {editable && onEdit && (
                    <button
                        type="button"
                        onClick={onEdit}
                        className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-background hover:text-foreground"
                        aria-label={`Edit ${label}`}
                    >
                        <Pencil className="size-3.5" />
                    </button>
                )}
            </div>
            <p className={cn('agri-stat-value', valueClass)}>{value}</p>
        </div>
    );
}

function PanelHeader({
    title,
    tone,
    icon: Icon,
}: {
    title: string;
    tone: 'orange' | 'teal';
    icon: LucideIcon;
}) {
    const toneClass =
        tone === 'orange'
            ? 'border-amber-500/30 bg-amber-500/10 text-amber-800'
            : 'border-teal-500/30 bg-teal-500/10 text-teal-800';

    return (
        <div
            className={cn(
                'flex items-center gap-2 rounded-t-2xl border-b px-5 py-3',
                toneClass,
            )}
        >
            <Icon className="size-4" />
            <h2 className="text-sm font-bold tracking-wide uppercase">{title}</h2>
        </div>
    );
}

export default function CashDrawerPage() {
    const { businessDayResetHour, hasCashDrawerPin, printSettings } =
        usePage<PageProps>().props;
    const receiptStore = printSettings?.receipt_store ?? DEFAULT_RECEIPT_STORE;
    const currencySymbol = printSettings?.currency_symbol ?? 'PHP';
    const doublePrintReceipt = printSettings?.double_print_receipt ?? false;

    const [unlocked, setUnlocked] = useState(false);
    const [unlocking, setUnlocking] = useState(false);
    const [gatePin, setGatePin] = useState('');
    const [gateError, setGateError] = useState<string | null>(null);
    const unlockedPinRef = useRef('');

    const [selectedDate, setSelectedDate] = useState(() =>
        currentBusinessDate(undefined, businessDayResetHour),
    );
    const [data, setData] = useState<CashDrawerData | null>(null);
    const [loading, setLoading] = useState(true);
    const [savingCash, setSavingCash] = useState(false);
    const [savingExpense, setSavingExpense] = useState(false);
    const [savingStartingCash, setSavingStartingCash] = useState(false);

    const [cashAmount, setCashAmount] = useState('');
    const [cashRemarks, setCashRemarks] = useState('');

    const [expenseName, setExpenseName] = useState('');
    const [expenseAmount, setExpenseAmount] = useState('');
    const [expenseSeriesNo, setExpenseSeriesNo] = useState('');
    const [expensePaymentType, setExpensePaymentType] =
        useState<DrawerExpensePaymentType>('cash');
    const [expenseFilter, setExpenseFilter] = useState<ExpenseFilter>('all');

    const [startingCashOpen, setStartingCashOpen] = useState(false);
    const [startingCashDraft, setStartingCashDraft] = useState('');

    const [editingCashAddition, setEditingCashAddition] =
        useState<CashAddition | null>(null);
    const [editCashAmount, setEditCashAmount] = useState('');
    const [editCashRemarks, setEditCashRemarks] = useState('');

    const [editingExpense, setEditingExpense] = useState<DrawerExpense | null>(null);
    const [editExpenseName, setEditExpenseName] = useState('');
    const [editExpenseAmount, setEditExpenseAmount] = useState('');
    const [editExpenseSeriesNo, setEditExpenseSeriesNo] = useState('');
    const [editExpensePaymentType, setEditExpensePaymentType] =
        useState<DrawerExpensePaymentType>('cash');

    const [deleteTarget, setDeleteTarget] = useState<DeleteTarget | null>(null);
    const [deleting, setDeleting] = useState(false);

    const isToday = isCurrentBusinessDate(
        selectedDate,
        undefined,
        businessDayResetHour,
    );
    const revisionRef = useRef<string | null>(null);
    const watchAbortRef = useRef<AbortController | null>(null);
    const mutationInFlightRef = useRef(false);
    const liveBusinessDateRef = useRef(
        currentBusinessDate(undefined, businessDayResetHour),
    );

    const abortWatch = useCallback(() => {
        watchAbortRef.current?.abort();
        watchAbortRef.current = null;
    }, []);

    const applyDrawerData = useCallback((payload: CashDrawerData) => {
        revisionRef.current = payload.revision;
        setData(payload);
    }, []);

    const applyMutation = useCallback(
        (mutation: CashDrawerMutation) => {
            revisionRef.current = mutation.revision;
            setData((current) =>
                current ? mergeDrawerMutation(current, mutation) : null,
            );
        },
        [],
    );

    const runMutation = useCallback(
        async (
            action: () => Promise<{ data: CashDrawerMutation }>,
            setBusy: (busy: boolean) => void,
        ) => {
            mutationInFlightRef.current = true;
            abortWatch();
            setBusy(true);
            try {
                const response = await action();
                applyMutation(response.data);
                return response.data;
            } catch (e) {
                toast.error(e instanceof Error ? e.message : 'Request failed');
                return null;
            } finally {
                setBusy(false);
                mutationInFlightRef.current = false;
            }
        },
        [abortWatch, applyMutation],
    );

    const load = useCallback(async (options?: { silent?: boolean }) => {
        if (!options?.silent) {
            setLoading(true);
        }
        try {
            const response = await fetchCashDrawerSummary(selectedDate);
            const payload = response.data;
            if (isCashDrawerUnchanged(payload)) {
                revisionRef.current = payload.revision;
                return;
            }
            applyDrawerData(payload);
        } catch (e) {
            if (!options?.silent) {
                toast.error(
                    e instanceof Error ? e.message : 'Failed to load cash drawer',
                );
            }
        } finally {
            if (!options?.silent) {
                setLoading(false);
            }
        }
    }, [applyDrawerData, selectedDate]);

    useEffect(() => {
        const timer = window.setInterval(() => {
            const businessToday = currentBusinessDate(
                undefined,
                businessDayResetHour,
            );
            setSelectedDate((current) =>
                current === liveBusinessDateRef.current
                    ? businessToday
                    : current,
            );
            liveBusinessDateRef.current = businessToday;
        }, 30_000);

        return () => window.clearInterval(timer);
    }, [businessDayResetHour]);

    useEffect(() => {
        if (!unlocked) return;
        revisionRef.current = null;
        void load();
    }, [load, unlocked]);

    useEffect(() => {
        if (!isToday || !unlocked) {
            return;
        }

        let active = true;

        const sleep = (ms: number) =>
            new Promise<void>((resolve) => {
                window.setTimeout(resolve, ms);
            });

        const runWatchLoop = async () => {
            while (active) {
                if (document.hidden) {
                    await sleep(2000);
                    continue;
                }

                try {
                    const controller = new AbortController();
                    watchAbortRef.current = controller;

                    const response = await watchCashDrawer(
                        selectedDate,
                        revisionRef.current,
                        controller.signal,
                    );
                    if (!active) {
                        return;
                    }

                    if (mutationInFlightRef.current) {
                        continue;
                    }

                    const { changed, revision } = response.data;
                    revisionRef.current = revision;

                    if (changed) {
                        await load({ silent: true });
                    }
                } catch (error) {
                    if (!active) {
                        return;
                    }
                    if (
                        error instanceof DOMException &&
                        error.name === 'AbortError'
                    ) {
                        continue;
                    }
                    await sleep(1000);
                }
            }
        };

        void runWatchLoop();

        const onVisibility = () => {
            if (!active || document.hidden) {
                return;
            }
            const businessToday = currentBusinessDate(
                undefined,
                businessDayResetHour,
            );
            setSelectedDate((current) =>
                current === liveBusinessDateRef.current
                    ? businessToday
                    : current,
            );
            liveBusinessDateRef.current = businessToday;
            void load({ silent: true });
        };

        document.addEventListener('visibilitychange', onVisibility);

        return () => {
            active = false;
            abortWatch();
            document.removeEventListener('visibilitychange', onVisibility);
        };
    }, [abortWatch, businessDayResetHour, isToday, load, selectedDate, unlocked]);

    const summary = data?.summary;

    const filteredExpenses = useMemo(() => {
        const rows = data?.expenses ?? [];
        if (expenseFilter === 'all') return rows;
        return rows.filter((row) => row.payment_type === expenseFilter);
    }, [data?.expenses, expenseFilter]);

    const nextReferenceNo = useMemo(() => {
        const savedCount = (data?.expenses ?? []).filter((row) => row.id > 0).length;
        return formatExpenseReferenceNo(selectedDate, savedCount + 1);
    }, [data?.expenses, selectedDate]);

    const runAction = async (
        action: () => Promise<{ data: CashDrawerMutation }>,
        setBusy: (busy: boolean) => void,
    ) => runMutation(action, setBusy);

    // The page is already gated behind the unlock screen below, so
    // individual actions reuse the PIN that was verified at unlock time
    // instead of prompting again for every add/edit/delete.
    const requestCashDrawerPin = useCallback(
        (action: (pin: string) => Promise<void>) => {
            void action(unlockedPinRef.current);
        },
        [],
    );

    const handleUnlock = async () => {
        if (!/^\d{4,6}$/.test(gatePin)) {
            setGateError('PIN must be 4 to 6 digits.');
            return;
        }

        setUnlocking(true);
        setGateError(null);
        try {
            const response = await verifyCashDrawerPin(gatePin);
            if (response.data.verified) {
                unlockedPinRef.current = gatePin;
                setUnlocked(true);
            } else {
                setGateError('Incorrect PIN.');
            }
        } catch (e) {
            setGateError(e instanceof Error ? e.message : 'Incorrect PIN.');
        } finally {
            setUnlocking(false);
        }
    };

    const handleAddCash = () => {
        const amount = Number(cashAmount);
        if (!Number.isFinite(amount) || amount < 0) {
            toast.error('Enter a valid cash amount');
            return;
        }

        const remarks = cashRemarks.trim();
        if (amount === 0 && remarks === '') {
            toast.error('Remarks are required for a zero cash amount');
            return;
        }

        requestCashDrawerPin(async (pin) => {
            const snapshot = data;
            const tempId = -Date.now();
            const optimistic: CashAddition = {
                id: tempId,
                amount,
                remarks,
                user_name: 'Saving...',
                created_at: new Date().toISOString(),
            };

            setCashAmount('');
            setCashRemarks('');
            if (snapshot) {
                setData(applyOptimisticCashAddition(snapshot, optimistic));
            }

            const mutation = await runAction(
                () => addCashAddition(selectedDate, amount, remarks, pin),
                setSavingCash,
            );
            if (mutation) {
                toast.success('Cash added');
            } else if (snapshot) {
                setData(snapshot);
                setCashAmount(String(amount));
                setCashRemarks(remarks);
            }
        });
    };

    const handleAddExpense = () => {
        const name = expenseName.trim();
        const amount = Number(expenseAmount);
        if (!name) {
            toast.error('Expense name is required');
            return;
        }
        if (!Number.isFinite(amount) || amount <= 0) {
            toast.error('Enter a valid expense amount');
            return;
        }
        const paymentType = expensePaymentType;
        const seriesNo = expenseSeriesNo.trim();
        requestCashDrawerPin(async (pin) => {
            const snapshot = data;
            const tempId = -Date.now();
            const optimistic: DrawerExpense = {
                id: tempId,
                reference_no: nextReferenceNo,
                series_no: seriesNo || null,
                name,
                amount,
                payment_type: paymentType,
                payment_label: expensePaymentLabel(paymentType),
                user_name: 'Saving...',
                created_at: new Date().toISOString(),
            };

            setExpenseName('');
            setExpenseAmount('');
            setExpenseSeriesNo('');
            setExpensePaymentType('cash');
            if (snapshot) {
                setData(applyOptimisticExpense(snapshot, optimistic));
            }

            const mutation = await runAction(
                () =>
                    addDrawerExpense(
                        selectedDate,
                        name,
                        amount,
                        paymentType,
                        pin,
                        seriesNo,
                    ),
                setSavingExpense,
            );
            if (mutation) {
                toast.success('Expense added');
            } else if (snapshot) {
                setData(snapshot);
                setExpenseName(name);
                setExpenseAmount(String(amount));
                setExpenseSeriesNo(seriesNo);
                setExpensePaymentType(paymentType);
            }
        });
    };

    const printExpense = async (expense: DrawerExpense) => {
        const lines = buildExpenseReceiptLines(
            expense,
            receiptStore,
            currencySymbol,
        );
        const copies = doublePrintReceipt ? 2 : 1;
        try {
            await printThermalCopies(lines, copies);
        } catch (e) {
            toast.error(
                e instanceof Error ? e.message : 'Failed to print expense',
            );
        }
    };

    const printCashAddition = async (addition: CashAddition) => {
        const lines = buildCashAdditionReceiptLines(
            addition,
            receiptStore,
            currencySymbol,
            selectedDate,
        );
        const copies = doublePrintReceipt ? 2 : 1;
        try {
            await printThermalCopies(lines, copies);
        } catch (e) {
            toast.error(
                e instanceof Error ? e.message : 'Failed to print cash addition',
            );
        }
    };

    const openEditCashAddition = (addition: CashAddition) => {
        setEditingCashAddition(addition);
        setEditCashAmount(String(addition.amount));
        setEditCashRemarks(addition.remarks);
    };

    const handleSaveCashAddition = () => {
        if (!editingCashAddition) return;
        const amount = Number(editCashAmount);
        if (!Number.isFinite(amount) || amount < 0) {
            toast.error('Enter a valid cash amount');
            return;
        }
        const remarks = editCashRemarks.trim();
        if (amount === 0 && remarks === '') {
            toast.error('Remarks are required for a zero cash amount');
            return;
        }
        requestCashDrawerPin(async (pin) => {
            const payload = await runAction(
                () =>
                    updateCashAddition(
                        editingCashAddition.id,
                        amount,
                        remarks,
                        pin,
                    ),
                setSavingCash,
            );
            if (payload) {
                setEditingCashAddition(null);
                toast.success('Cash addition updated');
            }
        });
    };

    const handleDeleteCashAddition = (addition: CashAddition) => {
        setDeleteTarget({ kind: 'cash_addition', item: addition });
    };

    const handleDeleteExpense = (expense: DrawerExpense) => {
        setDeleteTarget({ kind: 'expense', item: expense });
    };

    const confirmDelete = () => {
        if (!deleteTarget) return;

        requestCashDrawerPin(async (pin) => {
            setDeleting(true);
            try {
                if (deleteTarget.kind === 'expense') {
                    const payload = await runAction(
                        () => deleteDrawerExpense(deleteTarget.item.id, pin),
                        setSavingExpense,
                    );
                    if (payload) {
                        toast.success('Expense deleted');
                        setDeleteTarget(null);
                    }
                } else {
                    const payload = await runAction(
                        () => deleteCashAddition(deleteTarget.item.id, pin),
                        setSavingCash,
                    );
                    if (payload) {
                        toast.success('Cash addition deleted');
                        setDeleteTarget(null);
                    }
                }
            } finally {
                setDeleting(false);
            }
        });
    };

    const deleteDialogTitle =
        deleteTarget?.kind === 'expense'
            ? 'Delete expense?'
            : 'Delete cash addition?';

    const deleteDialogDescription =
        deleteTarget?.kind === 'expense' ? (
            <>
                This will permanently remove{' '}
                <span className="font-semibold text-foreground">
                    {deleteTarget.item.name}
                </span>{' '}
                ({peso(deleteTarget.item.amount)} · {deleteTarget.item.payment_label})
                from the drawer for {selectedDate}. This action cannot be undone.
            </>
        ) : deleteTarget?.kind === 'cash_addition' ? (
            <>
                This will permanently remove the cash addition of{' '}
                <span className="font-semibold text-foreground">
                    {peso(deleteTarget.item.amount)}
                </span>
                {deleteTarget.item.remarks ? (
                    <>
                        {' '}
                        ({deleteTarget.item.remarks})
                    </>
                ) : null}{' '}
                from the drawer for {selectedDate}. This action cannot be undone.
            </>
        ) : null;

    const handleSaveStartingCash = () => {
        const amount = Number(startingCashDraft);
        if (!Number.isFinite(amount) || amount < 0) {
            toast.error('Enter a valid starting cash amount');
            return;
        }
        requestCashDrawerPin(async (pin) => {
            const payload = await runAction(
                () => updateStartingCash(selectedDate, amount, pin),
                setSavingStartingCash,
            );
            if (payload) {
                setStartingCashOpen(false);
                toast.success('Starting cash updated');
            }
        });
    };

    const openEditExpense = (expense: DrawerExpense) => {
        setEditingExpense(expense);
        setEditExpenseName(expense.name);
        setEditExpenseAmount(String(expense.amount));
        setEditExpenseSeriesNo(expense.series_no ?? '');
        setEditExpensePaymentType(expense.payment_type);
    };

    const handleSaveExpense = () => {
        if (!editingExpense) return;
        const name = editExpenseName.trim();
        const amount = Number(editExpenseAmount);
        if (!name) {
            toast.error('Expense name is required');
            return;
        }
        if (!Number.isFinite(amount) || amount <= 0) {
            toast.error('Enter a valid expense amount');
            return;
        }
        requestCashDrawerPin(async (pin) => {
            const payload = await runAction(
                () =>
                    updateDrawerExpense(
                        editingExpense.id,
                        name,
                        amount,
                        editExpensePaymentType,
                        pin,
                        editExpenseSeriesNo,
                    ),
                setSavingExpense,
            );
            if (payload) {
                setEditingExpense(null);
                toast.success('Expense updated');
            }
        });
    };

    const handleDownloadCashAdded = async () => {
        try {
            const response = await exportCashAdditions(selectedDate);
            const rows = response.data.rows;
            downloadCsv(
                `cash-added-${selectedDate}.csv`,
                ['Date', 'Amount', 'Remarks', 'Added By', 'Created At'],
                rows.map((row: CashAddition) => [
                    selectedDate,
                    row.amount,
                    row.remarks,
                    row.user_name,
                    row.created_at,
                ]),
            );
        } catch (e) {
            toast.error(e instanceof Error ? e.message : 'Download failed');
        }
    };

    const handleDownloadExpenses = async () => {
        try {
            const response = await exportDrawerExpenses(selectedDate, expenseFilter);
            const rows = response.data.rows;
            downloadCsv(
                `drawer-expenses-${selectedDate}.csv`,
                ['Reference No', 'Series No', 'Name', 'Amount', 'Payment Type', 'User', 'Created At'],
                rows.map((row: DrawerExpense) => [
                    row.reference_no,
                    row.series_no ?? '',
                    row.name,
                    row.amount,
                    row.payment_label,
                    row.user_name,
                    row.created_at,
                ]),
            );
        } catch (e) {
            toast.error(e instanceof Error ? e.message : 'Download failed');
        }
    };

    const handlePrintAllExpenses = async () => {
        if (filteredExpenses.length === 0) {
            toast.error('No expenses to print');
            return;
        }

        const filterLabel =
            expenseFilter === 'all'
                ? 'ALL'
                : expenseFilter === 'gcash'
                  ? 'GCASH'
                  : expenseFilter.toUpperCase();

        const lines = buildAllExpensesReceiptLines(
            filteredExpenses,
            receiptStore,
            currencySymbol,
            { businessDate: selectedDate, filterLabel },
        );
        const copies = doublePrintReceipt ? 2 : 1;

        try {
            await printThermalCopies(lines, copies);
            toast.success(
                `Printed ${filteredExpenses.length} expense${filteredExpenses.length === 1 ? '' : 's'}`,
            );
        } catch (e) {
            toast.error(
                e instanceof Error ? e.message : 'Failed to print expenses',
            );
        }
    };

    if (!unlocked) {
        return (
            <>
                <Head title="Cash Drawer" />
                <div className="flex min-h-[70vh] items-center justify-center p-6">
                    <div className="w-full max-w-sm rounded-2xl border border-border/60 bg-card p-6 text-center shadow-sm">
                        <div className="mx-auto mb-4 flex size-12 items-center justify-center rounded-full bg-amber-500/10 text-amber-600">
                            <Lock className="size-6" />
                        </div>
                        <h1 className="text-lg font-bold text-foreground">
                            Cash Drawer Locked
                        </h1>
                        {hasCashDrawerPin ? (
                            <>
                                <p className="mt-1 text-sm text-muted-foreground">
                                    Enter the cash drawer PIN to continue.
                                </p>
                                <div className="mt-4 grid gap-2 text-left">
                                    <Label htmlFor="cash-drawer-gate-pin">PIN</Label>
                                    <Input
                                        id="cash-drawer-gate-pin"
                                        type="password"
                                        inputMode="numeric"
                                        maxLength={6}
                                        autoFocus
                                        value={gatePin}
                                        onChange={(e) => {
                                            setGatePin(
                                                e.target.value.replace(/\D/g, ''),
                                            );
                                            setGateError(null);
                                        }}
                                        onKeyDown={(e) => {
                                            if (e.key === 'Enter') {
                                                void handleUnlock();
                                            }
                                        }}
                                    />
                                    {gateError ? (
                                        <p className="text-sm text-destructive">
                                            {gateError}
                                        </p>
                                    ) : null}
                                </div>
                                <Button
                                    className="mt-4 w-full"
                                    onClick={() => void handleUnlock()}
                                    disabled={unlocking}
                                >
                                    {unlocking ? (
                                        <Loader2 className="size-4 animate-spin" />
                                    ) : null}
                                    Unlock
                                </Button>
                            </>
                        ) : (
                            <p className="mt-2 text-sm text-muted-foreground">
                                No cash drawer PIN has been set yet. Ask an admin to
                                set one under Settings → Security before this page
                                can be unlocked.
                            </p>
                        )}
                    </div>
                </div>
            </>
        );
    }

    return (
        <>
            <Head title="Cash Drawer" />
            <div className="agri-page-container">
                <PageHeader
                    title="Cash Drawer"
                    description={`Business day resets daily at ${businessDayResetLabel(businessDayResetHour)}. Sales and drawer totals follow that window.`}
                    badge="Muñoz Macam Agri"
                    actions={
                        <div className="flex flex-wrap items-center gap-2">
                            {isToday && (
                                <div className="flex items-center gap-2 rounded-xl border border-emerald-500/30 bg-emerald-500/10 px-3 py-2 text-xs font-semibold text-emerald-800">
                                    <span className="size-2 animate-pulse rounded-full bg-emerald-500" />
                                    Live
                                </div>
                            )}
                            <div className="flex items-center gap-2 rounded-xl border border-border/60 bg-card px-3 py-2">
                                <Calendar className="size-4 text-muted-foreground" />
                                <Input
                                    type="date"
                                    value={selectedDate}
                                    onChange={(e) => {
                                        const value = e.target.value;
                                        setSelectedDate(value);
                                        liveBusinessDateRef.current = value;
                                    }}
                                    className="h-8 w-[10.5rem] border-0 bg-transparent p-0 shadow-none focus-visible:ring-0"
                                />
                            </div>
                            <Button
                                variant="outline"
                                size="sm"
                                onClick={() => void load()}
                                disabled={loading}
                            >
                                {loading ? (
                                    <Loader2 className="size-4 animate-spin" />
                                ) : (
                                    <RefreshCw className="size-4" />
                                )}
                                Refresh
                            </Button>
                        </div>
                    }
                />

                <section className="agri-card rounded-2xl border border-primary/20 bg-gradient-to-br from-primary/5 via-card to-card p-6 shadow-sm">
                    <div className="flex flex-col gap-6 lg:flex-row lg:items-end lg:justify-between">
                        <div>
                            <p className="text-sm font-semibold tracking-wide text-muted-foreground uppercase">
                                Cash In Drawer
                            </p>
                            <p className="mt-2 text-4xl font-bold tracking-tight text-primary md:text-5xl">
                                {summary ? peso(summary.cash_in_drawer) : '—'}
                            </p>
                            <p className="mt-3 max-w-2xl text-sm text-muted-foreground">
                                Starting Cash + Cash Added + Cash Sales − Cash Expenses
                            </p>
                        </div>
                        <div className="grid w-full max-w-lg grid-cols-1 gap-3 sm:grid-cols-3">
                            <div className="rounded-xl border border-border/60 bg-background/80 p-4">
                                <p className="text-[11px] font-semibold tracking-wider text-muted-foreground uppercase">
                                    Bank Transfer Sales
                                </p>
                                <p className="mt-1 text-xl font-bold text-foreground">
                                    {summary ? peso(summary.bank_transfer_sales) : '—'}
                                </p>
                            </div>
                            <div className="rounded-xl border border-border/60 bg-background/80 p-4">
                                <p className="text-[11px] font-semibold tracking-wider text-muted-foreground uppercase">
                                    GCash Sales
                                </p>
                                <p className="mt-1 text-xl font-bold text-foreground">
                                    {summary ? peso(summary.gcash_sales) : '—'}
                                </p>
                            </div>
                            <div className="rounded-xl border border-border/60 bg-background/80 p-4">
                                <p className="text-[11px] font-semibold tracking-wider text-muted-foreground uppercase">
                                    Cheque Sales
                                </p>
                                <p className="mt-1 text-xl font-bold text-foreground">
                                    {summary ? peso(summary.cheque_sales) : '—'}
                                </p>
                            </div>
                        </div>
                    </div>
                </section>

                <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-5">
                    <SummaryCard
                        label="Starting Cash"
                        value={summary ? peso(summary.starting_cash) : '—'}
                        tone="green"
                        editable
                        onEdit={() => {
                            setStartingCashDraft(
                                summary ? String(summary.starting_cash) : '0',
                            );
                            setStartingCashOpen(true);
                        }}
                    />
                    <SummaryCard
                        label="Cash Added"
                        value={summary ? peso(summary.cash_added) : '—'}
                        tone="orange"
                    />
                    <SummaryCard
                        label="Cash Sales"
                        value={summary ? peso(summary.cash_sales) : '—'}
                        tone="red"
                    />
                    <SummaryCard
                        label="Cash Expenses"
                        value={summary ? peso(summary.cash_expenses) : '—'}
                        tone="teal"
                    />
                    <SummaryCard
                        label="Non-Cash Expenses"
                        value={summary ? peso(summary.non_cash_expenses) : '—'}
                        tone="teal"
                    />
                </section>

                <section className="grid gap-6 lg:grid-cols-2">
                    <div className="overflow-hidden rounded-2xl border border-border/60 bg-card shadow-sm">
                        <PanelHeader title="Cash Added" tone="orange" icon={Banknote} />
                        <div className="space-y-4 p-5">
                            <div className="space-y-4">
                                <div className="space-y-2">
                                    <Label htmlFor="cash-amount">Cash Amount *</Label>
                                    <Input
                                        id="cash-amount"
                                        type="number"
                                        min="0"
                                        step="0.01"
                                        placeholder="0.00"
                                        value={cashAmount}
                                        onChange={(e) => setCashAmount(e.target.value)}
                                    />
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="cash-remarks">Remarks</Label>
                                    <Input
                                        id="cash-remarks"
                                        placeholder="Optional note"
                                        value={cashRemarks}
                                        onChange={(e) => setCashRemarks(e.target.value)}
                                    />
                                </div>
                            </div>
                            <div className="flex flex-wrap gap-2">
                                <Button
                                    variant="outline"
                                    size="sm"
                                    onClick={() => void handleDownloadCashAdded()}
                                >
                                    <Download className="size-4" />
                                    Download Cash Added
                                </Button>
                                <Button
                                    size="sm"
                                    className="bg-amber-600 text-white shadow-sm hover:bg-amber-700"
                                    onClick={() => void handleAddCash()}
                                    disabled={savingCash}
                                >
                                    {savingCash ? (
                                        <Loader2 className="size-4 animate-spin" />
                                    ) : (
                                        <Plus className="size-4" />
                                    )}
                                    Add Cash
                                </Button>
                            </div>
                            <div className="space-y-2">
                                {(data?.cash_additions ?? []).length === 0 ? (
                                    <p className="rounded-xl border border-dashed border-border/70 px-4 py-8 text-center text-sm text-muted-foreground">
                                        No cash additions for this date.
                                    </p>
                                ) : (
                                    (data?.cash_additions ?? []).map((row) => (
                                        <div
                                            key={row.id}
                                            className="flex items-start justify-between gap-3 rounded-xl border border-border/60 bg-background/60 px-4 py-3"
                                        >
                                            <div className="min-w-0">
                                                <p className="font-semibold text-foreground">
                                                    {peso(row.amount)}
                                                </p>
                                                <p className="text-sm text-muted-foreground">
                                                    {row.remarks || 'No remarks'}
                                                </p>
                                                <p className="mt-1 text-xs text-muted-foreground">
                                                    {row.user_name} · {formatDateTime(row.created_at)}
                                                </p>
                                            </div>
                                            <div className="flex shrink-0 items-start gap-2">
                                                <button
                                                    type="button"
                                                    onClick={() => void printCashAddition(row)}
                                                    className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                                                    aria-label="Print cash addition"
                                                >
                                                    <Printer className="size-3.5" />
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => openEditCashAddition(row)}
                                                    className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                                                    aria-label="Edit cash addition"
                                                >
                                                    <Pencil className="size-3.5" />
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => handleDeleteCashAddition(row)}
                                                    className="rounded-md p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                                                    aria-label="Delete cash addition"
                                                >
                                                    <Trash2 className="size-3.5" />
                                                </button>
                                            </div>
                                        </div>
                                    ))
                                )}
                            </div>
                        </div>
                    </div>

                    <div className="overflow-hidden rounded-2xl border border-border/60 bg-card shadow-sm">
                        <PanelHeader title="Expense Added" tone="teal" icon={Wallet} />
                        <div className="space-y-4 p-5">
                            <div className="flex flex-wrap gap-2">
                                {(
                                    [
                                        ['all', 'All'],
                                        ['cash', 'Cash'],
                                        ['gcash', 'GCash'],
                                        ['bank', 'Bank'],
                                    ] as const
                                ).map(([key, label]) => (
                                    <button
                                        key={key}
                                        type="button"
                                        onClick={() => setExpenseFilter(key)}
                                        className={cn(
                                            'rounded-full px-3 py-1 text-xs font-semibold transition-colors',
                                            expenseFilter === key
                                                ? 'bg-teal-600 text-white'
                                                : 'bg-muted text-muted-foreground hover:bg-muted/80',
                                        )}
                                    >
                                        {label}
                                    </button>
                                ))}
                            </div>
                            <div className="space-y-4">
                                <div className="space-y-2">
                                    <Label htmlFor="expense-reference-no">Reference No.</Label>
                                    <Input
                                        id="expense-reference-no"
                                        value={nextReferenceNo}
                                        readOnly
                                        className="bg-muted/50 text-muted-foreground"
                                    />
                                    <p className="text-xs text-muted-foreground">
                                        Format: date + daily number (e.g. {selectedDate}-001).
                                        Auto-assigned when you save.
                                    </p>
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="expense-series-no">Series No.</Label>
                                    <Input
                                        id="expense-series-no"
                                        placeholder="Optional (e.g. cheque series)"
                                        value={expenseSeriesNo}
                                        onChange={(e) => setExpenseSeriesNo(e.target.value)}
                                    />
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="expense-name">Expense Name *</Label>
                                    <Input
                                        id="expense-name"
                                        placeholder="e.g. Delivery fee"
                                        value={expenseName}
                                        onChange={(e) => setExpenseName(e.target.value)}
                                    />
                                </div>
                                <div className="space-y-2">
                                    <Label htmlFor="expense-amount">Expense Amount *</Label>
                                    <Input
                                        id="expense-amount"
                                        type="number"
                                        min="0"
                                        step="0.01"
                                        placeholder="0.00"
                                        value={expenseAmount}
                                        onChange={(e) => setExpenseAmount(e.target.value)}
                                    />
                                </div>
                                <div className="space-y-2">
                                    <Label>Payment Type</Label>
                                    <div className="flex flex-wrap gap-4 pt-2">
                                        {(
                                            [
                                                ['cash', 'Cash'],
                                                ['gcash', 'GCash'],
                                                ['bank', 'Bank'],
                                            ] as const
                                        ).map(([value, label]) => (
                                            <label
                                                key={value}
                                                className="flex items-center gap-2 text-sm"
                                            >
                                                <input
                                                    type="radio"
                                                    name="expense-payment"
                                                    checked={expensePaymentType === value}
                                                    onChange={() =>
                                                        setExpensePaymentType(value)
                                                    }
                                                />
                                                {label}
                                            </label>
                                        ))}
                                    </div>
                                </div>
                            </div>
                            <div className="flex flex-wrap gap-2">
                                <Button
                                    variant="outline"
                                    size="sm"
                                    onClick={() => void handleDownloadExpenses()}
                                >
                                    <Download className="size-4" />
                                    Download All Expense
                                </Button>
                                <Button
                                    variant="outline"
                                    size="sm"
                                    onClick={() => void handlePrintAllExpenses()}
                                >
                                    <Printer className="size-4" />
                                    Print All Expenses
                                </Button>
                                <Button
                                    size="sm"
                                    className="bg-teal-600 text-white shadow-sm hover:bg-teal-700"
                                    onClick={() => void handleAddExpense()}
                                    disabled={savingExpense}
                                >
                                    {savingExpense ? (
                                        <Loader2 className="size-4 animate-spin" />
                                    ) : (
                                        <Plus className="size-4" />
                                    )}
                                    Add Expense
                                </Button>
                            </div>
                            <div className="space-y-2">
                                {filteredExpenses.length === 0 ? (
                                    <p className="rounded-xl border border-dashed border-border/70 px-4 py-8 text-center text-sm text-muted-foreground">
                                        No expenses for this filter.
                                    </p>
                                ) : (
                                    filteredExpenses.map((row) => (
                                        <div
                                            key={row.id}
                                            className="flex items-start justify-between gap-3 rounded-xl border border-border/60 bg-background/60 px-4 py-3"
                                        >
                                            <div className="min-w-0">
                                                <p className="text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                                                    Reference No. {row.reference_no}
                                                    {row.series_no
                                                        ? ` · Series ${row.series_no}`
                                                        : ''}
                                                </p>
                                                <p className="font-semibold text-foreground">
                                                    {row.name} · {row.user_name}
                                                </p>
                                                <p className="text-sm text-muted-foreground">
                                                    {row.payment_label} · {formatDateTime(row.created_at)}
                                                </p>
                                            </div>
                                            <div className="flex shrink-0 items-start gap-2">
                                                <p className="font-bold text-teal-700">
                                                    {peso(row.amount)}
                                                </p>
                                                <button
                                                    type="button"
                                                    onClick={() => void printExpense(row)}
                                                    className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                                                    aria-label="Print expense"
                                                >
                                                    <Printer className="size-3.5" />
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => openEditExpense(row)}
                                                    className="rounded-md p-1 text-muted-foreground hover:bg-muted hover:text-foreground"
                                                    aria-label="Edit expense"
                                                >
                                                    <Pencil className="size-3.5" />
                                                </button>
                                                <button
                                                    type="button"
                                                    onClick={() => handleDeleteExpense(row)}
                                                    className="rounded-md p-1 text-muted-foreground hover:bg-destructive/10 hover:text-destructive"
                                                    aria-label="Delete expense"
                                                >
                                                    <Trash2 className="size-3.5" />
                                                </button>
                                            </div>
                                        </div>
                                    ))
                                )}
                            </div>
                        </div>
                    </div>
                </section>
            </div>

            <Dialog open={startingCashOpen} onOpenChange={setStartingCashOpen}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Edit Starting Cash</DialogTitle>
                    </DialogHeader>
                    <div className="space-y-2 py-2">
                        <Label htmlFor="starting-cash">Starting Cash (₱)</Label>
                        <Input
                            id="starting-cash"
                            type="number"
                            min="0"
                            step="0.01"
                            value={startingCashDraft}
                            onChange={(e) => setStartingCashDraft(e.target.value)}
                        />
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setStartingCashOpen(false)}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => void handleSaveStartingCash()}
                            disabled={savingStartingCash}
                        >
                            {savingStartingCash ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                'Save'
                            )}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={editingCashAddition !== null}
                onOpenChange={(open) => {
                    if (!open) setEditingCashAddition(null);
                }}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Edit Cash Addition</DialogTitle>
                    </DialogHeader>
                    <div className="space-y-4 py-2">
                        <div className="space-y-2">
                            <Label htmlFor="edit-cash-amount">Cash Amount (₱)</Label>
                            <Input
                                id="edit-cash-amount"
                                type="number"
                                min="0"
                                step="0.01"
                                value={editCashAmount}
                                onChange={(e) => setEditCashAmount(e.target.value)}
                            />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="edit-cash-remarks">Remarks</Label>
                            <Input
                                id="edit-cash-remarks"
                                placeholder="Optional note"
                                value={editCashRemarks}
                                onChange={(e) => setEditCashRemarks(e.target.value)}
                            />
                        </div>
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setEditingCashAddition(null)}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => void handleSaveCashAddition()}
                            disabled={savingCash}
                        >
                            {savingCash ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                'Save'
                            )}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={editingExpense !== null}
                onOpenChange={(open) => {
                    if (!open) setEditingExpense(null);
                }}
            >
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle>Edit Expense</DialogTitle>
                    </DialogHeader>
                    <div className="space-y-4 py-2">
                        <div className="space-y-2">
                            <Label htmlFor="edit-expense-reference-no">Reference No.</Label>
                            <Input
                                id="edit-expense-reference-no"
                                value={editingExpense?.reference_no ?? ''}
                                readOnly
                                className="bg-muted/50 text-muted-foreground"
                            />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="edit-expense-series-no">Series No.</Label>
                            <Input
                                id="edit-expense-series-no"
                                placeholder="Optional (e.g. cheque series)"
                                value={editExpenseSeriesNo}
                                onChange={(e) => setEditExpenseSeriesNo(e.target.value)}
                            />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="edit-expense-name">Expense Name</Label>
                            <Input
                                id="edit-expense-name"
                                value={editExpenseName}
                                onChange={(e) => setEditExpenseName(e.target.value)}
                            />
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="edit-expense-amount">Expense Amount (₱)</Label>
                            <Input
                                id="edit-expense-amount"
                                type="number"
                                min="0"
                                step="0.01"
                                value={editExpenseAmount}
                                onChange={(e) => setEditExpenseAmount(e.target.value)}
                            />
                        </div>
                        <div className="space-y-2">
                            <Label>Payment Type</Label>
                            <div className="flex flex-wrap gap-4">
                                {(
                                    [
                                        ['cash', 'Cash'],
                                        ['gcash', 'GCash'],
                                        ['bank', 'Bank'],
                                    ] as const
                                ).map(([value, label]) => (
                                    <label
                                        key={value}
                                        className="flex items-center gap-2 text-sm"
                                    >
                                        <input
                                            type="radio"
                                            name="edit-expense-payment"
                                            checked={editExpensePaymentType === value}
                                            onChange={() =>
                                                setEditExpensePaymentType(value)
                                            }
                                        />
                                        {label}
                                    </label>
                                ))}
                            </div>
                        </div>
                    </div>
                    <DialogFooter>
                        <Button
                            variant="outline"
                            onClick={() => setEditingExpense(null)}
                        >
                            Cancel
                        </Button>
                        <Button
                            onClick={() => void handleSaveExpense()}
                            disabled={savingExpense}
                        >
                            {savingExpense ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                'Save'
                            )}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

            <Dialog
                open={deleteTarget !== null}
                onOpenChange={(open) => {
                    if (!open && !deleting) setDeleteTarget(null);
                }}
            >
                <DialogContent className="sm:max-w-md">
                    <DialogHeader className="items-center text-center sm:items-center sm:text-center">
                        <div className="mb-1 flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
                            <Trash2 className="size-5" />
                        </div>
                        <DialogTitle>{deleteDialogTitle}</DialogTitle>
                        <DialogDescription className="text-center">
                            {deleteDialogDescription}
                        </DialogDescription>
                    </DialogHeader>
                    <DialogFooter className="gap-2 sm:justify-center">
                        <Button
                            variant="outline"
                            onClick={() => setDeleteTarget(null)}
                            disabled={deleting}
                        >
                            Cancel
                        </Button>
                        <Button
                            variant="destructive"
                            onClick={() => void confirmDelete()}
                            disabled={deleting}
                        >
                            {deleting ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                'Delete'
                            )}
                        </Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>

        </>
    );
}
