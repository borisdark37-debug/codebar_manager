<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Console\Seeds\WithoutModelEvents;
use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    use WithoutModelEvents;

    /**
     * Seed the application's database.
     */
    public function run(): void
    {
        // Deux super administrateurs par défaut
        User::firstOrCreate(
            ['email' => 'superadmin1@codebar.local'],
            [
                'name' => 'Super Admin 1',
                'password' => \Illuminate\Support\Facades\Hash::make('Password123!'),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_active' => true,
            ]
        );

        User::firstOrCreate(
            ['email' => 'superadmin2@codebar.local'],
            [
                'name' => 'Super Admin 2',
                'password' => \Illuminate\Support\Facades\Hash::make('Password123!'),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_active' => true,
            ]
        );

        // Utilisateur de test pour rétrocompatibilité
        User::firstOrCreate(
            ['email' => 'test@example.com'],
            [
                'name' => 'Test User',
                'password' => \Illuminate\Support\Facades\Hash::make('password'),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_active' => true,
            ]
        );
    }
}
