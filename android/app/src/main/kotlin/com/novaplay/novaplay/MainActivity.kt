package com.novaplay.novaplay

import android.app.PictureInPictureParams
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.novaplay/player"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        enterPictureInPictureMode(
                            PictureInPictureParams.Builder()
                                .setAspectRatio(Rational(16, 9))
                                .build()
                        )
                        result.success(true)
                    } else {
                        result.error("UNSUPPORTED", "Picture-in-Picture requires Android 8.0 or newer", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
