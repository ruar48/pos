<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->increments('id');
            $table->string('full_name', 120);
            $table->string('username', 80)->unique();
            $table->string('email', 120)->unique();
            $table->timestamp('email_verified_at')->nullable();
            $table->string('password_hash');
            $table->rememberToken()->nullable();
            $table->string('role', 50)->default('admin');
            $table->unsignedTinyInteger('status')->default(1);
            $table->unsignedInteger('branch_id')->nullable();
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('categories', function (Blueprint $table) {
            $table->increments('id');
            $table->string('name', 120)->unique();
            $table->string('icon', 80)->nullable();
            $table->string('description', 255)->nullable();
        });

        Schema::create('products', function (Blueprint $table) {
            $table->increments('id');
            $table->unsignedInteger('category_id');
            $table->string('name', 150);
            $table->text('description')->nullable();
            $table->string('sku', 60)->nullable()->unique();
            $table->string('barcode', 60)->nullable()->unique();
            $table->string('unit', 120)->default('pc');
            $table->decimal('price', 12, 2)->default(0);
            $table->decimal('cost_price', 12, 2)->nullable();
            $table->integer('stock')->default(0);
            $table->integer('reorder_level')->default(5);
            $table->string('image_url', 255)->nullable();
            $table->string('status', 30)->default('active');
            $table->timestamp('created_at')->useCurrent();
            $table->timestamp('updated_at')->nullable();

            $table->foreign('category_id')
                ->references('id')
                ->on('categories')
                ->restrictOnDelete();
        });

        Schema::create('customers', function (Blueprint $table) {
            $table->increments('id');
            $table->string('customer_name', 150);
            $table->string('table_name', 150)->nullable();
            $table->string('order_type', 50)->default('Retail');
            $table->timestamp('created_at')->useCurrent();
        });

        Schema::create('branches', function (Blueprint $table) {
            $table->increments('id');
            $table->string('name', 120);
            $table->string('code', 40)->nullable();
            $table->string('location', 255)->nullable();
            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();
            $table->decimal('geofence_radius_km', 5, 2)->default(2.0);
            $table->boolean('is_active')->default(true);
            $table->timestamp('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('branches');
        Schema::dropIfExists('customers');
        Schema::dropIfExists('products');
        Schema::dropIfExists('categories');
        Schema::dropIfExists('users');
    }
};
