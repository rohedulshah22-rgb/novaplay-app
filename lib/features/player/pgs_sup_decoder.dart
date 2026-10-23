import 'dart:typed_data';

/// A rendered PGS subtitle cue.
class PgsSubtitleCue {
  const PgsSubtitleCue({
    required this.startMs,
    required this.endMs,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.bytes,
  });

  final int startMs;
  final int endMs;
  final int width;
  final int height;
  final int left;
  final int top;
  final int canvasWidth;
  final int canvasHeight;
  final Uint8List bytes;
}

/// Decodes Blu-ray Presentation Graphic Stream (SUP) packets into PNG cues.
///
/// The function has no isolate-local state and only uses `dart:typed_data`, so
/// it can be passed directly to [Isolate.run] or another isolate entry point.
List<PgsSubtitleCue> decodePgsSup(Uint8List bytes) {
  return _PgsDecoder().decode(bytes);
}

const int _maxSegmentLength = 16 * 1024 * 1024;
const int _maxDimension = 8192;
const int _maxPixels = 16 * 1024 * 1024;
const int _fallbackDurationMs = 10000;

class _PgsDecoder {
  final Map<int, Map<int, _PaletteColor>> _palettes = <int, Map<int, _PaletteColor>>{};
  final Map<int, _PgsObject> _objects = <int, _PgsObject>{};
  final List<PgsSubtitleCue> _cues = <PgsSubtitleCue>[];

  _Pcs? _pcs;
  _ActiveCue? _active;

  List<PgsSubtitleCue> decode(Uint8List bytes) {
    var offset = 0;
    while (offset + 13 <= bytes.length) {
      // A SUP packet starts with the ASCII signature "PG".  Resynchronising
      // one byte at a time makes a damaged packet harmless to later packets.
      if (bytes[offset] != 0x50 || bytes[offset + 1] != 0x47) {
        offset++;
        continue;
      }

      final segmentLength = _u16(bytes, offset + 11);
      final packetEnd = offset + 13 + segmentLength;
      if (segmentLength > _maxSegmentLength || packetEnd < offset || packetEnd > bytes.length) {
        break;
      }

      final ptsMs = _ptsToMs(_u32(bytes, offset + 2));
      final type = bytes[offset + 10];
      final payload = Uint8List.sublistView(bytes, offset + 13, packetEnd);
      switch (type) {
        case 0x14: // PDS
          _readPds(payload);
        case 0x15: // ODS
          _readOds(payload);
        case 0x16: // PCS
          _readPcs(payload, ptsMs);
        case 0x80: // END of display set
          _finishDisplaySet();
      }
      offset = packetEnd;
    }

    // Streams are often truncated while being read.  Do not leave an active
    // cue with an infinite end time in that case.
    _finishActive((_active?.startMs ?? 0) + _fallbackDurationMs);
    _cues.sort((a, b) {
      final byStart = a.startMs.compareTo(b.startMs);
      return byStart != 0 ? byStart : a.endMs.compareTo(b.endMs);
    });
    return List<PgsSubtitleCue>.unmodifiable(_cues);
  }

  void _readPds(Uint8List payload) {
    if (payload.length < 2) return;
    final paletteId = payload[0];
    final entries = <int, _PaletteColor>{};
    for (var p = 2; p + 4 < payload.length; p += 5) {
      final index = payload[p];
      final y = payload[p + 1];
      final cr = payload[p + 2];
      final cb = payload[p + 3];
      final alpha = payload[p + 4];
      entries[index] = _ycbcra(y, cr, cb, alpha);
    }
    if (entries.isNotEmpty) {
      final palette = _palettes.putIfAbsent(paletteId, () => <int, _PaletteColor>{});
      palette.addAll(entries);
    }
  }

