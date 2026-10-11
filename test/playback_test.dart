import 'package:flutter_test/flutter_test.dart';
import 'package:loftone/application/playback_controller.dart';
import 'package:loftone/data/library_repository.dart';
import 'package:loftone/data/stream_proxy.dart';
import 'package:loftone/domain/models.dart';
import 'support/fixtures.dart';

void main() {
  test('Restaura cola, posición y volumen sin abrir audio ni reproducir', () async {
    final repository = await LibraryRepository.open(':memory:');
    await repository.saveTrack(const Track(id: 'a', title: 'A', durationMs: 60000));
    await repository.saveTrack(const Track(id: 'b', title: 'B', durationMs: 60000));
    await repository.setting('player', const QueueSnapshot(ids: ['gone','a','b'], index: 2, positionMs: 12400,
      volume: 38, muted: true, repeat: 'all', shuffle: true).toJson());
    final engine = FakeAudioEngine();
    final controller = PlaybackController(repository, engine, (_) async => const ResolvedSource('file.wav', true), (error) => fail(error));
    await controller.restore();
    expect(controller.queue, ['a','b']); expect(controller.index, 1); expect(controller.position.inMilliseconds, 12400);
    expect(controller.volume, 38); expect(controller.muted, isTrue); expect(controller.playing, isFalse); expect(engine.opens, 0);
    await controller.toggle(); expect(engine.isPlaying, isTrue); expect(engine.lastPosition.inMilliseconds, 12400);
    await controller.reorder(1, 0); expect(controller.index, 0); expect(controller.current!.id, 'b');
    await controller.seek(const Duration(seconds: 20)); await controller.shutdown();
    final nextEngine = FakeAudioEngine();
    final restored = PlaybackController(repository, nextEngine, (_) async => const ResolvedSource('file.wav', true), (error) => fail(error));
    await restored.restore(); expect(restored.position.inSeconds, 20); expect(nextEngine.opens, 0);
    expect(restored.queue, ['b','a']); await restored.shutdown(); await repository.close();
  });
  test('Quitar canción actual deja la cola pausada y persiste la nueva selección', () async {
    final repository = await LibraryRepository.open(':memory:');
    const a = Track(id: 'a', title: 'A'); const b = Track(id: 'b', title: 'B');
    await repository.saveTrack(a); await repository.saveTrack(b);
    final engine = FakeAudioEngine();
    final controller = PlaybackController(repository, engine, (_) async => const ResolvedSource('x.wav', true), (error) => fail(error));
    await controller.restore(); await controller.playTracks([a,b]); await controller.remove('a');
    expect(controller.queue, ['b']); expect(controller.current?.id, 'b'); expect(controller.playing, isFalse);
    await controller.shutdown(); await repository.close();
  });
}
