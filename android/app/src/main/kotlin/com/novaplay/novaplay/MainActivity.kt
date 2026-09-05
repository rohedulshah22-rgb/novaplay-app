package com.novaplay.novaplay

import android.Manifest
import android.app.PictureInPictureParams
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.graphics.drawable.Icon
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.app.RecoverableSecurityException
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.BatteryManager
import android.provider.MediaStore
import android.provider.Settings
import android.media.MediaScannerConnection
import android.util.Rational
import android.util.Size
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.roundToInt
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    companion object {
        private const val PIP_ACTION = "com.novaplay.PIP_ACTION"
        private const val ACTION_PLAY_PAUSE = "play_pause"
        private const val ACTION_CLOSE = "close"
    }

    private val playerChannelName = "com.novaplay/player"
    private val mediaChannelName = "com.novaplay/media"
    private val permissionRequestCode = 4012
    private val deleteRequestCode = 4013
    private val executor = Executors.newSingleThreadExecutor()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingDeleteResult: MethodChannel.Result? = null
    private var playerChannel: MethodChannel? = null
    private var notificationTapPending = false
    private var pipEnabled = false
    private var pipPlaying = true
    private var pipWidth = 16
    private var pipHeight = 9
    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.getStringExtra("action")) {
                ACTION_CLOSE -> finishAndRemoveTask()
                ACTION_PLAY_PAUSE -> playerChannel?.invokeMethod("pipAction", ACTION_PLAY_PAUSE)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (playerChannel == null) {
            notificationTapPending = true
        } else {
            playerChannel?.invokeMethod("notificationTapped", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, playerChannelName)
        playerChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPip" -> enterPip(
                    result,
                    call.argument<Int>("width"),
                    call.argument<Int>("height"),
                )
                "setPipState" -> setPipState(call, result)
                else -> result.notImplemented()
            }
        }
        if (notificationTapPending) {
            notificationTapPending = false
            playerChannel?.invokeMethod("notificationTapped", null)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPermissionState" -> result.success(permissionState())
                "getDeviceStatus" -> result.success(deviceStatus())
                "requestMediaPermission" -> requestMediaPermission(result)
                "openAppSettings" -> openAppSettings(result)
                "queryVideos" -> queryVideos(result)
                "cacheThumbnail" -> cacheThumbnail(call, result)
                "publishAudio" -> publishAudio(call, result)
                "moveToVault" -> moveToVault(call, result)
                "restoreFromVault" -> restoreFromVault(call, result)
                "deleteMedia" -> deleteMedia(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun enterPip(
        result: MethodChannel.Result? = null,
        width: Int? = null,
        height: Int? = null,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result?.error("UNSUPPORTED", "Picture-in-Picture requires Android 8.0 or newer", null)
            return
        }
        if (width != null && height != null && width > 0 && height > 0) {
            pipWidth = width
            pipHeight = height
        }
        enterPictureInPictureMode(buildPipParams())
        result?.success(true)
    }

    private fun setPipState(call: MethodCall, result: MethodChannel.Result) {
        pipEnabled = call.argument<Boolean>("enabled") ?: false
        pipPlaying = call.argument<Boolean>("playing") ?: pipPlaying
        val width = call.argument<Int>("width")
        val height = call.argument<Int>("height")
        if (width != null && height != null && width > 0 && height > 0) {
            pipWidth = width
            pipHeight = height
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isInPictureInPictureMode) {
            setPictureInPictureParams(buildPipParams())
        }
        result.success(true)
    }

    private fun buildPipParams(): PictureInPictureParams {
        val aspect = (pipWidth.toDouble() / pipHeight.toDouble()).coerceIn(
            1.0 / 2.39,
            2.39,
        )
        val denominator = 1000
        val ratio = Rational((aspect * denominator).roundToInt(), denominator)
        return PictureInPictureParams.Builder()
            .setAspectRatio(ratio)
            .setActions(buildPipActions())
            .build()
    }

    private fun buildPipActions(): List<android.app.RemoteAction> {
        val playPauseIntent = PendingIntent.getBroadcast(
            this,
            9101,
            Intent(PIP_ACTION).setPackage(packageName).putExtra("action", ACTION_PLAY_PAUSE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val closeIntent = PendingIntent.getBroadcast(
            this,
            9102,
            Intent(PIP_ACTION).setPackage(packageName).putExtra("action", ACTION_CLOSE),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val playPauseIcon = if (pipPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        return listOf(
            android.app.RemoteAction(
                Icon.createWithResource(this, playPauseIcon),
                if (pipPlaying) "Pause" else "Play",
                if (pipPlaying) "Pause NovaPlay" else "Play NovaPlay",
                playPauseIntent,
            ),
            android.app.RemoteAction(
                Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
                "Close",
                "Close NovaPlay",
                closeIntent,
            ),
        )
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipEnabled && pipPlaying && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !isInPictureInPictureMode) {
            enterPip()
        }
    }

    private fun deviceStatus(): Map<String, Any> {
        val manager = getSystemService(BATTERY_SERVICE) as? BatteryManager
        val battery = manager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: -1
        return mapOf("batteryPercent" to battery.coerceIn(0, 100))
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == deleteRequestCode) {
            val pending = pendingDeleteResult
            pendingDeleteResult = null
            if (resultCode == RESULT_OK) {
                pending?.success(true)
            } else {
                pending?.error("DELETE_CANCELLED", "Delete permission was not granted", null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
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

    private fun deleteMedia(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val uriValue = call.argument<String>("uri")
        if (path.isNullOrBlank() && uriValue.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "path or uri is required", null)
            return
        }
        executor.execute {
            val targetUris = linkedSetOf<Uri>()
            try {
                if (!uriValue.isNullOrBlank() && uriValue.startsWith("content://")) {
                    targetUris += Uri.parse(uriValue)
                }
                if (!path.isNullOrBlank()) {
                    if (path.startsWith("content://")) {
                        targetUris += Uri.parse(path)
                    } else {
                        targetUris += resolveMediaUris(path)
                    }
                }

                var deleted = 0
                for (uri in targetUris) {
                    deleted += contentResolver.delete(uri, null, null)
                }
                if (deleted == 0 && !path.isNullOrBlank() && !path.startsWith("content://")) {
                    val file = File(path)
                    if (file.exists() && file.delete()) deleted = 1
                }
                if (deleted == 0) {
                    runOnUiThread {
                        result.error("NOT_FOUND", "Media file was not found", null)
                    }
                } else {
                    if (!path.isNullOrBlank() && !path.startsWith("content://")) {
                        MediaScannerConnection.scanFile(this, arrayOf(path), null, null)
                    }
                    runOnUiThread { result.success(true) }
                }
            } catch (security: RecoverableSecurityException) {
                runOnUiThread {
                    requestDeleteAuthorization(
                        targetUris = if (!uriValue.isNullOrBlank() && uriValue.startsWith("content://")) {
                            listOf(Uri.parse(uriValue))
                        } else if (!path.isNullOrBlank() && path.startsWith("content://")) {
                            listOf(Uri.parse(path))
                        } else {
                            resolveMediaUris(path.orEmpty())
                        },
                        security = security,
                        result = result,
                    )
                }
            } catch (security: SecurityException) {
                runOnUiThread {
                    result.error(
                        "PERMISSION_REQUIRED",
                        "Android requires permission to delete this media file",
                        security.message,
                    )
                }
            } catch (error: Exception) {
                runOnUiThread {
                    result.error("DELETE_FAILED", error.message ?: "Could not delete media file", null)
                }
            }
        }
    }

    private fun resolveMediaUris(path: String): List<Uri> {
        if (path.isBlank()) return emptyList()
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Files.getContentUri("external")
        }
        val result = mutableListOf<Uri>()
        contentResolver.query(
            collection,
            arrayOf(MediaStore.Files.FileColumns._ID),
            "${MediaStore.Files.FileColumns.DATA} = ?",
            arrayOf(path),
            null,
        )?.use { cursor ->
            val idColumn = cursor.getColumnIndex(MediaStore.Files.FileColumns._ID)
            if (idColumn >= 0) {
                while (cursor.moveToNext()) {
                    result += ContentUris.withAppendedId(collection, cursor.getLong(idColumn))
                }
            }
        }
        return result
    }

    private fun requestDeleteAuthorization(
        targetUris: List<Uri>,
        security: RecoverableSecurityException,
        result: MethodChannel.Result,
    ) {
        if (targetUris.isEmpty()) {
            result.error("PERMISSION_REQUIRED", "Android requires permission to delete this media file", security.message)
            return
        }
        if (pendingDeleteResult != null) {
            result.error("BUSY", "A delete authorization request is already in progress", null)
            return
        }
        pendingDeleteResult = result
        try {
            val sender = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                MediaStore.createDeleteRequest(contentResolver, targetUris).intentSender
            } else {
                security.userAction.actionIntent.intentSender
            }
            startIntentSenderForResult(sender, deleteRequestCode, null, 0, 0, 0)
        } catch (error: Exception) {
            pendingDeleteResult = null
            result.error("PERMISSION_REQUIRED", error.message ?: "Delete permission was not granted", null)
        }
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

    private fun moveToVault(call: MethodCall, result: MethodChannel.Result) {
        val sourcePath = call.argument<String>("sourcePath")
        val contentUri = call.argument<String>("contentUri")
        val displayName = call.argument<String>("displayName") ?: "video.mp4"
        if (sourcePath.isNullOrBlank() && contentUri.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "sourcePath or contentUri is required", null)
            return
        }
        executor.execute {
            try {
                val vaultDirectory = File(filesDir, "private_vault").apply { mkdirs() }
                val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
                val destination = File(vaultDirectory, "${System.currentTimeMillis()}_$safeName")
                val input = if (!sourcePath.isNullOrBlank() && File(sourcePath).exists()) {
                    FileInputStream(File(sourcePath))
                } else {
                    contentResolver.openInputStream(Uri.parse(contentUri))
                        ?: throw IllegalStateException("Unable to read the selected video")
                }
                input.use { stream -> destination.outputStream().use { output -> stream.copyTo(output) } }
                if (!sourcePath.isNullOrBlank() && File(sourcePath).exists()) {
                    File(sourcePath).delete()
                } else if (!contentUri.isNullOrBlank()) {
                    contentResolver.delete(Uri.parse(contentUri), null, null)
                }
                runOnUiThread { result.success(mapOf("vaultPath" to destination.absolutePath)) }
            } catch (error: Exception) {
                runOnUiThread { result.error("VAULT_MOVE_FAILED", error.message, null) }
            }
        }
    }

    private fun restoreFromVault(call: MethodCall, result: MethodChannel.Result) {
        val vaultPath = call.argument<String>("vaultPath")
        val originalPath = call.argument<String>("originalPath")
        val relativePath = call.argument<String>("relativePath")
        val displayName = call.argument<String>("displayName") ?: "restored_video.mp4"
        if (vaultPath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "vaultPath is required", null)
            return
        }
        executor.execute {
            try {
                val source = File(vaultPath)
                if (!source.exists()) throw IllegalStateException("Vault video was not found")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
                        put(MediaStore.Video.Media.MIME_TYPE, "video/*")
                        put(
                            MediaStore.Video.Media.RELATIVE_PATH,
                            relativePath?.takeIf { it.isNotBlank() } ?: (Environment.DIRECTORY_MOVIES + "/NovaPlay/"),
                        )
                        put(MediaStore.Video.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Unable to create public media entry")
                    try {
                        contentResolver.openOutputStream(uri)?.use { output ->
                            source.inputStream().use { input -> input.copyTo(output) }
                        } ?: throw IllegalStateException("Unable to write restored video")
                        contentResolver.update(uri, ContentValues().apply {
                            put(MediaStore.Video.Media.IS_PENDING, 0)
                        }, null, null)
                    } catch (error: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw error
                    }
                    source.delete()
                    runOnUiThread { result.success(uri.toString()) }
                } else {
                    val requested = originalPath?.takeIf { it.startsWith("/") && !it.startsWith(filesDir.absolutePath) }
                    val target = if (requested != null) File(requested) else File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                        "NovaPlay/$displayName",
                    )
                    target.parentFile?.mkdirs()
                    source.inputStream().use { input -> target.outputStream().use { output -> input.copyTo(output) } }
                    source.delete()
                    MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf("video/*"), null)
                    runOnUiThread { result.success(target.absolutePath) }
                }
            } catch (error: Exception) {
                runOnUiThread { result.error("VAULT_RESTORE_FAILED", error.message, null) }
            }
        }
    }

    private fun publishAudio(call: MethodCall, result: MethodChannel.Result) {
        val tempPath = call.argument<String>("tempPath")
        val displayName = call.argument<String>("displayName") ?: "NovaPlay Audio.mp3"
        if (tempPath.isNullOrBlank()) {
            result.error("INVALID_ARGUMENT", "tempPath is required", null)
            return
        }
        executor.execute {
            try {
                val source = File(tempPath)
                if (!source.exists() || source.length() == 0L) {
                    runOnUiThread { result.error("AUDIO_NOT_FOUND", "Extracted audio was not found", null) }
                    return@execute
                }
                val publishedUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                        put(MediaStore.Audio.Media.MIME_TYPE, "audio/mpeg")
                        put(MediaStore.Audio.Media.RELATIVE_PATH, Environment.DIRECTORY_MUSIC + "/NovaPlay")
                        put(MediaStore.Audio.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IllegalStateException("Unable to create Music/NovaPlay media entry")
                    try {
                        contentResolver.openOutputStream(uri)?.use { output ->
                            source.inputStream().use { input -> input.copyTo(output) }
                        } ?: throw IllegalStateException("Unable to open Music/NovaPlay output")
                        contentResolver.update(uri, ContentValues().apply {
                            put(MediaStore.Audio.Media.IS_PENDING, 0)
                        }, null, null)
                        uri.toString()
                    } catch (error: Exception) {
                        contentResolver.delete(uri, null, null)
                        throw error
                    }
                } else {
                    val directory = File(
                        Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC),
                        "NovaPlay",
                    )
                    directory.mkdirs()
                    val output = File(directory, displayName)
                    source.inputStream().use { input -> output.outputStream().use { out -> input.copyTo(out) } }
                    MediaScannerConnection.scanFile(this, arrayOf(output.absolutePath), arrayOf("audio/mpeg"), null)
                    output.absolutePath
                }
                source.delete()
                runOnUiThread { result.success(publishedUri) }
            } catch (error: Exception) {
                runOnUiThread { result.error("AUDIO_PUBLISH_FAILED", error.message, null) }
            }
        }
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(PIP_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipActionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipActionReceiver, filter)
        }
    }

    override fun onDestroy() {
        runCatching { unregisterReceiver(pipActionReceiver) }
        pipEnabled = false
        executor.shutdownNow()
        super.onDestroy()
    }
}
