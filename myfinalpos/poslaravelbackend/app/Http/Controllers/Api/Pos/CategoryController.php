<?php

namespace App\Http\Controllers\Api\Pos;

use App\Http\Controllers\Controller;
use App\Support\PosApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class CategoryController extends Controller
{
    use PosApiResponse;

    public function handle(Request $request): JsonResponse
    {
        if (! Schema::hasTable('categories')) {
            return $this->posError(
                'POS database is not ready. Import backend/sql/agriculture_system.sql first.',
                503,
            );
        }

        return match ($request->method()) {
            'GET' => $this->index(),
            'POST' => $this->store($request),
            'PUT' => $this->update($request),
            default => $this->posError('Method not allowed', 405),
        };
    }

    private function index(): JsonResponse
    {
        $rows = DB::select(
            'SELECT id, name, icon, description
             FROM categories
             ORDER BY name ASC',
        );

        return $this->posSuccess([
            'data' => array_map(fn ($row) => (array) $row, $rows),
        ]);
    }

    private function store(Request $request): JsonResponse
    {
        $name = trim((string) $request->input('name', ''));
        $description = trim((string) $request->input('description', ''));
        $icon = trim((string) $request->input('icon', ''));

        if ($name === '') {
            return $this->posError('Category name is required', 400);
        }

        $existing = DB::selectOne(
            'SELECT id, name, icon, description
             FROM categories
             WHERE LOWER(name) = LOWER(?)
             LIMIT 1',
            [$name],
        );

        if ($existing) {
            return $this->posSuccess([
                'message' => 'Category already exists',
                'data' => (array) $existing,
            ]);
        }

        if ($icon === '') {
            $icon = $this->suggestIcon($name);
        }

        $categoryId = (int) DB::table('categories')->insertGetId([
            'name' => $name,
            'icon' => $icon,
            'description' => $description === '' ? null : $description,
        ]);

        $category = DB::selectOne(
            'SELECT id, name, icon, description FROM categories WHERE id = ? LIMIT 1',
            [$categoryId],
        );

        return $this->posSuccess([
            'message' => 'Category created successfully',
            'data' => (array) $category,
        ], 201);
    }

    private function update(Request $request): JsonResponse
    {
        $id = (int) $request->input('id', 0);
        $name = trim((string) $request->input('name', ''));
        $description = trim((string) $request->input('description', ''));
        $icon = trim((string) $request->input('icon', ''));

        if ($id <= 0) {
            return $this->posError('Category id is required', 400);
        }

        if ($name === '') {
            return $this->posError('Category name is required', 400);
        }

        $current = DB::selectOne(
            'SELECT id, name, icon, description FROM categories WHERE id = ? LIMIT 1',
            [$id],
        );

        if (! $current) {
            return $this->posError('Category not found', 404);
        }

        $duplicate = DB::selectOne(
            'SELECT id FROM categories WHERE LOWER(name) = LOWER(?) AND id != ? LIMIT 1',
            [$name, $id],
        );

        if ($duplicate) {
            return $this->posError('Another category already uses this name', 409);
        }

        if ($icon === '') {
            $icon = $this->suggestIcon($name);
        }

        DB::table('categories')->where('id', $id)->update([
            'name' => $name,
            'icon' => $icon,
            'description' => $description === '' ? null : $description,
        ]);

        $category = DB::selectOne(
            'SELECT id, name, icon, description FROM categories WHERE id = ? LIMIT 1',
            [$id],
        );

        return $this->posSuccess([
            'message' => 'Category updated successfully',
            'data' => (array) $category,
        ]);
    }

    private function suggestIcon(string $name): string
    {
        $normalized = strtolower(trim($name));

        if ($normalized === '') {
            return 'category';
        }

        if (str_contains($normalized, 'seedling')
            || str_contains($normalized, 'nursery')
            || str_contains($normalized, 'plant')) {
            return 'local_florist';
        }
        if (str_contains($normalized, 'seed')) {
            return 'eco';
        }
        if (str_contains($normalized, 'fertil') || str_contains($normalized, 'compost')) {
            return 'compost';
        }
        if (str_contains($normalized, 'pestic')
            || str_contains($normalized, 'herb')
            || str_contains($normalized, 'fungic')
            || str_contains($normalized, 'insect')) {
            return 'shield';
        }
        if (str_contains($normalized, 'feed')
            || str_contains($normalized, 'animal')
            || str_contains($normalized, 'livestock')
            || str_contains($normalized, 'poultry')
            || str_contains($normalized, 'broiler')
            || str_contains($normalized, 'layer')) {
            return 'pets';
        }
        if (str_contains($normalized, 'tool')
            || str_contains($normalized, 'equipment')
            || str_contains($normalized, 'machinery')
            || str_contains($normalized, 'tractor')) {
            return 'build';
        }
        if (str_contains($normalized, 'irrig')
            || str_contains($normalized, 'water')
            || str_contains($normalized, 'drip')
            || str_contains($normalized, 'sprinkler')) {
            return 'water_drop';
        }
        if (str_contains($normalized, 'harvest')
            || str_contains($normalized, 'crate')
            || str_contains($normalized, 'sack')
            || str_contains($normalized, 'supply')
            || str_contains($normalized, 'supplies')) {
            return 'inventory_2';
        }
        if (str_contains($normalized, 'vet') || str_contains($normalized, 'medic')) {
            return 'medical_services';
        }
        if (str_contains($normalized, 'grain')
            || str_contains($normalized, 'rice')
            || str_contains($normalized, 'corn')) {
            return 'grain';
        }
        if (str_contains($normalized, 'organic')) {
            return 'park';
        }

        return 'category';
    }
}
