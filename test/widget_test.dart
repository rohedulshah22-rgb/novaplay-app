import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:novaplay/app.dart';
import 'package:novaplay/features/media/domain/natural_sort.dart';
import 'package:novaplay/features/media/domain/video_file.dart';

void main() {
  testWidgets('NovaPlay renders the offline cinema home', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NovaPlayApp()));
    expect(find.text('NovaPlay'), findsOneWidget);
    expect(find.text('Your offline cinema'), findsOneWidget);
  });

  test('natural sort keeps Episode 10 after Episode 2', () {
    final names = [
      'Show Episode 10.mkv',
      'Show Episode 2.mkv',
      'Show Episode 1.mkv',
    ];
    names.sort(NaturalSort.compareStrings);
    expect(names, [
      'Show Episode 1.mkv',
      'Show Episode 2.mkv',
      'Show Episode 10.mkv',
    ]);

    final videos = names
        .map(
          (name) => VideoFile(
            id: name,
            path: name,
            name: name,
            sizeBytes: 1,
            modifiedAt: DateTime(2026),
          ),
        )
        .toList();
    videos.sort(NaturalSort.compareVideos);
    expect(videos.last.name, 'Show Episode 10.mkv');
  });
}
