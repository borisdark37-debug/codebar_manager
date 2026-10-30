<?php

namespace Tests\Feature\Api;

use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ComprehensiveApiEndpointsTest extends TestCase
{
    use RefreshDatabase;

    public function test_api_health_endpoints_return_200_and_expected_structure(): void
    {
        // 1. /api/health
        $res1 = $this->getJson('/api/health');
        $res1->assertOk()
            ->assertJsonStructure(['status', 'database', 'timestamp'])
            ->assertJson(['status' => 'ok', 'database' => 'connected']);

        // 2. /api/v1/health
        $res2 = $this->getJson('/api/v1/health');
        $res2->assertOk()
            ->assertJsonStructure(['status', 'database', 'timestamp'])
            ->assertJson(['status' => 'ok', 'database' => 'connected']);
    }

    public function test_api_auth_login_endpoint_scenarios(): void
    {
        User::factory()->create([
            'email' => 'login.test@example.com',
            'password' => 'secretPassword123',
            'role' => User::ROLE_MANAGER,
        ]);

        // 1. Succès sur /api/auth/login
        $success = $this->postJson('/api/auth/login', [
            'email' => 'login.test@example.com',
            'password' => 'secretPassword123',
            'device_name' => 'TestDevice',
        ]);
        $success->assertOk()
            ->assertJsonStructure(['token', 'user' => ['id', 'email', 'name', 'role']]);

        // 2. Échec mot de passe incorrect -> 401
        $badAuth = $this->postJson('/api/auth/login', [
            'email' => 'login.test@example.com',
            'password' => 'mauvais_mdp',
        ]);
        $badAuth->assertStatus(401);

        // 3. Validation payload manquant -> 422
        $invalidPayload = $this->postJson('/api/auth/login', []);
        $invalidPayload->assertStatus(422)
            ->assertJsonValidationErrors(['email', 'password']);
    }

    public function test_api_migrate_super_admin_endpoint_scenarios(): void
    {
        // 1. Conflit HTTP 409 : un utilisateur standard (manager) possède déjà cet email
        User::factory()->create([
            'email' => 'existing.manager@example.com',
            'role' => User::ROLE_MANAGER,
        ]);
        $conflict409Res = $this->postJson('/api/migrate-super-admin', [
            'name' => 'Attempted Super Admin',
            'email' => 'existing.manager@example.com',
            'password' => 'secretPassword123',
        ]);
        $conflict409Res->assertStatus(409)
            ->assertJson(['message' => 'Cet email est déjà associé à un utilisateur qui n\'est pas super administrateur.']);

        // 2. Création initiale réussie (HTTP 200)
        $res = $this->postJson('/api/migrate-super-admin', [
            'name' => 'Initial Super Admin',
            'email' => 'root.admin@example.com',
            'password' => 'rootSecretPass456',
            'device_name' => 'AdminTerminal',
        ]);

        $res->assertOk()
            ->assertJsonStructure(['token', 'user'])
            ->assertJsonPath('user.role', 'super_admin');

        // 3. Tentative de recréation / écrasement par un second super admin -> 403 Forbidden
        $conflictRes = $this->postJson('/api/migrate-super-admin', [
            'name' => 'Attacker',
            'email' => 'attacker@example.com',
            'password' => 'hacked',
        ]);
        $conflictRes->assertStatus(403);

        // 4. Validation payload incomplet -> 422 Unprocessable Entity
        $emptyRes = $this->postJson('/api/migrate-super-admin', [
            'email' => 'only_email@example.com',
        ]);
        $emptyRes->assertStatus(422);

        // 5. Vérification du préfixe REST /api/v1/migrate-super-admin
        $v1Conflict = $this->postJson('/api/v1/migrate-super-admin', [
            'name' => 'V1 Super Admin Duplicate',
            'email' => 'v1.dup@example.com',
            'password' => 'pass123',
        ]);
        $v1Conflict->assertStatus(403);
    }

    public function test_api_sync_push_and_pull_unauthenticated_and_validation(): void
    {
        // 1. Non authentifié -> 401
        $this->postJson('/api/v1/sync/push', ['mutations' => []])->assertUnauthorized();
        $this->getJson('/api/v1/sync/pull')->assertUnauthorized();

        // 2. Authentifié mais payload invalide -> 422
        $user = User::factory()->create();
        $this->actingAs($user)->postJson('/api/v1/sync/push', [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['mutations']);

        // 3. Authentifié mais timestamp pull invalide -> 422
        $this->actingAs($user)->getJson('/api/v1/sync/pull?since=invalid_date')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['since']);
    }

    public function test_api_products_list_endpoint(): void
    {
        $user = User::factory()->create();
        Product::create([
            'uuid' => (string) Str::uuid(),
            'internal_code' => 'CAP-API-1',
            'name' => 'Test API Prod',
            'price' => 10,
            'quantity' => 2,
        ]);

        $res = $this->actingAs($user)->getJson('/api/products');
        $res->assertOk()
            ->assertJsonStructure(['products']);
        $this->assertCount(1, $res->json('products'));
    }
}