  void _readOds(Uint8List payload) {
    // object_id (2), version (1), sequence_descriptor (1), data_length (3)
    if (payload.length < 7) return;
    final objectId = _u16(payload, 0);
    final sequence = payload[3];
    final isFirst = (sequence & 0x80) != 0;
    final isLast = (sequence & 0x40) != 0;
    final declaredLength = _u24(payload, 4);
    var dataStart = 7;
    var width = 0;
    var height = 0;

    if (isFirst) {
      if (payload.length < 11 || declaredLength < 4) return;
      width = _u16(payload, 7);
      height = _u16(payload, 9);
      dataStart = 11;
      if (!_validDimensions(width, height)) return;
      _objects[objectId] = _PgsObject(width, height);
    }

    final object = _objects[objectId];
    if (object == null || dataStart > payload.length) return;
    // The ODS length includes the four-byte width/height prefix on the first
    // fragment and excludes it on continuation fragments.
    final available = payload.length - dataStart;
    final declaredDataLength = isFirst ? declaredLength - 4 : declaredLength;
    final count = _min(available, declaredDataLength);
    if (count < 0 || object.rle.length + count > _maxSegmentLength) return;
    object.rle.addAll(payload.sublist(dataStart, dataStart + count));
    if (isLast) object.complete = true;
  }

  void _readPcs(Uint8List payload, int ptsMs) {
    // width, height, frame rate, composition number, state, palette update,
    // palette id, object count.
    if (payload.length < 11) return;
    final width = _u16(payload, 0);
    final height = _u16(payload, 2);
    if (!_validDimensions(width, height)) {
      _pcs = _Pcs(width, height, payload[9], ptsMs, <_PcsObject>[], true);
      return;
    }

    final paletteId = payload[9];
    final objectCount = payload[10];
    var cursor = 11;
    final objects = <_PcsObject>[];
    for (var i = 0; i < objectCount; i++) {
      if (cursor + 8 > payload.length) return;
      final objectId = _u16(payload, cursor);
      final flags = payload[cursor + 3];
      final x = _u16(payload, cursor + 4);
      final y = _u16(payload, cursor + 6);
      cursor += 8;
      var cropX = 0;
      var cropY = 0;
      var cropWidth = 0;
      var cropHeight = 0;
      final cropped = (flags & 0x40) != 0;
      if (cropped) {
        if (cursor + 8 > payload.length) return;
        cropX = _u16(payload, cursor);
        cropY = _u16(payload, cursor + 2);
        cropWidth = _u16(payload, cursor + 4);
        cropHeight = _u16(payload, cursor + 6);
        cursor += 8;
      }
      objects.add(_PcsObject(
        objectId: objectId,
        x: x,
        y: y,
        cropped: cropped,
        cropX: cropX,
        cropY: cropY,
        cropWidth: cropWidth,
        cropHeight: cropHeight,
      ));
    }
    // Epoch/acquisition state may accompany the first complete composition;
    // it replaces the old cue but is not itself a clear when objects exist.
    _pcs = _Pcs(width, height, paletteId, ptsMs, objects, objectCount == 0);
  }

  void _finishDisplaySet() {
    final pcs = _pcs;
    if (pcs == null) return;
    if (pcs.clear || pcs.objects.isEmpty) {
      _finishActive(pcs.ptsMs);
      _pcs = null;
      return;
    }

    final rendered = _render(pcs);
    if (rendered == null) return;
    // A new display set's presentation time is the previous cue's end time.
    _finishActive(pcs.ptsMs);
    _active = _ActiveCue(
      startMs: pcs.ptsMs,
      width: rendered.width,
      height: rendered.height,
      left: rendered.left,
      top: rendered.top,
      canvasWidth: pcs.width,
      canvasHeight: pcs.height,
      png: rendered.png,
    );
    _pcs = null;
  }

  void _finishActive(int endMs) {
    final active = _active;
    if (active == null) return;
    final safeEnd = endMs > active.startMs ? endMs : active.startMs + 1;
    _cues.add(PgsSubtitleCue(
      startMs: active.startMs,
      endMs: safeEnd,
      width: active.width,
      height: active.height,
      left: active.left,
      top: active.top,
      canvasWidth: active.canvasWidth,
      canvasHeight: active.canvasHeight,
      bytes: active.png,
    ));
    _active = null;
  }

