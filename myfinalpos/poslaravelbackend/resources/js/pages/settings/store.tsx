import { Head, usePage } from '@inertiajs/react';
import {
    Building2,
    Calculator,
    Clock,
    CreditCard,
    ImageIcon,
    Loader2,
    Percent,
    Printer,
    ListChecks,
    Mail,
    Receipt,
    Save,
    Shield,
    Store,
    Upload,
    User,
} from 'lucide-react';
import { useMemo, useRef, useState, type ReactNode } from 'react';
import { toast } from 'sonner';
import { ThermalReceiptPreview } from '@/components/thermal-receipt-preview';
import { Button } from '@/components/ui/button';
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
    saveStoreSettings,
    type ReceiptStore,
    type StoreBranch,
    type StoreSettings,
} from '@/lib/store-settings-api';

const CURRENCY_OPTIONS: Record<string, string> = {
    '₱': 'Philippine Peso (₱)',
    $: 'US Dollar ($)',
    '€': 'Euro (€)',
    PHP: 'PHP label',
};

type AccountInfo = {
    name: string;
    email: string;
    role: string;
};

type PageProps = {
    settings: StoreSettings;
    branches: StoreBranch[];
    account: AccountInfo | null;
};

function SummaryCard({
    label,
    value,
    icon: Icon,
    accent,
}: {
    label: string;
    value: string;
    icon: typeof Percent;
    accent?: string;
}) {
    return (
        <div className="rounded-xl border border-border/60 bg-secondary/15 p-4">
            <div className="flex items-start justify-between gap-2">
                <div>
                    <p className="text-xs font-medium text-muted-foreground">
                        {label}
                    </p>
                    <p className="mt-1 text-lg font-bold text-foreground">
                        {value}
                    </p>
                </div>
                <div
                    className="rounded-lg bg-primary/10 p-2"
                    style={accent ? { color: accent } : undefined}
                >
                    <Icon className="size-4 text-primary" />
                </div>
            </div>
        </div>
    );
}

function TimeField({
    label,
    value,
    onChange,
}: {
    label: string;
    value: string;
    onChange: (value: string) => void;
}) {
    return (
        <div className="grid gap-2">
            <Label>{label}</Label>
            <Input
                type="time"
                value={value}
                onChange={(e) => onChange(e.target.value)}
            />
        </div>
    );
}

function SettingsSection({
    title,
    subtitle,
    icon: Icon,
    children,
}: {
    title: string;
    subtitle: string;
    icon: typeof Store;
    children: ReactNode;
}) {
    return (
        <section className="rounded-2xl border border-border/60 bg-card p-5">
            <div className="mb-4 flex items-start gap-3">
                <div className="rounded-xl bg-primary/10 p-2.5">
                    <Icon className="size-5 text-primary" />
                </div>
                <div>
                    <h2 className="font-semibold text-foreground">{title}</h2>
                    <p className="mt-0.5 text-sm text-muted-foreground">
                        {subtitle}
                    </p>
                </div>
            </div>
            <div className="space-y-3">{children}</div>
        </section>
    );
}

function ToggleRow({
    label,
    description,
    checked,
    onChange,
}: {
    label: string;
    description: string;
    checked: boolean;
    onChange: (value: boolean) => void;
}) {
    return (
        <label className="flex cursor-pointer items-start justify-between gap-4 rounded-xl border border-border/60 bg-secondary/20 px-4 py-3">
            <div>
                <p className="font-medium text-foreground">{label}</p>
                <p className="mt-0.5 text-sm text-muted-foreground">
                    {description}
                </p>
            </div>
            <input
                type="checkbox"
                checked={checked}
                onChange={(e) => onChange(e.target.checked)}
                className="mt-1 size-4 accent-primary"
            />
        </label>
    );
}

function printModeLabel(form: StoreSettings): string {
    if (!form.auto_print_receipt) return 'Manual';
    return form.double_print_receipt ? 'Auto ×2' : 'Auto';
}

function InfoRow({ label, value }: { label: string; value: string }) {
    return (
        <div className="flex items-center justify-between gap-4 border-b border-border/40 py-2 last:border-0">
            <span className="text-sm text-muted-foreground">{label}</span>
            <span className="text-sm font-medium text-foreground">{value}</span>
        </div>
    );
}

