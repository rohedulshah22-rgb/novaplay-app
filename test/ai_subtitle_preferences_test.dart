import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:novaplay/features/player/ai_subtitle_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('AI CC is disabled by default on fresh storage', () async {
    final values = await AiSubtitlePreferences.load();

    expect(values.enabled, isFalse);
    expect(values.language, 'English');
    expect(values.fontScale, 1.0);
  });

  test('AI CC preferences persist across loads', () async {
    await AiSubtitlePreferences.save(
      enabled: true,
      language: 'Bengali',
      fontScale: 1.4,
    );

    final values = await AiSubtitlePreferences.load();

    expect(values.enabled, isTrue);
    expect(values.language, 'Bengali');
    expect(values.fontScale, 1.4);
  });
}