  _Rendered? _render(_Pcs pcs) {
    final palette = _palettes[pcs.paletteId];
    if (palette == null || pcs.width * pcs.height > _maxPixels) return null;
    final canvas = Uint8List(pcs.width * pcs.height * 4);
    var left = pcs.width;
    var top = pcs.height;
    var right = -1;
    var bottom = -1;

    for (final placement in pcs.objects) {
      final object = _objects[placement.objectId];
      if (object == null || !object.complete || object.rle.isEmpty) continue;
      final decoded = _decodeRle(object.width, object.height, object.rle);
      if (decoded == null) continue;
      var sourceX = 0;
      var sourceY = 0;
      var sourceWidth = object.width;
      var sourceHeight = object.height;
      if (placement.cropped) {
        sourceX = placement.cropX;
        sourceY = placement.cropY;
        sourceWidth = placement.cropWidth;
        sourceHeight = placement.cropHeight;
      }
      if (sourceX < 0 || sourceY < 0 || sourceX >= object.width || sourceY >= object.height) continue;
      sourceWidth = _min(sourceWidth, object.width - sourceX);
      sourceHeight = _min(sourceHeight, object.height - sourceY);
      if (sourceWidth <= 0 || sourceHeight <= 0) continue;
      final clippedLeft = placement.x < 0 ? 0 : placement.x;
      final clippedTop = placement.y < 0 ? 0 : placement.y;
      final clippedRight = _min(pcs.width, placement.x + sourceWidth) - 1;
      final clippedBottom = _min(pcs.height, placement.y + sourceHeight) - 1;
      if (clippedLeft > clippedRight || clippedTop > clippedBottom) continue;
      if (clippedLeft < left) left = clippedLeft;
      if (clippedTop < top) top = clippedTop;
      if (clippedRight > right) right = clippedRight;
      if (clippedBottom > bottom) bottom = clippedBottom;

      for (var row = 0; row < sourceHeight; row++) {
        final destinationY = placement.y + row;
        if (destinationY < 0 || destinationY >= pcs.height) continue;
        for (var column = 0; column < sourceWidth; column++) {
          final destinationX = placement.x + column;
          if (destinationX < 0 || destinationX >= pcs.width) continue;
          final sourceIndex = (sourceY + row) * object.width + sourceX + column;
          if (decoded.present[sourceIndex] == 0) continue;
          final color = palette[decoded.indices[sourceIndex]];
          if (color == null || color.a == 0) continue;
          _blend(canvas, (destinationY * pcs.width + destinationX) * 4, color);
        }
      }
    }

    if (right < left || bottom < top) return null;
    final width = right - left + 1;
    final height = bottom - top + 1;
    final cropped = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      final from = ((top + y) * pcs.width + left) * 4;
      final to = y * width * 4;
      cropped.setRange(to, to + width * 4, canvas, from);
    }
    return _Rendered(left, top, width, height, _png(cropped, width, height));
  }
}

class _Pcs {
  const _Pcs(this.width, this.height, this.paletteId, this.ptsMs, this.objects, this.clear);
  final int width;
  final int height;
  final int paletteId;
  final int ptsMs;
  final List<_PcsObject> objects;
  final bool clear;
}

class _PcsObject {
  const _PcsObject({
    required this.objectId,
    required this.x,
    required this.y,
    required this.cropped,
    required this.cropX,
    required this.cropY,
    required this.cropWidth,
    required this.cropHeight,
  });
  final int objectId;
  final int x;
  final int y;
  final bool cropped;
  final int cropX;
  final int cropY;
  final int cropWidth;
  final int cropHeight;
}

class _PgsObject {
  _PgsObject(this.width, this.height);
  final int width;
  final int height;
  final List<int> rle = <int>[];
  bool complete = false;
}

