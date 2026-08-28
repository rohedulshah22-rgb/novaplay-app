# NovaPlay

## Official launcher icon

NovaPlay uses the **Nebula-Play Glowing Triangle** launcher mark: a dark AMOLED squircle with an electric cyan-to-purple play triangle. The editable vector master is `assets/icons/app_icon.svg`; `assets/icons/play_foreground.svg` is the transparent adaptive-icon foreground. The PNG companions are generated deterministically with `tooling/render_app_icon.sh`, then `flutter_launcher_icons` creates the Android mdpi, hdpi, xhdpi, xxhdpi, and xxxhdpi resources from `pubspec.yaml`.


NovaPlay is a dark-first, offline Android video player built with Flutter. Current release: **1.0.2+3**. Its interface is intentionally minimal and cinematic rather than resembling a legacy desktop media player: deep AMOLED surfaces, quiet glass cards, cyan/violet accents, strong typography, and gesture-first playback controls.

## Included product surface

| Area | Included implementation |
|---|---|
| Home | Resume-watching carousel, smart folder summaries, instant search, grid/list toggle, empty and permission states |
| Library | Recursive local scan for MP4, MKV, AVI, WEBM, MOV, FLV, TS, M4V, 3GP, MPEG, and MPG |
| Filtering | Duration chips and resolution chips, with search across filenames and folder names |
| Playback | MediaKit/libmpv-backed video rendering, centered Previous/Stop/Play-Pause/Next controls, folder-aware queue playback, automatic next-video advance, swipe-left/right navigation with animated title badges, instant single-tap HUD toggle, cumulative double-tap ±10-second seeking with animated side indicators, horizontal seek preview, left brightness swipe, right volume swipe, auto-hide controls, lock mode, and speed presets from 0.25x to 3x |
| Dialogue Enhancer | One-tap HUD toggle that writes an MPV `af` chain with low-frequency reduction, vocal-band boosts, and compression for clearer dialogue |
| AI Live Subtitles | Opt-in `AI CC` HUD control; extracts six-second audio windows locally, sends them to a configured Whisper-compatible relay or optional OpenAI build-time endpoint, translates to Bengali, Hindi, English, Spanish, Japanese, Korean, French, German, Arabic, Portuguese, or Chinese, and renders high-contrast captions |
| Capture | One-tap high-resolution PNG snapshot via MediaKit and five-second animated GIF export via FFmpegKit, saved to named gallery albums |
| Precision scrubbing | Timestamped thumbnail strip generated from the local video while dragging the seek bar |
| Reels | Dedicated full-screen vertical PageView feed that prioritizes portrait videos and keeps playback lifecycle scoped to each page |
| Private Vault | Fingerprint/face/PIN/pattern unlock via `local_auth`, app-support storage, `.nomedia` shielding, import-and-move workflow, and locked-by-default gallery |
| Tracks | Embedded audio track selection, explicit `None / Turn Off Subtitles`, language-labeled immediate switching, and external subtitle selection for SRT, VTT, ASS, and SSA files |
| Playback utilities | Session sleep timer with preset/custom/end-of-video modes, high-quality MP3 extraction to `Music/NovaPlay`, and Chromecast/DLNA local-network casting with remote playback controls |
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
  player/cast_service.dart
  media/data/audio_extraction_service.dart
  media/presentation/audio_extraction_dialog.dart
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

The current Google Play release is version `1.0.3+4` (`versionName 1.0.3`, `versionCode 4`). Build the production Android App Bundle with an Android SDK configured for the project:

```bash
flutter build appbundle --release
```

The bundle is generated at `build/app/outputs/bundle/release/app-release.aab`.

The sandbox validation completed successfully for `flutter analyze` and `flutter test`. A local APK build could not be executed in the sandbox because no Android SDK was installed there; this is an environment limitation, not a Dart analyzer failure.

## Android permission behavior

NovaPlay now uses a native version-aware permission bridge. Android 14 and newer request `READ_MEDIA_VIDEO` together with `READ_MEDIA_VISUAL_USER_SELECTED`, Android 13 requests `READ_MEDIA_VIDEO`, and Android 9 through Android 12 requests `READ_EXTERNAL_STORAGE`. The first library load triggers the native system permission dialog. The Home banner can request access again or open the app’s Settings page when Android reports a permanently denied state.

