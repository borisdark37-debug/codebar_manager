<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;

class UserController extends Controller
{
    public function index()
    {
        return response()->json([
            'users' => User::query()
                ->select('id', 'name', 'email', 'role', 'is_active', 'disabled_at', 'created_by', 'created_at', 'updated_at')
                ->orderBy('name')
                ->get(),
        ]);
    }

    public function store(Request $request)
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:255'],
            'email' => ['required', 'email', 'max:255', 'unique:users,email'],
            'password' => ['required', 'string', 'min:4'],
            'role' => ['required', 'in:admin,manager,super_admin'],
            'created_by' => ['nullable', 'string', 'max:255'],
        ]);

        if (empty($data['created_by']) && $request->user()) {
            $data['created_by'] = $request->user()->name ?? $request->user()->email;
        }

        // Si rôle super_admin, on s'assure qu'il n'y a pas de créateur
        if ($data['role'] === 'super_admin') {
            $data['created_by'] = null;
        }

        $data['password'] = Hash::make($data['password']);
        $data['is_active'] = true;
        $user = User::create($data);

        ActivityLog::create([
            'user_id' => $request->user() ? $request->user()->id : $user->id,
            'action' => 'user.created',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
            'metadata' => [
                'role' => $user->role,
                'email' => $user->email,
                'created_by' => $user->created_by,
            ],
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'user' => $user->only('id', 'name', 'email', 'role', 'is_active', 'disabled_at', 'created_by', 'created_at'),
        ], 201);
    }

    /**
     * Synchronise une liste d'utilisateurs créés ou modifiés en local.
     */
    public function sync(Request $request)
    {
        $request->validate([
            'users' => ['required', 'array'],
            'users.*.name' => ['required', 'string'],
            'users.*.email' => ['required', 'email'],
            'users.*.role' => ['required', 'in:admin,manager,super_admin'],
            'users.*.password' => ['nullable', 'string'],
            'users.*.created_by' => ['nullable', 'string'],
            'users.*.is_active' => ['nullable', 'boolean'],
        ]);

        $synced = [];
        $creatorName = $request->user() ? ($request->user()->name ?? $request->user()->email) : 'super_admin';

        foreach ($request->users as $uData) {
            $user = User::where('email', $uData['email'])->first();

            if ($user) {
                // Mise à jour de l'utilisateur existant
                $updateData = [
                    'name' => $uData['name'],
                    'role' => $uData['role'],
                ];
                if (isset($uData['is_active'])) {
                    $updateData['is_active'] = (bool) $uData['is_active'];
                    if (!$updateData['is_active'] && !$user->disabled_at) {
                        $updateData['disabled_at'] = now();
                    } elseif ($updateData['is_active']) {
                        $updateData['disabled_at'] = null;
                    }
                }
                if (!empty($uData['password'])) {
                    $updateData['password'] = Hash::make($uData['password']);
                }
                $user->update($updateData);
            } else {
                // Création d'un nouvel utilisateur synchronisé
                $rawPassword = !empty($uData['password']) ? $uData['password'] : '0000';
                $user = User::create([
                    'name' => $uData['name'],
                    'email' => $uData['email'],
                    'password' => Hash::make($rawPassword),
                    'role' => $uData['role'],
                    'is_active' => $uData['is_active'] ?? true,
                    'created_by' => $uData['role'] === 'super_admin' ? null : ($uData['created_by'] ?? $creatorName),
                ]);
            }

            $synced[] = $user->only('id', 'name', 'email', 'role', 'is_active', 'disabled_at', 'created_by', 'created_at');
        }

        ActivityLog::create([
            'user_id' => $request->user()->id,
            'action' => 'users.synced',
            'entity_type' => 'user',
            'entity_id' => 'bulk',
            'metadata' => ['count' => count($synced)],
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'synced' => $synced,
            'message' => count($synced) . ' utilisateur(s) synchronisé(s) avec succès.',
        ]);
    }

    /**
     * Active ou désactive un utilisateur.
     */
    public function toggleActive(Request $request, User $user)
    {
        if ($user->role === 'super_admin') {
            return response()->json(['message' => 'Impossible de désactiver le compte Super Administrateur.'], 403);
        }

        $newActiveState = !$user->is_active;
        $user->is_active = $newActiveState;
        $user->disabled_at = $newActiveState ? null : now();
        $user->save();

        ActivityLog::create([
            'user_id' => $request->user()->id,
            'action' => $newActiveState ? 'user.activated' : 'user.disabled',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
            'metadata' => ['email' => $user->email, 'is_active' => $user->is_active],
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'message' => $newActiveState ? 'Utilisateur activé.' : 'Utilisateur désactivé.',
            'user' => $user->only('id', 'name', 'email', 'role', 'is_active', 'disabled_at', 'created_by'),
        ]);
    }

    /**
     * Supprime définitivement un utilisateur (si désactivé depuis au moins 30 jours, ou forcé).
     */
    public function destroy(Request $request, User $user)
    {
        if ($user->role === 'super_admin') {
            return response()->json(['message' => 'Impossible de supprimer le compte Super Administrateur.'], 403);
        }

        // Vérification des 30 jours si non forcé
        $force = filter_var($request->query('force', false), FILTER_VALIDATE_BOOLEAN);

        if (!$force) {
            if ($user->is_active || !$user->disabled_at) {
                return response()->json([
                    'message' => 'L\'utilisateur doit d\'abord être désactivé pendant 30 jours avant suppression définitive.',
                ], 422);
            }

            $daysDisabled = Carbon::parse($user->disabled_at)->diffInDays(now());
            if ($daysDisabled < 30) {
                return response()->json([
                    'message' => "L'utilisateur n'est désactivé que depuis {$daysDisabled} jour(s). La suppression automatique/définitive nécessite 30 jours.",
                    'days_remaining' => 30 - $daysDisabled,
                ], 422);
            }
        }

        $userEmail = $user->email;
        $userId = $user->id;
        $user->tokens()->delete();
        $user->delete();

        ActivityLog::create([
            'user_id' => $request->user()->id,
            'action' => 'user.deleted',
            'entity_type' => 'user',
            'entity_id' => (string) $userId,
            'metadata' => ['email' => $userEmail],
            'ip_address' => $request->ip(),
        ]);

        return response()->json([
            'message' => "L'utilisateur $userEmail a été supprimé définitivement du système.",
        ]);
    }

    /**
     * Réinitialise le mot de passe d'un utilisateur à la valeur fournie.
     * Réservé au super_admin.
     */
    public function resetPassword(Request $request)
    {
        $data = $request->validate([
            'email' => ['required', 'email', 'exists:users,email'],
            'password' => ['required', 'string', 'min:4'],
        ]);

        $user = User::where('email', $data['email'])->firstOrFail();

        $user->update(['password' => Hash::make($data['password'])]);

        ActivityLog::create([
            'user_id' => $request->user()->id,
            'action' => 'user.password_reset',
            'entity_type' => 'user',
            'entity_id' => (string) $user->id,
            'metadata' => ['email' => $user->email, 'role' => $user->role],
            'ip_address' => $request->ip(),
        ]);

        return response()->json(['message' => 'Mot de passe réinitialisé avec succès.']);
    }
}
