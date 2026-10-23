<?php

return [

    /*
    | Tablet API sign-in tokens.
    |
    | Newer tablet builds get a token at login and send it on every request;
    | the server then trusts only the token's user (never a user id in the
    | request body). Requests WITHOUT a token are still accepted while this
    | is false, so tablets on the older app keep working during the switch.
    |
    | Once every tablet runs the new app, set POS_REQUIRE_TOKEN=true in .env
    | (and run `php artisan config:clear` if config is cached): token-less
    | requests are then refused, except login, forgot-password, product
    | images and the health check.
    */
    'require_token' => (bool) env('POS_REQUIRE_TOKEN', false),

    // Days a tablet stays signed in without being used.
    'token_idle_days' => (int) env('POS_TOKEN_IDLE_DAYS', 30),

];
