<?php

namespace Tests\Feature\Security;

use App\Models\Product;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class SecurityAndPrivilegeTest extends TestCase
{
    use RefreshDatabase;

    public function test_unauthenticated_request_cannot_access_sync_or_admin_endpoints(): void
    {
        $this->postJson('/api/v1/sync/push', [])->assertUnauthorized();
        $this->getJson('/api/v1/sync/pull')->assertUnauthorized();
        $this->getJson('/api/users')->assertUnauthorized();
        $this->getJson('/api/activity-logs')->assertUnauthorized();
    }

    public function test_manager_cannot_escalate_privileges_to_admin_or_super_admin(): void
    {
        $manager = User::factory()->create([
            'email' => 'manager.victim@example.com',
            'role' => User::ROLE_MANAGER,
        ]);

        // Tentative d'auto-promotion vers super_admin
        $response = $this->actingAs($manager)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'user',
                    'action' => 'update',
                    'data' => [
                        'email' => 'manager.victim@example.com',
                        'role' => 'super_admin',
                    ],
                ],
            ],
        ]);

        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'error')
            ->assertJsonPath('results.0.error', 'Élévation de privilèges interdite : un utilisateur standard ne peut pas modifier son rôle.');

        // Le rôle en base de données doit impérativement rester 'manager'
        $this->assertEquals(User::ROLE_MANAGER, $manager->fresh()->role);
    }

    public function test_manager_cannot_create_or_delete_other_users(): void
    {
        $manager = User::factory()->create(['role' => User::ROLE_MANAGER]);
        $targetUser = User::factory()->create(['email' => 'innocent@example.com', 'role' => User::ROLE_MANAGER]);

        // 1. Tentative de création d'un nouvel utilisateur
        $createRes = $this->actingAs($manager)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'user',
                    'action' => 'create',
                    'data' => [
                        'email' => 'illegal.user@example.com',
                        'name' => 'Illegal User',
                        'password' => 'secret',
                    ],
                ],
            ],
        ]);

        $createRes->assertStatus(207)
            ->assertJsonPath('results.0.status', 'error')
            ->assertJsonPath('results.0.error', 'Action non autorisée. Seul le Super Administrateur peut créer, supprimer ou modifier le statut des comptes.');

        $this->assertDatabaseMissing('users', ['email' => 'illegal.user@example.com']);

        // 2. Tentative de suppression d'un utilisateur existant
        $deleteRes = $this->actingAs($manager)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'user',
                    'action' => 'delete',
                    'data' => ['email' => 'innocent@example.com'],
                ],
            ],
        ]);

        $deleteRes->assertStatus(207)
            ->assertJsonPath('results.0.status', 'error');

        $this->assertDatabaseHas('users', ['email' => 'innocent@example.com']);
    }

    public function test_sql_injection_payloads_are_escaped_and_stored_literally(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $sqlInjectionCode = "CAP-SQL'; DROP TABLE products; --";
        $sqlInjectionName = "Nom Injecté ' OR 1=1 --";
        $prodUuid = (string) Str::uuid();

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $prodUuid,
                        'internal_code' => $sqlInjectionCode,
                        'name' => $sqlInjectionName,
                        'price' => 15.00,
                        'quantity' => 1,
                    ],
                ],
            ],
        ]);

        $response->assertOk()->assertJsonPath('results.0.status', 'synced');

        // La table products existe toujours et le produit contient la chaîne littérale exacte
        $product = Product::find($prodUuid);
        $this->assertNotNull($product);
        $this->assertEquals($sqlInjectionCode, $product->internal_code);
        $this->assertEquals($sqlInjectionName, $product->name);
    }

    public function test_huge_image_payload_exceeding_10mb_is_rejected(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        // Génération d'une chaîne dépassant 10 Mo (10 * 1024 * 1024 + 10 octets)
        $oversizedBase64 = str_repeat('A', (10 * 1024 * 1024) + 16);

        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => (string) Str::uuid(),
                        'internal_code' => 'CAP-OVERSIZED',
                        'name' => 'Produit Trop Volumineux',
                        'price' => 10,
                        'quantity' => 1,
                        'image_base64' => $oversizedBase64,
                    ],
                ],
            ],
        ]);

        $response->assertStatus(207)
            ->assertJsonPath('status', 'partial')
            ->assertJsonPath('results.0.status', 'error')
            ->assertJsonPath('results.0.error', "L'image dépasse la taille maximale autorisée (10 Mo).");
    }

    public function test_corrupted_or_garbage_image_base64_handled_safely(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_SUPER_ADMIN]);
        $uuid = (string) Str::uuid();

        // Envoi d'une chaîne corrompue/non valide
        $response = $this->actingAs($user)->postJson('/api/v1/sync/push', [
            'mutations' => [
                [
                    'idempotency_key' => (string) Str::uuid(),
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => [
                        'uuid' => $uuid,
                        'internal_code' => 'CAP-CORRUPT-IMG',
                        'name' => 'Image Corrompue',
                        'price' => 12,
                        'quantity' => 2,
                        'image_base64' => '!!!%%%???NotValidBase64@@@',
                    ],
                ],
            ],
        ]);

        // Doit accepter la persistance sans générer d'exception interne 500
        $response->assertOk()
            ->assertJsonPath('results.0.status', 'synced');

        $this->assertDatabaseHas('products', ['uuid' => $uuid]);
    }
}
