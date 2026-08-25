# NovaPlay

NovaPlay is a dark-first, offline Android video player built with Flutter. Current release: **1.0.2+3**. Its interface is intentionally minimal and cinematic rather than resembling a legacy desktop media player: deep AMOLED surfaces, quiet glass cards, cyan/violet accents, strong typography, and gesture-first playback controls.

## Included product surface

| Area | Included implementation |
|---|---|
| Home | Resume-watching carousel, smart folder summaries, instant search, grid/list toggle, empty and permission states |
| Library | Recursive local scan for MP4, MKV, AVI, WEBM, MOV, FLV, TS, M4V, 3GP, MPEG, and MPG |
| Filtering | Duration chips and resolution chips, with search across filenames and folder names |
| Playback | MediaKit/libmpv-backed video rendering, play/pause, double-tap ±10 seconds, horizontal seek preview, left brightness swipe, right volume swipe, auto-hide controls, lock mode, speed presets from 0.25x to 3x |
| Dialogue Enhancer | One-tap HUD toggle that writes an MPV `af` chain with low-frequency reduction, vocal-band boosts, and compression for clearer dialogue |
| AI Live Subtitles | Opt-in `AI CC` HUD control; extracts six-second audio windows locally, sends them to a configured Whisper-compatible relay or optional OpenAI build-time endpoint, translates to Bengali, Hindi, English, Spanish, Japanese, Korean, French, German, Arabic, Portuguese, or Chinese, and renders high-contrast captions |
| Capture | One-tap high-resolution PNG snapshot via MediaKit and five-second animated GIF export via FFmpegKit, saved to named gallery albums |
| Precision scrubbing | Timestamped thumbnail strip generated from the local video while dragging the seek bar |
| Reels | Dedicated full-screen vertical PageView feed that prioritizes portrait videos and keeps playback lifecycle scoped to each page |
| Private Vault | Fingerprint/face/PIN/pattern unlock via `local_auth`, app-support storage, `.nomedia` shielding, import-and-move workflow, and locked-by-default gallery |
| Tracks | Embedded audio track selection and embedded/external subtitle selection for SRT, VTT, ASS, and SSA files |
| System integration | Android scoped-storage, biometric, gallery, wake-lock, and PiP declarations; app brightness and system volume control; native PiP bridge |
| Architecture | Feature-first folders with Riverpod 3 Notifier state and a repository boundary for scan/cache operations |

## Directory structure

```text
lib/
  app.dart
  main.dart
  core/
    theme/app_theme.dart
    widgets/nova_widgets.dart
  features/
    home/home_screen.dart
    folders/folders_screen.dart
    folders/folder_videos_screen.dart
    playlists/playlists_screen.dart
    reels/reels_screen.dart
    settings/settings_screen.dart
    vault/vault_provider.dart
    vault/vault_screen.dart
    player/player_screen.dart
    player/ai_subtitle_preferences.dart
    player/ai_subtitle_service.dart
    player/capture_service.dart
    player/precision_scrubber.dart
    media/
      data/media_repository.dart
      data/thumbnail_cache.dart
      domain/video_file.dart
      presentation/media_providers.dart
      presentation/video_card.dart
android/app/src/main/
  AndroidManifest.xml
  kotlin/com/novaplay/novaplay/MainActivity.kt
test/widget_test.dart
pubspec.yaml
docs-feature-research.md
docs-media-architecture.md
```

## Local development

Install Flutter 3.41 or newer and Dart 3.12 or newer, then run:

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

For a production Android artifact, use an Android SDK with the project’s configured compile/target SDK and build an ABI-split release bundle or APK:

```bash
flutter build appbundle --release
# or
flutter build apk --release --split-per-abi
```

The sandbox validation completed successfully for `flutter analyze` and `flutter test`. A local APK build could not be executed in the sandbox because no Android SDK was installed there; this is an environment limitation, not a Dart analyzer failure.

## Android permission behavior

