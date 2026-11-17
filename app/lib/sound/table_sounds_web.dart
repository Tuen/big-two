import "dart:js_interop";
import "dart:js_interop_unsafe";

import "package:flutter/services.dart";

JSObject? _ctx;

void unlockAudio() {
  try {
    _ctx ??= _makeContext();
    final ctx = _ctx;
    if (ctx == null) return;
    final resumed = ctx.callMethod("resume".toJS);
    if (resumed != null && resumed.isA<JSPromise>()) {
      (resumed as JSPromise).toDart.then((_) {}, onError: (_) {});
    }
  } catch (_) {
    _ctx = null;
  }
}

JSObject? _makeContext() {
  final ctor = globalContext.getProperty("AudioContext".toJS);
  final webkit = globalContext.getProperty("webkitAudioContext".toJS);
  final JSAny? chosen = ctor != null && ctor.isA<JSFunction>() ? ctor : webkit;
  if (chosen == null || !chosen.isA<JSFunction>()) return null;
  return (chosen as JSFunction).callAsConstructor<JSObject>();
}

void playDeal() {
  _tone(523, 0, 0.07, 0.12, "triangle");
  _tone(659, 0.07, 0.07, 0.12, "triangle");
  _tone(784, 0.14, 0.07, 0.12, "triangle");
  _tone(1046, 0.21, 0.12, 0.14, "triangle");
}

void playCard() {
  _tone(880, 0, 0.06, 0.16, "square");
  _tone(1320, 0.03, 0.08, 0.08, "sine");
}

void playPass() {
  _tone(240, 0, 0.12, 0.14, "sine");
  _tone(160, 0.08, 0.12, 0.08, "sine");
}

void playYourTurn() {
  _tone(660, 0, 0.09, 0.14, "sine");
  _tone(880, 0.1, 0.14, 0.16, "sine");
}

int _flourishGen = 0;
final List<JSObject> _flourishSources = [];

void playWinFlourish() {
  final gen = ++_flourishGen;
  _stopSources();
  _playFlourish(gen);
}

void stopWinFlourish() {
  _flourishGen++;
  _stopSources();
}

void _stopSources() {
  for (final source in _flourishSources) {
    try {
      source.callMethod("stop".toJS);
    } catch (_) {
      // Already stopped.
    }
  }
  _flourishSources.clear();
}

Future<void> _playFlourish(int gen) async {
  try {
    final swoosh = await rootBundle.load("assets/sounds/swoosh.wav");
    final fanfare = await rootBundle.load("assets/sounds/fanfare.wav");
    if (gen != _flourishGen) return;
    await _playBuffer(swoosh, 0, gen);
    await _playBuffer(fanfare, 0.08, gen);
  } catch (_) {
    // A missing file or a blocked device must not stop the celebration.
  }
}

Future<void> _playBuffer(ByteData data, double delay, int gen) async {
  final ctx = _ctx;
  if (ctx == null || gen != _flourishGen) return;
  final bytes = Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  final arrayBuffer = bytes.toJS.getProperty("buffer".toJS);
  final decoded = ctx.callMethod("decodeAudioData".toJS, arrayBuffer);
  if (decoded == null || !decoded.isA<JSPromise>()) return;
  final buffer = await (decoded as JSPromise).toDart;
  if (gen != _flourishGen || buffer == null || !buffer.isA<JSObject>()) return;
  final source = ctx.callMethod("createBufferSource".toJS) as JSObject;
  source.setProperty("buffer".toJS, buffer);
  final destination = ctx.getProperty("destination".toJS) as JSObject;
  source.callMethod("connect".toJS, destination);
  final now = (ctx.getProperty("currentTime".toJS) as JSNumber).toDartDouble;
  source.callMethod("start".toJS, (now + delay).toJS);
  _flourishSources.add(source);
}

void playHandOver(bool roundOver) {
  _tone(523, 0, 0.1, 0.14, "triangle");
  _tone(659, 0.1, 0.1, 0.14, "triangle");
  _tone(784, 0.2, 0.16, 0.16, "triangle");
  if (roundOver) {
    _tone(1046, 0.36, 0.22, 0.16, "triangle");
  }
}

void _tone(num freq, num start, num duration, num volume, String type) {
  final ctx = _ctx;
  if (ctx == null) return;
  try {
    final now = (ctx.getProperty("currentTime".toJS) as JSNumber).toDartDouble;
    final osc = ctx.callMethod("createOscillator".toJS) as JSObject;
    final gain = ctx.callMethod("createGain".toJS) as JSObject;
    osc.setProperty("type".toJS, type.toJS);
    final frequency = osc.getProperty("frequency".toJS) as JSObject;
    frequency.setProperty("value".toJS, freq.toJS);
    final amp = gain.getProperty("gain".toJS) as JSObject;
    final begin = now + start.toDouble();
    final end = begin + duration.toDouble();
    amp.callMethod("setValueAtTime".toJS, volume.toJS, begin.toJS);
    amp.callMethod("exponentialRampToValueAtTime".toJS, 0.001.toJS, end.toJS);
    final destination = ctx.getProperty("destination".toJS) as JSObject;
    osc.callMethod("connect".toJS, gain);
    gain.callMethod("connect".toJS, destination);
    osc.callMethod("start".toJS, begin.toJS);
    osc.callMethod("stop".toJS, (end + 0.02).toJS);
  } catch (_) {
    // Ignore a single failed tone. The table keeps playing.
  }
}
