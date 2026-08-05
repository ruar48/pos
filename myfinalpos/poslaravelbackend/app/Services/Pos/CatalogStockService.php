<?php



namespace App\Services\Pos;



use App\Support\CatalogStockRevision;

use Illuminate\Support\Facades\DB;

use Illuminate\Support\Facades\Schema;



class CatalogStockService

{

    /**

     * @return array<string, mixed>

     */

    public function syncPayload(?string $sinceRevision = null): array

    {

        $revision = CatalogStockRevision::current();



        if (

            $sinceRevision !== null

            && $sinceRevision !== ''

            && hash_equals($revision, $sinceRevision)

        ) {

            return [

                'unchanged' => true,

                'revision' => $revision,

            ];

        }



        return [

            'unchanged' => false,

            'revision' => $revision,

            'products' => $this->productStockMap(),

        ];

    }



    /**

     * @return array<string, float>

     */

    private function productStockMap(): array

    {

        if (! Schema::hasTable('products')) {

            return [];

        }



        $rows = DB::select(

            'SELECT id, stock FROM products WHERE status = "active"',

        );



        $map = [];

        foreach ($rows as $row) {

            $map[(string) $row->id] = (float) ($row->stock ?? 0);

        }



        return $map;

    }

}

