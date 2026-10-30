<?php

namespace Tests\Feature\EndToEnd;

use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class EndToEndSyncFlowTest extends TestCase
{
    use RefreshDatabase;

    public function test_full_multi_client_offline_online_sync_cycle(): void
    {
        $superAdmin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $client1Time = Carbon::now()->subMinutes(10);

        // --- ÉTAPE 1 : Client 1 génère des mutations hors-ligne ---
        $prodUuid1 = (string) Str::uuid();
        $prodUuid2 = (string) Str::uuid();
        $idemp1 = (string) Str::uuid();
        $idemp2 = (string) Str::uuid();

        $client1Outbox = [
            'mutations' => [
                [
                    'idempotency_key' => $idemp1,
                    'entity_type' => 'product',
                    'action' => 'create',
                    'client_timestamp' => $client1Time->toIso8601String(),
                    'data' => [
                        'uuid' => $prodUuid1,
                        'internal_code' => 'CAP-E2E-01',
                        'name' => 'Produit Client 1 Offline',
                        'format' => '50ml',
                        'containment' => 'Pot',
                        'price' => 22.50,
                        'quantity' => 10,
                        'created_at' => $client1Time->toIso8601String(),
                        'updated_at' => $client1Time->toIso8601String(),
                    ],
                ],
                [
                    'idempotency_key' => $idemp2,
                    'entity_type' => 'product',
                    'action' => 'create',
                    'client_timestamp' => $client1Time->addSecond()->toIso8601String(),
                    'data' => [
                        'uuid' => $prodUuid2,
                        'internal_code' => 'CAP-E2E-02',
                        'name' => 'Produit Client 1 Supprimable',
                        'format' => '100ml',
                        'containment' => 'Flacon',
                        'price' => 35.00,
                        'quantity' => 5,
                        'created_at' => $client1Time->toIso8601String(),
                        'updated_at' => $client1Time->toIso8601String(),
                    ],
                ],
            ],
        ];

        // --- ÉTAPE 2 : Client 1 se reconnecte et PUSH ses mutations vers Laravel ---
        $pushRes1 = $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', $client1Outbox);
        $pushRes1->assertOk()
            ->assertJsonPath('status', 'success')
            ->assertJsonPath('results.0.status', 'synced')
            ->assertJsonPath('results.1.status', 'synced');

        // Validation persistance centrale
        $this->assertDatabaseHas('products', ['uuid' => $prodUuid1, 'internal_code' => 'CAP-E2E-01']);
        $this->assertDatabaseHas('products', ['uuid' => $prodUuid2, 'internal_code' => 'CAP-E2E-02']);

        // --- ÉTAPE 3 : Client 2 se connecte et effectue un PULL delta ---
        $client2Since = Carbon::now()->subHours(1);
        $pullRes1 = $this->actingAs($superAdmin)->getJson('/api/v1/sync/pull?since=' . urlencode($client2Since->toIso8601String()));
        $pullRes1->assertOk()
            ->assertJsonPath('status', 'success');

        $client2ReceivedUuids = collect($pullRes1->json('products'))->pluck('uuid')->all();
        $this->assertContains($prodUuid1, $client2ReceivedUuids);
        $this->assertContains($prodUuid2, $client2ReceivedUuids);

        // --- ÉTAPE 4 : Client 1 supprime prodUuid2 et modifie prodUuid1 ---
        $updateTime = Carbon::now();
        $idemp3 = (string) Str::uuid();
        $idemp4 = (string) Str::uuid();

        $client1UpdateOutbox = [
            'mutations' => [
                [
                    'idempotency_key' => $idemp3,
                    'entity_type' => 'product',
                    'action' => 'update',
                    'client_timestamp' => $updateTime->toIso8601String(),
                    'data' => [
                        'uuid' => $prodUuid1,
                        'internal_code' => 'CAP-E2E-01',
                        'name' => 'Produit Client 1 Mis à Jour',
                        'price' => 24.00,
                        'updated_at' => $updateTime->toIso8601String(),
                    ],
                ],
                [
                    'idempotency_key' => $idemp4,
                    'entity_type' => 'product',
                    'action' => 'delete',
                    'client_timestamp' => $updateTime->toIso8601String(),
                    'data' => [
                        'uuid' => $prodUuid2,
                    ],
                ],
            ],
        ];

        $pushRes2 = $this->actingAs($superAdmin)->postJson('/api/v1/sync/push', $client1UpdateOutbox);
        $pushRes2->assertOk()
            ->assertJsonPath('status', 'success');

        $this->assertDatabaseHas('products', ['uuid' => $prodUuid1, 'name' => 'Produit Client 1 Mis à Jour']);
        $this->assertSoftDeleted('products', ['uuid' => $prodUuid2]);

        // --- ÉTAPE 5 : Client 2 effectue un PULL delta depuis sa dernière sync ---
        $pullRes2 = $this->actingAs($superAdmin)->getJson('/api/v1/sync/pull?since=' . urlencode($client2Since->toIso8601String()));
        $pullRes2->assertOk();

        // Vérification de la présence du tombstone pour le produit 2
        $tombstones = $pullRes2->json('tombstones.products');
        $this->assertContains($prodUuid2, $tombstones);

        // Vérification que le produit 1 a bien la nouvelle valeur
        $updatedProd = collect($pullRes2->json('products'))->firstWhere('uuid', $prodUuid1);
        $this->assertNotNull($updatedProd);
        $this->assertEquals('Produit Client 1 Mis à Jour', $updatedProd['name']);
        $this->assertEquals('24.00', (string) $updatedProd['price']);
    }
}
