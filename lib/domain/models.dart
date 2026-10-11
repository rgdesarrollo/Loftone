import 'dart:convert';

const audioExtensions = ['mp3', 'flac', 'wav', 'm4a', 'aac', 'ogg', 'opus'];

class Track {
  final String id, title, artist, album;
  final String? path, fingerprint, nasId, remotePath, cachedPath, artwork, etag;
  final int durationMs, trackNumber, addedAt, size;
  final bool managed, favorite, available, edited;
  const Track({required this.id, required this.title,
    this.artist = 'Artista desconocido', this.album = 'Álbum desconocido',
    this.path, this.fingerprint, this.nasId, this.remotePath, this.cachedPath,
    this.artwork, this.etag, this.durationMs = 0, this.trackNumber = 0,
    this.addedAt = 0, this.size = 0, this.managed = false,
    this.favorite = false, this.available = true, this.edited = false});
  bool get remote => nasId != null;
  Map<String, dynamic> toJson() => {
    'id': id, 'title': title, 'artist': artist, 'album': album, 'path': path,
    'fingerprint': fingerprint, 'nasId': nasId, 'remotePath': remotePath,
    'cachedPath': cachedPath, 'artwork': artwork, 'etag': etag,
    'durationMs': durationMs, 'trackNumber': trackNumber, 'addedAt': addedAt,
    'size': size, 'managed': managed, 'favorite': favorite,
    'available': available, 'edited': edited,
  };
  factory Track.fromJson(Map<String, dynamic> m) => Track(
    id: m['id'], title: m['title'], artist: m['artist'] ?? 'Artista desconocido',
    album: m['album'] ?? 'Álbum desconocido', path: m['path'],
    fingerprint: m['fingerprint'], nasId: m['nasId'], remotePath: m['remotePath'],
    cachedPath: m['cachedPath'], artwork: m['artwork'], etag: m['etag'],
    durationMs: m['durationMs'] ?? 0, trackNumber: m['trackNumber'] ?? 0,
    addedAt: m['addedAt'] ?? 0, size: m['size'] ?? 0,
    managed: m['managed'] ?? false, favorite: m['favorite'] ?? false,
    available: m['available'] ?? true, edited: m['edited'] ?? false);
  Track change(Map<String, dynamic> values) => Track.fromJson({...toJson(), ...values});
}

class MusicPlaylist {
  final String id, name;
  final List<String> trackIds;
  const MusicPlaylist(this.id, this.name, this.trackIds);
}

class NasConfig {
  final String id, name, localAddress, remoteAddress, username, folder;
  final int port;
  final bool useRemote;
  const NasConfig({required this.id, required this.name, required this.localAddress,
    this.remoteAddress = '', required this.username, this.folder = '/music/',
    this.port = 5006, this.useRemote = false});
  Uri get origin {
    final address = (useRemote ? remoteAddress : localAddress).trim();
    if (address.isEmpty) throw const AppException('Introduce la dirección del NAS.');
    final uri = Uri.tryParse(address.contains('://') ? address : 'https://$address');
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') || port < 1 || port > 65535) {
      throw const AppException('Usa una dirección HTTPS sin usuario ni carpeta; indica la carpeta por separado.');
    }
    if (uri.host.toLowerCase().contains('quickconnect.to')) {
      throw const AppException('QuickConnect no es compatible con WebDAV. Usa un dominio HTTPS directo o tu VPN.');
    }
    return uri.replace(port: uri.hasPort ? uri.port : port, path: '/');
  }
  Uri uriFor(String decodedPath) {
    final path = canonicalRemotePath(decodedPath);
    return origin.replace(path: decodedPath.endsWith('/') && path != '/' ? '$path/' : path);
  }
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'localAddress': localAddress,
    'remoteAddress': remoteAddress, 'username': username, 'folder': folder,
    'port': port, 'useRemote': useRemote};
  factory NasConfig.fromJson(Map<String, dynamic> m) => NasConfig(id: m['id'],
    name: m['name'], localAddress: m['localAddress'], remoteAddress: m['remoteAddress'] ?? '',
    username: m['username'], folder: m['folder'], port: m['port'], useRemote: m['useRemote'] ?? false);
}

String canonicalRemotePath(String path) {
  final parts = path.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty).toList();
  if (parts.any((s) => s == '..' || s == '.' || s.contains('\u0000'))) {
    throw const AppException('La ruta del NAS no es válida.');
  }
  return '/${parts.join('/')}';
}

class QueueSnapshot {
  final List<String> ids;
  final int index, positionMs;
  final double volume;
  final bool shuffle, muted;
  final String repeat;
  const QueueSnapshot({this.ids = const [], this.index = 0, this.positionMs = 0,
    this.volume = 70, this.shuffle = false, this.muted = false, this.repeat = 'off'});
  Map<String, dynamic> toJson() => {'ids': ids, 'index': index, 'positionMs': positionMs,
    'volume': volume, 'shuffle': shuffle, 'muted': muted, 'repeat': repeat};
  factory QueueSnapshot.fromJson(Map<String, dynamic> m) => QueueSnapshot(
    ids: List<String>.from(m['ids'] ?? []), index: m['index'] ?? 0,
    positionMs: m['positionMs'] ?? 0, volume: (m['volume'] as num? ?? 70).toDouble().clamp(0, 100),
    shuffle: m['shuffle'] ?? false, muted: m['muted'] ?? false, repeat: m['repeat'] ?? 'off');
  QueueSnapshot reconcile(Set<String> valid) {
    final current = index >= 0 && index < ids.length ? ids[index] : null;
    final kept = ids.where(valid.contains).toList();
    final next = current == null ? -1 : kept.indexOf(current);
    return QueueSnapshot(ids: kept, index: next < 0 ? 0 : next,
      positionMs: next < 0 ? 0 : positionMs, volume: volume, shuffle: shuffle,
      muted: muted, repeat: repeat);
  }
}

class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

class CancelToken {
  bool cancelled = false;
  final List<void Function()> _listeners = [];
  void onCancel(void Function() callback) { _listeners.add(callback); if (cancelled) callback(); }
  void cancel() { cancelled = true; for (final callback in _listeners) { callback(); } }
  void check() { if (cancelled) throw const AppException('Operación cancelada. Los archivos completados se conservan.'); }
}

Map<String, dynamic> decodeObject(String value) => jsonDecode(value) as Map<String, dynamic>;
