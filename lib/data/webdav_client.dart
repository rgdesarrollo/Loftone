import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:xml/xml.dart';
import '../domain/models.dart';

abstract interface class CredentialStore {
  Future<String?> read(String id);
  Future<void> write(String id, String password);
}

class SystemCredentialStore implements CredentialStore {
  final FlutterSecureStorage storage;
  const SystemCredentialStore([this.storage = const FlutterSecureStorage()]);
  static const _prefix = 'loftone.nas.', _legacyPrefix = 'mi_musica.nas.';
  @override
  Future<String?> read(String id) async {
    final value = await storage.read(key: '$_prefix$id');
    if (value != null) return value;
    // Migra las contraseñas guardadas con el nombre antiguo de la app.
    final legacy = await storage.read(key: '$_legacyPrefix$id');
    if (legacy != null) {
      await storage.write(key: '$_prefix$id', value: legacy);
      await storage.delete(key: '$_legacyPrefix$id');
    }
    return legacy;
  }
  @override
  Future<void> write(String id, String password) => storage.write(key: '$_prefix$id', value: password);
}

class DavEntry {
  final String path, name;
  final bool directory;
  final int size;
  final String? etag;
  const DavEntry(this.path, this.name, this.directory, this.size, this.etag);
}

String networkMessage(Object e) {
  if (e is AppException) return e.message;
  if (e is HandshakeException || e is TlsException) return 'El certificado HTTPS no es válido o no es de confianza. Comprueba el dominio y el certificado del NAS.';
  if (e is TimeoutException) return 'El NAS no respondió a tiempo. Comprueba la conexión y vuelve a intentarlo.';
  if (e is SocketException || e is HttpException) return 'No se puede contactar con el NAS. Comprueba la red, la VPN y la dirección.';
  return 'No se pudo completar la operación. Comprueba la conexión y los permisos.';
}

class DavResponse {
  final HttpClientResponse response;
  final HttpClient client;
  DavResponse(this.response, this.client);
  void close() => client.close(force: true);
}

class WebDavClient {
  final CredentialStore credentials;
  final HttpClient Function() clientFactory;
  WebDavClient(this.credentials, {HttpClient Function()? clientFactory})
    : clientFactory = clientFactory ?? HttpClient.new;

  Future<DavResponse> request(NasConfig config, String path, {String method = 'GET',
    Map<String, String> headers = const {}, String? body, CancelToken? token,
    String? password}) async {
    final uri = config.uriFor(path); // HTTPS and origin are validated for every request.
    token?.check();
    final secret = password ?? await credentials.read(config.id);
    if (secret == null || secret.isEmpty) throw const AppException('Guarda la contraseña del NAS antes de conectar.');
    final client = clientFactory()..connectionTimeout = const Duration(seconds: 12);
    token?.onCancel(() => client.close(force: true));
    try {
      final request = await client.openUrl(method, uri).timeout(const Duration(seconds: 15));
      request.followRedirects = false; // Never forward credentials to a redirect target.
      request.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64Encode(utf8.encode('${config.username}:$secret'))}');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      headers.forEach(request.headers.set);
      if (body != null) { request.headers.contentType = ContentType('application', 'xml', charset: 'utf-8'); request.write(body); }
      final response = await request.close().timeout(const Duration(seconds: 20));
      final status = response.statusCode;
      if (![200, 206, 207, 416].contains(status)) {
        throw AppException(switch (status) {
          401 => 'Usuario o contraseña incorrectos.',
          403 => 'Permisos insuficientes. Concede lectura de la carpeta y acceso a WebDAV Server.',
          404 => 'No se encontró la carpeta o canción en el NAS.',
          >= 300 && < 400 => 'El NAS redirige la petición. Introduce la dirección HTTPS final de WebDAV.',
          _ => 'El NAS devolvió el error HTTP $status.',
        });
      }
      return DavResponse(response, client);
    } catch (e) {
      client.close(force: true); token?.check(); throw AppException(networkMessage(e));
    }
  }
  Future<List<DavEntry>> list(NasConfig config, String path, {CancelToken? token, String? password}) async {
    final dir = '${canonicalRemotePath(path).replaceAll(RegExp(r'/+$'), '')}/';
    final result = await request(config, dir, method: 'PROPFIND',
      headers: {'Depth': '1'}, body: '<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getetag/><d:getlastmodified/></d:prop></d:propfind>',
      token: token, password: password);
    try {
      if (result.response.statusCode != 207) throw const AppException('Esta dirección no es un endpoint WebDAV válido (se esperaba HTTP 207).');
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in result.response.timeout(const Duration(seconds: 20))) {
        token?.check(); bytes.add(chunk);
        if (bytes.length > 16 * 1024 * 1024) throw const AppException('Esta carpeta es demasiado grande. Divide la biblioteca en subcarpetas.');
      }
      final xml = utf8.decode(bytes.takeBytes());
      final origin = config.origin;
      return await Isolate.run(() => parseListing(xml, origin, dir));
    } catch (e) { throw AppException(networkMessage(e)); }
    finally { result.close(); }
  }
  static List<DavEntry> parseListing(String xml, Uri origin, String requestedPath) {
    final doc = XmlDocument.parse(xml);
    final entries = <DavEntry>[];
    if (doc.rootElement.name.local != 'multistatus') throw const AppException('La respuesta no es una lista WebDAV válida.');
    for (final node in doc.rootElement.childElements.where((e) => e.name.local == 'response')) {
      final href = node.childElements.where((e) => e.name.local == 'href').firstOrNull?.innerText;
      if (href == null) continue;
      final uri = origin.resolve(href);
      if (uri.origin != origin.origin || uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) continue;
      final decoded = '/${uri.pathSegments.where((s) => s.isNotEmpty).join('/')}';
      final path = canonicalRemotePath(decoded);
      final root = canonicalRemotePath(requestedPath);
      if (path == root || !(path.startsWith(root == '/' ? '/' : '$root/'))) continue;
      final relative = root == '/' ? path.substring(1) : path.substring(root.length + 1);
      if (relative.contains('/')) continue; // Only direct children; no traversal or recursive loops.
      final properties = node.childElements.where((e) => e.name.local == 'propstat')
        .where((e) => e.childElements.any((s) => s.name.local == 'status' && s.innerText.contains(' 200 ')))
        .expand((e) => e.childElements.where((s) => s.name.local == 'prop')).expand((e) => e.childElements).toList();
      if (properties.isEmpty) continue;
      String? value(String name) => properties.where((e) => e.name.local == name).firstOrNull?.innerText;
      final directory = properties.any((e) => e.name.local == 'resourcetype' && e.descendantElements.any((n) => n.name.local == 'collection'));
      entries.add(DavEntry(path, value('displayname')?.trim().isNotEmpty == true ? value('displayname')! : relative,
        directory, int.tryParse(value('getcontentlength') ?? '') ?? 0, value('getetag') ?? value('getlastmodified')));
    }
    entries.sort((a,b) => a.directory != b.directory ? (a.directory ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }
  Future<Uint8List> prefix(NasConfig config, String path, int maximum, CancelToken token) async {
    final result = await request(config, path, headers: {'Range': 'bytes=0-${maximum - 1}'}, token: token);
    final bytes = BytesBuilder(copy: false);
    try {
      await for (final chunk in result.response.timeout(const Duration(seconds: 15))) {
        token.check(); final remaining = maximum - bytes.length;
        bytes.add(chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
        if (bytes.length >= maximum) break;
      }
      return bytes.takeBytes();
    } finally { result.close(); }
  }
}