NovaPlay now uses a native version-aware permission bridge. Android 14 and newer request `READ_MEDIA_VIDEO` together with `READ_MEDIA_VISUAL_USER_SELECTED`, Android 13 requests `READ_MEDIA_VIDEO`, and Android 9 through Android 12 requests `READ_EXTERNAL_STORAGE`. The first library load triggers the native system permission dialog. The Home banner can request access again or open the app’s Settings page when Android reports a permanently denied state.

The app observes lifecycle `resumed` events and checks native permission state again after returning from Settings. When full/partial/denied state changes, the library is refreshed without requiring an app restart. Permission state is not treated as permanent cached data, matching Android’s guidance for selected-media access [13] [14].

## MediaStore and removable storage

The Android bridge queries `MediaStore.Video.Media` using `MediaStore.VOLUME_EXTERNAL` on Android 10 and newer, which provides the system view across shared external storage volumes, including indexed removable SD-card volumes. Android 9 uses `MediaStore.Video.Media.EXTERNAL_CONTENT_URI`. The query returns stable content URIs plus display name, file size, duration, resolution, MIME type, modification time, and storage path metadata.

Library cards use a disk-backed thumbnail cache. Native MediaStore rows are thumbnailized through `ContentResolver.loadThumbnail()` when available, while explicitly selected custom directories use the local video-thumbnail fallback. The Folders tab exposes a `Pick a folder` action through `file_picker` for USB/SD/custom locations that are not visible in the user’s MediaStore view; only explicitly selected directories use the targeted filesystem fallback. Tapping a Smart folder or Folders item opens `FolderVideosScreen`, which provides folder-scoped video browsing, sort/filter controls, grid/list switching, direct player navigation, and standard back navigation.

## Playback notes

MediaKit is initialized before `runApp`, and each player instance is disposed with the screen. The player uses the video package and native video libraries recommended by the MediaKit package documentation. Gesture behavior is implemented in the Flutter layer, while MediaKit provides codec/track/rate/seek primitives. External subtitles are loaded as a `SubtitleTrack.uri` after a native file pick. PiP is exposed through a small Android `MethodChannel`, guarded for Android versions below Oreo.

### AI Live Subtitles and translation

AI CC is deliberately **OFF on fresh installation**. The player loads the saved toggle, target language, and caption-size preference from `SharedPreferences`; no speech-recognition request is made until the user opens the player controls and enables AI CC. The bottom sheet provides the On/Off switch, target language picker, and caption-size slider. Disabling AI CC cancels the six-second polling loop and removes the caption overlay.

When enabled, NovaPlay uses FFmpegKit to extract a short mono 16 kHz WAV window from the active local video, then submits that window to a Whisper-compatible multipart endpoint. The endpoint is configured at build time with `--dart-define=NOVAPLAY_AI_SUBTITLE_ENDPOINT=https://your-relay.example/v1/subtitles`; it should authenticate upstream and return JSON containing `translated_text`, `translation`, `text`, `transcript`, or a `segments` array. This relay-first design keeps provider credentials out of the APK. For development-only builds, a direct OpenAI fallback can be enabled with `--dart-define=NOVAPLAY_OPENAI_API_KEY=...`; do not ship a long-lived provider key inside a public APK. The optional model names are `NOVAPLAY_AI_MODEL` and `NOVAPLAY_TRANSLATION_MODEL`.

The caption overlay is bottom-aligned, high contrast, shadowed, and labeled with the selected target language. Protected `content://` media sources currently report a clear limitation message rather than attempting an unsafe copy. The service is owned by `PlayerScreen`, and its HTTP client and polling timer are closed when the player route is disposed.

Inside `PlayerScreen`, the player allows portrait and both landscape orientations, listens to accelerometer sensor events when orientation is not manually locked, switches landscape playback to immersive system UI, and restores portrait/edge-to-edge behavior on exit. The HUD includes a manual orientation lock button, aspect cycling across Fit, Fill, 16:9, Stretch, and Original, two-finger pinch zoom, and a fullscreen battery/time pill.

