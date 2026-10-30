<?php

namespace Tests\Feature;

use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class SyncEngineTest extends TestCase
{
    use RefreshDatabase;

    public function test_v1_sync_push_creates_product_with_idempotency_key(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();
        $idempotencyKey = (string) Str::uuid();

        $response = $this->actingAs($user)
            ->postJson('/api/v1/sync/push', [
                'mutations' => [
                    [
                        'idempotency_key' => $idempotencyKey,
                        'entity_type' => 'product',
                        'action' => 'create',
                        'data' => [
                            'uuid' => $uuid,
                            'internal_code' => 'CAP-1001',
                            'name' => 'Produit Sync Test',
                            'format' => '50ml',
                            'containment' => 'Pot',
                            'price' => 19.99,
                            'quantity' => 15,
                            'created_at' => Carbon::now()->toIso8601String(),
                            'updated_at' => Carbon::now()->toIso8601String(),
                        ],
                    ],
                ],
            ]);

        $response->assertOk()
            ->assertJsonPath('status', 'success')
            ->assertJsonPath('results.0.status', 'synced')
            ->assertJsonPath('results.0.uuid', $uuid);

        $this->assertDatabaseHas('products', [
            'uuid' => $uuid,
            'internal_code' => 'CAP-1001',
            'name' => 'Produit Sync Test',
        ]);

        $this->assertDatabaseHas('sync_idempotency_keys', [
            'key' => $idempotencyKey,
            'status' => 'synced',
        ]);
    }

    public function test_v1_sync_push_idempotent_replay_does_not_duplicate_side_effects(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();
        $idempotencyKey = (string) Str::uuid();

        $payload = [
            'mutations' => [
                [
                    'idempotency_key' => $idempotencyKey,
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-1002',
                        'name' => 'Produit Idempotent',
                        'price' => 10.0,
                        'quantity' => 5,
                        'created_at' => Carbon::now()->toIso8601String(),
                        'updated_at' => Carbon::now()->toIso8601String(),
                    ],
                ],
            ],
        ];

        // 1ère exécution
        $first = $this->actingAs($user)->postJson('/api/v1/sync/push', $payload);
        $first->assertOk()->assertJsonPath('results.0.status', 'synced');

        // 2ème exécution avec la même clé d'idempotence
        $second = $this->actingAs($user)->postJson('/api/v1/sync/push', $payload);
        $second->assertOk()
            ->assertJsonPath('results.0.status', 'synced')
            ->assertJsonPath('results.0.idempotent_replay', true);

        $this->assertEquals(1, Product::where('uuid', $uuid)->count());
    }

    public function test_v1_sync_push_rejects_duplicate_internal_code(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid1 = (string) Str::uuid();
        $uuid2 = (string) Str::uuid();

        Product::create([
            'uuid' => $uuid1,
            'internal_code' => 'CAP-EXISTS',
            'name' => 'Produit Existant',
            'price' => 5.0,
            'quantity' => 1,
            'created_at' => Carbon::now(),
            'updated_at' => Carbon::now(),
        ]);

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $uuid2,
                        'internal_code' => 'CAP-EXISTS',
                        'name' => 'Produit Conflit Code',
                        'price' => 15.0,
                        'quantity' => 2,
                        'created_at' => Carbon::now()->toIso8601String(),
                        'updated_at' => Carbon::now()->toIso8601String(),
                    ],
                ],
            ],
        ]);

        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'error');
    }

    public function test_v1_sync_push_detects_last_write_wins_conflict(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();
        $serverTime = Carbon::now();

        Product::create([
            'uuid' => $uuid,
            'internal_code' => 'CAP-LWW',
            'name' => 'Version Serveur Recente',
            'price' => 50.0,
            'quantity' => 1,
            'created_at' => $serverTime,
            'updated_at' => $serverTime,
        ]);

        // Client tente de pousser une version antérieure
        $oldClientTime = $serverTime->copy()->subHours(2);

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'update',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-LWW',
                        'name' => 'Ancienne Version Client',
                        'price' => 40.0,
                        'quantity' => 1,
                        'updated_at' => $oldClientTime->toIso8601String(),
                    ],
                    'client_timestamp' => $oldClientTime->toIso8601String(),
                ],
            ],
        ]);

        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'conflict');
    }

    public function test_v1_sync_pull_returns_deltas_and_tombstones_since_timestamp(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);

        $past = Carbon::now()->subDays(2);
        $since = Carbon::now()->subHours(1);

        // Produit ancien (avant $since)
        Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-OLD',
            'name' => 'Vieux Produit',
            'price' => 10,
            'quantity' => 2,
            'created_at' => $past,
            'updated_at' => $past,
        ]);

        // Produit récent (après $since)
        $newProduct = Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-RECENT',
            'name' => 'Nouveau Produit',
            'price' => 30,
            'quantity' => 5,
            'created_at' => Carbon::now(),
            'updated_at' => Carbon::now(),
        ]);

        // Produit supprimé récemment (tombstone)
        $deletedProduct = Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-DELETED',
            'name' => 'Produit Supprimé',
            'price' => 10,
            'quantity' => 0,
            'created_at' => $past,
            'updated_at' => Carbon::now(),
            'deleted_at' => Carbon::now(),
        ]);

        $response = $this->actingAs($user)->getJson('/api/v1/sync/pull?since=' . urlencode($since->toIso8601String()));

        $response->assertOk()
            ->assertJsonPath('status', 'success')
            ->assertJsonStructure(['server_time', 'products', 'users', 'tombstones']);

        $returnedUuids = collect($response->json('products'))->pluck('uuid')->all();
        $this->assertContains($newProduct->uuid, $returnedUuids);
        $this->assertNotContains('CAP-OLD', collect($response->json('products'))->pluck('internal_code')->all());

        $tombstones = $response->json('tombstones.products');
        $this->assertContains($deletedProduct->uuid, $tombstones);
    }

    public function test_v1_sync_push_user_mutation_creates_and_updates_without_demoting_role(): void
    {
        $superAdmin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $idemp1 = (string) Str::uuid();
        $idemp2 = (string) Str::uuid();

        // 1. Création d'un admin via mutation
        $createRes = $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => $idemp1,
                    'entity_type' => 'user',
                    'action' => 'create',
                    'data' => [
                        'name' => 'Alice Admin',
                        'email' => 'alice.admin@example.com',
                        'password' => 'secret456',
                        'role' => 'admin',
                    ],
                ],
            ],
        ]);

        $createRes->assertOk()
            ->assertJsonPath('results.0.status', 'synced')
            ->assertJsonPath('results.0.uuid', 'alice.admin@example.com');

        $this->assertDatabaseHas('users', [
            'email' => 'alice.admin@example.com',
            'role' => 'admin',
            'is_active' => true,
        ]);

        $alice = User::where('email', 'alice.admin@example.com')->first();
        $this->assertNotNull($alice);
        $this->assertTrue(Hash::check('secret456', $alice->password), 'Le mot de passe synchronisé doit correspondre au hash sécurisé');
        $this->assertFalse(Hash::check('mauvais_mot_de_passe', $alice->password));

        // 2. Modification partielle sans préciser le rôle : le rôle ne doit JAMAIS être écrasé à 'manager'
        $updateRes = $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => $idemp2,
                    'entity_type' => 'user',
                    'action' => 'update',
                    'data' => [
                        'email' => 'alice.admin@example.com',
                        'is_active' => false,
                    ],
                ],
            ],
        ]);

        $updateRes->assertOk()->assertJsonPath('results.0.status', 'synced');

        $user = User::where('email', 'alice.admin@example.com')->first();
        $this->assertNotNull($user);
        $this->assertFalse((bool) $user->is_active);
        $this->assertEquals('admin', $user->role, 'Le rôle de l\'utilisateur ne doit pas être rétrogradé à manager');

        // Vérification de l'enregistrement dans ActivityLog
        $this->assertDatabaseHas('activity_logs', [
            'action' => 'user.created',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
        ]);
        $this->assertDatabaseHas('activity_logs', [
            'action' => 'user.updated',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
        ]);
    }

    public function test_v1_sync_push_lww_protects_deleted_product_from_stale_update(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();

        $product = Product::create([
            'uuid' => $uuid,
            'internal_code' => 'CAP-DEL-LWW',
            'name' => 'Produit Supprimé Sur Serveur',
            'price' => 20.0,
            'quantity' => 10,
            'created_at' => Carbon::now()->subHours(3),
            'updated_at' => Carbon::now()->subHours(2),
        ]);

        // Suppression logique sur le serveur à T = -1h
        $deletionTime = Carbon::now()->subHour();
        $product->deleted_at = $deletionTime;
        $product->save();

        // Le client hors-ligne tente de pousser une mise à jour horodatée à T = -1h30 (avant la suppression)
        $staleClientTime = Carbon::now()->subHours(1)->subMinutes(30);

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'update',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-DEL-LWW',
                        'name' => 'Tentative de résurrection par client obsolète',
                        'price' => 25.0,
                    ],
                    'client_timestamp' => $staleClientTime->toIso8601String(),
                ],
            ],
        ]);

        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'conflict');

        // Le produit doit impérativement rester supprimé sur le serveur
        $fresh = Product::withTrashed()->find($uuid);
        $this->assertNotNull($fresh->deleted_at, 'Le produit supprimé ne doit pas avoir été ressuscité');
    }

    public function test_v1_sync_pull_includes_force_deleted_products_and_deleted_users_in_tombstones(): void
    {
        $superAdmin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $since = Carbon::now()->subMinutes(10);

        // 1. Suppression définitive d'un produit
        $prodUuid = (string) Str::uuid();
        $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $prodUuid,
                        'internal_code' => 'CAP-TOMB-1',
                        'name' => 'À détruire',
                        'price' => 1,
                        'quantity' => 1,
                    ],
                ],
            ],
        ])->assertOk();

        $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'permanent_delete',
                    'data' => ['uuid' => $prodUuid],
                ],
            ],
        ])->assertOk();

        // 2. Suppression d'un utilisateur
        $userToDelete = User::factory()->create(['email' => 'deleted.user@example.com', 'role' => 'manager']);
        $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'user',
                    'action' => 'delete',
                    'data' => ['email' => $userToDelete->email],
                ],
            ],
        ])->assertOk();

        // 3. Appel de pull
        $response = $this->actingAs($superAdmin)->getJson('/api/v1/sync/pull?since=' . urlencode($since->toIso8601String()));

        $response->assertOk();
        $tombstones = $response->json('tombstones');

        $this->assertContains($prodUuid, $tombstones['products']);
        $this->assertContains($prodUuid, $tombstones['force_deleted_products']);
        $this->assertContains('deleted.user@example.com', $tombstones['users']);
    }
}