The app observes lifecycle `resumed` events and checks native permission state again after returning from Settings. When full/partial/denied state changes, the library is refreshed without requiring an app restart. Permission state is not treated as permanent cached data, matching Android’s guidance for selected-media access [13] [14].

## MediaStore and removable storage

The Android bridge queries `MediaStore.Video.Media` using `MediaStore.VOLUME_EXTERNAL` on Android 10 and newer, which provides the system view across shared external storage volumes, including indexed removable SD-card volumes. Android 9 uses `MediaStore.Video.Media.EXTERNAL_CONTENT_URI`. The query returns stable content URIs plus display name, file size, duration, resolution, MIME type, modification time, and storage path metadata.

Library cards use a disk-backed thumbnail cache. Native MediaStore rows are thumbnailized through `ContentResolver.loadThumbnail()` when available, while explicitly selected custom directories use the local video-thumbnail fallback. The Folders tab exposes a `Pick a folder` action through `file_picker` for USB/SD/custom locations that are not visible in the user’s MediaStore view; only explicitly selected directories use the targeted filesystem fallback. Tapping a Smart folder or Folders item opens `FolderVideosScreen`, which provides folder-scoped video browsing, sort/filter controls, grid/list switching, direct player navigation, and standard back navigation.

## Playback utilities

The player settings sheet includes a sleep timer with 15, 30, 45, and 60 minute presets, a custom duration, and an `End of current video` mode. When the timer expires, MediaKit playback is paused and the screen is allowed to sleep. The settings sheet shows the active countdown and exposes `Cancel Timer`.

Home and folder video cards expose `Extract Audio / Convert to MP3` through the overflow button and long press. FFmpegKit runs asynchronously, reports conversion progress in a dialog, and the native Android bridge publishes the resulting high-quality MP3 to the public `Music/NovaPlay` folder through MediaStore, with a legacy MediaScanner fallback.

The player HUD includes a Cast button backed by `dart_cast`. NovaPlay discovers Chromecast and DLNA/UPnP renderers on the same Wi-Fi network, serves supported local files through the package’s local proxy, and provides remote play, pause, seek, and volume controls. Receiver support varies by container and TV firmware; casting is optional and does not replace the local MediaKit player until a device connection succeeds.

## Playback notes

MediaKit is initialized before `runApp`, and each player instance is disposed with the screen. The player uses the video package and native video libraries recommended by the MediaKit package documentation. Gesture behavior is implemented in the Flutter layer, while MediaKit provides codec/track/rate/seek primitives. PlayerScreen opens a MediaKit `Playlist` from the current folder queue, keeps `PlaylistMode.none` so the queue stops after its last item, and advances to the next item on each completed media event. The center control row exposes Previous, Stop, Play/Pause, and Next; Stop saves the current history point, stops and disposes the player, then returns to the list. Native subtitle output starts at `None` until the user selects a track. The Subtitles sheet lists human-readable language metadata, offers `None / Turn Off Subtitles`, and switches tracks immediately without restarting playback. External subtitles are loaded as a `SubtitleTrack.uri` after a native file pick. PiP is exposed through a small Android `MethodChannel`, guarded for Android versions below Oreo.

### AI Live Subtitles and translation

AI CC is deliberately **OFF on fresh installation**. The player loads the saved toggle, target language, and caption-size preference from `SharedPreferences`; no speech-recognition request is made until the user opens the player controls and enables AI CC. The bottom sheet provides the On/Off switch, target language picker, and caption-size slider. Disabling AI CC cancels the six-second polling loop, removes the translated caption overlay, and restores the previously selected native subtitle track.

When enabled, NovaPlay uses a cue-first pipeline. It first consumes MediaKit’s live subtitle-text stream, so a manually selected embedded English, Korean, Hindi, or other subtitle track can be translated as soon as its cue appears. The selected native track remains active for cue delivery, but MediaKit’s native subtitle renderer is hidden, so only the translated Flutter overlay is shown and source/translated captions never overlap. It also checks for a matching local `.srt` or `.vtt` sidecar and, for filesystem-readable videos with no sidecar, extracts the first embedded subtitle stream to a temporary SRT file using FFmpegKit. Cue timestamps are preserved through translation, so the translated caption is rendered only during the source cue’s active playback interval.

