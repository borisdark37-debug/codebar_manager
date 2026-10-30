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
            ['email' => 'capucine@gmail.com'],
            [
                'name' => 'Capucine Bolo',
                'password' => \Illuminate\Support\Facades\Hash::make('Password123!'),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_active' => true,
            ]
        );

        User::firstOrCreate(
            ['email' => 'borisdark37@gmail.com'],
            [
                'name' => 'Boris Dark',
                'password' => \Illuminate\Support\Facades\Hash::make('Password123!'),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_active' => true,
            ]
        );
    }
}
