<?php

namespace Tests\Feature\Database;

use App\Models\ActivityLog;
use App\Models\Product;
use App\Models\SyncIdempotencyKey;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;
use Tests\TestCase;

class DatabaseIntegrityTest extends TestCase
{
    use RefreshDatabase;

    public function test_all_expected_tables_and_columns_exist(): void
    {
        $this->assertTrue(Schema::hasTable('products'));
        $this->assertTrue(Schema::hasTable('users'));
        $this->assertTrue(Schema::hasTable('sync_idempotency_keys'));
        $this->assertTrue(Schema::hasTable('activity_logs'));
        $this->assertTrue(Schema::hasTable('personal_access_tokens'));

        $this->assertTrue(Schema::hasColumns('products', [
            'uuid', 'internal_code', 'name', 'format', 'containment', 'price', 'quantity', 'image_base64', 'created_at', 'updated_at', 'deleted_at'
        ]));

        $this->assertTrue(Schema::hasColumns('users', [
            'id', 'name', 'email', 'password', 'role', 'is_active', 'disabled_at', 'created_by'
        ]));

        $this->assertTrue(Schema::hasColumns('sync_idempotency_keys', [
            'key', 'entity_type', 'entity_id', 'status', 'response_data', 'created_at'
        ]));
    }

    public function test_strict_uniqueness_constraint_on_internal_code(): void
    {
        Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-STRICT-1',
            'name' => 'Premier Produit',
            'price' => 10,
            'quantity' => 1,
        ]);

        $this->expectException(QueryException::class);

        // Insertion brute en base avec le même internal_code doit échouer au niveau du moteur SQL
        DB::table('products')->insert([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-STRICT-1',
            'name' => 'Second Produit Conflit',
            'price' => 20,
            'quantity' => 1,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function test_strict_uniqueness_constraint_on_user_email(): void
    {
        User::create([
            'name' => 'Utilisateur Initial',
            'email' => 'duplicate.db@example.com',
            'password' => 'secret',
            'role' => User::ROLE_MANAGER,
        ]);

        $this->expectException(QueryException::class);

        DB::table('users')->insert([
            'name' => 'Utilisateur Doublon',
            'email' => 'duplicate.db@example.com',
            'password' => 'another_secret',
            'role' => User::ROLE_MANAGER,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    public function test_database_transaction_rollbacks_cleanly_on_exception(): void
    {
        $initialProductCount = Product::count();
        $initialLogCount = ActivityLog::count();

        try {
            DB::transaction(function () {
                Product::create([
                    'uuid' => (string) Str::uuid(),
                    'internal_code' => 'CAP-ROLLBACK-1',
                    'name' => 'Produit Annulé',
                    'price' => 15,
                    'quantity' => 1,
                ]);

                ActivityLog::create([
                    'action' => 'product.created',
                    'entity_type' => 'product',
                    'entity_id' => 'fake-uuid',
                ]);

                // Déclenchement intentionnel d'une exception
                throw new \RuntimeException('Erreur critique simulée en milieu de transaction');
            });
        } catch (\RuntimeException $e) {
            $this->assertEquals('Erreur critique simulée en milieu de transaction', $e->getMessage());
        }

        // Vérification stricte du rollback intégral
        $this->assertEquals($initialProductCount, Product::count());
        $this->assertEquals($initialLogCount, ActivityLog::count());
        $this->assertDatabaseMissing('products', ['internal_code' => 'CAP-ROLLBACK-1']);
    }

    public function test_database_indexes_exist_on_search_and_ordering_columns(): void
    {
        // Vérification que les colonnes clés possèdent bien des index
        $productIndexes = collect(DB::select("PRAGMA index_list('products')"))->pluck('name')->all();
        $this->assertNotEmpty($productIndexes);

        $hasInternalCodeIndex = false;
        foreach ($productIndexes as $idx) {
            $cols = collect(DB::select("PRAGMA index_info('$idx')"))->pluck('name')->all();
            if (in_array('internal_code', $cols, true)) {
                $hasInternalCodeIndex = true;
                break;
            }
        }
        $this->assertTrue($hasInternalCodeIndex, 'La colonne internal_code doit être indexée pour des recherches rapides');
    }

    public function test_referential_integrity_and_null_on_delete_constraint(): void
    {
        // Activer explicitement les contraintes SQLite si nécessaire
        DB::statement('PRAGMA foreign_keys = ON;');

        $user = User::factory()->create([
            'email' => 'audit.user@example.com',
            'role' => User::ROLE_MANAGER,
        ]);

        $log = ActivityLog::create([
            'user_id' => $user->id,
            'action' => 'user.logged_in',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
            'metadata' => ['device' => 'TestDevice'],
        ]);

        $this->assertEquals($user->id, $log->user_id);

        // Suppression de l'utilisateur relié
        $user->delete();

        // L'intégrité référentielle doit être préservée : le journal d'activité subsiste
        // avec son user_id automatiquement passé à NULL (nullOnDelete)
        $this->assertDatabaseHas('activity_logs', ['id' => $log->id]);
        $freshLog = ActivityLog::find($log->id);
        $this->assertNotNull($freshLog);
        $this->assertNull($freshLog->user_id, 'Le user_id du journal doit être nullOnDelete lors de la suppression de l\'utilisateur');
    }
}
