import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../domain/models.dart';

class LibraryRepository {
  final Database db;
  LibraryRepository._(this.db);
  static Future<LibraryRepository> open(String path) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) async { await db.execute('PRAGMA foreign_keys = ON'); await db.execute('PRAGMA journal_mode = WAL'); },
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE tracks(id TEXT PRIMARY KEY, fingerprint TEXT UNIQUE, nas_id TEXT, remote_path TEXT, data TEXT NOT NULL, UNIQUE(nas_id, remote_path))');
        await db.execute('CREATE TABLE playlists(id TEXT PRIMARY KEY, name TEXT NOT NULL)');
        await db.execute('CREATE TABLE playlist_tracks(playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE, track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, position INTEGER NOT NULL, PRIMARY KEY(playlist_id, track_id))');
        await db.execute('CREATE TABLE settings(key TEXT PRIMARY KEY, value TEXT NOT NULL)');
        await db.execute('CREATE TABLE history(id INTEGER PRIMARY KEY AUTOINCREMENT, track_id TEXT NOT NULL REFERENCES tracks(id) ON DELETE CASCADE, played_at INTEGER NOT NULL)');
      }));
    return LibraryRepository._(db);
  }
  Future<List<Track>> tracks() async => (await db.query('tracks', orderBy: 'rowid DESC'))
    .map((r) => Track.fromJson(decodeObject(r['data'] as String))).toList();
  Future<Track?> track(String id) async {
    final rows = await db.query('tracks', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Track.fromJson(decodeObject(rows.first['data'] as String));
  }
  Future<Track?> duplicate(String hash) async {
    final rows = await db.query('tracks', where: 'fingerprint = ?', whereArgs: [hash]);
    return rows.isEmpty ? null : Track.fromJson(decodeObject(rows.first['data'] as String));
  }
  Map<String, Object?> _row(Track t) => {'id': t.id, 'fingerprint': t.fingerprint,
    'nas_id': t.nasId, 'remote_path': t.remotePath, 'data': jsonEncode(t.toJson())};
  Future<void> saveTrack(Track t) async {
    await db.transaction((txn) async {
      final count = await txn.update('tracks', _row(t), where: 'id = ?', whereArgs: [t.id]);
      if (count == 0) await txn.insert('tracks', _row(t));
    });
  }
  Future<void> removeTrack(String id) => db.delete('tracks', where: 'id = ?', whereArgs: [id]);
  Future<void> removeTracks(Iterable<String> ids) async {
    final unique = ids.toSet();
    if (unique.isEmpty) return;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in unique) {
        batch.delete('tracks', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
  }
  Future<void> setting(String key, Object? value) async => db.insert('settings',
    {'key': key, 'value': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<dynamic> readSetting(String key) async {
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }
  Future<void> savePlaylist(MusicPlaylist playlist) async {
    await db.transaction((txn) async {
      final count = await txn.update('playlists', {'name': playlist.name}, where: 'id = ?', whereArgs: [playlist.id]);
      if (count == 0) await txn.insert('playlists', {'id': playlist.id, 'name': playlist.name});
      await txn.delete('playlist_tracks', where: 'playlist_id = ?', whereArgs: [playlist.id]);
      final batch = txn.batch();
      final unique = playlist.trackIds.toSet().toList();
      for (var i = 0; i < unique.length; i++) {
        batch.insert('playlist_tracks', {'playlist_id': playlist.id, 'track_id': unique[i], 'position': i});
      }
      await batch.commit(noResult: true);
    });
  }
  Future<List<MusicPlaylist>> playlists() async {
    final result = <MusicPlaylist>[];
    for (final r in await db.query('playlists', orderBy: 'name COLLATE NOCASE')) {
      final rows = await db.query('playlist_tracks', where: 'playlist_id = ?', whereArgs: [r['id']], orderBy: 'position');
      result.add(MusicPlaylist(r['id'] as String, r['name'] as String, rows.map((r) => r['track_id'] as String).toList()));
    }
    return result;
  }
  Future<void> deletePlaylist(String id) => db.delete('playlists', where: 'id = ?', whereArgs: [id]);
  Future<void> recordPlay(String id) async {
    await db.insert('history', {'track_id': id, 'played_at': DateTime.now().millisecondsSinceEpoch});
    await db.execute('DELETE FROM history WHERE id NOT IN (SELECT id FROM history ORDER BY id DESC LIMIT 1000)');
  }
  Future<List<String>> history() async => (await db.rawQuery('SELECT track_id, MAX(played_at) AS last FROM history GROUP BY track_id ORDER BY last DESC LIMIT 100'))
    .map((r) => r['track_id'] as String).toList();
  Future<void> commitMigration(List<Track> tracks, String folder) async {
    await db.transaction((txn) async {
      for (final track in tracks) { await txn.update('tracks', _row(track), where: 'id = ?', whereArgs: [track.id]); }
      await txn.insert('settings', {'key': 'libraryFolder', 'value': jsonEncode(folder)}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }
  Future<void> close() => db.close();
}
