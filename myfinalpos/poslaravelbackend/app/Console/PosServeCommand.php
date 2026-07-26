<?php

namespace App\Console;

use App\Support\PosApiLogger;
use Illuminate\Foundation\Console\ServeCommand;

use function Illuminate\Support\php_binary;

class PosServeCommand extends ServeCommand
{
    public function handle()
    {
        PosApiLogger::bootstrap('info', [
            'message' => 'artisan.serve.start',
            'php' => PosApiLogger::phpEnvironmentContext(),
            'server_command' => $this->serverCommand(),
        ]);

        return parent::handle();
    }

    /**
     * @return array<int, string>
     */
    protected function serverCommand()
    {
        $uploadTmp = storage_path('app/tmp');
        $publicUploads = public_path('uploads/products');

        foreach ([$uploadTmp, $publicUploads] as $directory) {
            if (! is_dir($directory)) {
                @mkdir($directory, 0777, true);
            }
        }

        $server = file_exists(base_path('server.php'))
            ? base_path('server.php')
            : base_path('vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php');

        return [
            php_binary(),
            '-d', 'display_errors=0',
            '-d', 'log_errors=1',
            '-d', 'post_max_size=32M',
            '-d', 'upload_max_filesize=32M',
            '-d', 'upload_tmp_dir='.$uploadTmp,
            '-S',
            $this->host().':'.$this->port(),
            $server,
        ];
    }
}
