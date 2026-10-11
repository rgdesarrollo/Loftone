import 'dart:io';
import 'dart:isolate';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import 'library_repository.dart';

Future<String> fileFingerprint(String path) => Isolate.run(() async =>
  (await sha256.bind(File(path).openRead()).first).toString());

Future<Map<String, dynamic>> extractMetadata(String path, String artFolder, String id) => Isolate.run(() {
  final values = <String, dynamic>{};
  try {
    final meta = readMetadata(File(path), getImage: true);
    if (meta.title?.trim().isNotEmpty == true) values['title'] = meta.title!.trim();
    if (meta.artist?.trim().isNotEmpty == true) values['artist'] = meta.artist!.trim();
    if (meta.album?.trim().isNotEmpty == true) values['album'] = meta.album!.trim();
    values['durationMs'] = meta.duration?.inMilliseconds ?? 0;
    values['trackNumber'] = meta.trackNumber ?? 0;
    if (meta.pictures.isNotEmpty && meta.pictures.first.bytes.length < 12 * 1024 * 1024) {
      final picture = meta.pictures.first;
      final out = File(p.join(artFolder, '$id.cover'));
      out.parent.createSync(recursive: true);
      out.writeAsBytesSync(picture.bytes, flush: true);
      values['artwork'] = out.path;
    }
  } catch (_) { /* Missing or unsupported tags do not prevent audio playback. */ }
  return values;
});

Future<void> copyCancellable(File input, File destination, CancelToken token,
    {void Function(int bytes)? progress}) async {
  await destination.parent.create(recursive: true);
  final partial = File('${destination.path}.${const Uuid().v4()}.part');
  final output = partial.openWrite();
  var bytes = 0;
  try {
    await for (final chunk in input.openRead()) {
      token.check(); output.add(chunk); bytes += chunk.length;
      await output.flush(); progress?.call(bytes);
    }
    await output.close(); token.check();
    await partial.rename(destination.path);
  } catch (_) {
    await output.close();
    if (await partial.exists()) await partial.delete();
    rethrow;
  }
}

class ImportReport {
  int added = 0, duplicates = 0, skipped = 0;
  final List<String> errors = [];
}

class LocalLibrary {
  final LibraryRepository repository;
  final String artworkFolder;
  String musicFolder;
  LocalLibrary(this.repository, this.musicFolder, this.artworkFolder);
  Stream<String> discover(List<String> inputs, CancelToken token) async* {
    for (final path in inputs) {
      token.check();
      if (await FileSystemEntity.isDirectory(path)) {
        await for (final entity in Directory(path).list(recursive: true, followLinks: false)) {
          token.check();
          if (entity is File) yield entity.path;
        }
      } else { yield path; }
    }
  }
  Future<ImportReport> import(List<String> inputs, {required bool copy,
    required CancelToken token, required void Function(String, int) progress}) async {
    final report = ImportReport();
    var processed = 0;
    await for (final path in discover(inputs, token)) {
      token.check();
      if (!audioExtensions.contains(p.extension(path).toLowerCase().replaceFirst('.', ''))) { report.skipped++; continue; }
      progress(p.basename(path), processed);
      try {
        final hash = await fileFingerprint(path);
        token.check();
        final existing = await repository.duplicate(hash);
        if (existing != null && existing.path != null && await File(existing.path!).exists()) {
          report.duplicates++; processed++; continue;
        }
        final id = existing?.id ?? const Uuid().v4();
        final destination = copy ? p.join(musicFolder, '$id${p.extension(path).toLowerCase()}') : path;
        if (copy) {
          await copyCancellable(File(path), File(destination), token);
          if (await fileFingerprint(destination) != hash) {
            await File(destination).delete();
            throw const AppException('El archivo cambió durante la copia; vuelve a importarlo.');
          }
        }
        final metadata = await extractMetadata(destination, artworkFolder, id);
        final track = (existing ?? Track(id: id, title: p.basenameWithoutExtension(path),
          addedAt: DateTime.now().millisecondsSinceEpoch)).change({
          if (existing?.edited != true) ...metadata,
          'path': destination, 'fingerprint': hash, 'managed': copy, 'available': true,
          'size': await File(destination).length()});
        await repository.saveTrack(track);
        report.added++;
      } catch (e) {
        token.check();
        report.errors.add('${p.basename(path)}: no se pudo importar. Comprueba el archivo y sus permisos.');
      }
      processed++;
    }
    return report;
  }
  Future<void> relocate(Track track, String newPath) async {
    if (!await File(newPath).exists()) throw const AppException('El archivo seleccionado no existe.');
    final fingerprint = await fileFingerprint(newPath);
    if (track.fingerprint != null && track.fingerprint != fingerprint) {
      throw const AppException('El contenido no coincide con la canción original.');
    }
    await repository.saveTrack(track.change({'path': newPath, 'managed': false, 'available': true}));
  }
  Future<void> checkMissing() async {
    for (final track in await repository.tracks()) {
      if (!track.remote) {
        final available = track.path != null && await File(track.path!).exists();
        if (track.available != available) await repository.saveTrack(track.change({'available': available}));
      }
    }
  }
  Future<void> migrate(String selectedFolder, CancelToken token, void Function(String, int) progress) async {
    final target = p.join(selectedFolder, 'Loftone - Biblioteca');
    if (p.equals(p.normalize(target), p.normalize(musicFolder))) return;
    final staged = <Track>[];
    for (final track in await repository.tracks()) {
      if (!track.managed || track.path == null) continue;
      token.check(); progress(track.title, staged.length);
      final dest = p.join(target, p.basename(track.path!));
      if (await File(dest).exists()) {
        if (await fileFingerprint(dest) != track.fingerprint) {
          throw const AppException('La carpeta de destino contiene un archivo distinto con el mismo identificador.');
        }
      } else { await copyCancellable(File(track.path!), File(dest), token); }
      if (await fileFingerprint(dest) != track.fingerprint) throw const AppException('No se pudo verificar la copia. La biblioteca anterior sigue activa.');
      staged.add(track.change({'path': dest, 'available': true}));
    }
    token.check(); await repository.commitMigration(staged, target); musicFolder = target;
    // Keep prior copies as a recoverable backup; never remove user originals.
  }
}
