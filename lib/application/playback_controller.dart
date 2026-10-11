import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import '../data/library_repository.dart';
import '../data/stream_proxy.dart';
import '../domain/models.dart';

abstract interface class AudioEngine {
  Stream<bool> get playingStream;
  Stream<bool> get completedStream;
  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<String> get errorStream;
  Future<void> open(String uri, {required bool play, required Duration position});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> volume(double value);
  Future<void> dispose();
}

class MediaKitEngine implements AudioEngine {
  final Player player = Player(configuration: const PlayerConfiguration(title: 'Loftone'));
  @override
  Stream<bool> get playingStream => player.stream.playing;
  @override
  Stream<bool> get completedStream => player.stream.completed;
  @override
  Stream<Duration> get positionStream => player.stream.position;
  @override
  Stream<Duration> get durationStream => player.stream.duration;
  @override
  Stream<String> get errorStream => player.stream.error;
  @override
  Future<void> open(String uri, {required bool play, required Duration position}) async {
    await player.open(Media(uri, start: position > Duration.zero ? position : null), play: play);
  }
  @override
  Future<void> play() => player.play();
  @override
  Future<void> pause() => player.pause();
  @override
  Future<void> stop() => player.stop();
  @override
  Future<void> seek(Duration position) => player.seek(position);
  @override
  Future<void> volume(double value) => player.setVolume(value);
  @override
  Future<void> dispose() => player.dispose();
}

