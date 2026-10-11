import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../data/download_service.dart';
import '../data/library_repository.dart';
import '../data/local_library.dart';
import '../data/nas_library.dart';
import '../data/stream_proxy.dart';
import '../data/webdav_client.dart';
import '../domain/models.dart';
import 'playback_controller.dart';

final appProvider = ChangeNotifierProvider<AppController>((ref) => throw StateError('Aplicación sin inicializar'));

class AppController extends ChangeNotifier {
  final LibraryRepository repository;
  final LocalLibrary local;
  final WebDavClient dav;
  final StreamProxy proxy;
  final NasLibrary nasLibrary;
  final DownloadService downloads;
  final String dataFolder;
  late final PlaybackController playback;
  List<Track> tracks = [];
  List<MusicPlaylist> playlists = [];
  List<NasConfig> servers = [];
  List<String> history = [];
  int page = 0, accent = 0xffb6ef72, cacheLimitMb = 2048;
  bool dark = true, copyOnImport = true, busy = false, _closed = false;
  String query = '', sort = 'added', status = '', taskLabel = '';
  bool isError = false;
  double? taskProgress;
  CancelToken? token;
  String? selectedPlaylist, group;
  AppController(this.repository, this.local, this.dav, this.proxy, this.nasLibrary,
    this.downloads, this.dataFolder, {AudioEngine? engine}) {
    playback = PlaybackController(repository, engine ?? MediaKitEngine(), (track) => resolveSource(track, () async {
      final config = servers.where((s) => s.id == track.nasId).firstOrNull;
      if (config == null) throw const AppException('Configura el NAS de esta canción para reproducirla.');
      return proxy.url(config, track.remotePath!);
    }), (message) => messageToUser(message, error: true));
    playback.addListener(_refresh);
    proxy.onError = (message) => messageToUser(message, error: true);
  }
  static Future<AppController> create() async {
    final folder = await getApplicationSupportDirectory(); await folder.create(recursive: true);
    await _migrateLegacyDatabase(folder.path);
    final repository = await LibraryRepository.open(p.join(folder.path, 'loftone.sqlite'));
    final music = await repository.readSetting('libraryFolder') as String? ?? p.join(folder.path, 'Musica');
    final artwork = p.join(folder.path, 'Caratulas');
    final dav = WebDavClient(const SystemCredentialStore());
    final app = AppController(repository, LocalLibrary(repository, music, artwork), dav,
      StreamProxy(dav), NasLibrary(repository, dav, artwork, p.join(folder.path, 'Temporal')),
      DownloadService(repository, dav, p.join(folder.path, 'Descargas'), artwork), folder.path);
    await app.initialize(); return app;
  }
  /// Copia la base de datos creada con el nombre antiguo de la app
  /// (mi_musica.sqlite) al nuevo nombre para conservar la biblioteca existente.
  static Future<void> _migrateLegacyDatabase(String folderPath) async {
    final legacy = p.join(folderPath, 'mi_musica.sqlite');
    final target = p.join(folderPath, 'loftone.sqlite');
    if (!await File(legacy).exists() || await File(target).exists()) return;
    for (final suffix in ['', '-wal', '-shm']) {
      final source = File('$legacy$suffix');
      if (await source.exists()) {
        await source.copy('$target$suffix');
      }
    }
  }
  void _refresh() { if (!_closed) notifyListeners(); }
  Future<void> initialize() async {
    dark = await repository.readSetting('dark') as bool? ?? true;
    accent = await repository.readSetting('accent') as int? ?? 0xffb6ef72;
    cacheLimitMb = await repository.readSetting('cacheLimitMb') as int? ?? 2048;
    copyOnImport = await repository.readSetting('copyOnImport') as bool? ?? true;
    servers = ((await repository.readSetting('servers') as List?) ?? []).map((m) => NasConfig.fromJson(Map<String,dynamic>.from(m))).toList();
    await local.checkMissing(); await reload(); await playback.restore();
  }
  Future<void> reload() async { tracks = await repository.tracks(); playlists = await repository.playlists(); history = await repository.history(); _refresh(); }
  void messageToUser(String text, {bool error = false}) { status = text; isError = error; _refresh(); }
  void navigate(int target, {String? playlist, String? selectedGroup}) { page = target; selectedPlaylist = playlist; group = selectedGroup; query = ''; _refresh(); }
  void search(String value) { query = value; _refresh(); }
  void setSort(String value) { sort = value; _refresh(); }
  MusicPlaylist? get activePlaylist => playlists.where((p) => p.id == selectedPlaylist).firstOrNull;
  List<Track> get visibleTracks {
    var result = tracks.where((t) {
      if (page == 5 && !t.favorite) return false;
      if (page == 4 && activePlaylist != null && !activePlaylist!.trackIds.contains(t.id)) return false;
      if (page == 2 && group != null && '${t.artist}\u0000${t.album}' != group) return false;
      if (page == 3 && group != null && t.artist != group) return false;
      return '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(query.toLowerCase());
    }).toList();
    if (page == 4 && activePlaylist != null) {
      result.sort((a,b) => activePlaylist!.trackIds.indexOf(a.id).compareTo(activePlaylist!.trackIds.indexOf(b.id)));
    } else {
      result.sort((a,b) => switch(sort) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'artist' => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        'album' => a.album.toLowerCase().compareTo(b.album.toLowerCase()),
        'duration' => a.durationMs.compareTo(b.durationMs),
        _ => b.addedAt.compareTo(a.addedAt),
      });
    }
    return result;
  }
  Future<void> guard(Future<void> Function() action) async {
    try { await action(); } catch (e) { messageToUser(e is AppException ? e.message : networkMessage(e), error: true); }
  }
  Future<void> task(String label, Future<void> Function(CancelToken) action) async {
    if (busy) { messageToUser('Espera a que termine la operación actual o cancélala.', error: true); return; }
    busy = true; token = CancelToken(); taskLabel = label; taskProgress = null; _refresh();
    try { await action(token!); }
    catch (e) { messageToUser(e is AppException ? e.message : networkMessage(e), error: true); }
    finally { busy = false; token = null; taskProgress = null; await reload(); }
  }
  void progress(String name, int count) { taskLabel = '$name · $count completadas'; _refresh(); }
  Future<void> importPaths(List<String> paths, {bool? copy}) => task('Preparando importación…', (token) async {
    final report = await local.import(paths, copy: copy ?? copyOnImport, token: token, progress: progress);
    messageToUser('${report.added} añadidas · ${report.duplicates} duplicadas · ${report.skipped} archivos omitidos${report.errors.isEmpty ? '' : '\n${report.errors.join('\n')}'}', error: report.errors.isNotEmpty);
  });
  Future<void> favorite(Track track) => guard(() async {
    final latest = await repository.track(track.id);
    if (latest != null) await repository.saveTrack(latest.change({'favorite': !latest.favorite})); await reload();
  });
  Future<void> removeTrack(Track track) => guard(() async { await playback.remove(track.id); await repository.removeTrack(track.id); await reload(); messageToUser('Canción quitada de la biblioteca. Su archivo se conserva.'); });
  Future<void> editTrack(Track track, Map<String,dynamic> values) => guard(() async {
    final latest = await repository.track(track.id);
    if (latest != null) await repository.saveTrack(latest.change({...values, 'edited': true})); await reload();
  });
  Future<void> savePlaylist(String name, {MusicPlaylist? existing}) => guard(() async {
    if (name.trim().isEmpty) throw const AppException('Escribe un nombre para la playlist.');
    final playlist = MusicPlaylist(existing?.id ?? const Uuid().v4(), name.trim(), existing?.trackIds ?? []);
    await repository.savePlaylist(playlist); await reload(); navigate(4, playlist: playlist.id);
  });
  Future<void> playlistAdd(MusicPlaylist playlist, Track track) => guard(() async {
    final latest = playlists.where((p) => p.id == playlist.id).firstOrNull ?? playlist;
    await repository.savePlaylist(MusicPlaylist(latest.id, latest.name, [...latest.trackIds, track.id])); await reload(); messageToUser('Añadida a «${playlist.name}».');
  });
  Future<void> playlistRemove(MusicPlaylist playlist, Track track) => guard(() async {
    await repository.savePlaylist(MusicPlaylist(playlist.id, playlist.name, playlist.trackIds.where((id) => id != track.id).toList())); await reload();
  });
  Future<void> reorderPlaylist(int from, int to) => guard(() async {
    final playlist = activePlaylist; if (playlist == null || query.isNotEmpty) return;
    final ids = List<String>.from(playlist.trackIds);
    ids.insert(to, ids.removeAt(from)); await repository.savePlaylist(MusicPlaylist(playlist.id, playlist.name, ids)); await reload();
  });
  Future<void> saveServer(NasConfig config, String password) async {
    config.origin; canonicalRemotePath(config.folder);
    if (config.username.trim().isEmpty || config.username.contains(':')) throw const AppException('Introduce un usuario válido, sin dos puntos.');
    if (password.isNotEmpty) {
      await dav.credentials.write(config.id, password);
    } else if (await dav.credentials.read(config.id) == null) {
      throw const AppException('Introduce la contraseña para guardar esta conexión.');
    }
    final next = [...servers.where((s) => s.id != config.id), config];
    await repository.setting('servers', next.map((s) => s.toJson()).toList()); servers = next; _refresh();
  }
  Future<void> indexFolder(NasConfig config, String folder) => task('Conectando con ${config.name}…', (token) async {
    final count = await nasLibrary.index(config, folder, token, progress); messageToUser('$count canciones indexadas.');
  });
  Future<void> refreshNas(NasConfig config) => task('Actualizando índice…', (token) async {
    final roots = List<String>.from(await repository.readSetting('nasRoots:${config.id}') ?? [config.folder]);
    for (final root in roots) { await nasLibrary.index(config, root, token, progress); }
    messageToUser('Índice actualizado.');
  });
  Future<void> downloadTracks(List<Track> selected) => task('Preparando descargas…', (token) async {
    var count = 0;
    for (final track in selected.where((t) => t.remote)) {
      token.check(); final server = servers.where((s) => s.id == track.nasId).firstOrNull;
      if (server == null) throw const AppException('No se encuentra la configuración del NAS.');
      await downloads.download(track, server, token, cacheLimitMb * 1024 * 1024, (done,total) {
        taskLabel = 'Descargando ${track.title} · ${(done / 1048576).toStringAsFixed(1)} MB';
        taskProgress = total > 0 ? (done / total).clamp(0, 1) : null; _refresh();
      }); count++;
    }
    messageToUser('$count canciones disponibles sin conexión.');
  });
  Future<void> preference(String key, Object value) async {
    await repository.setting(key, value);
    switch (key) {
      case 'dark': dark = value as bool;
      case 'accent': accent = value as int;
      case 'copyOnImport': copyOnImport = value as bool;
      case 'cacheLimitMb': cacheLimitMb = value as int;
    }
    _refresh();
  }
  Future<void> shutdown() async {
    token?.cancel(); await playback.shutdown(); await proxy.close();
    _closed = true; playback.removeListener(_refresh);
    // In-flight cancelled tasks may still finish a database transaction. Let the
    // process release SQLite after their completion instead of closing it early.
  }
}
