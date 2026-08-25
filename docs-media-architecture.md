# NovaPlay Media Architecture Notes

## Permission matrix

NovaPlay requests only video-read access. On Android 14 and newer, the native bridge requests `READ_MEDIA_VIDEO` together with `READ_MEDIA_VISUAL_USER_SELECTED`, allowing the system to return full or selected-video access. On Android 13, it requests `READ_MEDIA_VIDEO`. On Android 9 through Android 12, it requests `READ_EXTERNAL_STORAGE`.

The app does not persist permission state as authoritative data. Every foreground resume checks the native permission state again, because Android allows the user to change access in Settings while the app is backgrounded. When state changes, the Riverpod controller queries MediaStore again and updates the UI.

## MediaStore query strategy

The Android bridge queries `MediaStore.Video.Media` using `MediaStore.VOLUME_EXTERNAL` on Android 10 and newer. This synthetic volume is the framework view over all shared external storage volumes, including primary shared storage and indexed removable SD-card volumes. On Android 9, it uses `MediaStore.Video.Media.EXTERNAL_CONTENT_URI`.

The query returns the stable content URI, display name, byte size, duration, width, height, MIME type, modification time, `DATA` path when available, and `RELATIVE_PATH` on Android 10 and newer. The Dart model retains both the content URI and the path. MediaStore rows are handled as the authoritative library; a small custom-directory scanner is used only after the user explicitly selects a directory through the Storage Access Framework.

Queries run on a dedicated native executor rather than the Android main thread. The Dart layer merges MediaStore rows with explicitly selected custom directories and resume progress.

## Thumbnail and metadata cache

MediaStore supplies duration, resolution, MIME type, byte size, and modification time directly in the query. For thumbnails, NovaPlay first asks Android `ContentResolver.loadThumbnail()` for a cached JPEG under the app cache directory. Local custom-directory files use the `video_thumbnail` fallback. The UI consumes the cache asynchronously, so library cards do not regenerate a thumbnail on every rebuild.

## Official references

[1]: https://developer.android.com/training/data-storage/shared/media "Access media files from shared storage"
[2]: https://developer.android.com/about/versions/14/changes/partial-photo-video-access "Grant partial access to photos and videos"
[3]: https://developer.android.com/reference/android/provider/MediaStore "MediaStore API reference"
[4]: https://developer.android.com/reference/android/Manifest.permission#READ_MEDIA_VISUAL_USER_SELECTED "READ_MEDIA_VISUAL_USER_SELECTED permission"
