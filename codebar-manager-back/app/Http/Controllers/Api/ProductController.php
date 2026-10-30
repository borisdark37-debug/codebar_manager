<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Product;
use Carbon\Carbon;
use Illuminate\Http\Request;

class ProductController extends Controller
{
    public function index(Request $request)
    {
        $request->validate([
            'updated_since' => ['sometimes', 'date'],
            'include_deleted' => ['sometimes', 'boolean'],
        ]);

        // Inclure les suppressions logiques afin que les clients puissent
        // retirer localement les produits supprimés sur le serveur.
        $query = $request->boolean('include_deleted')
            ? Product::withTrashed()
            : Product::query();

        // Filtre optionnel : produits modifiés depuis une date donnée
        if ($request->has('updated_since')) {
            $since = Carbon::parse($request->updated_since);
            $query->where('updated_at', '>', $since);
        }

        $products = $query->orderBy('internal_code')->get();

        return response()->json(['products' => $products]);
    }
}
