<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PosUser extends Model
{
    public $timestamps = false;

    protected $table = 'users';

    protected $fillable = [
        'full_name',
        'username',
        'email',
        'password_hash',
        'role',
        'status',
        'branch_id',
    ];

    protected $hidden = [
        'password_hash',
    ];

    protected function casts(): array
    {
        return [
            'status' => 'integer',
            'branch_id' => 'integer',
            'created_at' => 'datetime',
        ];
    }
}
