<?php

namespace Tests\Unit;

use App\Models\Product;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ProductModelTest extends TestCase
{
    use RefreshDatabase;

    public function test_product_attributes_fillable_and_key_type(): void
    {
        $uuid = (string) Str::uuid();
        $product = new Product([
            'uuid' => $uuid,
            'internal_code' => 'CAP-1001',
            'name' => 'Produit Huile Végétale',
            'format' => '100ml',
            'containment' => 'Flacon',
            'price' => 29.50,
            'quantity' => 12,
            'image_base64' => 'dGVzdA==',
        ]);

        $this->assertEquals($uuid, $product->uuid);
        $this->assertEquals('CAP-1001', $product->internal_code);
        $this->assertEquals('Produit Huile Végétale', $product->name);
        $this->assertEquals('100ml', $product->format);
        $this->assertEquals('Flacon', $product->containment);
        $this->assertEquals(29.50, $product->price);
        $this->assertEquals(12, $product->quantity);
        $this->assertEquals('dGVzdA==', $product->image_base64);

        $this->assertFalse($product->getIncrementing());
        $this->assertEquals('string', $product->getKeyType());
        $this->assertEquals('uuid', $product->getKeyName());
    }

    public function test_product_casts_attributes_correctly(): void
    {
        $now = Carbon::now();
        $product = Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-1002',
            'name' => 'Produit Sérum',
            'price' => 45.99,
            'quantity' => 8,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $fresh = Product::find($product->uuid);
        $this->assertNotNull($fresh);
        $this->assertInstanceOf(Carbon::class, $fresh->created_at);
        $this->assertInstanceOf(Carbon::class, $fresh->updated_at);
        $this->assertEquals('45.99', (string) $fresh->price);
        $this->assertIsInt($fresh->quantity);
        $this->assertEquals(8, $fresh->quantity);
    }

    public function test_product_soft_deletes_and_restoration(): void
    {
        $product = Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-1003',
            'name' => 'Produit Éphémère',
            'price' => 10,
            'quantity' => 1,
        ]);

        $this->assertNull($product->deleted_at);
        $product->delete();

        $this->assertSoftDeleted('products', ['uuid' => $product->uuid]);
        $this->assertNull(Product::find($product->uuid));
        $this->assertNotNull(Product::withTrashed()->find($product->uuid));

        $product->restore();
        $this->assertNull($product->fresh()->deleted_at);
        $this->assertNotNull(Product::find($product->uuid));
    }
}
