<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('products', function (Blueprint $table) {
            // UUID comme clé primaire, généré côté client Flutter
            $table->uuid('uuid')->primary();

            // Code interne CAP-XXXX, unique
            $table->string('internal_code', 32)->unique();

            $table->string('name', 255);
            $table->string('format', 64)->nullable();
            $table->string('containment', 64)->nullable();

            // Horodatages avec précision (pour la résolution de conflits)
            $table->timestampTz('created_at')->nullable();
            $table->timestampTz('updated_at')->nullable();

            // Suppression logique (soft delete)
            $table->timestampTz('deleted_at')->nullable();

            $table->index('updated_at');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('products');
    }
};