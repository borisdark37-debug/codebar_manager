<?php

namespace Tests\Feature\Performance;

use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Tests\TestCase;

class PerformanceAndLoadTest extends TestCase
{
    use RefreshDatabase;

    public function test_batch_sync_push_performance_with_100_mutations(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);

        $mutations = [];
        for ($i = 1; $i <= 100; $i++) {
            $mutations[] = [
                'idempotency_key' => 'perf-key-' . $i . '-' . Str::random(8),
                'entity_type' => 'product',
                'action' => 'create',
                'data' => [
                    'uuid' => (string) Str::uuid(),
                    'internal_code' => sprintf('CAP-LOAD-%04d', $i),
                    'name' => "Produit Charge #$i",
                    'format' => '50ml',
                    'containment' => 'Pot',
                    'price' => 19.90 + ($i * 0.1),
                    'quantity' => $i,
                    'created_at' => Carbon::now()->toIso8601String(),
                    'updated_at' => Carbon::now()->toIso8601String(),
                ],
            ];
        }

        $startTime = microtime(true);
        $memBefore = memory_get_usage();

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => $mutations,
        ]);

        $duration = microtime(true) - $startTime;
        $memAfter = memory_get_usage();

        $response->assertOk()
            ->assertJsonPath('status', 'success')
            ->assertJsonCount(100, 'results');

        $this->assertEquals(100, Product::count());

        // Assertions de performances raisonnables
        // 100 mutations traitées en moins de 3.5 secondes
        $this->assertLessThan(3.5, $duration, "Le lot de 100 mutations doit être traité en moins de 3.5s (temps mesuré: {$duration}s)");
    }

    public function test_batch_sync_push_scalability_with_250_mutations(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);

        $batchSize = 250;
        $mutations = [];
        for ($i = 1; $i <= $batchSize; $i++) {
            $mutations[] = [
                'idempotency_key' => 'perf-250-' . $i . '-' . Str::random(8),
                'entity_type' => 'product',
                'action' => 'create',
                'data' => [
                    'uuid' => (string) Str::uuid(),
                    'internal_code' => sprintf('CAP-SCALE-%05d', $i),
                    'name' => "Produit Échelle #$i",
                    'format' => '100ml',
                    'containment' => 'Flacon',
                    'price' => 10.0 + ($i * 0.05),
                    'quantity' => ($i % 50) + 1,
                    'created_at' => Carbon::now()->toIso8601String(),
                    'updated_at' => Carbon::now()->toIso8601String(),
                ],
            ];
        }

        $startTime = microtime(true);
        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => $mutations,
        ]);
        $duration = microtime(true) - $startTime;

        $response->assertOk()
            ->assertJsonPath('status', 'success')
            ->assertJsonCount($batchSize, 'results');

        $this->assertEquals($batchSize, Product::where('internal_code', 'like', 'CAP-SCALE-%')->count());
        $this->assertLessThan(6.0, $duration, "Le lot de 250 mutations doit être traité en moins de 6.0s (temps mesuré: {$duration}s)");
    }

    public function test_indexed_sql_queries_execution_speed_on_large_dataset(): void
    {
        $now = Carbon::now();
        $batch = [];

        for ($i = 1; $i <= 200; $i++) {
            $batch[] = [
                'uuid' => (string) Str::uuid(),
                'internal_code' => sprintf('CAP-IDX-%05d', $i),
                'name' => "Produit Index #$i",
                'price' => 20.0,
                'quantity' => 10,
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }

        DB::table('products')->insert($batch);

        // 1. Recherche par internal_code indexé
        $startQuery = microtime(true);
        $found = Product::where('internal_code', 'CAP-IDX-00150')->first();
        $queryTime = (microtime(true) - $startQuery) * 1000; // en ms

        $this->assertNotNull($found);
        $this->assertEquals('Produit Index #150', $found->name);
        $this->assertLessThan(100.0, $queryTime, "La recherche indexée doit s'exécuter en moins de 100ms (temps: {$queryTime}ms)");

        // 2. Recherche par updated_at avec tri
        $startRange = microtime(true);
        $count = Product::where('updated_at', '>=', $now->subMinute())->count();
        $rangeTime = (microtime(true) - $startRange) * 1000;

        $this->assertEquals(200, $count);
        $this->assertLessThan(150.0, $rangeTime, "Le filtrage par date doit s'exécuter en moins de 150ms (temps: {$rangeTime}ms)");
    }
}
