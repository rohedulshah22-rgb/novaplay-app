import 'package:flutter_test/flutter_test.dart';

import 'package:novaplay/features/player/language_names.dart';

void main() {
  test('maps requested two- and three-letter aliases to full names', () {
    expect(languageName('ger'), 'German');
    expect(languageName('heb'), 'Hebrew');
    expect(languageName('hrv'), 'Croatian');
    expect(languageName('ukr'), 'Ukrainian');
    expect(languageName('vie'), 'Vietnamese');
    expect(languageName('eng'), 'English');
    expect(languageName('ko'), 'Korean');
    expect(languageName('hin'), 'Hindi');
    expect(languageName('spa'), 'Spanish');
    expect(languageName('fra'), 'French');
    expect(languageName('ara'), 'Arabic');
    expect(languageName('por'), 'Portuguese');
    expect(languageName('bn'), 'Bengali');
  });

  test('normalizes locale-like values and unknown codes readably', () {
    expect(languageName('pt-BR'), 'Portuguese');
    expect(languageName('zh_CN'), 'Chinese');
    expect(languageName('und'), 'Unknown language');
    expect(languageName('x-klingon'), 'X Klingon');
  });

  test('formats title and language without exposing raw ISO codes', () {
    expect(trackLanguageLabel(title: 'eng', language: null), 'English');
    expect(
      trackLanguageLabel(title: 'Main', language: 'ben'),
      'Main · Bengali',
    );
    expect(trackLanguageLabel(), 'Unknown language');
  });
}
