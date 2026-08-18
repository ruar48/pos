<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    /** @use HasFactory<\Database\Factories\UserFactory> */
    use HasFactory, Notifiable;

    public $timestamps = false;

    protected $fillable = [
        'full_name',
        'name',
        'username',
        'email',
        'password_hash',
        'role',
        'status',
        'branch_id',
        'email_verified_at',
    ];

    protected $hidden = [
        'password_hash',
        'remember_token',
    ];

    protected $appends = [
        'name',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'status' => 'integer',
            'branch_id' => 'integer',
            'password_hash' => 'hashed',
        ];
    }

    public function getAuthPassword(): string
    {
        return (string) $this->password_hash;
    }

    public function getNameAttribute(): string
    {
        return (string) $this->full_name;
    }

    public function setNameAttribute(string $value): void
    {
        $this->attributes['full_name'] = $value;
    }

    public function isActive(): bool
    {
        return (int) $this->status === 1;
    }
}