class _DecodedRle {
  const _DecodedRle(this.indices, this.present);
  final Uint8List indices;
  final Uint8List present;
}

_DecodedRle? _decodeRle(int width, int height, List<int> input) {
  if (!_validDimensions(width, height)) return null;
  final pixels = Uint8List(width * height);
  final present = Uint8List(width * height);
  var inputOffset = 0;
  var x = 0;
  var y = 0;
  while (inputOffset < input.length && y < height) {
    final value = input[inputOffset++];
    if (value != 0) {
      if (x < width) {
        final at = y * width + x;
        pixels[at] = value;
        present[at] = 1;
      }
      x++;
      continue;
    }
    if (inputOffset >= input.length) break;
    final control = input[inputOffset++];
    if (control == 0) {
      x = 0;
      y++;
      continue;
    }
    var runLength = 0;
    var colorIndex = 0;
    if (control < 0x40) {
      runLength = control;
    } else if (control < 0x80) {
      if (inputOffset >= input.length) break;
      runLength = ((control - 0x40) << 8) | input[inputOffset++];
    } else if (control < 0xc0) {
      if (inputOffset >= input.length) break;
      runLength = control - 0x80;
      colorIndex = input[inputOffset++];
    } else {
      if (inputOffset + 1 >= input.length) break;
      runLength = ((control - 0xc0) << 8) | input[inputOffset++];
      colorIndex = input[inputOffset++];
    }
    if (runLength == 0) continue;
    for (var count = 0; count < runLength; count++) {
      if (x < width) {
        final at = y * width + x;
        pixels[at] = colorIndex;
        present[at] = 1;
      }
      x++;
    }
  }
  return _DecodedRle(pixels, present);
}

class _PaletteColor {
  const _PaletteColor(this.r, this.g, this.b, this.a);
  final int r;
  final int g;
  final int b;
  final int a;
}

class _ActiveCue {
  const _ActiveCue({
    required this.startMs,
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.png,
  });
  final int startMs;
  final int width;
  final int height;
  final int left;
  final int top;
  final int canvasWidth;
  final int canvasHeight;
  final Uint8List png;
}

class _Rendered {
  const _Rendered(this.left, this.top, this.width, this.height, this.png);
  final int left;
  final int top;
  final int width;
  final int height;
  final Uint8List png;
}

_PaletteColor _ycbcra(int y, int cr, int cb, int alpha) {
  final red = _clampByte((y + 1.402 * (cr - 128)).round());
  final green = _clampByte((y - 0.344136 * (cb - 128) - 0.714136 * (cr - 128)).round());
  final blue = _clampByte((y + 1.772 * (cb - 128)).round());
  return _PaletteColor(red, green, blue, alpha);
}

void _blend(Uint8List canvas, int offset, _PaletteColor source) {
  final sa = source.a;
  if (sa == 255 || canvas[offset + 3] == 0) {
    canvas[offset] = source.r;
    canvas[offset + 1] = source.g;
    canvas[offset + 2] = source.b;
    canvas[offset + 3] = sa;
    return;
  }
  final da = canvas[offset + 3];
  final outA = sa + ((da * (255 - sa) + 127) ~/ 255);
  if (outA == 0) return;
  final redPremultiplied = source.r * sa + ((canvas[offset] * da * (255 - sa) + 127) ~/ 255);
  final greenPremultiplied = source.g * sa + ((canvas[offset + 1] * da * (255 - sa) + 127) ~/ 255);
  final bluePremultiplied = source.b * sa + ((canvas[offset + 2] * da * (255 - sa) + 127) ~/ 255);
  canvas[offset] = _clampByte((redPremultiplied + outA ~/ 2) ~/ outA);
  canvas[offset + 1] = _clampByte((greenPremultiplied + outA ~/ 2) ~/ outA);
  canvas[offset + 2] = _clampByte((bluePremultiplied + outA ~/ 2) ~/ outA);
  canvas[offset + 3] = outA;
}

