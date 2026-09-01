# Audio Cutter integration sources

- `ringtone_set_plus` 0.0.2+2 documentation: https://pub.dev/packages/ringtone_set_plus/versions/0.0.2+2
  - Android-only plugin; exposes `RingtoneSet.setRingtoneFromFile`, `setNotificationFromFile`, and `setAlarmFromFile`.
  - Its documentation requests `WRITE_SETTINGS` and storage permissions.
- `share_plus` documentation: https://pub.dev/packages/share_plus
  - Current package documentation shows `SharePlus.instance.share(ShareParams(files: [XFile(...)], ...))`.
  - Current release line is 13.x; the project must use a compatible 13.x constraint because `share_plus` 10.x conflicts with `flutter_secure_storage_windows` through incompatible `win32` constraints.
- Existing full FFmpeg package documentation: https://pub.dev/packages/ffmpeg_kit_flutter_new
  - Existing NovaPlay dependency `ffmpeg_kit_flutter_new` already provides FFmpeg/FFprobe and the audio codecs needed for MP3 trimming; no second FFmpeg package is required.
