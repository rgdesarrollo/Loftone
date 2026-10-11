import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../application/app_controller.dart';
import '../data/webdav_client.dart';
import '../domain/models.dart';
import 'widgets.dart';

class NasScreen extends ConsumerStatefulWidget {
  const NasScreen({super.key});
  @override
  ConsumerState<NasScreen> createState() => _NasScreenState();
}
class _NasScreenState extends ConsumerState<NasScreen> {
  String? selectedId, path;
  List<DavEntry> entries = [];
  bool loading = false;
  String? error;
  CancelToken? browseToken;
  @override
  void dispose() { browseToken?.cancel(); super.dispose(); }
  Future<void> browse(NasConfig config, String target) async {
    browseToken?.cancel(); final token = CancelToken(); browseToken = token;
    setState(() { loading = true; error = null; selectedId = config.id; });
    try {
      final result = await ref.read(appProvider).dav.list(config, target, token: token);
      if (mounted && !token.cancelled) setState(() { entries = result; path = target; });
    } catch (e) { if (mounted && !token.cancelled) setState(() => error = networkMessage(e)); }
    finally { if (mounted && !token.cancelled) setState(() => loading = false); }
  }
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider); final config = app.servers.where((s) => s.id == selectedId).firstOrNull;
    return ListView(padding: const EdgeInsets.fromLTRB(30, 12, 30, 30), children: [
      Card(child: Padding(padding: const EdgeInsets.all(24), child: Row(children: [
        Icon(Icons.dns_outlined, size: 38, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 20),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Toda tu colección, estés donde estés', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          SizedBox(height: 8), Text('Conecta por WebDAV HTTPS. Fuera de casa, usa tu VPN o una dirección remota accesible.', style: TextStyle(height: 1.5))])),
      ]))),
      const SizedBox(height: 18), Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => serverDialog(context, app), icon: const Icon(Icons.add), label: const Text('Añadir Synology'))),
      const SizedBox(height: 18),
      for (final server in app.servers) Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 210, child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.storage_rounded), title: Text(server.name), subtitle: Text(server.useRemote ? 'Conexión remota · HTTPS' : 'Conexión local · HTTPS'))),
        OutlinedButton.icon(onPressed: loading ? null : () => browse(server, server.folder), icon: const Icon(Icons.folder_open), label: const Text('Explorar')),
        TextButton.icon(onPressed: app.busy ? null : () => app.refreshNas(server), icon: const Icon(Icons.sync), label: const Text('Actualizar índice')),
        IconButton(tooltip: 'Editar conexión local o remota', onPressed: () => serverDialog(context, app, existing: server), icon: const Icon(Icons.tune)),
      ]))),
      if (app.servers.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 30), child: EmptyState(icon: Icons.cloud_outlined,
        title: 'Tu NAS todavía no está conectado', subtitle: 'Necesitas WebDAV Server activado, un certificado de confianza y un usuario con permisos de lectura. QuickConnect no sirve como dirección WebDAV.')),
      if (config != null) ...[const SizedBox(height: 20), Wrap(spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(config.name, style: Theme.of(context).textTheme.titleLarge),
        OutlinedButton.icon(onPressed: loading || app.busy || path == null ? null : () => app.indexFolder(config, path!), icon: const Icon(Icons.playlist_add), label: const Text('Indexar esta carpeta')),
        TextButton(onPressed: loading ? null : () => browse(config, path ?? config.folder), child: const Text('Reconectar')),
      ]), const SizedBox(height: 12),
        Row(children: [IconButton(tooltip: 'Carpeta superior', onPressed: path == null || canonicalRemotePath(path!) == canonicalRemotePath(config.folder) ? null : () {
          final parts = canonicalRemotePath(path!).split('/')..removeLast(); browse(config, parts.join('/'));
        }, icon: const Icon(Icons.arrow_upward)), Expanded(child: SelectableText(path ?? config.folder))]),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.all(16), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (!loading && error == null && entries.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Esta carpeta está vacía.')),
        for (final entry in entries) ListTile(leading: Icon(entry.directory ? Icons.folder_outlined : Icons.audio_file_outlined),
          title: Text(entry.name), subtitle: entry.directory ? const Text('Carpeta') : Text('${(entry.size / 1048576).toStringAsFixed(1)} MB'),
          onTap: entry.directory && !loading ? () => browse(config, entry.path) : null,
          trailing: entry.directory ? IconButton(tooltip: 'Indexar esta carpeta', onPressed: app.busy ? null : () => app.indexFolder(config, entry.path), icon: const Icon(Icons.playlist_add)) : null),
      ],
    ]);
  }
}