Text cues are translated through the configured `NOVAPLAY_TRANSLATION_ENDPOINT` when present, then a direct OpenAI build-time key if explicitly supplied, and finally the Google Translate-compatible endpoint for a practical keyless text-translation fallback. The optional speech path extracts six-second mono 16 kHz WAV windows with FFmpegKit and submits them to a Whisper-compatible multipart endpoint configured with `--dart-define=NOVAPLAY_AI_SUBTITLE_ENDPOINT=https://your-relay.example/v1/subtitles`. The endpoint should authenticate upstream and return JSON containing `translated_text`, `translation`, `text`, `transcript`, or a `segments` array. For development-only builds, a direct OpenAI fallback can be enabled with `--dart-define=NOVAPLAY_OPENAI_API_KEY=...`; do not ship a long-lived provider key inside a public APK. The optional model names are `NOVAPLAY_AI_MODEL` and `NOVAPLAY_TRANSLATION_MODEL`.

When a cue cannot be translated, NovaPlay leaves the video viewport clear and continues playback without a relay-warning banner or repeated SnackBar. Protected `content://` media sources use the live MediaKit subtitle-text path when available; audio-only recognition remains best-effort and requires an explicitly configured speech provider. The caption overlay is bottom-aligned, high contrast, and shadowed. Subtitle and audio sheets share an offline ISO 639-1/639-2 formatter, including aliases such as `ger`, `heb`, `hrv`, `ukr`, `vie`, `eng`, `kor`, `hin`, `spa`, `fra`, `ara`, `por`, and `ben`, with readable fallback names for unknown values. The service is owned by `PlayerScreen`, and its HTTP client, temporary subtitle files, and polling timer are closed when the player route is disposed.

AI Voice Dubbing (Beta) is independently persisted as `isAiDubbingEnabled` and defaults to **OFF** whenever no saved preference exists. Turning it on keeps the switch visually off until the bilingual **Feature Under Creation** confirmation is accepted; Cancel leaves it off, while Enable Anyway activates Android’s native offline TTS engine. Before speaking, NovaPlay removes bracketed annotations, parenthetical sound descriptions, braces, and music symbols, then estimates standard speech time as `wordCount × 0.35` seconds and clamps the resulting cue-fit rate to `0.9–1.65`. If a new cue arrives with no more than 300 ms remaining in the active speech handoff, the current sentence is given that short completion window before the next utterance replaces it. The primary player volume is temporarily reduced to 25% until speech completes. Turning dubbing off stops speech immediately and restores the prior player volume without prompting.

Inside `PlayerScreen`, the player allows portrait and both landscape orientations, listens to accelerometer sensor events when orientation is not manually locked, switches landscape playback to immersive system UI, and restores portrait/edge-to-edge behavior on exit. The HUD includes a manual orientation lock button, aspect cycling across Fit, Fill, 16:9, Stretch, and Original, two-finger pinch zoom, and a fullscreen battery/time pill. A single tap on the video viewport toggles the HUD immediately, while Flutter’s tap recognizers reserve double taps for side-aware seeking. Rapid taps accumulate into ±20s, ±30s, and larger jumps; a timed animated indicator appears on the left or right side without interrupting playback.

### Resume playback and history

NovaPlay persists playback history in `SharedPreferences` through `PlaybackHistoryEntry`, keyed by the media identifier. The player saves position, total duration, and last-played time every two seconds, on pause, and during route disposal. Positions beyond 95% of the known duration are marked finished and reset to zero so completed videos do not remain in the resume carousel. Existing legacy progress data is migrated when first read.

When a video has a saved point beyond five seconds, it is sought automatically after MediaKit duration initialization and shows a lightweight `Resumed from HH:MM:SS` SnackBar with a `Restart` action. The Home header includes a History button that opens the most recently played resumable video directly. Resume cards and the History action are ordered by last-played time, while all video-list and folder entry points inherit the same PlayerScreen behavior. Folder detail passes its active filtered and naturally sorted list into the PlayerScreen queue, and the player saves the current queue item before each explicit or automatic transition.

