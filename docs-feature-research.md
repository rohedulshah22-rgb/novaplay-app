# Feature update research notes

## Verified package guidance

| Need | Package/version | Verified API or constraint |
|---|---|---|
| Biometric/PIN unlock | `local_auth: ^3.0.2` | `LocalAuthentication.authenticate` supports biometrics with passcode/PIN fallback by default; Android support starts at SDK 24. |
| GIF and gallery export | `ffmpeg_kit_flutter_new: ^4.6.2`, `saver_gallery: ^5.1.0` | FFmpegKit supports local file commands and FFprobe; Saver Gallery supports saving GIF/image/video files to Android gallery albums. Saver Gallery 5.x requires Flutter 3.41+, Dart 3.12+, JDK 17, compile SDK 36. |
| Native playback | `media_kit: ^1.2.6`, `media_kit_video: ^2.0.1`, `media_kit_libs_video: ^1.0.7` | MediaKit exposes `Player.screenshot`, rate/seek, audio/subtitle tracks, and `Player.setProperty` for mpv properties. |
| Precision scrub thumbnails | Existing `video_thumbnail: ^0.5.6` | `VideoThumbnail.thumbnailData` can create local frame thumbnails at a requested timestamp. |

## Source URLs

- https://pub.dev/packages/local_auth
- https://pub.dev/packages/saver_gallery
- https://pub.dev/packages/ffmpeg_kit_flutter_new
- https://pub.dev/packages/media_kit
- https://pub.dev/packages/video_thumbnail
- https://mpv-player-mpv.mintlify.app/av/audio-filters