Future<void> serverDialog(BuildContext context, AppController app, {NasConfig? existing}) async {
  await showDialog<void>(context: context, builder: (context) => _ServerDialog(app: app, existing: existing));
}
class _ServerDialog extends StatefulWidget {
  final AppController app;
  final NasConfig? existing;
  const _ServerDialog({required this.app, this.existing});
  @override
  State<_ServerDialog> createState() => _ServerDialogState();
}
class _ServerDialogState extends State<_ServerDialog> {
  final form = GlobalKey<FormState>();
  late final String id;
  late final List<TextEditingController> fields;
  bool remote = false, busy = false, showPassword = false;
  String message = '';
  CancelToken? token;
  @override
  void initState() {
    super.initState(); final server = widget.existing; id = server?.id ?? const Uuid().v4(); remote = server?.useRemote ?? false;
    fields = [server?.name ?? 'Mi Synology', server?.localAddress ?? '', server?.remoteAddress ?? '',
      '${server?.port ?? 5006}', server?.username ?? '', '', server?.folder ?? '/music/'].map((s) => TextEditingController(text: s)).toList();
  }
  @override
  void dispose() { token?.cancel(); for (final field in fields) { field.dispose(); } super.dispose(); }
  NasConfig config() => NasConfig(id: id, name: fields[0].text.trim(), localAddress: fields[1].text.trim(),
    remoteAddress: fields[2].text.trim(), port: int.parse(fields[3].text), username: fields[4].text.trim(),
    folder: canonicalRemotePath(fields[6].text), useRemote: remote);
  Future<void> submit(bool test) async {
    if (!form.currentState!.validate()) return;
    setState(() { busy = true; message = ''; }); token = CancelToken();
    try {
      final server = config(); server.origin;
      if (test) {
        final entries = await widget.app.dav.list(server, server.folder, password: fields[5].text.isEmpty ? null : fields[5].text, token: token);
        if (mounted) setState(() => message = 'Conexión HTTPS correcta: ${entries.length} elementos accesibles.');
      } else {
        await widget.app.saveServer(server, fields[5].text);
        if (mounted) Navigator.pop(context);
        widget.app.messageToUser('Conexión guardada. Pulsa «Explorar» para elegir qué carpetas indexar.');
      }
    } catch (e) { if (mounted) setState(() => message = networkMessage(e)); }
    finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(title: Text(widget.existing == null ? 'Conectar Synology NAS' : 'Configurar Synology NAS'),
    content: SizedBox(width: 530, child: SingleChildScrollView(child: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('La contraseña se guarda en el almacén seguro del sistema. La validación HTTPS permanece activada.'), const SizedBox(height: 18),
      SegmentedButton<bool>(segments: const [ButtonSegment(value: false, label: Text('Local'), icon: Icon(Icons.home_outlined)),
        ButtonSegment(value: true, label: Text('Remota'), icon: Icon(Icons.public))], selected: {remote}, onSelectionChanged: busy ? null : (v) => setState(() => remote = v.first)),
      const SizedBox(height: 18),
      for (var i = 0; i < fields.length; i++) Padding(padding: const EdgeInsets.only(bottom: 13), child: TextFormField(controller: fields[i], enabled: !busy,
        obscureText: i == 5 && !showPassword, autocorrect: false, enableSuggestions: i != 5, keyboardType: i == 3 ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: ['Nombre del NAS', 'Dirección local', 'Dirección remota (opcional)', 'Puerto HTTPS', 'Usuario',
          widget.existing == null ? 'Contraseña' : 'Nueva contraseña (vacío: conservar)', 'Carpeta de música'][i],
          hintText: i == 1 ? 'https://nas.tudominio.es' : i == 2 ? 'https://tunombre.synology.me' : null,
          suffixIcon: i == 5 ? IconButton(tooltip: showPassword ? 'Ocultar contraseña' : 'Mostrar contraseña', onPressed: () => setState(() => showPassword = !showPassword), icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility)) : null),
        validator: (v) {
          if ([0, 1, 3, 4, 6].contains(i) && (v?.trim().isEmpty ?? true)) return 'Este campo es obligatorio.';
          if (i == 2 && remote && (v?.trim().isEmpty ?? true)) return 'Introduce la dirección remota.';
          if (i == 3 && ((int.tryParse(v ?? '') ?? 0) < 1 || (int.tryParse(v ?? '') ?? 0) > 65535)) return 'Puerto válido: 1 a 65535.';
          if (i == 5 && widget.existing == null && (v?.isEmpty ?? true)) return 'Introduce la contraseña.';
          return null;
        })),
      if (busy) const LinearProgressIndicator(),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 14), child: Semantics(liveRegion: true, child: Text(message))),
    ])))), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      OutlinedButton(onPressed: busy ? null : () => submit(true), child: const Text('Probar conexión')),
      FilledButton(onPressed: busy ? null : () => submit(false), child: const Text('Guardar conexión'))]);
}
