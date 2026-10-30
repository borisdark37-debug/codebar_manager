<?php

use App\Http\Controllers\Api\ActivityLogController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\ProductController;
use App\Http\Controllers\Api\SyncController;
use App\Http\Controllers\Api\UserController;
use Illuminate\Support\Facades\Route;

$healthHandler = function () {
    $dbOk = true;
    try {
        \Illuminate\Support\Facades\DB::connection()->getPdo();
    } catch (\Throwable $e) {
        $dbOk = false;
    }

    return response()->json([
        'status' => 'ok',
        'database' => $dbOk ? 'connected' : 'disconnected',
        'timestamp' => \Carbon\Carbon::now()->toIso8601String(),
    ]);
};

// Health check
Route::get('/health', $healthHandler);

// Authentification publique & migration Super Admin
Route::post('/login', [AuthController::class, 'login']);
Route::post('/auth/login', [AuthController::class, 'login']);
Route::post('/migrate-super-admin', [AuthController::class, 'migrateSuperAdmin']);

// Routes protégées par token Sanctum
Route::middleware('auth:sanctum')->group(function () {
    // Endpoints de synchronisation
    Route::post('/sync', [SyncController::class, 'push']);
    Route::post('/sync/push', [SyncController::class, 'push']);
    Route::get('/sync/pull', [SyncController::class, 'pull']);

    // Produits
    Route::get('/products', [ProductController::class, 'index']);

    // Administration Super Admin
    Route::middleware('role:super_admin')->group(function () {
        Route::get('/users', [UserController::class, 'index']);
        Route::post('/users', [UserController::class, 'store']);
        Route::post('/users/sync', [UserController::class, 'sync']);
        Route::patch('/users/{user}/toggle-active', [UserController::class, 'toggleActive']);
        Route::delete('/users/{user}', [UserController::class, 'destroy']);
        Route::post('/users/reset-password', [UserController::class, 'resetPassword']);
        Route::get('/activity-logs', [ActivityLogController::class, 'index']);
    });
});

// Préfixe v1 pour compatibilité REST API v1
Route::prefix('v1')->group(function () use ($healthHandler) {
    Route::get('/health', $healthHandler);
    Route::post('/login', [AuthController::class, 'login']);
    Route::post('/auth/login', [AuthController::class, 'login']);
    Route::post('/migrate-super-admin', [AuthController::class, 'migrateSuperAdmin']);

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('/sync', [SyncController::class, 'push']);
        Route::post('/sync/push', [SyncController::class, 'push']);
        Route::get('/sync/pull', [SyncController::class, 'pull']);
        Route::get('/products', [ProductController::class, 'index']);

        Route::middleware('role:super_admin')->group(function () {
            Route::get('/users', [UserController::class, 'index']);
            Route::post('/users', [UserController::class, 'store']);
            Route::post('/users/sync', [UserController::class, 'sync']);
            Route::patch('/users/{user}/toggle-active', [UserController::class, 'toggleActive']);
            Route::delete('/users/{user}', [UserController::class, 'destroy']);
            Route::post('/users/reset-password', [UserController::class, 'resetPassword']);
            Route::get('/activity-logs', [ActivityLogController::class, 'index']);
        });
    });
});
