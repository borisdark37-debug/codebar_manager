<?php

namespace Tests\Unit;

use App\Models\SyncIdempotencyKey;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class SyncIdempotencyKeyModelTest extends TestCase
{
    use RefreshDatabase;

    public function test_sync_idempotency_key_model_attributes_and_casts(): void
    {
        $key = (string) Str::uuid();
        $record = SyncIdempotencyKey::create([
            'key' => $key,
            'entity_type' => 'product',
            'entity_id' => 'prod-uuid-1',
            'status' => 'synced',
            'response_data' => ['success' => true, 'timestamp' => Carbon::now()->toIso8601String()],
            'created_at' => Carbon::now(),
        ]);

        $this->assertEquals($key, $record->key);
        $this->assertEquals('prod-uuid-1', $record->entity_id);
        $this->assertEquals('synced', $record->status);
        $this->assertIsArray($record->response_data);
        $this->assertTrue($record->response_data['success']);

        $fresh = SyncIdempotencyKey::find($key);
        $this->assertNotNull($fresh);
        $this->assertEquals($key, $fresh->key);
        $this->assertInstanceOf(Carbon::class, $fresh->created_at);
        $this->assertFalse($fresh->getIncrementing());
        $this->assertEquals('string', $fresh->getKeyType());
    }
}
