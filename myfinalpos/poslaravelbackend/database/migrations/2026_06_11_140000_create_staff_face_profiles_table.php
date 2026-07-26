<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('staff_face_profiles')) {
            return;
        }

        Schema::create('staff_face_profiles', function (Blueprint $table) {
            $table->unsignedInteger('user_id')->primary();
            $table->json('descriptor_json');
            $table->unsignedTinyInteger('confidence_score')->default(0);
            $table->unsignedInteger('enrolled_by')->nullable();
            $table->timestamp('enrolled_at')->useCurrent();
            $table->timestamp('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->index('enrolled_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('staff_face_profiles');
    }
};
