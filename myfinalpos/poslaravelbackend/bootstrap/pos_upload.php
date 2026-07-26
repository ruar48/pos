<?php

$uploadTmp = dirname(__DIR__).'/storage/app/tmp';
if (! is_dir($uploadTmp)) {
    mkdir($uploadTmp, 0755, true);
}

@ini_set('upload_tmp_dir', realpath($uploadTmp) ?: $uploadTmp);
@ini_set('display_errors', '0');
@ini_set('log_errors', '1');
