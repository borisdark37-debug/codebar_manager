<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Product extends Model
{
    use HasUuids, SoftDeletes;

    /**
     * La clé primaire n'est pas auto-incrémentée.
     */
    public $incrementing = false;

    /**
     * Le type de la clé primaire est une chaîne (UUID).
     */
    protected $keyType = 'string';

    /**
     * Le nom de la clé primaire est 'uuid', pas 'id'.
     */
    protected $primaryKey = 'uuid';

    /**
     * Le trait HasUuids utilise la colonne 'uuid' par défaut.
     * On lui indique explicitement.
     */
    public function uniqueIds(): array
    {
        return ['uuid'];
    }

    protected $fillable = [
        'uuid',
        'internal_code',
        'name',
        'format',
        'containment',
        'created_at',
        'updated_at',
        'deleted_at',
        'price',
        'quantity',
        'image_base64',
    ];

    protected $casts = [
        'created_at' => 'datetime',
        'updated_at' => 'datetime',
        'deleted_at' => 'datetime',
        'price' => 'decimal:2',
        'quantity' => 'integer',
    ];
}
