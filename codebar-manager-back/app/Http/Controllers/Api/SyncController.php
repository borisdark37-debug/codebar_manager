<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use App\Models\Product;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class SyncController extends Controller
{
    /**
     * Point d'entrée de synchronisation push (lot ordonné de mutations avec clés d'idempotence).
     * Rétrocompatible avec l'ancien format {'changes': [...]}.
     */
    public function push(Request $request)
    {
        // Support du format moderne {'mutations': [...]} ou du format historique {'changes': [...]}
        if ($request->has('changes') && !$request->has('mutations')) {
            return $this->processLegacyChanges($request);
        }

        return $this->processMutations($request);
    }

    /**
     * Alias rétrocompatible pour /api/sync.
     */
    public function sync(Request $request)
    {
        return $this->push($request);
    }

    /**
     * Traitement du flux transactionnel de mutations avec clés d'idempotence.
     */
    private function processMutations(Request $request)
    {
        $validated = $request->validate([
            'idempotency_key' => 'nullable|string|max:128',
            'mutations' => 'required|array',
            'mutations.*.idempotency_key' => 'required|string|max:128',
            'mutations.*.entity_type' => 'required|string|in:product,user',
            'mutations.*.action' => 'required|string|in:create,update,delete,permanent_delete,toggle_active',
            'mutations.*.data' => 'required|array',
            'mutations.*.client_timestamp' => 'nullable|date',
        ]);

        $results = [];

        DB::transaction(function () use ($validated, $request, &$results) {
            foreach ($validated['mutations'] as $mutation) {
                $results[] = $this->applySingleMutation($mutation, $request);
            }
        });

        $hasErrors = collect($results)->contains(fn($r) => in_array($r['status'], ['error', 'conflict'], true));

        return response()->json([
            'status' => $hasErrors ? 'partial' : 'success',
            'server_time' => Carbon::now()->toIso8601String(),
            'results' => $results,
        ], $hasErrors ? 207 : 200);
    }

    /**
     * Applique une mutation individuelle avec vérification d'idempotence et Last-Write-Wins.
     */
    private function applySingleMutation(array $mutation, Request $request): array
    {
        $key = $mutation['idempotency_key'];
        $entityType = $mutation['entity_type'];
        $action = $mutation['action'];
        $data = $mutation['data'];
        $clientTime = !empty($mutation['client_timestamp'])
            ? Carbon::parse($mutation['client_timestamp'])
            : (!empty($data['updated_at']) ? Carbon::parse($data['updated_at']) : Carbon::now());

        // 1. Dédoublonnage d'idempotence
        $existingIdempotency = DB::table('sync_idempotency_keys')->where('key', $key)->first();
        if ($existingIdempotency) {
            $entityId = $existingIdempotency->entity_id ?? ($data['uuid'] ?? ($data['id'] ?? null));
            return [
                'idempotency_key' => $key,
                'uuid' => (string) $entityId,
                'entity_type' => $entityType,
                'status' => $existingIdempotency->status ?? 'synced',
                'idempotent_replay' => true,
            ];
        }

        $result = ['idempotency_key' => $key, 'entity_type' => $entityType];

        // 2. Traitement selon le type d'entité
        if ($entityType === 'product') {
            $result = array_merge($result, $this->applyProductMutation($action, $data, $clientTime, $request));
        } elseif ($entityType === 'user') {
            $result = array_merge($result, $this->applyUserMutation($action, $data, $clientTime, $request));
        }

        // 3. Enregistrement de la clé d'idempotence si succès
        if (($result['status'] ?? '') === 'synced') {
            DB::table('sync_idempotency_keys')->insert([
                'key' => $key,
                'entity_type' => $entityType,
                'entity_id' => (string) ($result['uuid'] ?? ($data['uuid'] ?? ($data['id'] ?? null))),
                'status' => 'synced',
                'created_at' => Carbon::now(),
            ]);
        }

        return $result;
    }

    /**
     * Traitement d'une mutation de produit.
     */
    private function applyProductMutation(string $action, array $data, Carbon $clientTime, Request $request): array
    {
        $uuid = $data['uuid'] ?? null;
        if (!$uuid) {
            return ['status' => 'error', 'error' => 'Identifiant UUID produit manquant.'];
        }

        // Évite qu'une horloge cliente erronée dans le futur lointain ne verrouille les écritures
        if ($clientTime->gt(Carbon::now()->addMinutes(5))) {
            $clientTime = Carbon::now();
        }

        $existing = Product::withTrashed()->find($uuid);

        // Détermination du timestamp le plus récent côté serveur (updated_at ou deleted_at)
        $serverLastModified = $existing ? max(
            $existing->updated_at ? $existing->updated_at->timestamp : 0,
            $existing->deleted_at ? $existing->deleted_at->timestamp : 0
        ) : 0;

        if ($action === 'permanent_delete') {
            if ($existing) {
                // Si la version serveur est plus récente que la demande de suppression
                if ($serverLastModified > $clientTime->timestamp) {
                    return [
                        'uuid' => $uuid,
                        'status' => 'conflict',
                        'server_updated_at' => ($existing->deleted_at && $existing->deleted_at->timestamp > ($existing->updated_at?->timestamp ?? 0))
                            ? $existing->deleted_at->toIso8601String()
                            : $existing->updated_at->toIso8601String(),
                        'message' => 'La version serveur est plus récente.',
                    ];
                }

                $existing->forceDelete();
                ActivityLog::create([
                    'user_id' => $request->user()?->id,
                    'action' => 'product.force_deleted',
                    'entity_type' => 'product',
                    'entity_id' => $uuid,
                    'ip_address' => $request->ip(),
                ]);
            }
            return ['uuid' => $uuid, 'status' => 'synced'];
        }

        if ($action === 'delete') {
            if ($existing) {
                // LWW : si le serveur a une modification plus récente que la suppression
                if ($serverLastModified > $clientTime->timestamp) {
                    return [
                        'uuid' => $uuid,
                        'status' => 'conflict',
                        'server_updated_at' => ($existing->deleted_at && $existing->deleted_at->timestamp > ($existing->updated_at?->timestamp ?? 0))
                            ? $existing->deleted_at->toIso8601String()
                            : $existing->updated_at->toIso8601String(),
                        'message' => 'La version serveur est plus récente.',
                    ];
                }

                $existing->delete();
                ActivityLog::create([
                    'user_id' => $request->user()?->id,
                    'action' => 'product.deleted',
                    'entity_type' => 'product',
                    'entity_id' => $uuid,
                    'ip_address' => $request->ip(),
                ]);
            }
            return ['uuid' => $uuid, 'status' => 'synced'];
        }

        // Action create ou update
        $internalCode = $data['internal_code'] ?? null;
        if (!$internalCode) {
            return ['uuid' => $uuid, 'status' => 'error', 'error' => 'Code interne manquant.'];
        }

        // Conflit d'unicité sur internal_code
        $codeConflict = Product::withTrashed()
            ->where('internal_code', $internalCode)
            ->where('uuid', '!=', $uuid)
            ->exists();

        if ($codeConflict) {
            return [
                'uuid' => $uuid,
                'status' => 'error',
                'error' => "Le code $internalCode est déjà utilisé par un autre produit.",
            ];
        }

        // Résolution Last-Write-Wins (prenant en compte updated_at ET deleted_at)
        if ($existing && $serverLastModified > $clientTime->timestamp) {
            return [
                'uuid' => $uuid,
                'status' => 'conflict',
                'server_updated_at' => ($existing->deleted_at && $existing->deleted_at->timestamp > ($existing->updated_at?->timestamp ?? 0))
                    ? $existing->deleted_at->toIso8601String()
                    : $existing->updated_at->toIso8601String(),
                'message' => 'La version serveur est plus récente.',
            ];
        }

        $imageBase64 = array_key_exists('image_base64', $data) ? $data['image_base64'] : ($existing ? $existing->image_base64 : null);
        if ($imageBase64 !== null) {
            if (!is_string($imageBase64) || trim($imageBase64) === '') {
                $imageBase64 = null;
            } elseif (strlen($imageBase64) > 10 * 1024 * 1024) {
                return [
                    'uuid' => $uuid,
                    'status' => 'error',
                    'error' => "L'image dépasse la taille maximale autorisée (10 Mo).",
                ];
            }
        }

        Product::withTrashed()->updateOrCreate(
            ['uuid' => $uuid],
            [
                'internal_code' => $internalCode,
                'name' => $data['name'] ?? ($existing ? $existing->name : 'Sans nom'),
                'format' => array_key_exists('format', $data) ? $data['format'] : ($existing ? $existing->format : null),
                'containment' => array_key_exists('containment', $data) ? $data['containment'] : ($existing ? $existing->containment : null),
                'created_at' => !empty($data['created_at']) ? Carbon::parse($data['created_at']) : ($existing ? $existing->created_at : Carbon::now()),
                'updated_at' => $clientTime,
                'deleted_at' => !empty($data['deleted_at']) ? Carbon::parse($data['deleted_at']) : null,
                'price' => isset($data['price']) ? (float) $data['price'] : ($existing ? $existing->price : 0),
                'quantity' => isset($data['quantity']) ? (int) $data['quantity'] : ($existing ? $existing->quantity : 0),
                'image_base64' => $imageBase64,
            ]
        );

        ActivityLog::create([
            'user_id' => $request->user()?->id,
            'action' => $existing ? 'product.updated' : 'product.created',
            'entity_type' => 'product',
            'entity_id' => $uuid,
            'metadata' => ['internal_code' => $internalCode, 'name' => $data['name'] ?? ''],
            'ip_address' => $request->ip(),
        ]);

        return ['uuid' => $uuid, 'status' => 'synced'];
    }

    /**
     * Traitement d'une mutation utilisateur.
     */
    private function applyUserMutation(string $action, array $data, Carbon $clientTime, Request $request): array
    {
        $email = $data['email'] ?? null;
        if (!$email) {
            return ['status' => 'error', 'error' => 'Email utilisateur manquant.'];
        }

        $authUser = $request->user();
        $isSuperAdmin = $authUser && $authUser->role === User::ROLE_SUPER_ADMIN;

        // Protection contre l'usurpation et l'élévation de privilèges
        if (!$isSuperAdmin) {
            if (in_array($action, ['create', 'delete', 'toggle_active'], true)) {
                return [
                    'uuid' => $email,
                    'status' => 'error',
                    'error' => 'Action non autorisée. Seul le Super Administrateur peut créer, supprimer ou modifier le statut des comptes.',
                ];
            }

            if ($authUser && $authUser->email !== $email) {
                return [
                    'uuid' => $email,
                    'status' => 'error',
                    'error' => 'Action non autorisée sur un autre compte utilisateur.',
                ];
            }

            if (isset($data['role']) && $data['role'] !== $authUser->role) {
                return [
                    'uuid' => $email,
                    'status' => 'error',
                    'error' => 'Élévation de privilèges interdite : un utilisateur standard ne peut pas modifier son rôle.',
                ];
            }

            if (isset($data['is_active'])) {
                return [
                    'uuid' => $email,
                    'status' => 'error',
                    'error' => 'Un utilisateur standard ne peut pas modifier son statut d\'activation.',
                ];
            }
        }

        $user = User::where('email', $email)->first();

        if ($action === 'delete') {
            if ($user && $user->role !== User::ROLE_SUPER_ADMIN) {
                $user->tokens()->delete();
                $user->delete();
                ActivityLog::create([
                    'user_id' => $request->user()?->id,
                    'action' => 'user.deleted',
                    'entity_type' => 'user',
                    'entity_id' => (string) $user->id,
                    'metadata' => ['email' => $email],
                    'ip_address' => $request->ip(),
                ]);
            }
            return ['uuid' => $email, 'status' => 'synced'];
        }

        if ($action === 'toggle_active') {
            if ($user && $user->role !== User::ROLE_SUPER_ADMIN) {
                $isActive = (bool) ($data['is_active'] ?? !$user->is_active);
                $user->is_active = $isActive;
                $user->disabled_at = $isActive ? null : Carbon::now();
                $user->save();
                ActivityLog::create([
                    'user_id' => $request->user()?->id,
                    'action' => $isActive ? 'user.activated' : 'user.disabled',
                    'entity_type' => 'user',
                    'entity_id' => (string) $user->id,
                    'metadata' => ['email' => $email, 'is_active' => $isActive],
                    'ip_address' => $request->ip(),
                ]);
            }
            return ['uuid' => $email, 'status' => 'synced'];
        }

        // create ou update
        $creatorName = $request->user()?->name ?? 'super_admin';

        if ($user) {
            $updateData = [];
            if (isset($data['name'])) {
                $updateData['name'] = $data['name'];
            }
            // Ne pas écraser le rôle existant si non fourni, et interdire la dégradation du super_admin
            if (isset($data['role']) && $user->role !== User::ROLE_SUPER_ADMIN) {
                $updateData['role'] = $data['role'];
            }
            if (isset($data['is_active']) && $user->role !== User::ROLE_SUPER_ADMIN) {
                $updateData['is_active'] = (bool) $data['is_active'];
                if (!$updateData['is_active'] && !$user->disabled_at) {
                    $updateData['disabled_at'] = Carbon::now();
                } elseif ($updateData['is_active']) {
                    $updateData['disabled_at'] = null;
                }
            }
            if (!empty($data['password'])) {
                $updateData['password'] = Hash::make($data['password']);
            }
            if (!empty($updateData)) {
                $user->update($updateData);
            }
            ActivityLog::create([
                'user_id' => $request->user()?->id,
                'action' => 'user.updated',
                'entity_type' => 'user',
                'entity_id' => (string) $user->id,
                'metadata' => ['email' => $email],
                'ip_address' => $request->ip(),
            ]);
        } else {
            $rawPassword = !empty($data['password']) ? $data['password'] : '0000';
            $role = $data['role'] ?? 'manager';
            $user = User::create([
                'name' => $data['name'] ?? 'Utilisateur',
                'email' => $email,
                'password' => Hash::make($rawPassword),
                'role' => $role,
                'is_active' => $data['is_active'] ?? true,
                'created_by' => $role === User::ROLE_SUPER_ADMIN ? null : ($data['created_by'] ?? $creatorName),
            ]);
            ActivityLog::create([
                'user_id' => $request->user()?->id,
                'action' => 'user.created',
                'entity_type' => 'user',
                'entity_id' => (string) $user->id,
                'metadata' => ['email' => $email, 'role' => $role],
                'ip_address' => $request->ip(),
            ]);
        }

        return ['uuid' => $email, 'status' => 'synced'];
    }

    /**
     * Traitement de l'ancien format {'changes': [...]}.
     */
    private function processLegacyChanges(Request $request)
    {
        $validated = $request->validate([
            'changes' => 'required|array',
            'changes.*.uuid' => 'required|uuid',
            'changes.*.internal_code' => 'required|string|max:32',
            'changes.*.name' => 'required|string|max:255',
            'changes.*.format' => 'nullable|string|max:64',
            'changes.*.containment' => 'nullable|string|max:64',
            'changes.*.created_at' => 'nullable|date',
            'changes.*.updated_at' => 'required|date',
            'changes.*.deleted_at' => 'nullable|date',
            'changes.*.price' => 'required|numeric|min:0|max:9999999999.99',
            'changes.*.quantity' => 'required|integer|min:0|max:4294967295',
            'changes.*.image_base64' => 'nullable|string',
        ]);

        $results = [];

        DB::transaction(function () use ($validated, $request, &$results) {
            foreach ($validated['changes'] as $change) {
                $clientUpdatedAt = Carbon::parse($change['updated_at']);
                $action = !empty($change['deleted_at']) ? 'delete' : 'update';
                $results[] = $this->applyProductMutation($action, $change, $clientUpdatedAt, $request);
            }
        });

        $hasErrors = collect($results)->contains(fn($r) => in_array($r['status'], ['error', 'conflict'], true));

        return response()->json([
            'status' => $hasErrors ? 'partial' : 'success',
            'server_time' => Carbon::now()->toIso8601String(),
            'results' => $results,
        ], $hasErrors ? 207 : 200);
    }

    /**
     * Récupération delta incrémentale (produits, utilisateurs et tombstones depuis 'since').
     */
    public function pull(Request $request)
    {
        $request->validate([
            'since' => ['nullable', 'date'],
            'include_deleted' => ['sometimes', 'boolean'],
        ]);

        $since = $request->filled('since') ? Carbon::parse($request->input('since')) : null;
        $includeDeleted = $request->boolean('include_deleted', true);

        // 1. Produits modifiés ou créés
        $productsQuery = $includeDeleted ? Product::withTrashed() : Product::query();
        if ($since) {
            $productsQuery->where(function ($q) use ($since) {
                $q->where('updated_at', '>', $since)
                  ->orWhere('deleted_at', '>', $since);
            });
        }
        $products = $productsQuery->orderBy('updated_at')->get();

        // 2. Tombstones (produits supprimés logiquement + définitivement)
        $softDeletedProductUuids = Product::onlyTrashed()
            ->when($since, fn($q) => $q->where('deleted_at', '>', $since))
            ->pluck('uuid')
            ->values();

        $forceDeletedProductUuids = ActivityLog::where('action', 'product.force_deleted')
            ->when($since, fn($q) => $q->where('created_at', '>', $since))
            ->pluck('entity_id')
            ->values();

        $allProductTombstones = $softDeletedProductUuids->concat($forceDeletedProductUuids)->unique()->values();

        // Tombstones utilisateurs (utilisateurs supprimés)
        $deletedUsers = ActivityLog::where('action', 'user.deleted')
            ->when($since, fn($q) => $q->where('created_at', '>', $since))
            ->get()
            ->map(fn($log) => $log->metadata['email'] ?? $log->entity_id)
            ->filter()
            ->unique()
            ->values();

        // 3. Utilisateurs modifiés ou créés (si utilisateur authentifié)
        $users = collect();
        if ($request->user()) {
            $usersQuery = User::query()
                ->select('id', 'name', 'email', 'role', 'is_active', 'disabled_at', 'created_by', 'created_at', 'updated_at')
                ->when($since, fn($q) => $q->where('updated_at', '>', $since))
                ->orderBy('updated_at');
            $users = $usersQuery->get();
        }

        return response()->json([
            'status' => 'success',
            'server_time' => Carbon::now()->toIso8601String(),
            'products' => $products,
            'users' => $users,
            'tombstones' => [
                'products' => $allProductTombstones,
                'force_deleted_products' => $forceDeletedProductUuids,
                'users' => $deletedUsers,
            ],
        ]);
    }
}
