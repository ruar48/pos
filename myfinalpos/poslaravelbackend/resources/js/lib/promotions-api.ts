import { laravelFetch } from '@/lib/laravel-fetch';

export type CouponDiscountType = 'fixed' | 'percentage';

export type Coupon = {
    id: number;
    code: string;
    description: string | null;
    discount_type: CouponDiscountType;
    discount_value: number;
    min_order_amount: number;
    start_date: string;
    end_date: string;
    max_uses: number | null;
    usage_count: number;
    status: number;
    created_at: string | null;
};

export type CouponFormInput = {
    action?: 'create' | 'update' | 'toggle';
    id?: number;
    code: string;
    description?: string;
    discount_type: CouponDiscountType;
    discount_value: number;
    min_order_amount?: number;
    start_date: string;
    end_date: string;
    max_uses?: number | null;
};

export async function fetchCoupons(includeInactive = true) {
    const params = includeInactive ? '?include_inactive=1' : '';
    return laravelFetch<{ data: Coupon[] }>(`/pos/promotions/coupons${params}`);
}

export async function saveCoupon(input: CouponFormInput) {
    return laravelFetch<{ message: string; data: Coupon }>('/pos/promotions/coupons', {
        method: 'POST',
        body: JSON.stringify(input),
    });
}

export async function toggleCoupon(id: number) {
    return laravelFetch<{ message: string; data: Coupon }>('/pos/promotions/coupons', {
        method: 'POST',
        body: JSON.stringify({ action: 'toggle', id }),
    });
}