Folder detail views default to natural A-to-Z ordering. `NaturalSort` recognizes S01E01, E01, Episode 1, and similar episode tokens before applying token-aware numeric comparison, so Episode 10 follows Episode 9 instead of sorting before it. Folder sort, duration filter, resolution filter, and grid/list preferences are persisted with `SharedPreferences`; Recent and Largest remain available from the view menu.

List, grid, folder-detail, and Reels views never construct a MediaKit `Player` or `VideoController`. They render only cached static thumbnails. Playback begins only after an explicit video tap opens `PlayerScreen`; that screen owns the single active controller, pauses it during teardown, and disposes it before the route is released. This prevents background audio from leaking while browsing or switching tabs.

The dialogue enhancer uses an MPV `af` filter chain through the native MediaKit backend. It reduces low-frequency impact rumble, lifts the vocal presence range around 1.4–3 kHz, and applies light compression. The filter is cleared when the toggle is disabled. This is a playback enhancement rather than a destructive transcode.

Capture actions are intentionally local-first: MediaKit’s native screenshot API produces a high-resolution PNG at the current frame, while FFmpegKit seeks to the current position and encodes a five-second 12 fps GIF. Saver Gallery writes both outputs to `Pictures/NovaPlay/Snapshots` or `Pictures/NovaPlay/GIFs` on Android.

The Private Vault stores videos under an Android app-private `files/private_vault` directory, which is outside MediaStore and protected from gallery indexing. Vault metadata is persisted locally while the 4-digit PIN is stored with `flutter_secure_storage`; Android backup is disabled for the application. The first unlock creates the PIN, then NovaPlay prefers fingerprint/face authentication when available and falls back to the PIN. Video cards and folder items expose `Move to Private Folder`; the native bridge copies the source into private storage, removes the public MediaStore/file entry, and refreshes the library. Vault items support direct playback, `Unhide / Restore Video` back into MediaStore, PIN changes, biometric preference, vault lock, and reset.

NovaPlay supports Android Picture-in-Picture on Android 8.0 and newer. The Android activity declares `supportsPictureInPicture`, handles orientation and screen-size configuration changes, and uses the native PiP bridge to preserve the source aspect ratio. The player’s floating button enters PiP explicitly, while minimizing the app during active playback automatically enters PiP. The native window exposes a play/pause toggle and a close action; the latter terminates the task and releases the player through the normal PlayerScreen lifecycle.

The Music tab scans local `.mp3`, `.m4a`, `.aac`, `.flac`, and `.wav` files with `on_audio_query`, and presents All Songs, Albums, Artists, and Folders groupings. A shared mini-player remains above the bottom navigation while browsing NovaPlay, and tapping it opens the full-screen player with artwork, seek, repeat, shuffle, previous, and next controls. `just_audio` supplies local-file playback while `audio_service` owns the Android foreground media service, lock-screen notification, headset/media-button actions, and background transport controls. Audio access requests `READ_MEDIA_AUDIO` on Android 13+ and uses the existing shared-storage permission fallback on older Android versions [16] [17] [18].

The current source is intentionally modular so the next production iteration can add richer playlist persistence and richer media metadata without rewriting the visual shell. The active folder queue and player-owned MediaKit lifecycle are already implemented in `PlayerScreen`, while the singleton music handler remains alive for background audio playback.

## GitHub Actions

`.github/workflows/build.yml` runs on pushes and pull requests targeting `main`, as well as manual dispatches. It resolves dependencies, checks formatting, runs `flutter analyze`, runs widget tests, builds the production App Bundle with `flutter build appbundle --release`, uploads `novaplay-production-aab`, then builds the direct-install test APK with `flutter build apk --release` and uploads `novaplay-production-apk` from `build/app/outputs/flutter-apk/app-release.apk`.

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
[16]: https://pub.dev/packages/just_audio "just_audio package documentation"
[17]: https://pub.dev/packages/audio_service "audio_service package documentation"
[18]: https://pub.dev/packages/on_audio_query "on_audio_query package documentation"
[19]: https://pub.dev/packages/flutter_tts "flutter_tts package documentation"
