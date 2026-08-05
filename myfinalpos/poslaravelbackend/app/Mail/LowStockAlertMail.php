<?php

namespace App\Mail;

use Illuminate\Bus\Queueable;
use Illuminate\Mail\Mailable;
use Illuminate\Mail\Mailables\Content;
use Illuminate\Mail\Mailables\Envelope;
use Illuminate\Queue\SerializesModels;

class LowStockAlertMail extends Mailable
{
    use Queueable, SerializesModels;

    /**
     * @param  array{
     *     product_id: int,
     *     name: string,
     *     sku: ?string,
     *     stock: float,
     *     reorder_level: int,
     *     store_name: string
     * }  $product
     */
    public function __construct(
        public readonly array $product,
    ) {}

    public function envelope(): Envelope
    {
        $name = (string) ($this->product['name'] ?? 'Product');
        $stock = (float) ($this->product['stock'] ?? 0);

        return new Envelope(
            subject: 'Low stock: '.$name.' ('.$stock.' left)',
        );
    }

    public function content(): Content
    {
        return new Content(
            view: 'mail.low-stock-alert',
            with: [
                'product' => $this->product,
            ],
        );
    }
}
