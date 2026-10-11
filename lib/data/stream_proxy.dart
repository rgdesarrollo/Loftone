import 'dart:async';
import 'dart:io';
import 'package:uuid/uuid.dart';
import '../domain/models.dart';
import 'webdav_client.dart';

// libmpv receives only a random loopback URL. TLS validation, credentials and
// redirects remain under Dart HttpClient control, including every Range request.
class StreamProxy {
  final WebDavClient dav;
  HttpServer? _server;
  final Map<String, (NasConfig, String)> _routes = {};
  final Set<DavResponse> _active = {};
  void Function(String)? onError;
  StreamProxy(this.dav);
  Future<String> url(NasConfig config, String remotePath) async {
    _server ??= await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    if (_routes.isEmpty) _server!.listen(_serve);
    final key = const Uuid().v4(); _routes[key] = (config, remotePath);
    return 'http://127.0.0.1:${_server!.port}/$key';
  }
  Future<void> _serve(HttpRequest request) async {
    DavResponse? upstream;
    try {
      final route = _routes[request.uri.path.replaceFirst('/', '')];
      if (route == null || !['GET','HEAD'].contains(request.method)) {
        request.response.statusCode = 404; await request.response.close(); return;
      }
      final range = request.headers.value('range');
      upstream = await dav.request(route.$1, route.$2, method: request.method,
        headers: {'Range': ?range});
      _active.add(upstream);
      request.response.statusCode = upstream.response.statusCode;
      for (final name in ['content-type','content-length','content-range','accept-ranges']) {
        final value = upstream.response.headers.value(name);
        if (value != null) request.response.headers.set(name, value);
      }
      if (request.method == 'GET') await request.response.addStream(upstream.response.timeout(const Duration(seconds: 20)));
      await request.response.close();
    } catch (e) {
      if (e is! SocketException) onError?.call(networkMessage(e));
      try { request.response.statusCode = 502; await request.response.close(); } catch (_) { }
    } finally { if (upstream != null) { _active.remove(upstream); upstream.close(); } }
  }
  Future<void> close() async {
    for (final response in _active) { response.close(); }
    _active.clear(); _routes.clear(); await _server?.close(force: true); _server = null;
  }
}

class ResolvedSource {
  final String uri;
  final bool local;
  const ResolvedSource(this.uri, this.local);
}

Future<ResolvedSource> resolveSource(Track track, Future<String> Function() remoteUrl) async {
  if (track.cachedPath != null && await File(track.cachedPath!).exists()) return ResolvedSource(track.cachedPath!, true);
  if (track.path != null && await File(track.path!).exists()) return ResolvedSource(track.path!, true);
  if (track.remote) return ResolvedSource(await remoteUrl(), false);
  throw const AppException('No se encuentra este archivo. Usa «Localizar archivo» en el menú de la canción.');
}
