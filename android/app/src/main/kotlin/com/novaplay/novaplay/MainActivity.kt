package com.novaplay.novaplay

import android.Manifest
import android.app.PictureInPictureParams
import android.content.ContentUris
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import android.util.Rational
import android.util.Size
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val playerChannelName = "com.novaplay/player"
    private val mediaChannelName = "com.novaplay/media"
    private val permissionRequestCode = 4012
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playerChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> enterPip(result)
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionState" -> result.success(permissionState())
                "requestMediaPermission" -> requestMediaPermission(result)
                "openAppSettings" -> openAppSettings(result)
                "queryVideos" -> queryVideos(result)
                "cacheThumbnail" -> cacheThumbnail(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPip(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            enterPictureInPictureMode(
                PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
            )
            result.success(true)
        } else {
            result.error("UNSUPPORTED", "Picture-in-Picture requires Android 8.0 or newer", null)
        }
    }

    private fun permissionState(): Map<String, Any> {
        val api = Build.VERSION.SDK_INT
        val full = if (api >= Build.VERSION_CODES.TIRAMISU) {
            checkSelfPermission(Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
        val partial = api >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
            checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED &&
            !full
        return mapOf(
            "api" to api,
            "granted" to (full || partial),
            "full" to full,
            "partial" to partial,
            "needsSettings" to (!full && !partial && hasPermanentlyDeniedPermission())
        )
    }

    private fun requestMediaPermission(result: MethodChannel.Result) {
        val state = permissionState()
        if (state["granted"] == true) {
            result.success(state)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "A permission request is already in progress", null)
            return
        }
        pendingPermissionResult = result
        val permissions = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE -> arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO,
                Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED
            )
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> arrayOf(
                Manifest.permission.READ_MEDIA_VIDEO
            )
            else -> arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
        }
        requestPermissions(permissions, permissionRequestCode)
    }

    private fun hasPermanentlyDeniedPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_VIDEO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return !shouldShowRequestPermissionRationale(permission) &&
            checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequestCode) {
            pendingPermissionResult?.success(permissionState())
            pendingPermissionResult = null
        }
    }

    private fun openAppSettings(result: MethodChannel.Result) {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
        result.success(true)
    }

    private fun queryVideos(result: MethodChannel.Result) {
        executor.execute {
            val rows = ArrayList<Map<String, Any?>>()
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }
            val projection = mutableListOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.SIZE,
                MediaStore.Video.Media.DURATION,
                MediaStore.Video.Media.WIDTH,
                MediaStore.Video.Media.HEIGHT,
                MediaStore.Video.Media.DATE_MODIFIED,
                MediaStore.Video.Media.MIME_TYPE,
                MediaStore.Video.Media.DATA
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                projection.add(MediaStore.Video.Media.RELATIVE_PATH)
            }
            contentResolver.query(
                collection,
                projection.toTypedArray(),
                null,
                null,
                "${MediaStore.Video.Media.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val idColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val nameColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val sizeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                val durationColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DURATION)
                val widthColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.WIDTH)
                val heightColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.HEIGHT)
                val modifiedColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)
                val mimeColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)
                val dataColumn = cursor.getColumnIndexOrThrow(MediaStore.Video.Media.DATA)
                val relativeColumn = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    cursor.getColumnIndex(MediaStore.Video.Media.RELATIVE_PATH)
                } else {
                    -1
                }
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(idColumn)
                    val uri = ContentUris.withAppendedId(collection, id)
                    val dataPath = cursor.getString(dataColumn) ?: ""
                    val relativePath = if (relativeColumn >= 0) cursor.getString(relativeColumn) ?: "" else ""
                    rows.add(
                        mapOf(
                            "id" to uri.toString(),
                            "uri" to uri.toString(),
                            "path" to if (dataPath.isNotEmpty()) dataPath else uri.toString(),
                            "name" to (cursor.getString(nameColumn) ?: "Untitled video"),
                            "sizeBytes" to cursor.getLong(sizeColumn),
                            "durationMs" to cursor.getLong(durationColumn),
                            "width" to cursor.getInt(widthColumn),
                            "height" to cursor.getInt(heightColumn),
                            "modifiedAtMs" to cursor.getLong(modifiedColumn) * 1000L,
                            "mimeType" to (cursor.getString(mimeColumn) ?: "video/*"),
                            "relativePath" to relativePath
                        )
                    )
                }
            }
            runOnUiThread { result.success(rows) }
        }
    }

    private fun cacheThumbnail(call: MethodCall, result: MethodChannel.Result) {
        val uriValue = call.argument<String>("uri")
        val key = call.argument<String>("key")
        if (uriValue.isNullOrEmpty() || key.isNullOrEmpty()) {
            result.error("INVALID_ARGUMENT", "uri and key are required", null)
            return
        }
        executor.execute {
            try {
                val directory = File(cacheDir, "novaplay-thumbnails")
                directory.mkdirs()
                val output = File(directory, "$key.jpg")
                if (!output.exists()) {
                    val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        contentResolver.loadThumbnail(Uri.parse(uriValue), Size(640, 360), null)
                    } else {
                        val id = ContentUris.parseId(Uri.parse(uriValue))
                        MediaStore.Video.Thumbnails.getThumbnail(contentResolver, id, MediaStore.Video.Thumbnails.MINI_KIND, null)
                    }
                    FileOutputStream(output).use { stream -> bitmap.compress(Bitmap.CompressFormat.JPEG, 82, stream) }
                }
                runOnUiThread { result.success(output.absolutePath) }
            } catch (error: Exception) {
                runOnUiThread { result.error("THUMBNAIL_FAILED", error.message, null) }
            }
        }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
