<?php

namespace Tests\Feature\Resilience;

use App\Models\Product;
use App\Models\SyncIdempotencyKey;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ResilienceAndChaosTest extends TestCase
{
    use RefreshDatabase;

    public function test_resilience_to_multiple_consecutive_idempotent_replays(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();
        $idempKey = 'chaos-idemp-' . Str::uuid();

        $payload = [
            'mutations' => [
                [
                    'idempotency_key' => $idempKey,
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-CHAOS-01',
                        'name' => 'Produit Rejeu Chaotique',
                        'price' => 50,
                        'quantity' => 10,
                    ],
                ],
            ],
        ];

        // 1ère exécution
        $first = $this->actingAs($user)->postJson('/api/v1/sync/push', $payload);
        $first->assertOk()->assertJsonPath('results.0.status', 'synced');

        // Rejeu 5 fois d'affilée (simulation de retry intempestif d'un réseau instable)
        for ($i = 1; $i <= 5; $i++) {
            $replay = $this->actingAs($user)->postJson('/api/v1/sync/push', $payload);
            $replay->assertOk()
                ->assertJsonPath('results.0.status', 'synced')
                ->assertJsonPath('results.0.idempotent_replay', true);
        }

        // Il ne doit y avoir strictement qu'une seule ligne en base et une seule clé
        $this->assertEquals(1, Product::where('uuid', $uuid)->count());
        $this->assertEquals(1, SyncIdempotencyKey::where('key', $idempKey)->count());
    }

    public function test_clock_drift_future_timestamp_clamping(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();

        // Le client a une horloge déréglée 2 ans dans le futur
        $futureClock = Carbon::now()->addYears(2);

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'client_timestamp' => $futureClock->toIso8601String(),
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-DRIFT-FUT',
                        'name' => 'Produit Horloge Futuriste',
                        'price' => 20,
                        'quantity' => 5,
                    ],
                ],
            ],
        ]);

        $response->assertOk()->assertJsonPath('results.0.status', 'synced');

        // La date enregistrée en base doit avoir été plafonnée à l'heure du serveur actuelle (+ max 5 min)
        $prod = Product::find($uuid);
        $this->assertNotNull($prod);
        $this->assertTrue($prod->updated_at->lessThanOrEqualTo(Carbon::now()->addMinutes(6)));
    }

    public function test_clock_drift_past_timestamp_lww_protection(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();

        $product = Product::create([
            'uuid' => $uuid,
            'internal_code' => 'CAP-DRIFT-PAST',
            'name' => 'Version Récente Serveur',
            'price' => 50,
            'quantity' => 5,
            'updated_at' => Carbon::now(),
        ]);

        // Client avec horloge dans le passé lointain tente d'écraser la donnée récente
        $pastClock = Carbon::now()->subDays(10);

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'update',
                    'client_timestamp' => $pastClock->toIso8601String(),
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-DRIFT-PAST',
                        'name' => 'Tentative écrasement par passé',
                        'price' => 10,
                        'updated_at' => $pastClock->toIso8601String(),
                    ],
                ],
            ],
        ]);

        // Doit signaler un conflit LWW sans écraser la version du serveur
        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'conflict');

        $this->assertEquals('Version Récente Serveur', $product->fresh()->name);
        $this->assertEquals('50.00', (string) $product->fresh()->price);
    }
}
