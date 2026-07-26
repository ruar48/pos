<?php

namespace App\Support;

class Geofence
{
    public static function distanceKm(
        float $lat1,
        float $lng1,
        float $lat2,
        float $lng2,
    ): float {
        $earthRadiusKm = 6371.0;
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);

        $a = sin($dLat / 2) ** 2
            + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        $c = 2 * atan2(sqrt($a), sqrt(1 - $a));

        return round($earthRadiusKm * $c, 3);
    }

    /**
     * @return array{within: bool, distance_km: float|null, skipped: bool}
     */
    public static function check(
        ?float $branchLat,
        ?float $branchLng,
        float $radiusKm,
        float $userLat,
        float $userLng,
    ): array {
        if ($branchLat === null || $branchLng === null) {
            return ['within' => true, 'distance_km' => null, 'skipped' => true];
        }

        $distanceKm = self::distanceKm($branchLat, $branchLng, $userLat, $userLng);

        return [
            'within' => $distanceKm <= $radiusKm,
            'distance_km' => $distanceKm,
            'skipped' => false,
        ];
    }
}
