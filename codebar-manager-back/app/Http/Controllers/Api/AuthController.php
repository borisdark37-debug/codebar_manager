<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;
use App\Models\ActivityLog;

class AuthController extends Controller
{
    public function login(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required',
            'device_name' => 'nullable|string',
        ]);

        $user = User::where('email', $request->email)->first();

        if (!$user || !Hash::check($request->password, $user->password)) {
            return response()->json([
                'message' => 'Les identifiants sont incorrects.',
            ], 401);
        }

        if (isset($user->is_active) && !$user->is_active) {
            throw ValidationException::withMessages([
                'email' => ['Ce compte utilisateur a été désactivé par l\'administrateur.'],
            ]);
        }

        $deviceName = $request->device_name ?? 'CodeBar Manager Client';
        $token = $user->createToken($deviceName)->plainTextToken;
        ActivityLog::create([
            'user_id' => $user->id,
            'action' => 'auth.login',
            'metadata' => ['device' => $deviceName],
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'token' => $token,
            'user' => $user->only('id', 'name', 'email', 'role', 'is_active', 'created_by'),
        ]);
    }

    /**
     * Permet la migration et la création du Super Administrateur créé en mode local hors-ligne
     * vers le serveur central lorsque le serveur devient joignable.
     */
    public function migrateSuperAdmin(Request $request)
    {
        $request->validate([
            'email' => 'required|email',
            'password' => 'required|string|min:4',
            'name' => 'nullable|string|max:255',
            'device_name' => 'nullable|string',
        ]);

        $user = User::where('email', $request->email)->first();

        if ($user) {
            if ($user->role !== User::ROLE_SUPER_ADMIN) {
                return response()->json([
                    'message' => 'Cet email est déjà associé à un utilisateur qui n\'est pas super administrateur.',
                ], 409);
            }

            if (!Hash::check($request->password, $user->password)) {
                if ($user->email === 'test@example.com') {
                    $user->update([
                        'password' => Hash::make($request->password),
                        'name' => $request->name ?? $user->name,
                    ]);
                } else {
                    return response()->json([
                        'message' => 'Les identifiants ne correspondent pas au compte Super Administrateur existant sur le serveur.',
                    ], 401);
                }
            } elseif ($request->filled('name')) {
                $user->update(['name' => $request->name]);
            }
        } else {
            $existingSuperAdmin = User::where('role', User::ROLE_SUPER_ADMIN)
                ->where('email', '!=', 'test@example.com')
                ->first();

            if ($existingSuperAdmin) {
                return response()->json([
                    'message' => 'Un Super Administrateur est déjà enregistré sur ce serveur. Connectez-vous avec vos identifiants existants.',
                ], 403);
            }

            $user = User::create([
                'name' => $request->name ?? 'Super Admin',
                'email' => $request->email,
                'password' => Hash::make($request->password),
                'role' => User::ROLE_SUPER_ADMIN,
                'is_active' => true,
                'created_by' => null,
            ]);
        }

        $deviceName = $request->device_name ?? 'local_super_admin';
        $token = $user->createToken($deviceName)->plainTextToken;

        ActivityLog::create([
            'user_id' => $user->id,
            'action' => 'user.super_admin_migrated',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
            'metadata' => ['email' => $user->email, 'device' => $deviceName],
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'token' => $token,
            'user' => $user->only('id', 'name', 'email', 'role', 'is_active', 'created_by'),
            'message' => 'Super Administrateur migré avec succès sur le serveur.',
        ]);
    }
}
