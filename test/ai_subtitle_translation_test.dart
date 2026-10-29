import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novaplay/features/player/ai_subtitle_preferences.dart';
import 'package:novaplay/features/player/ai_subtitle_service.dart';

void main() {
  test('embedded English caption uses Google Translate for Bengali', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode([
          [
            ['হ্যালো, পৃথিবী!', 'Hello, world!', null, null, 1],
          ],
          null,
          'en',
        ]),
        200,
      );
    });
    final service = AiSubtitleService(client: client);

    final result = await service.recognizeAndTranslate(
      sourcePath: '/sample/video.mkv',
      position: const Duration(seconds: 8),
      language: const AiSubtitleLanguage(code: 'bn', label: 'Bengali'),
      sourceText: 'Hello, world!',
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.url.host, 'translate.googleapis.com');
    expect(requests.single.url.queryParameters['tl'], 'bn');
    expect(result.caption?.text, 'হ্যালো, পৃথিবী!');
    client.close();
  });
}
