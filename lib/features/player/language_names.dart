/// Human-readable names for common ISO 639-1 and ISO 639-2 language codes.
///
/// MediaKit can expose either a two-letter code, a three-letter code, or a
/// locale-like value such as `en-US`. Keep this mapping local so subtitle and
/// audio selection sheets present consistent labels without network access.
const Map<String, String> _languageNames = {
  'ar': 'Arabic',
  'ara': 'Arabic',
  'bn': 'Bengali',
  'ben': 'Bengali',
  'bg': 'Bulgarian',
  'bul': 'Bulgarian',
  'ca': 'Catalan',
  'cat': 'Catalan',
  'cs': 'Czech',
  'ces': 'Czech',
  'cze': 'Czech',
  'da': 'Danish',
  'dan': 'Danish',
  'de': 'German',
  'deu': 'German',
  'ger': 'German',
  'el': 'Greek',
  'ell': 'Greek',
  'gre': 'Greek',
  'en': 'English',
  'eng': 'English',
  'es': 'Spanish',
  'spa': 'Spanish',
  'et': 'Estonian',
  'est': 'Estonian',
  'fa': 'Persian',
  'fas': 'Persian',
  'per': 'Persian',
  'fi': 'Finnish',
  'fin': 'Finnish',
  'fr': 'French',
  'fra': 'French',
  'fre': 'French',
  'he': 'Hebrew',
  'heb': 'Hebrew',
  'hi': 'Hindi',
  'hin': 'Hindi',
  'hr': 'Croatian',
  'hrv': 'Croatian',
  'hu': 'Hungarian',
  'hun': 'Hungarian',
  'id': 'Indonesian',
  'ind': 'Indonesian',
  'is': 'Icelandic',
  'isl': 'Icelandic',
  'ice': 'Icelandic',
  'it': 'Italian',
  'ita': 'Italian',
  'ja': 'Japanese',
  'jpn': 'Japanese',
  'ko': 'Korean',
  'kor': 'Korean',
  'lt': 'Lithuanian',
  'lit': 'Lithuanian',
  'lv': 'Latvian',
  'lav': 'Latvian',
  'ms': 'Malay',
  'msa': 'Malay',
  'may': 'Malay',
  'nl': 'Dutch',
  'nld': 'Dutch',
  'dut': 'Dutch',
  'no': 'Norwegian',
  'nor': 'Norwegian',
  'pl': 'Polish',
  'pol': 'Polish',
  'pt': 'Portuguese',
  'por': 'Portuguese',
  'ro': 'Romanian',
  'ron': 'Romanian',
  'rum': 'Romanian',
  'ru': 'Russian',
  'rus': 'Russian',
  'sk': 'Slovak',
  'slk': 'Slovak',
  'slo': 'Slovak',
  'sl': 'Slovenian',
  'slv': 'Slovenian',
  'sr': 'Serbian',
  'srp': 'Serbian',
  'sv': 'Swedish',
  'swe': 'Swedish',
  'ta': 'Tamil',
  'tam': 'Tamil',
  'te': 'Telugu',
  'tel': 'Telugu',
  'th': 'Thai',
  'tha': 'Thai',
  'tr': 'Turkish',
  'tur': 'Turkish',
  'uk': 'Ukrainian',
  'ukr': 'Ukrainian',
  'ur': 'Urdu',
  'urd': 'Urdu',
  'vi': 'Vietnamese',
  'vie': 'Vietnamese',
  'zh': 'Chinese',
  'zho': 'Chinese',
  'chi': 'Chinese',
};

/// Converts an ISO code or locale-like value into a human-readable name.
///
/// Unknown values are normalized into title case instead of being displayed
/// as an opaque raw code. Values such as `und`, `unk`, and `unknown` are
/// represented as `Unknown language`.
String languageName(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return 'Unknown language';

  final normalized = raw.toLowerCase().replaceAll('_', '-');
  final code = normalized.split('-').first;
  if (code == 'und' || code == 'unk' || code == 'unknown') {
    return 'Unknown language';
  }
  final known = _languageNames[code];
  if (known != null) return known;

  final fallback = normalized
      .replaceAll('-', ' ')
      .split(RegExp(r'[ .]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
  return fallback.isEmpty ? 'Unknown language' : fallback;
}

/// Formats a MediaKit track title and language without duplicating the name.
String trackLanguageLabel({String? title, String? language}) {
  final cleanTitle = title?.trim();
  final cleanLanguage = language?.trim();
  final hasTitle = cleanTitle != null && cleanTitle.isNotEmpty;
  final hasLanguage = cleanLanguage != null && cleanLanguage.isNotEmpty;
  final name = hasLanguage ? languageName(cleanLanguage) : null;

  if (hasTitle && hasLanguage) {
    final titleLooksLikeLanguage =
        cleanTitle.toLowerCase() == cleanLanguage.toLowerCase() ||
        cleanTitle.toLowerCase() == name!.toLowerCase();
    if (titleLooksLikeLanguage) return name!;
    return '$cleanTitle · $name';
  }
  if (hasTitle) {
    final titleLanguage = _languageNames[cleanTitle.toLowerCase()];
    return titleLanguage ?? cleanTitle;
  }
  if (hasLanguage) return name!;
  return 'Unknown language';
}
