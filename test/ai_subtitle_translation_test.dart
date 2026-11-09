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
      return http.Response.bytes(
        utf8.encode(
          jsonEncode([
            [
              ['হ্যালো, পৃথিবী!', 'Hello, world!', null, null, 1],
            ],
            null,
            'en',
          ]),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
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

  test('cue translation preserves the original playback window', () async {
    final client = MockClient((_) async {
      return http.Response.bytes(
        utf8.encode(
          jsonEncode([
            [
              ['হ্যালো!', 'Hello!', null, null, 1],
            ],
            null,
            'en',
          ]),
        ),
        200,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = AiSubtitleService(client: client);
    const start = Duration(milliseconds: 1250);
    const end = Duration(milliseconds: 3780);

    final result = await service.translateCaptionCue(
      cue: const AiCaption(text: 'Hello!', start: start, end: end),
      language: const AiSubtitleLanguage(code: 'bn', label: 'Bengali'),
    );

    expect(result.caption?.text, 'হ্যালো!');
    expect(result.caption?.start, start);
    expect(result.caption?.end, end);
    client.close();
  });
}
