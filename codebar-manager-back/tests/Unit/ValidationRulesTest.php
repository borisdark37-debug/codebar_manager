<?php

namespace Tests\Unit;

use Illuminate\Support\Facades\Validator;
use Tests\TestCase;

class ValidationRulesTest extends TestCase
{
    public function test_sync_push_payload_validation_rules(): void
    {
        $rules = [
            'mutations' => 'required|array',
            'mutations.*.idempotency_key' => 'required|string|max:128',
            'mutations.*.entity_type' => 'required|string|in:product,user',
            'mutations.*.action' => 'required|string|in:create,update,delete,permanent_delete,toggle_active',
            'mutations.*.data' => 'required|array',
            'mutations.*.client_timestamp' => 'nullable|date',
        ];

        // 1. Valid payload
        $validData = [
            'mutations' => [
                [
                    'idempotency_key' => 'idemp-1',
                    'entity_type' => 'product',
                    'action' => 'create',
                    'data' => ['uuid' => '123', 'internal_code' => 'CAP-1', 'name' => 'Test'],
                ],
            ],
        ];
        $validator = Validator::make($validData, $rules);
        $this->assertFalse($validator->fails());

        // 2. Missing mutations
        $invalidData = ['mutations' => []];
        $validator = Validator::make($invalidData, ['mutations' => 'required|array|min:1']);
        $this->assertTrue($validator->fails());

        // 3. Invalid entity_type
        $invalidEntity = [
            'mutations' => [
                [
                    'idempotency_key' => 'idemp-2',
                    'entity_type' => 'invalid_entity',
                    'action' => 'create',
                    'data' => [],
                ],
            ],
        ];
        $validator = Validator::make($invalidEntity, $rules);
        $this->assertTrue($validator->fails());
        $this->assertArrayHasKey('mutations.0.entity_type', $validator->errors()->toArray());

        // 4. Invalid action
        $invalidAction = [
            'mutations' => [
                [
                    'idempotency_key' => 'idemp-3',
                    'entity_type' => 'user',
                    'action' => 'drop_database',
                    'data' => [],
                ],
            ],
        ];
        $validator = Validator::make($invalidAction, $rules);
        $this->assertTrue($validator->fails());
        $this->assertArrayHasKey('mutations.0.action', $validator->errors()->toArray());
    }

    public function test_auth_login_validation_rules(): void
    {
        $rules = [
            'email' => 'required|email',
            'password' => 'required|string|min:4',
        ];

        // Valid
        $v1 = Validator::make(['email' => 'test@example.com', 'password' => 'pass123'], $rules);
        $this->assertFalse($v1->fails());

        // Missing email
        $v2 = Validator::make(['password' => 'pass123'], $rules);
        $this->assertTrue($v2->fails());
        $this->assertArrayHasKey('email', $v2->errors()->toArray());

        // Invalid email format
        $v3 = Validator::make(['email' => 'not-an-email', 'password' => 'pass123'], $rules);
        $this->assertTrue($v3->fails());

        // Password too short
        $v4 = Validator::make(['email' => 'test@example.com', 'password' => '12'], $rules);
        $this->assertTrue($v4->fails());
    }
}
