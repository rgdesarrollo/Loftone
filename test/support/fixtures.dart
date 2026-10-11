import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:loftone/application/playback_controller.dart';
import 'package:loftone/data/webdav_client.dart';

Future<File> writeTestWave(String path, {int seconds = 6}) async {
  const rate = 44100;
  final frames = rate * seconds;
  final bytes = ByteData(44 + frames * 2);
  void text(int offset, String value) { for (var i = 0; i < value.length; i++) { bytes.setUint8(offset + i, value.codeUnitAt(i)); } }
  text(0, 'RIFF'); bytes.setUint32(4, 36 + frames * 2, Endian.little); text(8, 'WAVE');
  text(12, 'fmt '); bytes.setUint32(16, 16, Endian.little); bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little); bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little); bytes.setUint16(32, 2, Endian.little); bytes.setUint16(34, 16, Endian.little);
  text(36, 'data'); bytes.setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) { bytes.setInt16(44 + i * 2, (sin(2 * pi * 440 * i / rate) * 1000).round(), Endian.little); }
  final file = File(path); await file.parent.create(recursive: true); await file.writeAsBytes(bytes.buffer.asUint8List()); return file;
}

class MemoryCredentials implements CredentialStore {
  final values = <String,String>{};
  @override
  Future<String?> read(String id) async => values[id];
  @override
  Future<void> write(String id, String password) async { values[id] = password; }
}

class FakeAudioEngine implements AudioEngine {
  final playing = StreamController<bool>.broadcast(sync: true);
  final completed = StreamController<bool>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration>.broadcast(sync: true);
  final errors = StreamController<String>.broadcast(sync: true);
  String? uri;
  bool isPlaying = false;
  int opens = 0;
  Duration lastPosition = Duration.zero;
  @override
  Stream<bool> get playingStream => playing.stream;
  @override
  Stream<bool> get completedStream => completed.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration> get durationStream => durations.stream;
  @override
  Stream<String> get errorStream => errors.stream;
  @override
  Future<void> open(String uri, {required bool play, required Duration position}) async {
    this.uri = uri; opens++; lastPosition = position; isPlaying = play; playing.add(play);
  }
  @override
  Future<void> play() async { isPlaying = true; playing.add(true); }
  @override
  Future<void> pause() async { isPlaying = false; playing.add(false); }
  @override
  Future<void> stop() async { isPlaying = false; playing.add(false); }
  @override
  Future<void> seek(Duration position) async { lastPosition = position; positions.add(position); }
  @override
  Future<void> volume(double value) async { }
  @override
  Future<void> dispose() async { await playing.close(); await completed.close(); await positions.close(); await durations.close(); await errors.close(); }
}
