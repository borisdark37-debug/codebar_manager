<?php

namespace Tests\Feature\Regression;

use App\Models\ActivityLog;
use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class RegressionTestSuiteTest extends TestCase
{
    use RefreshDatabase;

    public function test_regression_super_admin_migration_preserves_password_and_grants_sanctum_access(): void
    {
        $response = $this->postJson('/api/migrate-super-admin', [
            'name' => 'Super Admin Test',
            'email' => 'superadmin.reg@example.com',
            'password' => 'SecurePass987!',
            'device_name' => 'RegressionDevice',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'user'])
            ->assertJsonPath('user.role', 'super_admin');

        $token = $response->json('token');

        // Vérification qu'on peut immédiatement se connecter avec le mot de passe défini
        $loginRes = $this->postJson('/api/auth/login', [
            'email' => 'superadmin.reg@example.com',
            'password' => 'SecurePass987!',
            'device_name' => 'SecondDevice',
        ]);
        $loginRes->assertOk();

        // Vérification de l'accès aux routes réservées au super admin avec le token
        $usersList = $this->withToken($token)->getJson('/api/users');
        $usersList->assertOk();
    }

    public function test_regression_internal_code_is_never_mutated_or_reassigned_on_updates(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();

        // Création initiale avec CAP-REG-001
        $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-REG-001',
                        'name' => 'Produit Code Fixe',
                        'price' => 10,
                        'quantity' => 1,
                    ],
                ],
            ],
        ])->assertOk();

        // Tentative de modification des détails du produit en conservant le code
        $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'update',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-REG-001',
                        'name' => 'Produit Nom Modifié',
                        'price' => 12,
                        'quantity' => 2,
                    ],
                ],
            ],
        ])->assertOk();

        $prod = Product::find($uuid);
        $this->assertEquals('CAP-REG-001', $prod->internal_code);
        $this->assertEquals('Produit Nom Modifié', $prod->name);
    }

    public function test_regression_tombstones_are_retained_across_multiple_pulls(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();

        // Création puis suppression
        Product::create([
            'uuid' => $uuid,
            'internal_code' => 'CAP-REG-DEL',
            'name' => 'Produit A Supprimer',
            'price' => 5,
            'quantity' => 1,
        ]);

        $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'delete',
                    'data' => ['uuid' => $uuid],
                ],
            ],
        ])->assertOk();

        $since = Carbon::now()->subMinutes(5);

        // Premier pull
        $pull1 = $this->actingAs($user)->getJson('/api/v1/sync/pull?since=' . urlencode($since->toIso8601String()));
        $pull1->assertOk();
        $this->assertContains($uuid, $pull1->json('tombstones.products'));

        // Deuxième pull immédiat (vérification de la persistance de l'état soft-delete)
        $pull2 = $this->actingAs($user)->getJson('/api/v1/sync/pull?since=' . urlencode($since->toIso8601String()));
        $pull2->assertOk();
        $this->assertContains($uuid, $pull2->json('tombstones.products'));
    }
}
