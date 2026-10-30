<?php

namespace Tests\Unit;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class UserModelTest extends TestCase
{
    use RefreshDatabase;

    public function test_user_roles_constants_and_helpers(): void
    {
        $superAdmin = new User(['role' => User::ROLE_SUPER_ADMIN]);
        $admin = new User(['role' => User::ROLE_ADMIN]);
        $manager = new User(['role' => User::ROLE_MANAGER]);

        $this->assertTrue($superAdmin->isSuperAdmin());
        $this->assertTrue($superAdmin->isAdmin());

        $this->assertFalse($admin->isSuperAdmin());
        $this->assertTrue($admin->isAdmin());

        $this->assertFalse($manager->isSuperAdmin());
        $this->assertFalse($manager->isAdmin());
    }

    public function test_user_password_hashing_and_hidden_attributes(): void
    {
        $user = User::create([
            'name' => 'Agent Dupont',
            'email' => 'dupont@example.com',
            'password' => 'clair_secret',
            'role' => User::ROLE_MANAGER,
        ]);

        $fresh = User::find($user->id);
        $this->assertNotEquals('clair_secret', $fresh->password);
        $this->assertTrue(Hash::check('clair_secret', $fresh->password));

        $array = $fresh->toArray();
        $this->assertArrayNotHasKey('password', $array);
        $this->assertArrayNotHasKey('remember_token', $array);
    }

    public function test_user_is_active_and_disabled_at_casts(): void
    {
        $user = User::create([
            'name' => 'Agent Inactif',
            'email' => 'inactif@example.com',
            'password' => 'secret123',
            'role' => User::ROLE_MANAGER,
            'is_active' => false,
            'disabled_at' => now(),
        ]);

        $this->assertFalse($user->is_active);
        $this->assertNotNull($user->disabled_at);
        $this->assertInstanceOf(\Carbon\Carbon::class, $user->disabled_at);
    }
}
