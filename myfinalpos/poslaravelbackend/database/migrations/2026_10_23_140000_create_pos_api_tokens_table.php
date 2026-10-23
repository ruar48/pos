<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('pos_api_tokens')) {
            return;
        }

        // Sign-in tokens for the tablet app (one per login). Only a SHA-256
        // hash is stored; the plain token lives on the tablet.
        Schema::create('pos_api_tokens', function (Blueprint $table) {
            $table->id();
            $table->unsignedInteger('user_id')->index();
            $table->char('token_hash', 64)->unique();
            $table->string('device_name', 120)->nullable();
            $table->timestamp('last_used_at')->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamp('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('pos_api_tokens');
    }
};
