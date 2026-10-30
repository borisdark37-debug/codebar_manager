<?php

namespace Tests\Feature\Integration;

use App\Models\ActivityLog;
use App\Models\Product;
use App\Models\SyncIdempotencyKey;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Tests\TestCase;

class SyncIntegrationTest extends TestCase
{
    use RefreshDatabase;

    public function test_sync_push_and_pull_lifecycle_with_mixed_entities_and_activity_logs(): void
    {
        $superAdmin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $prodUuid1 = (string) Str::uuid();
        $prodUuid2 = (string) Str::uuid();
        $idemp1 = (string) Str::uuid();
        $idemp2 = (string) Str::uuid();
        $idemp3 = (string) Str::uuid();

        // 1. Transaction combinée : création produit 1, création produit 2, création utilisateur manager
        $response = $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => $idemp1,
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $prodUuid1,
                        'internal_code' => 'CAP-INT-10',
                        'name' => 'Shampooing Bio',
                        'price' => 14.50,
                        'quantity' => 20,
                    ],
                ],
                [
                    'idempotency_key' => $idemp2,
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $prodUuid2,
                        'internal_code' => 'CAP-INT-20',
                        'name' => 'Après-Shampooing',
                        'price' => 18.00,
                        'quantity' => 15,
                    ],
                ],
                [
                    'idempotency_key' => $idemp3,
                    'entity_type' => 'user',
                    'action' => 'create',
                    'data' => [
                        'name' => 'Manager Intégration',
                        'email' => 'manager.integration@example.com',
                        'password' => 'secret987',
                        'role' => 'manager',
                    ],
                ],
            ],
        ]);

        $response->assertOk()
            ->assertJsonPath('status', 'success')
            ->assertJsonCount(3, 'results');

        // Vérification base de données
        $this->assertDatabaseHas('products', ['uuid' => $prodUuid1, 'internal_code' => 'CAP-INT-10']);
        $this->assertDatabaseHas('products', ['uuid' => $prodUuid2, 'internal_code' => 'CAP-INT-20']);
        $this->assertDatabaseHas('users', ['email' => 'manager.integration@example.com', 'role' => 'manager']);
        $mgr = User::where('email', 'manager.integration@example.com')->first();
        $this->assertNotNull($mgr);
        $this->assertTrue(Hash::check('secret987', $mgr->password), 'Le mot de passe du manager créé par sync doit être sécurisé par hash');
        $this->assertFalse(Hash::check('badpass', $mgr->password));

        // Vérification des clés d'idempotence
        $this->assertEquals(3, SyncIdempotencyKey::whereIn('key', [$idemp1, $idemp2, $idemp3])->count());

        // Vérification des journaux d'activité (ActivityLog)
        $this->assertDatabaseHas('activity_logs', ['action' => 'product.created', 'entity_id' => $prodUuid1]);
        $this->assertDatabaseHas('activity_logs', ['action' => 'product.created', 'entity_id' => $prodUuid2]);
        $this->assertDatabaseHas('activity_logs', ['action' => 'user.created']);

        // 2. Pull incrémental par un client
        $since = Carbon::now()->subMinutes(5);
        $pullRes = $this->actingAs($superAdmin)->getJson('/api/v1/sync/pull?since=' . urlencode($since->toIso8601String()));

        $pullRes->assertOk()
            ->assertJsonPath('status', 'success');

        $prodList = collect($pullRes->json('products'))->pluck('uuid')->all();
        $this->assertContains($prodUuid1, $prodList);
        $this->assertContains($prodUuid2, $prodList);

        $userList = collect($pullRes->json('users'))->pluck('email')->all();
        $this->assertContains('manager.integration@example.com', $userList);
    }

    public function test_sync_push_transaction_atomicity_and_partial_error_reporting(): void
    {
        $superAdmin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $existingUuid = (string) Str::uuid();

        Product::create([
            'uuid' => $existingUuid,
            'internal_code' => 'CAP-TAKEN',
            'name' => 'Produit Déjà Existant',
            'price' => 5,
            'quantity' => 1,
        ]);

        $newUuid = (string) Str::uuid();
        $dupUuid = (string) Str::uuid();

        // Envoi d'un lot contenant 1 valide et 1 en conflit de code interne
        $response = $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $newUuid,
                        'internal_code' => 'CAP-VALID-NEW',
                        'name' => 'Produit Valide',
                        'price' => 20,
                        'quantity' => 2,
                    ],
                ],
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $dupUuid,
                        'internal_code' => 'CAP-TAKEN', // Conflit !
                        'name' => 'Produit en doublon de code',
                        'price' => 30,
                        'quantity' => 1,
                    ],
                ],
            ],
        ]);

        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'synced')
            ->assertJsonPath('results.1.status', 'error');

        $this->assertDatabaseHas('products', ['uuid' => $newUuid]);
        $this->assertDatabaseMissing('products', ['uuid' => $dupUuid]);
    }
}
