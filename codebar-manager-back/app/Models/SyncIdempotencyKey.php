<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SyncIdempotencyKey extends Model
{
    /**
     * The table associated with the model.
     *
     * @var string
     */
    protected $table = 'sync_idempotency_keys';

    /**
     * Indicates if the model should be timestamped.
     *
     * @var bool
     */
    public $timestamps = false;

    /**
     * Indicates if the IDs are auto-incrementing.
     *
     * @var bool
     */
    public $incrementing = false;

    /**
     * The primary key associated with the table.
     *
     * @var string
     */
    protected $primaryKey = 'key';

    /**
     * The data type of the auto-incrementing ID.
     *
     * @var string
     */
    protected $keyType = 'string';

    /**
     * The attributes that are mass assignable.
     *
     * @var array<int, string>
     */
    protected $fillable = [
        'key',
        'entity_type',
        'entity_id',
        'status',
        'response_data',
        'created_at',
    ];

    /**
     * The attributes that should be cast.
     *
     * @var array<string, string>
     */
    protected $casts = [
        'response_data' => 'array',
        'created_at' => 'datetime',
    ];
}
