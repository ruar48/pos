<?php

$src = __DIR__ . '/../assets/images/munoz-macam-logo.png';
$out = __DIR__ . '/../android/app/src/main/res/drawable/splash_logo.png';
$canvas = 512;
$scale = 0.42;

$img = imagecreatefrompng($src);
if (!$img) {
    fwrite(STDERR, "Failed to load source image\n");
    exit(1);
}

$w = imagesx($img);
$h = imagesy($img);
$max = (int) ($canvas * $scale);
$ratio = min($max / $w, $max / $h);
$nw = (int) ($w * $ratio);
$nh = (int) ($h * $ratio);

$bg = imagecreatetruecolor($canvas, $canvas);
$bgColor = imagecolorallocate($bg, 234, 247, 239);
imagefill($bg, 0, 0, $bgColor);
imagealphablending($bg, true);

$dstX = (int) (($canvas - $nw) / 2);
$dstY = (int) (($canvas - $nh) / 2);
imagecopyresampled($bg, $img, $dstX, $dstY, 0, 0, $nw, $nh, $w, $h);
imagepng($bg, $out);

imagedestroy($img);
imagedestroy($bg);

echo "saved splash_logo.png logo={$nw}x{$nh} canvas={$canvas}\n";
