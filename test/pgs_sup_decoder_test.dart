import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novaplay/features/player/pgs_sup_decoder.dart';

void main() {
  test('decodes a one-colour RLE subtitle and closes it at a clear PCS', () {
    final packets = <int>[];
    packets.addAll(_packet(1000, 0x14, _pds()));
    packets.addAll(_packet(1000, 0x15, _ods()));
    packets.addAll(_packet(1000, 0x16, _pcs(objectCount: 1)));
    packets.addAll(_packet(1000, 0x80, <int>[]));
    packets.addAll(_packet(4000, 0x16, _pcs(objectCount: 0)));
    packets.addAll(_packet(4000, 0x80, <int>[]));

    final cues = decodePgsSup(Uint8List.fromList(packets));

    expect(cues, hasLength(1));
    expect(cues.single.startMs, 1000);
    expect(cues.single.endMs, 4000);
    // The 8x4 display was cropped to the three opaque pixels at (2, 1).
    expect(cues.single.width, 3);
    expect(cues.single.height, 1);
    expect(cues.single.left, 2);
    expect(cues.single.top, 1);
    expect(cues.single.canvasWidth, 8);
    expect(cues.single.canvasHeight, 4);
    expect(cues.single.bytes.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    expect(_pngU32(cues.single.bytes, 16), 3);
    expect(_pngU32(cues.single.bytes, 20), 1);
  });

  test('reassembles first/last ODS fragments', () {
    final packets = <int>[];
    packets.addAll(_packet(2000, 0x14, _pds()));
    final rle = <int>[0, 0x83, 1, 0, 0];
    packets.addAll(_packet(2000, 0x15, _ods(sequence: 0x80, rle: rle.sublist(0, 2), declaredLength: 9)));
    packets.addAll(_packet(2000, 0x15, _ods(sequence: 0x40, rle: rle.sublist(2), declaredLength: 3, continuation: true)));
    packets.addAll(_packet(2000, 0x16, _pcs(objectCount: 1)));
    packets.addAll(_packet(2000, 0x80, <int>[]));
    final cues = decodePgsSup(Uint8List.fromList(packets));
    expect(cues, hasLength(1));
    expect(cues.single.width, 3);
    expect(cues.single.height, 1);
    expect(cues.single.left, 2);
    expect(cues.single.top, 1);
    expect(cues.single.canvasWidth, 8);
    expect(cues.single.canvasHeight, 4);
  });

  test('ignores truncated and malformed packets without throwing', () {
    final malformed = Uint8List.fromList(<int>[0x50, 0x47, 0, 0, 0, 1, 0, 0, 0, 0, 0x16, 0xff, 0xff]);
    expect(() => decodePgsSup(malformed), returnsNormally);
    expect(decodePgsSup(malformed), isEmpty);

    final giantPcs = _packet(0, 0x16, <int>[0xff, 0xff, 0xff, 0xff, 0, 0, 0, 1, 0, 0, 0]);
    expect(() => decodePgsSup(Uint8List.fromList(giantPcs)), returnsNormally);
  });
}

List<int> _pds() => <int>[0, 0, 1, 235, 128, 128, 255];

List<int> _ods({int sequence = 0xc0, List<int>? rle, int? declaredLength, bool continuation = false}) {
  final pixels = rle ?? <int>[0, 0x83, 1, 0, 0];
  final length = declaredLength ?? 4 + pixels.length;
  return <int>[
    0,
    1,
    0,
    sequence,
    (length >> 16) & 0xff,
    (length >> 8) & 0xff,
    length & 0xff,
    if (!continuation) 0,
    if (!continuation) 3,
    if (!continuation) 0,
    if (!continuation) 1,
    ...pixels,
  ];
}

List<int> _pcs({required int objectCount}) {
  final header = <int>[0, 8, 0, 4, 0, 0, 1, 0x80, 0, 0, objectCount];
  if (objectCount == 0) return header;
  return <int>[...header, 0, 1, 0, 0, 0, 2, 0, 1];
}

List<int> _packet(int ptsMs, int type, List<int> payload) {
  final pts = ptsMs * 90;
  return <int>[
    0x50,
    0x47,
    (pts >> 24) & 0xff,
    (pts >> 16) & 0xff,
    (pts >> 8) & 0xff,
    pts & 0xff,
    0,
    0,
    0,
    0,
    type,
    (payload.length >> 8) & 0xff,
    payload.length & 0xff,
    ...payload,
  ];
}

int _pngU32(Uint8List png, int offset) =>
    (png[offset] << 24) | (png[offset + 1] << 16) | (png[offset + 2] << 8) | png[offset + 3];
