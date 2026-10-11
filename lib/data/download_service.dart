import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import 'library_repository.dart';
import 'local_library.dart';
import 'webdav_client.dart';

class DownloadService {
  final LibraryRepository repository;
  final WebDavClient dav;
  final String folder, artworkFolder;
  bool _busy = false;
  DownloadService(this.repository, this.dav, this.folder, this.artworkFolder);
  Future<int> usedBytes() async {
    if (!await Directory(folder).exists()) return 0;
    var total = 0;
    await for (final entry in Directory(folder).list(followLinks: false)) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }
  Future<void> download(Track track, NasConfig config, CancelToken token, int limitBytes,
    void Function(int, int) progress) async {
    if (_busy) throw const AppException('Ya hay una descarga en curso.');
    if (!track.remote) return;
    if (track.cachedPath != null && await File(track.cachedPath!).exists()) return;
    _busy = true;
    DavResponse? result;
    IOSink? sink;
    final dest = File(p.join(folder, '${track.id}${p.extension(track.remotePath!)}'));
    final partial = File('${dest.path}.${const Uuid().v4()}.part');
    try {
      token.check(); final used = await usedBytes();
      if (used + track.size > limitBytes) throw const AppException('No hay espacio dentro del límite de descargas. Aumenta el límite o elimina descargas.');
      await Directory(folder).create(recursive: true);
      result = await dav.request(config, track.remotePath!, token: token);
      if (result.response.statusCode != 200) throw const AppException('El NAS no entregó el archivo completo.');
      final length = result.response.contentLength;
      if (length > 0 && used + length > limitBytes) throw const AppException('La canción supera el espacio disponible para descargas.');
      sink = partial.openWrite(); var bytes = 0;
      await for (final chunk in result.response.timeout(const Duration(seconds: 20))) {
        token.check(); bytes += chunk.length;
        if (used + bytes > limitBytes) throw const AppException('Se alcanzó el límite de almacenamiento.');
        sink.add(chunk); await sink.flush(); progress(bytes, length > 0 ? length : track.size);
      }
      await sink.close(); sink = null; token.check();
      if (bytes == 0 || (length >= 0 && bytes != length)) throw const AppException('La descarga está incompleta. Vuelve a intentarlo.');
      await partial.rename(dest.path);
      final metadata = await extractMetadata(dest.path, artworkFolder, track.id);
      // Re-read to preserve favorite/metadata edits made while downloading.
      final latest = await repository.track(track.id);
      if (latest == null) { await dest.delete(); return; }
      await repository.saveTrack(latest.change({if (!latest.edited) ...metadata, 'cachedPath': dest.path}));
    } catch (e) { token.check(); throw AppException(networkMessage(e)); }
    finally {
      await sink?.close(); result?.close();
      if (await partial.exists()) await partial.delete(); _busy = false;
    }
  }
  Future<void> remove(Track track) async {
    final path = track.cachedPath;
    if (path == null) return;
    if (!p.isWithin(p.absolute(folder), p.absolute(path))) throw const AppException('La descarga no pertenece a la carpeta de caché.');
    if (await File(path).exists()) await File(path).delete();
    final latest = await repository.track(track.id);
    if (latest != null) await repository.saveTrack(latest.change({'cachedPath': null}));
  }
}
