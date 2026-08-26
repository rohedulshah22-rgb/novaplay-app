import 'package:shared_preferences/shared_preferences.dart';

class AiSubtitlePreferences {
  const AiSubtitlePreferences._();

  static const enabledKey = 'novaplay.ai_subtitles.enabled.v1';
  static const languageKey = 'novaplay.ai_subtitles.language.v1';
  static const fontScaleKey = 'novaplay.ai_subtitles.font_scale.v1';
  static const aiDubbingEnabledKey = 'isAiDubbingEnabled';

  static const languages = <AiSubtitleLanguage>[
    AiSubtitleLanguage(code: 'en', label: 'English'),
    AiSubtitleLanguage(code: 'bn', label: 'Bengali'),
    AiSubtitleLanguage(code: 'hi', label: 'Hindi'),
    AiSubtitleLanguage(code: 'es', label: 'Spanish'),
    AiSubtitleLanguage(code: 'ja', label: 'Japanese'),
    AiSubtitleLanguage(code: 'ko', label: 'Korean'),
    AiSubtitleLanguage(code: 'fr', label: 'French'),
    AiSubtitleLanguage(code: 'de', label: 'German'),
    AiSubtitleLanguage(code: 'ar', label: 'Arabic'),
    AiSubtitleLanguage(code: 'pt', label: 'Portuguese'),
    AiSubtitleLanguage(code: 'zh', label: 'Chinese'),
  ];

  static Future<AiSubtitlePreferenceValues> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLanguage = prefs.getString(languageKey) ?? 'English';
    final language = languages.any((item) => item.label == savedLanguage)
        ? savedLanguage
        : 'English';
    return AiSubtitlePreferenceValues(
      enabled: prefs.getBool(enabledKey) ?? false,
      aiDubbingEnabled: prefs.getBool(aiDubbingEnabledKey) ?? false,
      language: language,
      fontScale: (prefs.getDouble(fontScaleKey) ?? 1.0).clamp(.8, 1.8),
    );
  }

  static Future<void> save({
    bool? enabled,
    bool? aiDubbingEnabled,
    String? language,
    double? fontScale,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (enabled != null) await prefs.setBool(enabledKey, enabled);
    if (aiDubbingEnabled != null) {
      await prefs.setBool(aiDubbingEnabledKey, aiDubbingEnabled);
    }
    if (language != null) await prefs.setString(languageKey, language);
    if (fontScale != null) {
      await prefs.setDouble(fontScaleKey, fontScale.clamp(.8, 1.8));
    }
  }
}

class AiSubtitleLanguage {
  const AiSubtitleLanguage({required this.code, required this.label});

  final String code;
  final String label;
}

class AiSubtitlePreferenceValues {
  const AiSubtitlePreferenceValues({
    required this.enabled,
    required this.aiDubbingEnabled,
    required this.language,
    required this.fontScale,
  });

  final bool enabled;
  final bool aiDubbingEnabled;
  final String language;
  final double fontScale;
}
