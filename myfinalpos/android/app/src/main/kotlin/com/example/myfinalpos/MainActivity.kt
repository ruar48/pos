package com.example.myfinalpos

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        lockLandscape()
        super.onCreate(savedInstanceState)
    }

    override fun onStart() {
        lockLandscape()
        super.onStart()
    }

    override fun onResume() {
        lockLandscape()
        super.onResume()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        lockLandscape()
        super.onConfigurationChanged(newConfig)
    }

    private fun lockLandscape() {
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
    }
}