Folder detail views default to natural A-to-Z ordering. `NaturalSort` recognizes S01E01, E01, Episode 1, and similar episode tokens before applying token-aware numeric comparison, so Episode 10 follows Episode 9 instead of sorting before it. Folder sort, duration filter, resolution filter, and grid/list preferences are persisted with `SharedPreferences`; Recent and Largest remain available from the view menu.

List, grid, folder-detail, and Reels views never construct a MediaKit `Player` or `VideoController`. They render only cached static thumbnails. Playback begins only after an explicit video tap opens `PlayerScreen`; that screen owns the single active controller, pauses it during teardown, and disposes it before the route is released. This prevents background audio from leaking while browsing or switching tabs.

The dialogue enhancer uses an MPV `af` filter chain through the native MediaKit backend. It reduces low-frequency impact rumble, lifts the vocal presence range around 1.4–3 kHz, and applies light compression. The filter is cleared when the toggle is disabled. This is a playback enhancement rather than a destructive transcode.

Capture actions are intentionally local-first: MediaKit’s native screenshot API produces a high-resolution PNG at the current frame, while FFmpegKit seeks to the current position and encodes a five-second 12 fps GIF. Saver Gallery writes both outputs to `Pictures/NovaPlay/Snapshots` or `Pictures/NovaPlay/GIFs` on Android.

The Private Vault stores imported files under the app’s private support directory and creates `.nomedia` to prevent gallery indexing. Unlocking uses the device’s secure authentication surface; `local_auth` allows biometric authentication with device PIN/passcode/pattern fallback by default. The move workflow copies the chosen file into the vault and attempts to remove the original, while retaining the copy if a document provider disallows deletion.

The current source is intentionally modular so the next production iteration can add MediaStore IDs, thumbnail disk caching, true background-media notification controls, playlist persistence, per-folder browsing routes, and richer media metadata without rewriting the visual shell.

## GitHub Actions

`.github/workflows/build.yml` runs on pushes and pull requests targeting `main`, as well as manual dispatches. It resolves dependencies, checks formatting, runs `flutter analyze`, runs widget tests, builds split release APKs, and uploads the generated APKs as a workflow artifact named `novaplay-release-apks`.

## References

[1]: https://pub.dev/packages/media_kit "media_kit package documentation"
[2]: https://pub.dev/packages/media_kit_video "media_kit_video package documentation"
[3]: https://pub.dev/packages/flutter_riverpod "flutter_riverpod package documentation"
[4]: https://pub.dev/packages/permission_handler "permission_handler package documentation"
[5]: https://pub.dev/packages/file_picker "file_picker package documentation"
[6]: https://pub.dev/packages/video_thumbnail "video_thumbnail package documentation"
[7]: https://pub.dev/packages/screen_brightness "screen_brightness package documentation"
[8]: https://pub.dev/packages/volume_controller "volume_controller package documentation"
[9]: https://pub.dev/packages/local_auth "local_auth package documentation"
[10]: https://pub.dev/packages/ffmpeg_kit_flutter_new "ffmpeg_kit_flutter_new package documentation"
[11]: https://pub.dev/packages/saver_gallery "saver_gallery package documentation"
[12]: https://mpv-player-mpv.mintlify.app/av/audio-filters "MPV audio filters documentation"
[13]: https://developer.android.com/training/data-storage/shared/media "Access media files from shared storage"
[14]: https://developer.android.com/about/versions/14/changes/partial-photo-video-access "Grant partial access to photos and videos"
[15]: https://developer.android.com/reference/android/provider/MediaStore "MediaStore API reference"
[16]: https://developer.android.com/reference/android/Manifest.permission#READ_MEDIA_VISUAL_USER_SELECTED "READ_MEDIA_VISUAL_USER_SELECTED permission"
[17]: https://platform.openai.com/docs/guides/speech-to-text "OpenAI speech-to-text guide"
[18]: https://platform.openai.com/docs/api-reference/audio/createTranscription "OpenAI transcription API reference"
