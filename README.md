# NovaPlay

NovaPlay is a dark-first, offline Android video player built with Flutter. Its interface is intentionally minimal and cinematic rather than resembling a legacy desktop media player: deep AMOLED surfaces, quiet glass cards, cyan/violet accents, strong typography, and gesture-first playback controls.

## Included product surface

| Area | Included implementation |
|---|---|
| Home | Resume-watching carousel, smart folder summaries, instant search, grid/list toggle, empty and permission states |
| Library | Recursive local scan for MP4, MKV, AVI, WEBM, MOV, FLV, TS, M4V, 3GP, MPEG, and MPG |
| Filtering | Duration chips and resolution chips, with search across filenames and folder names |
| Playback | MediaKit/libmpv-backed video rendering, play/pause, double-tap ±10 seconds, horizontal seek preview, left brightness swipe, right volume swipe, auto-hide controls, lock mode, speed presets from 0.25x to 3x |
| Dialogue Enhancer | One-tap HUD toggle that writes an MPV `af` chain with low-frequency reduction, vocal-band boosts, and compression for clearer dialogue |
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
    playlists/playlists_screen.dart
    reels/reels_screen.dart
    settings/settings_screen.dart
    vault/vault_provider.dart
    vault/vault_screen.dart
    player/player_screen.dart
    player/capture_service.dart
    player/precision_scrubber.dart
    media/
      data/media_repository.dart
      domain/video_file.dart
      presentation/media_providers.dart
      presentation/video_card.dart
android/app/src/main/
  AndroidManifest.xml
  kotlin/com/novaplay/novaplay/MainActivity.kt
test/widget_test.dart
pubspec.yaml
docs-feature-research.md
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

Android 13 and newer request the media-video permission through `permission_handler`; older Android versions fall back to external-storage permission. The repository scans well-known roots first, then the shared external-storage root, deduplicates paths, caps the result at 3,000 files, and persists a JSON cache in `SharedPreferences`. The next production hardening step for very large libraries is replacing the recursive filesystem pass with a MediaStore query and WorkManager-triggered incremental updates.

## Playback notes

MediaKit is initialized before `runApp`, and each player instance is disposed with the screen. The player uses the video package and native video libraries recommended by the MediaKit package documentation. Gesture behavior is implemented in the Flutter layer, while MediaKit provides codec/track/rate/seek primitives. External subtitles are loaded as a `SubtitleTrack.uri` after a native file pick. PiP is exposed through a small Android `MethodChannel`, guarded for Android versions below Oreo.

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