export default function StoreSettingsPage() {
    const { settings: initial, branches, account } =
        usePage<PageProps>().props;
    const [form, setForm] = useState<StoreSettings>({
        ...initial,
        double_print_receipt: initial.double_print_receipt ?? false,
    });
    const [saving, setSaving] = useState(false);
    const logoInputRef = useRef<HTMLInputElement>(null);

    const update = <K extends keyof StoreSettings>(
        key: K,
        value: StoreSettings[K],
    ) => {
        setForm((prev) => ({ ...prev, [key]: value }));
    };

    const updateReceipt = <K extends keyof ReceiptStore>(
        key: K,
        value: ReceiptStore[K],
    ) => {
        setForm((prev) => ({
            ...prev,
            receipt_store: { ...prev.receipt_store, [key]: value },
        }));
    };

    const activeBranch = useMemo(
        () =>
            branches.find((b) => b.id === form.default_branch_id) ??
            branches[0],
        [branches, form.default_branch_id],
    );

    const printMode = printModeLabel(form);

    const handleLogoUpload = (file: File | null) => {
        if (!file) return;
        const reader = new FileReader();
        reader.onload = () => {
            const result = reader.result;
            if (typeof result !== 'string') return;
            const base64 = result.includes(',')
                ? result.split(',')[1]
                : result;
            updateReceipt('logo_image_base64', base64);
            updateReceipt('logo_image_url', null);
        };
        reader.readAsDataURL(file);
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            const saved = await saveStoreSettings(form);
            setForm(saved);
            toast.success('Settings saved');
        } catch (e) {
            toast.error(
                e instanceof Error ? e.message : 'Could not save settings',
            );
        } finally {
            setSaving(false);
        }
    };

    const formContent = (
        <div className="space-y-4">
            <div>
                <h2 className="text-lg font-semibold text-foreground">
                    Settings
                </h2>
                <p className="text-sm text-muted-foreground">
                    Store profile, tax, printer, and POS rules.
                </p>
            </div>

            <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <SummaryCard
                    label="Tax Rate"
                    value={`${(form.tax_rate * 100).toFixed(2)}%`}
                    icon={Percent}
                />
                <SummaryCard
                    label="Currency"
                    value={form.currency_symbol}
                    icon={CreditCard}
                />
                <SummaryCard
                    label="POS Terminal"
                    value={form.receipt_store.pos_terminal_id}
                    icon={Store}
                />
                <SummaryCard
                    label="Printing"
                    value={printMode}
                    icon={Printer}
                />
            </div>

            <SettingsSection
                title="Receipt Template"
                subtitle="Customize header, legal text, and QR code on receipts"
                icon={Receipt}
            >
                <div className="flex flex-wrap items-start gap-4">
                    <div className="flex size-[72px] items-center justify-center rounded-xl border border-border/60 bg-secondary/20">
                        {form.receipt_store.logo_image_base64 ||
                        form.receipt_store.logo_image_url ? (
                            <img
                                src={
                                    form.receipt_store.logo_image_base64
                                        ? form.receipt_store.logo_image_base64.startsWith(
                                              'data:',
                                          )
                                            ? form.receipt_store.logo_image_base64
                                            : `data:image/png;base64,${form.receipt_store.logo_image_base64}`
                                        : (form.receipt_store.logo_image_url ??
                                          '')
                                }
                                alt="Logo"
                                className="size-full rounded-xl object-contain p-1"
                            />
                        ) : (
                            <ImageIcon className="size-8 text-muted-foreground" />
                        )}
                    </div>
                    <div className="flex flex-col gap-2">
                        <input
                            ref={logoInputRef}
                            type="file"
                            accept="image/*"
                            className="hidden"
                            onChange={(e) =>
                                handleLogoUpload(e.target.files?.[0] ?? null)
                            }
                        />
                        <Button
                            type="button"
                            variant="outline"
                            size="sm"
                            onClick={() => logoInputRef.current?.click()}
                        >
                            <Upload className="size-4" />
                            Upload logo image
                        </Button>
                        {(form.receipt_store.logo_image_base64 ||
                            form.receipt_store.logo_image_url) && (
                            <Button
                                type="button"
                                variant="ghost"
                                size="sm"
                                onClick={() => {
                                    updateReceipt('logo_image_base64', null);
                                    updateReceipt('logo_image_url', null);
                                }}
                            >
                                Remove logo image
                            </Button>
                        )}
                    </div>
                </div>

                <div className="grid gap-3">
                    <div className="grid gap-2">
                        <Label>Logo banner text</Label>
                        <Input
                            value={form.receipt_store.logo_text}
                            onChange={(e) =>
                                updateReceipt('logo_text', e.target.value)
                            }
                            placeholder="[ Farm & Tractor ]"
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>Store Name</Label>
                        <Input
                            value={form.receipt_store.store_name}
                            onChange={(e) =>
                                updateReceipt('store_name', e.target.value)
                            }
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>Store Subtitle</Label>
                        <Input
                            value={form.receipt_store.store_subtitle}
                            onChange={(e) =>
                                updateReceipt('store_subtitle', e.target.value)
                            }
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>Address Line 1</Label>
                        <Input
                            value={form.receipt_store.address_line1}
                            onChange={(e) =>
                                updateReceipt('address_line1', e.target.value)
                            }
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>Address Line 2</Label>
                        <Input
                            value={form.receipt_store.address_line2}
                            onChange={(e) =>
                                updateReceipt('address_line2', e.target.value)
                            }
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>TIN</Label>
                        <Input
                            value={form.receipt_store.tin}
                            onChange={(e) =>
                                updateReceipt('tin', e.target.value)
                            }
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>Tax Status</Label>
                        <Input
                            value={form.receipt_store.tax_status}
                            onChange={(e) =>
                                updateReceipt('tax_status', e.target.value)
                            }
                            placeholder="NON-VAT REGISTERED"
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>POS Terminal ID</Label>
                        <Input
                            value={form.receipt_store.pos_terminal_id}
                            onChange={(e) =>
                                updateReceipt(
                                    'pos_terminal_id',
                                    e.target.value,
                                )
                            }
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>ATP Date Issued</Label>
                        <Input
                            value={form.receipt_store.atp_date_issued}
                            onChange={(e) =>
                                updateReceipt(
                                    'atp_date_issued',
                                    e.target.value,
                                )
                            }
                            placeholder="01/15/2026"
                        />
                    </div>
                    <div className="grid gap-2">
                        <Label>Invoice Series Range</Label>
                        <Input
                            value={form.receipt_store.series_range}
                            onChange={(e) =>
                                updateReceipt('series_range', e.target.value)
                            }
                        />
                    </div>
                </div>
            </SettingsSection>

            <SettingsSection
                title="Tax & Currency"
                subtitle="Set to 0% to disable VAT on all new sales and refunds"
                icon={Calculator}
            >
                <div className="grid gap-2">
                    <Label>Tax / VAT Rate (%)</Label>
                    <Input
                        type="number"
                        min={0}
                        max={100}
                        step={0.01}
                        value={(form.tax_rate * 100).toFixed(2)}
                        onChange={(e) =>
                            update(
                                'tax_rate',
                                Math.max(
                                    0,
                                    Math.min(
                                        1,
                                        Number(e.target.value) / 100,
                                    ),
                                ),
                            )
                        }
                    />
                </div>
                <div className="grid gap-2">
                    <Label>Currency Symbol</Label>
                    <Select
                        value={form.currency_symbol}
                        onValueChange={(value) =>
                            update('currency_symbol', value)
                        }
                    >
                        <SelectTrigger>
                            <SelectValue />
                        </SelectTrigger>
                        <SelectContent>
                            {Object.entries(CURRENCY_OPTIONS).map(
                                ([key, label]) => (
                                    <SelectItem key={key} value={key}>
                                        {label}
                                    </SelectItem>
                                ),
                            )}
                            {!CURRENCY_OPTIONS[form.currency_symbol] && (
                                <SelectItem value={form.currency_symbol}>
                                    {form.currency_symbol}
                                </SelectItem>
                            )}
                        </SelectContent>
                    </Select>
                </div>
            </SettingsSection>

            <SettingsSection
                title="Printer"
                subtitle="Receipt printing behavior for POS tablets"
                icon={Printer}
            >
                <ToggleRow
                    label="Auto Print Receipt"
                    description="Print automatically after payment"
                    checked={form.auto_print_receipt}
                    onChange={(value) =>
                        update('auto_print_receipt', value)
                    }
                />
                <ToggleRow
                    label="Double Print"
                    description="Print each receipt twice after payment"
                    checked={form.double_print_receipt}
                    onChange={(value) =>
                        update('double_print_receipt', value)
                    }
                />
            </SettingsSection>

            <SettingsSection
                title="Attendance Schedule"
                subtitle="Configure morning, break, afternoon, and time-out windows. All times are editable — nothing is hardcoded."
                icon={Clock}
            >
                <div className="space-y-6">
                    <div>
                        <h4 className="mb-3 text-sm font-semibold text-foreground">
                            Morning session
                        </h4>
                        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
                            <TimeField
                                label="Time-in acceptance start"
                                value={form.attendance_morning_accept_start}
                                onChange={(v) =>
                                    update('attendance_morning_accept_start', v)
                                }
                            />
                            <TimeField
                                label="Official start time"
                                value={form.attendance_morning_official_start}
                                onChange={(v) =>
                                    update('attendance_morning_official_start', v)
                                }
                            />
                            <TimeField
                                label="Grace period end (on time until)"
                                value={form.attendance_morning_grace_end}
                                onChange={(v) =>
                                    update('attendance_morning_grace_end', v)
                                }
                            />
                            <TimeField
                                label="Late period start"
                                value={form.attendance_morning_late_start}
                                onChange={(v) =>
                                    update('attendance_morning_late_start', v)
                                }
                            />
                            <TimeField
                                label="Morning cutoff (no more time-in)"
                                value={form.attendance_morning_cutoff}
                                onChange={(v) =>
                                    update('attendance_morning_cutoff', v)
                                }
                            />
                        </div>
                    </div>

                    <div>
                        <h4 className="mb-3 text-sm font-semibold text-foreground">
                            Break session
                        </h4>
                        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
                            <TimeField
                                label="Break time-out start"
                                value={form.attendance_break_out_start}
                                onChange={(v) =>
                                    update('attendance_break_out_start', v)
                                }
                            />
                            <TimeField
                                label="Break time-out end"
                                value={form.attendance_break_out_end}
                                onChange={(v) =>
                                    update('attendance_break_out_end', v)
                                }
                            />
                        </div>
                    </div>

                    <div>
                        <h4 className="mb-3 text-sm font-semibold text-foreground">
                            Afternoon session
                        </h4>
                        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
                            <TimeField
                                label="Time-in acceptance start"
                                value={form.attendance_afternoon_accept_start}
                                onChange={(v) =>
                                    update('attendance_afternoon_accept_start', v)
                                }
                            />
                            <TimeField
                                label="On-time limit"
                                value={form.attendance_afternoon_on_time_end}
                                onChange={(v) =>
                                    update('attendance_afternoon_on_time_end', v)
                                }
                            />
                            <TimeField
                                label="Late period start"
                                value={form.attendance_afternoon_late_start}
                                onChange={(v) =>
                                    update('attendance_afternoon_late_start', v)
                                }
                            />
                            <TimeField
                                label="Afternoon cutoff (no more time-in)"
                                value={form.attendance_afternoon_cutoff}
                                onChange={(v) =>
                                    update('attendance_afternoon_cutoff', v)
                                }
                            />
                        </div>
                    </div>

                    <div>
                        <h4 className="mb-3 text-sm font-semibold text-foreground">
                            Time-out
                        </h4>
                        <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
                            <TimeField
                                label="Time-out start"
                                value={form.attendance_timeout_start}
                                onChange={(v) =>
                                    update('attendance_timeout_start', v)
                                }
                            />
                        </div>
                    </div>
                </div>
                <p className="mt-4 text-xs text-muted-foreground">
                    Morning: accept {form.attendance_morning_accept_start}–
                    {form.attendance_morning_cutoff} (official{' '}
                    {form.attendance_morning_official_start}, on time until{' '}
                    {form.attendance_morning_grace_end}, late from{' '}
                    {form.attendance_morning_late_start}). Break out{' '}
                    {form.attendance_break_out_start}–{form.attendance_break_out_end}.
                    Afternoon: accept {form.attendance_afternoon_accept_start}–
                    {form.attendance_afternoon_cutoff} (on time until{' '}
                    {form.attendance_afternoon_on_time_end}, late from{' '}
                    {form.attendance_afternoon_late_start}). Time-out from{' '}
                    {form.attendance_timeout_start}. After each cutoff, employees
                    without a session time-in are marked absent for that session.
                </p>
            </SettingsSection>

            <SettingsSection
                title="POS Rules"
                subtitle="Checkout and inventory behavior"
                icon={ListChecks}
            >
                <ToggleRow
                    label="Allow Negative Stock"
                    description="Sell items even when stock is zero"
                    checked={form.allow_negative_stock}
                    onChange={(value) =>
                        update('allow_negative_stock', value)
                    }
                />
                <ToggleRow
                    label="Email on low stock"
                    description="Send an alert when item stock reaches its reorder level"
                    checked={form.low_stock_email_enabled ?? true}
                    onChange={(value) =>
                        update('low_stock_email_enabled', value)
                    }
                />
                {form.low_stock_email_enabled !== false && (
                    <div className="grid gap-2">
                        <Label htmlFor="low-stock-recipients">
                            Low stock alert emails
                        </Label>
                        <div className="relative">
                            <Mail className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-muted-foreground" />
                            <Input
                                id="low-stock-recipients"
                                className="pl-9"
                                placeholder={
                                    account?.email &&
                                    !account.email.endsWith('.local')
                                        ? `Leave blank to use ${account.email}`
                                        : 'ruarjomar03@gmail.com'
                                }
                                value={form.low_stock_email_recipients ?? ''}
                                onChange={(e) =>
                                    update(
                                        'low_stock_email_recipients',
                                        e.target.value,
                                    )
                                }
                            />
                        </div>
                        <p className="text-xs text-muted-foreground">
                            Comma-separated addresses. Leave blank to use your
                            Gmail sender ({' '}
                            <span className="font-medium">MAIL_FROM_ADDRESS</span>
                            ). Local demo accounts like{' '}
                            <span className="font-medium">admin@agriculture.local</span>{' '}
                            cannot receive mail.
                        </p>
                    </div>
                )}
                <ToggleRow
                    label="Loyalty Program"
                    description="Let registered customers earn and redeem points"
                    checked={form.loyalty_enabled}
                    onChange={(value) => update('loyalty_enabled', value)}
                />
                {form.loyalty_enabled && (
                    <div className="grid gap-3 rounded-xl border border-border/60 bg-secondary/10 p-4 md:grid-cols-3">
                        <div className="grid gap-2">
                            <Label>Points Earned</Label>
                            <Input
                                type="number"
                                min={0}
                                value={form.loyalty_points_per_unit}
                                onChange={(e) =>
                                    update(
                                        'loyalty_points_per_unit',
                                        Number(e.target.value),
                                    )
                                }
                            />
                        </div>
                        <div className="grid gap-2">
                            <Label>Spend Amount For Points</Label>
                            <Input
                                type="number"
                                min={1}
                                step={0.01}
                                value={form.loyalty_spend_unit}
                                onChange={(e) =>
                                    update(
                                        'loyalty_spend_unit',
                                        Number(e.target.value),
                                    )
                                }
                            />
                        </div>
                        <div className="grid gap-2">
                            <Label>
                                Points Needed For {form.currency_symbol}1
                                Discount
                            </Label>
                            <Input
                                type="number"
                                min={1}
                                value={form.loyalty_redeem_points_per_peso}
                                onChange={(e) =>
                                    update(
                                        'loyalty_redeem_points_per_peso',
                                        Number(e.target.value),
                                    )
                                }
                            />
                        </div>
                    </div>
                )}
            </SettingsSection>

            {account && (
                <SettingsSection
                    title="Signed In Account"
                    subtitle="Current web session"
                    icon={User}
                >
                    <InfoRow label="Name" value={account.name} />
                    <InfoRow label="Email" value={account.email} />
                    <InfoRow label="Role" value={account.role} />
                </SettingsSection>
            )}
        </div>
    );

    return (
        <>
            <Head title="Settings" />

            <h1 className="sr-only">Settings</h1>

            <div className="-m-6 flex flex-col md:-m-8 xl:min-h-[calc(100vh-12rem)] xl:flex-row">
                <div className="flex-1 overflow-y-auto p-6 md:p-8">
                    {formContent}
                </div>

                <aside className="flex flex-col border-t border-border/60 bg-secondary/10 xl:w-[min(100%,380px)] xl:border-t-0 xl:border-l">
                    <div className="flex-1 overflow-y-auto p-4">
                        <p className="mb-3 text-xs font-semibold tracking-wide text-muted-foreground uppercase">
                            Receipt preview
                        </p>
                        <ThermalReceiptPreview
                            store={form.receipt_store}
                            currencySymbol={form.currency_symbol}
                            taxRate={form.tax_rate}
                        />
                    </div>
                    <div className="border-t border-border/60 p-4">
                        <Button
                            className="h-12 w-full"
                            onClick={() => void handleSave()}
                            disabled={saving}
                        >
                            {saving ? (
                                <Loader2 className="size-4 animate-spin" />
                            ) : (
                                <Save className="size-4" />
                            )}
                            {saving ? 'Saving...' : 'Save Settings'}
                        </Button>
                    </div>
                </aside>
            </div>
        </>
    );
}

StoreSettingsPage.layout = {
    breadcrumbs: [
        {
            title: 'Settings',
            href: '/settings/store',
        },
    ],
};
