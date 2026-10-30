<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ActivityLog;
use Illuminate\Http\Request;

class ActivityLogController extends Controller
{
    public function index(Request $request)
    {
        $logs = ActivityLog::query()
            ->with('user:id,name,email')
            ->latest()
            ->paginate(min((int) $request->integer('per_page', 30), 100));

        return response()->json($logs);
    }
}
