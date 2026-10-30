<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Product;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_health_endpoint_is_public(): void
    {
        $this->getJson('/api/health')
            ->assertOk()
            ->assertJson(['status' => 'ok']);
    }

    public function test_user_can_login_and_read_products_with_sanctum_token(): void
    {
        User::factory()->create([
            'email' => 'sync@example.com',
            'password' => 'password',
        ]);

        $login = $this->postJson('/api/login', [
            'email' => 'sync@example.com',
            'password' => 'password',
            'device_name' => 'PHPUnit',
        ]);

        $login->assertOk()->assertJsonStructure(['token']);

        $this->withToken($login->json('token'))
            ->getJson('/api/products')
            ->assertOk()
            ->assertJson(['products' => []]);
    }

    public function test_products_requires_authentication(): void
    {
        $this->getJson('/api/products')->assertUnauthorized();
    }

    public function test_sync_accepts_flutter_product_payload_and_restoration_query(): void
    {
        $user = User::factory()->create();
        $uuid = '550e8400-e29b-41d4-a716-446655440000';

        $this->actingAs($user)
            ->postJson('/api/sync', [
                'changes' => [[
                    'uuid' => $uuid,
                    'internal_code' => 'CAP-0001',
                    'name' => 'Produit test',
                    'format' => '',
                    'containment' => '',
                    'created_at' => '2026-10-24T12:00:00.000Z',
                    'updated_at' => '2026-10-24T12:00:00.000Z',
                    'deleted_at' => null,
                    'price' => 12.50,
                    'quantity' => 4,
                    'image_base64' => null,
                ]],
            ])
            ->assertOk()
            ->assertJsonPath('results.0.status', 'synced');

        $this->actingAs($user)
            ->getJson('/api/products?include_deleted=1')
            ->assertOk()
            ->assertJsonPath('products.0.uuid', $uuid);
    }

    public function test_offline_created_super_admin_can_migrate_to_server(): void
    {
        $response = $this->postJson('/api/migrate-super-admin', [
            'email' => 'superadmin@example.com',
            'name' => 'Super Admin',
            'password' => 'secret1234',
            'device_name' => 'TestDevice',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'user'])
            ->assertJsonPath('user.role', 'super_admin')
            ->assertJsonPath('user.email', 'superadmin@example.com');

        $token = $response->json('token');
        $this->assertNotEmpty($token);

        // Check that user can now list users with Sanctum token
        $this->withToken($token)
            ->getJson('/api/users')
            ->assertOk()
            ->assertJsonPath('users.0.email', 'superadmin@example.com');
    }

    public function test_migrate_super_admin_rejects_unauthorized_when_another_super_admin_exists(): void
    {
        User::factory()->create([
            'email' => 'existing_admin@example.com',
            'role' => User::ROLE_SUPER_ADMIN,
        ]);

        $response = $this->postJson('/api/migrate-super-admin', [
            'email' => 'another_admin@example.com',
            'name' => 'Fake Admin',
            'password' => 'secret1234',
        ]);

        $response->assertStatus(403);
    }

    public function test_health_endpoint_reports_database_status(): void
    {
        $this->getJson('/api/health')
            ->assertOk()
            ->assertJson([
                'status' => 'ok',
                'database' => 'connected',
            ]);
    }

    public function test_sync_push_accepts_valid_compressed_image(): void
    {
        $user = User::factory()->create();
        $token = $user->createToken('test')->plainTextToken;

        $mutation = [
            'mutations' => [
                [
                    'idempotency_key' => 'img-test-1',
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
                        'internal_code' => 'CAP-9999',
                        'name' => 'Produit avec Image',
                        'price' => 19.99,
                        'quantity' => 5,
                        'image_base64' => base64_encode('fake-compressed-jpeg-bytes'),
                    ],
                ],
            ],
        ];

        $response = $this->withToken($token)
            ->postJson('/api/sync/push', $mutation);

        $response->assertOk()
            ->assertJsonPath('results.0.status', 'synced');

        $this->assertDatabaseHas('products', [
            'uuid' => 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
            'internal_code' => 'CAP-9999',
            'image_base64' => base64_encode('fake-compressed-jpeg-bytes'),
        ]);
    }

    public function test_database_seeder_creates_two_default_super_admins(): void
    {
        $this->seed(\Database\Seeders\DatabaseSeeder::class);

        $this->assertDatabaseHas('users', [
            'email' => 'capucine@gmail.com',
            'role' => User::ROLE_SUPER_ADMIN,
        ]);

        $this->assertDatabaseHas('users', [
            'email' => 'borisdark37@gmail.com',
            'role' => User::ROLE_SUPER_ADMIN,
        ]);

        // Vérifier la connexion avec Capucine Bolo
        $login1 = $this->postJson('/api/login', [
            'email' => 'capucine@gmail.com',
            'password' => 'Password123!',
        ]);
        $login1->assertOk()->assertJsonStructure(['token', 'user']);

        // Vérifier la connexion avec Boris Dark
        $login2 = $this->postJson('/api/login', [
            'email' => 'borisdark37@gmail.com',
            'password' => 'Password123!',
        ]);
        $login2->assertOk()->assertJsonStructure(['token', 'user']);
    }

    public function test_super_admin_can_reset_user_password_online(): void
    {
        $superAdmin = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $targetUser = User::factory()->create([
            'email' => 'target.user@example.com',
            'password' => \Illuminate\Support\Facades\Hash::make('OldPassword1'),
        ]);

        $res = $this->actingAs($superAdmin)->postJson('/api/users/reset-password', [
            'email' => 'target.user@example.com',
            'password' => '0000',
        ]);

        $res->assertOk()->assertJson(['message' => 'Mot de passe réinitialisé avec succès.']);
        $this->assertTrue(\Illuminate\Support\Facades\Hash::check('0000', $targetUser->fresh()->password));
    }
}