class PlaybackController extends ChangeNotifier {
  final LibraryRepository repository;
  final AudioEngine engine;
  final Future<ResolvedSource> Function(Track) resolve;
  final void Function(String) reportError;
  List<String> queue = [];
  int index = 0;
  Duration position = Duration.zero, duration = Duration.zero;
  double volume = 70;
  bool playing = false, shuffle = false, muted = false, loading = false;
  String repeat = 'off';
  Track? current;
  String? _loadedId;
  final _subscriptions = <StreamSubscription>[];
  Timer? _timer;
  bool _closed = false;
  Future<void> _operations = Future.value();
  PlaybackController(this.repository, this.engine, this.resolve, this.reportError) {
    _subscriptions.add(engine.playingStream.listen((value) { playing = value; _notify(); }));
    _subscriptions.add(engine.positionStream.listen((value) {
      if (!loading && _loadedId != null) { position = value; _notify(); }
    }));
    _subscriptions.add(engine.durationStream.listen((value) {
      if (value > Duration.zero) { duration = value; _notify(); }
    }));
    _subscriptions.add(engine.completedStream.listen((value) { if (value && !loading) unawaited(next(automatic: true)); }));
    _subscriptions.add(engine.errorStream.listen((_) {
      // Native errors can contain URLs. Never display or persist raw decoder logs.
      reportError('No se pudo reproducir la canción. Comprueba el formato, que el archivo esté completo y la conexión si procede del NAS.');
      playing = false; _loadedId = null; _notify();
    }));
  }
  void _notify() { if (!_closed) notifyListeners(); }
  QueueSnapshot get snapshot => QueueSnapshot(ids: List.of(queue), index: index,
    positionMs: position.inMilliseconds, volume: volume, muted: muted, shuffle: shuffle, repeat: repeat);
  Future<void> restore() async {
    final data = await repository.readSetting('player');
    final all = await repository.tracks();
    final state = (data == null ? const QueueSnapshot() : QueueSnapshot.fromJson(Map<String,dynamic>.from(data)))
      .reconcile(all.map((t) => t.id).toSet());
    queue = state.ids; index = state.index; position = Duration(milliseconds: state.positionMs);
    volume = state.volume; muted = state.muted; shuffle = state.shuffle; repeat = state.repeat;
    current = queue.isEmpty ? null : await repository.track(queue[index]);
    duration = Duration(milliseconds: current?.durationMs ?? 0);
    await engine.volume(muted ? 0 : volume);
    // Deliberately do not open remote media or autoplay on startup.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { unawaited(persist()); });
    _notify();
  }
  Future<void> persist() => repository.setting('player', snapshot.toJson());
  Future<void> _serial(Future<void> Function() action) {
    _operations = _operations.then((_) async {
      if (_closed) return;
      try { await action(); } catch (e) {
        reportError(e is AppException ? e.message : 'No se pudo iniciar la reproducción. Comprueba el archivo y el dispositivo de audio.');
        _loadedId = null; playing = false;
      } finally { loading = false; await persist(); _notify(); }
    });
    return _operations;
  }
  Future<void> _openCurrent({bool play = true}) async {
    if (queue.isEmpty) return;
    loading = true; _notify();
    await engine.pause(); playing = false;
    current = await repository.track(queue[index]);
    if (current == null) throw const AppException('La canción ya no está en la biblioteca.');
    duration = Duration(milliseconds: current!.durationMs);
    final source = await resolve(current!);
    await engine.open(source.uri, play: play, position: position);
    _loadedId = current!.id;
    if (play) await repository.recordPlay(current!.id);
    loading = false;
  }
  Future<void> playTracks(List<Track> tracks, {int start = 0}) => _serial(() async {
    if (tracks.isEmpty) return;
    queue = tracks.map((t) => t.id).toSet().toList(); index = start.clamp(0, queue.length - 1);
    position = Duration.zero; await _openCurrent();
  });
  Future<void> toggle() => _serial(() async {
    if (current == null) return;
    if (playing) { await engine.pause(); }
    else if (_loadedId != current!.id) { await _openCurrent(); }
    else { await engine.play(); }
  });
  Future<void> next({bool automatic = false}) => _serial(() async {
    if (queue.isEmpty) return;
    if (automatic && repeat == 'one') {
      position = Duration.zero; await _openCurrent(); return;
    }
    if (shuffle && queue.length > 1) {
      index = (index + 1 + Random().nextInt(queue.length - 1)) % queue.length;
    } else if (index + 1 < queue.length) { index++; }
    else if (repeat == 'all' || !automatic) { index = 0; }
    else { await engine.pause(); position = Duration.zero; _loadedId = null; playing = false; return; }
    position = Duration.zero; await _openCurrent();
  });
  Future<void> previous() => _serial(() async {
    if (queue.isEmpty) return;
    if (position.inSeconds > 3 && _loadedId != null) { position = Duration.zero; await engine.seek(position); return; }
    index = (index - 1 + queue.length) % queue.length; position = Duration.zero; await _openCurrent();
  });
  Future<void> seek(Duration value) => _serial(() async {
    position = value;
    if (_loadedId != null) await engine.seek(value);
  });
  Future<void> setVolume(double value) async { volume = value.clamp(0, 100); muted = false; await engine.volume(volume); await persist(); _notify(); }
  Future<void> toggleMute() async { muted = !muted; await engine.volume(muted ? 0 : volume); await persist(); _notify(); }
  Future<void> toggleShuffle() async { shuffle = !shuffle; await persist(); _notify(); }
  Future<void> cycleRepeat() async { repeat = switch (repeat) { 'off' => 'all', 'all' => 'one', _ => 'off' }; await persist(); _notify(); }
  Future<void> add(Track track) async { if (!queue.contains(track.id)) queue.add(track.id); if (current == null) { index = 0; current = track; } await persist(); _notify(); }
  Future<void> jump(int value) => _serial(() async { index = value; position = Duration.zero; await _openCurrent(); });
  Future<void> reorder(int from, int to) => _serial(() async {
    final id = current?.id;
    queue.insert(to, queue.removeAt(from));
    index = id == null ? 0 : queue.indexOf(id).clamp(0, queue.length - 1);
  });
  Future<void> remove(String id) => _serial(() async {
    final wasCurrent = current?.id == id;
    queue.remove(id);
    if (wasCurrent) {
      await engine.stop(); _loadedId = null; position = Duration.zero; playing = false;
      index = queue.isEmpty ? 0 : index.clamp(0, queue.length - 1);
      current = queue.isEmpty ? null : await repository.track(queue[index]);
    } else if (current != null) { index = queue.indexOf(current!.id).clamp(0, max(0, queue.length - 1)); }
  });
  Future<void> shutdown() async {
    if (_closed) return;
    _timer?.cancel(); await _operations; await persist(); _closed = true;
    for (final sub in _subscriptions) { await sub.cancel(); }
    await engine.dispose();
  }
}
