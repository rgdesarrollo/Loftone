import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:loftone/data/library_repository.dart';
import 'package:loftone/data/local_library.dart';
import 'package:loftone/data/stream_proxy.dart';
import 'package:loftone/domain/models.dart';
import 'support/fixtures.dart';

void main() {
  late Directory root;
  late LibraryRepository repository;
  late LocalLibrary library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('loftone_test_');
    repository = await LibraryRepository.open(p.join(root.path, 'library.sqlite'));
    library = LocalLibrary(repository, p.join(root.path, 'music'), p.join(root.path, 'art'));
  });
  tearDown(() async { await repository.close(); await root.delete(recursive: true); });

  test('La copia y la playlist sobreviven al reinicio y a mover el original', () async {
    final original = await writeTestWave(p.join(root.path, 'original', 'Mi canción.wav'));
    final result = await library.import([original.path], copy: true, token: CancelToken(), progress: (_, count) {});
    expect(result.added, 1);
    final track = (await repository.tracks()).single;
    expect(track.managed, isTrue); expect(track.durationMs, greaterThan(0));
    await repository.savePlaylist(MusicPlaylist('mix', 'Mi mezcla', [track.id]));
    await original.rename(p.join(root.path, 'original', 'movida.wav'));
    await repository.close(); repository = await LibraryRepository.open(p.join(root.path, 'library.sqlite'));
    final restored = (await repository.tracks()).single;
    expect((await repository.playlists()).single.trackIds, [track.id]);
    expect(await File(restored.path!).exists(), isTrue);
    expect(await fileFingerprint(restored.path!), restored.fingerprint);
    final source = await resolveSource(restored, () async => throw StateError('No debe consultar red'));
    expect(source.local, isTrue);
  });
  test('Detecta duplicados por contenido aunque tengan otro nombre', () async {
    final file = await writeTestWave(p.join(root.path, 'first.wav'));
    final other = await file.copy(p.join(root.path, 'another.wav'));
    final result = await library.import([file.path, other.path], copy: true, token: CancelToken(), progress: (_, count) {});
    expect(result.added, 1); expect(result.duplicates, 1); expect(await repository.tracks(), hasLength(1));
  });
  test('Referencias ausentes se identifican y pueden localizarse por huella', () async {
    final file = await writeTestWave(p.join(root.path, 'original.wav'));
    await library.import([file.path], copy: false, token: CancelToken(), progress: (_, count) {});
    final moved = await file.rename(p.join(root.path, 'moved.wav'));
    await library.checkMissing(); final track = (await repository.tracks()).single;
    expect(track.available, isFalse);
    await expectLater(resolveSource(track, () async => ''), throwsA(isA<AppException>()));
    await library.relocate(track, moved.path); expect((await repository.tracks()).single.available, isTrue);
    await repository.removeTrack(track.id); expect(await moved.exists(), isTrue);
  });
  test('Playlists mixtas, reordenación y edición no destruyen referencias', () async {
    const first = Track(id: 'a', title: 'A'); const second = Track(id: 'b', title: 'B', nasId: 'nas', remotePath: '/music/b.flac');
    await repository.saveTrack(first); await repository.saveTrack(second);
    await repository.savePlaylist(const MusicPlaylist('list', 'Local + NAS', ['a','b']));
    await repository.saveTrack(first.change({'title': 'Editada', 'favorite': true}));
    expect((await repository.playlists()).single.trackIds, ['a','b']);
    await repository.savePlaylist(const MusicPlaylist('list', 'Otra', ['b','a','b']));
    expect((await repository.playlists()).single.trackIds, ['b','a']);
    await repository.removeTrack('b'); expect((await repository.playlists()).single.trackIds, ['a']);
  });
  test('Eliminar varias canciones limpia también sus referencias en playlists', () async {
    const first = Track(id: 'a', title: 'A');
    const second = Track(id: 'b', title: 'B');
    const third = Track(id: 'c', title: 'C');
    await repository.saveTrack(first); await repository.saveTrack(second); await repository.saveTrack(third);
    await repository.savePlaylist(const MusicPlaylist('list', 'Álbum', ['a', 'b', 'c']));
    await repository.removeTracks(['a', 'b', 'b']);
    expect((await repository.tracks()).map((track) => track.id), ['c']);
    expect((await repository.playlists()).single.trackIds, ['c']);
  });
  test('La copia sin conexión tiene prioridad y cae a remoto si falta', () async {
    final cached = await writeTestWave(p.join(root.path, 'download.wav'));
    final track = Track(id: 'nas-a', title: 'NAS', nasId: 'nas', remotePath: '/music/a.wav', cachedPath: cached.path);
    var calls = 0;
    Future<String> remote() async { calls++; return 'https://nas/music/a.wav'; }
    expect((await resolveSource(track, remote)).uri, cached.path); expect(calls, 0);
    await cached.delete(); expect((await resolveSource(track, remote)).local, isFalse); expect(calls, 1);
  });
  test('Migración verifica las copias y cambia las rutas en una transacción', () async {
    final file = await writeTestWave(p.join(root.path, 'original.wav'));
    await library.import([file.path], copy: true, token: CancelToken(), progress: (_, count) {});
    final old = (await repository.tracks()).single;
    await library.migrate(p.join(root.path, 'destination'), CancelToken(), (_, count) {});
    final next = (await repository.tracks()).single;
    expect(next.path, isNot(old.path)); expect(await File(old.path!).exists(), isTrue);
    expect(await fileFingerprint(next.path!), old.fingerprint);
    expect(await repository.readSetting('libraryFolder'), library.musicFolder);
  });
  test('Cancelación de copia no deja archivos parciales ni toca el original', () async {
    final file = await writeTestWave(p.join(root.path, 'original.wav'));
    final token = CancelToken(); final destination = File(p.join(root.path, 'copy.wav'));
    await expectLater(copyCancellable(file, destination, token, progress: (_) => token.cancel()), throwsA(isA<AppException>()));
    expect(await destination.exists(), isFalse); expect(await file.exists(), isTrue);
    expect(await root.list().where((e) => e.path.endsWith('.part')).length, 0);
  });
}
