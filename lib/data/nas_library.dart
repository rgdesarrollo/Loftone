import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../domain/models.dart';
import 'library_repository.dart';
import 'local_library.dart';
import 'webdav_client.dart';

class NasLibrary {
  final LibraryRepository repository;
  final WebDavClient dav;
  final String artworkFolder, tempFolder;
  NasLibrary(this.repository, this.dav, this.artworkFolder, this.tempFolder);
  Future<int> index(NasConfig config, String folder, CancelToken token,
    void Function(String, int) progress) async {
    final root = canonicalRemotePath(folder);
    final configuredRoot = canonicalRemotePath(config.folder);
    if (root != configuredRoot && !root.startsWith(configuredRoot == '/' ? '/' : '$configuredRoot/')) {
      throw const AppException('Selecciona una carpeta dentro de la carpeta de música configurada.');
    }
    final visited = <String>{}, seen = <String>{};
    final pending = [root];
    var count = 0;
    try {
      while (pending.isNotEmpty) {
        token.check(); final current = pending.removeLast();
        if (!visited.add(current)) continue;
        progress(current, count);
        final entries = await dav.list(config, current, token: token);
        String? folderArt;
        final cover = entries.where((e) => !e.directory && ['cover.jpg','folder.jpg','cover.png','folder.png'].contains(e.name.toLowerCase())).firstOrNull;
        if (cover != null && cover.size < 2 * 1024 * 1024) {
          try {
            final file = File(p.join(artworkFolder, '${sha256.convert(utf8.encode('${config.id}:$current'))}.cover'));
            await file.parent.create(recursive: true);
            await file.writeAsBytes(await dav.prefix(config, cover.path, 2 * 1024 * 1024, token)); folderArt = file.path;
          } catch (_) { token.check(); }
        }
        for (final entry in entries) {
          token.check();
          if (entry.directory) { pending.add(entry.path); continue; }
          if (!audioExtensions.contains(p.extension(entry.path).toLowerCase().replaceFirst('.', ''))) continue;
          final id = 'nas-${sha256.convert(utf8.encode('${config.id}:${entry.path}'))}';
          seen.add(id); final existing = await repository.track(id);
          final changed = existing == null || existing.etag != entry.etag || existing.size != entry.size;
          Map<String, dynamic> metadata = {};
          if (changed && existing?.edited != true) {
            final scratch = File(p.join(tempFolder, '$id${p.extension(entry.path)}'));
            try {
              await scratch.parent.create(recursive: true);
              await scratch.writeAsBytes(await dav.prefix(config, entry.path, 1024 * 1024, token));
              metadata = await extractMetadata(scratch.path, artworkFolder, id);
            } catch (_) { token.check(); }
            finally { if (await scratch.exists()) await scratch.delete(); }
          }
          final track = (existing ?? Track(id: id, title: p.basenameWithoutExtension(entry.name),
            artist: p.posix.basename(p.posix.dirname(current)), album: p.posix.basename(current),
            nasId: config.id, remotePath: entry.path, addedAt: DateTime.now().millisecondsSinceEpoch))
            .change({...metadata, if (metadata['artwork'] == null && folderArt != null) 'artwork': folderArt,
              'size': entry.size, 'etag': entry.etag, 'available': true});
          await repository.saveTrack(track); count++; progress(track.title, count);
        }
      }
      token.check();
      // Only a completely successful listing can mark removed remote files unavailable.
      for (final track in await repository.tracks()) {
        if (track.nasId == config.id && track.remotePath != null &&
          (track.remotePath == root || track.remotePath!.startsWith(root == '/' ? '/' : '$root/')) && !seen.contains(track.id)) {
          await repository.saveTrack(track.change({'available': false}));
        }
      }
      final saved = List<String>.from(await repository.readSetting('nasRoots:${config.id}') ?? []);
      if (!saved.contains(root)) { saved.add(root); await repository.setting('nasRoots:${config.id}', saved); }
      return count;
    } catch (_) { token.check(); rethrow; }
  }
}
