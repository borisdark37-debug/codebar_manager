<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('sync_idempotency_keys', function (Blueprint $table): void {
            $table->string('key', 128)->primary();
            $table->string('entity_type', 64)->nullable();
            $table->string('entity_id', 128)->nullable();
            $table->string('status', 32)->default('synced');
            $table->text('response_data')->nullable();
            $table->timestampTz('created_at')->useCurrent();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sync_idempotency_keys');
    }
};