Uint8List _png(Uint8List rgba, int width, int height) {
  final scanlines = Uint8List(height * (width * 4 + 1));
  for (var y = 0; y < height; y++) {
    final rowStart = y * (width * 4 + 1);
    scanlines[rowStart] = 0; // PNG filter type: None.
    scanlines.setRange(rowStart + 1, rowStart + 1 + width * 4, rgba, y * width * 4);
  }
  final compressed = _zlibStored(scanlines);
  final output = BytesBuilder(copy: false);
  output.add(Uint8List.fromList(<int>[137, 80, 78, 71, 13, 10, 26, 10]));
  final ihdr = Uint8List(13);
  _putU32(ihdr, 0, width);
  _putU32(ihdr, 4, height);
  ihdr[8] = 8;
  ihdr[9] = 6; // RGBA
  output.add(_pngChunk('IHDR', ihdr));
  output.add(_pngChunk('IDAT', compressed));
  output.add(_pngChunk('IEND', Uint8List(0)));
  return output.takeBytes();
}

Uint8List _zlibStored(Uint8List input) {
  final output = BytesBuilder(copy: false);
  output.add(Uint8List.fromList(<int>[0x78, 0x01]));
  var offset = 0;
  do {
    final remaining = input.length - offset;
    final length = _min(remaining, 65535);
    final finalBlock = offset + length == input.length;
    output.add(Uint8List.fromList(<int>[
      finalBlock ? 1 : 0,
      length & 0xff,
      (length >> 8) & 0xff,
      (~length) & 0xff,
      ((~length) >> 8) & 0xff,
    ]));
    if (length != 0) output.add(Uint8List.sublistView(input, offset, offset + length));
    offset += length;
  } while (offset < input.length);
  final adler = _adler32(input);
  final trailer = Uint8List(4);
  _putU32(trailer, 0, adler);
  output.add(trailer);
  return output.takeBytes();
}

Uint8List _pngChunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final chunk = Uint8List(12 + data.length);
  _putU32(chunk, 0, data.length);
  chunk.setRange(4, 8, typeBytes);
  chunk.setRange(8, 8 + data.length, data);
  _putU32(chunk, 8 + data.length, _crc32(typeBytes, data));
  return chunk;
}

int _crc32(Uint8List type, Uint8List data) {
  var crc = 0xffffffff;
  for (final value in type) {
    crc = _crcByte(crc, value);
  }
  for (final value in data) {
    crc = _crcByte(crc, value);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}

int _crcByte(int crc, int value) {
  var result = (crc ^ value) & 0xff;
  for (var i = 0; i < 8; i++) {
    result = (result & 1) != 0 ? (result >> 1) ^ 0xedb88320 : result >> 1;
  }
  return ((crc >> 8) ^ result) & 0xffffffff;
}

int _adler32(Uint8List data) {
  var a = 1;
  var b = 0;
  for (final value in data) {
    a = (a + value) % 65521;
    b = (b + a) % 65521;
  }
  return (b << 16) | a;
}

int _u16(Uint8List data, int offset) => (data[offset] << 8) | data[offset + 1];
int _u24(Uint8List data, int offset) => (data[offset] << 16) | (data[offset + 1] << 8) | data[offset + 2];
int _u32(Uint8List data, int offset) =>
    (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];

void _putU32(Uint8List data, int offset, int value) {
  data[offset] = (value >> 24) & 0xff;
  data[offset + 1] = (value >> 16) & 0xff;
  data[offset + 2] = (value >> 8) & 0xff;
  data[offset + 3] = value & 0xff;
}

int _ptsToMs(int pts) => ((pts * 1000) + 45000) ~/ 90000;
int _min(int a, int b) => a < b ? a : b;
int _clampByte(int value) => value < 0 ? 0 : (value > 255 ? 255 : value);
bool _validDimensions(int width, int height) =>
    width > 0 && height > 0 && width <= _maxDimension && height <= _maxDimension && width * height <= _maxPixels;
