@php
    $storeName = (string) ($product['store_name'] ?? config('app.name'));
    $productName = (string) ($product['name'] ?? 'Product');
    $sku = trim((string) ($product['sku'] ?? ''));
    $stock = (int) ($product['stock'] ?? 0);
    $reorder = max(1, (int) ($product['reorder_level'] ?? 5));
    $shortfall = max(0, $reorder - $stock);
    $fillPercent = min(100, max(8, (int) round(($stock / $reorder) * 100)));
    $inventoryUrl = rtrim((string) config('app.url'), '/') . '/pos/inventory';
    $sentAt = now()->format('M j, Y g:i A');
@endphp
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Low stock alert</title>
</head>
<body style="margin:0;padding:0;background-color:#F4F6F5;font-family:Arial,Helvetica,sans-serif;color:#17202A;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background-color:#F4F6F5;padding:32px 16px;">
    <tr>
        <td align="center">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;">
                {{-- Brand header --}}
                <tr>
                    <td style="padding:0 0 16px 0;text-align:center;">
                        <div style="font-size:12px;font-weight:700;letter-spacing:0.12em;text-transform:uppercase;color:#64748B;">
                            {{ config('app.name') }}
                        </div>
                    </td>
                </tr>

                {{-- Main card --}}
                <tr>
                    <td style="background:#FFFFFF;border:1px solid #E1E7EC;border-radius:18px;overflow:hidden;box-shadow:0 10px 30px rgba(23,32,42,0.08);">
                        {{-- Green banner --}}
                        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                            <tr>
                                <td style="background:linear-gradient(135deg,#0E5F35 0%,#1F8A4C 100%);padding:28px 28px 24px 28px;">
                                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                                        <tr>
                                            <td>
                                                <span style="display:inline-block;background:#E8891C;color:#FFFFFF;font-size:11px;font-weight:700;letter-spacing:0.08em;text-transform:uppercase;padding:6px 10px;border-radius:999px;">
                                                    Low stock
                                                </span>
                                                <div style="margin-top:14px;font-size:24px;line-height:1.25;font-weight:700;color:#FFFFFF;">
                                                    Restock needed
                                                </div>
                                                <div style="margin-top:6px;font-size:14px;line-height:1.5;color:rgba(255,255,255,0.88);">
                                                    {{ $storeName }}
                                                </div>
                                            </td>
                                            <td align="right" valign="top" style="width:56px;">
                                                <div style="width:48px;height:48px;border-radius:14px;background:rgba(255,255,255,0.14);text-align:center;line-height:48px;font-size:24px;">
                                                    📦
                                                </div>
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                        </table>

                        {{-- Body --}}
                        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                            <tr>
                                <td style="padding:28px;">
                                    <div style="font-size:20px;line-height:1.35;font-weight:700;color:#17202A;">
                                        {{ $productName }}
                                    </div>
                                    @if ($sku !== '')
                                        <div style="margin-top:6px;font-size:13px;color:#64748B;">
                                            SKU: <span style="font-weight:600;color:#17202A;">{{ $sku }}</span>
                                        </div>
                                    @endif

                                    {{-- Stats --}}
                                    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin-top:22px;">
                                        <tr>
                                            <td width="33%" style="padding:14px 10px;background:#FFF7ED;border:1px solid #FED7AA;border-radius:12px;text-align:center;">
                                                <div style="font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#C2410C;">
                                                    Current
                                                </div>
                                                <div style="margin-top:6px;font-size:24px;font-weight:800;color:#E8891C;">
                                                    {{ $stock }}
                                                </div>
                                            </td>
                                            <td width="8"></td>
                                            <td width="33%" style="padding:14px 10px;background:#EAF7EF;border:1px solid #C8EAD4;border-radius:12px;text-align:center;">
                                                <div style="font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#0E5F35;">
                                                    Reorder at
                                                </div>
                                                <div style="margin-top:6px;font-size:24px;font-weight:800;color:#1F8A4C;">
                                                    {{ $reorder }}
                                                </div>
                                            </td>
                                            <td width="8"></td>
                                            <td width="33%" style="padding:14px 10px;background:#FEF2F2;border:1px solid #FECACA;border-radius:12px;text-align:center;">
                                                <div style="font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#B91C1C;">
                                                    Short by
                                                </div>
                                                <div style="margin-top:6px;font-size:24px;font-weight:800;color:#E23A4E;">
                                                    {{ $shortfall }}
                                                </div>
                                            </td>
                                        </tr>
                                    </table>

                                    {{-- Stock bar --}}
                                    <div style="margin-top:22px;">
                                        <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                                            <tr>
                                                <td style="font-size:12px;font-weight:600;color:#64748B;padding-bottom:8px;">
                                                    Stock level
                                                </td>
                                                <td align="right" style="font-size:12px;font-weight:700;color:#E8891C;padding-bottom:8px;">
                                                    {{ $fillPercent }}% of reorder target
                                                </td>
                                            </tr>
                                        </table>
                                        <div style="height:10px;background:#EAF7EF;border-radius:999px;overflow:hidden;border:1px solid #C8EAD4;">
                                            <div style="width:{{ $fillPercent }}%;height:10px;background:linear-gradient(90deg,#E8891C 0%,#E23A4E 100%);border-radius:999px;"></div>
                                        </div>
                                    </div>

                                    <div style="margin-top:22px;padding:14px 16px;background:#FAFBFC;border:1px solid #E1E7EC;border-radius:12px;font-size:14px;line-height:1.6;color:#475569;">
                                        This item has dropped to or below its reorder level. Restock soon to avoid running out during sales.
                                    </div>

                                    {{-- CTA --}}
                                    <table role="presentation" cellspacing="0" cellpadding="0" style="margin-top:24px;">
                                        <tr>
                                            <td style="border-radius:12px;background:#1F8A4C;">
                                                <a href="{{ $inventoryUrl }}" style="display:inline-block;padding:14px 22px;font-size:14px;font-weight:700;color:#FFFFFF;text-decoration:none;">
                                                    Open Inventory
                                                </a>
                                            </td>
                                        </tr>
                                    </table>
                                </td>
                            </tr>
                        </table>
                    </td>
                </tr>

                {{-- Footer --}}
                <tr>
                    <td style="padding:18px 8px 0 8px;text-align:center;font-size:12px;line-height:1.6;color:#94A3B8;">
                        Sent {{ $sentAt }} · {{ $storeName }}<br>
                        © {{ date('Y') }} {{ config('app.name') }}
                    </td>
                </tr>
            </table>
        </td>
    </tr>
</table>
</body>
</html>
