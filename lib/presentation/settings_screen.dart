import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/app_controller.dart';
import 'widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(30, 12, 30, 30), children: [
      _card(context, 'Hazlo tuyo', [
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tema oscuro'), subtitle: const Text('Una experiencia cómoda para escuchar de noche.'), value: app.dark, onChanged: (v) => app.preference('dark', v)),
        const SizedBox(height: 12), const Text('Color de acento'), const SizedBox(height: 12),
        Wrap(spacing: 14, children: [for (final color in [0xffb6ef72, 0xffa9a4ff, 0xff6bddd2, 0xffffb881, 0xffff91b9, 0xff8ccaff])
          Semantics(label: 'Color ${switch(color) { 0xffb6ef72 => 'verde', 0xffa9a4ff => 'violeta', 0xff6bddd2 => 'turquesa', 0xffffb881 => 'naranja', 0xffff91b9 => 'rosa', _ => 'azul' }}', selected: app.accent == color,
            child: IconButton.filled(style: IconButton.styleFrom(backgroundColor: Color(color), foregroundColor: Colors.black87),
              onPressed: () => app.preference('accent', color), icon: Icon(app.accent == color ? Icons.check : Icons.circle, size: 20))),
        ]),
      ]),
      _card(context, 'Biblioteca y archivos', [
        const Text('Carpeta donde se conservan tus canciones importadas'), const SizedBox(height: 10), SelectableText(app.local.musicFolder),
        const SizedBox(height: 16), Wrap(spacing: 12, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: app.busy ? null : () async {
            final confirmed = await confirmAction(context, 'Cambiar carpeta de biblioteca',
              'Se copiará y verificará tu música en una subcarpeta del destino. La biblioteca cambiará solo cuando todas las copias estén verificadas. Las copias anteriores se conservarán como respaldo.', action: 'Elegir destino');
            if (!confirmed) return;
            await app.guard(() async { final folder = await FilePicker.getDirectoryPath(dialogTitle: 'Nueva ubicación de la biblioteca');
              if (folder != null) await app.task('Migrando biblioteca…', (token) async { await app.local.migrate(folder, token, app.progress); app.messageToUser('Biblioteca migrada y verificada. Las copias anteriores se conservan como respaldo.'); }); });
          }, icon: const Icon(Icons.drive_file_move_outlined), label: const Text('Cambiar carpeta y migrar')),
          TextButton.icon(onPressed: app.busy ? null : () => app.task('Comprobando archivos…', (token) async { await app.local.checkMissing(); app.messageToUser('Disponibilidad de los archivos actualizada.'); }),
            icon: const Icon(Icons.fact_check_outlined), label: const Text('Comprobar archivos ausentes')),
        ]),
        const SizedBox(height: 20), const Text('Datos de la aplicación'), const SizedBox(height: 8), SelectableText(app.dataFolder),
        const SizedBox(height: 10), const Text('SQLite guarda biblioteca, playlists, ajustes y cola. Las carátulas y las descargas tienen carpetas separadas. Quitar canciones de la biblioteca no borra sus archivos.'),
      ]),
      _card(context, 'Escuchar sin conexión', [
        FutureBuilder<int>(future: app.downloads.usedBytes(), builder: (context, snapshot) => Text('Espacio ocupado: ${((snapshot.data ?? 0) / 1048576).toStringAsFixed(1)} MB de ${app.cacheLimitMb} MB')),
        const SizedBox(height: 16), DropdownButtonFormField<int>(initialValue: [512, 1024, 2048, 5120, 10240, 20480].contains(app.cacheLimitMb) ? app.cacheLimitMb : 2048,
          decoration: const InputDecoration(labelText: 'Límite de descargas'), items: [for (final size in [512, 1024, 2048, 5120, 10240, 20480]) DropdownMenuItem(value: size, child: Text(size < 1024 ? '$size MB' : '${size ~/ 1024} GB'))],
          onChanged: (value) { if (value != null) app.preference('cacheLimitMb', value); }),
        const SizedBox(height: 12), const Text('Las descargas se gestionan manualmente. Al llegar al límite se detienen las nuevas descargas; tu música importada nunca se elimina para liberar espacio.'),
        const SizedBox(height: 14), OutlinedButton.icon(onPressed: app.busy ? null : () async {
          if (await confirmAction(context, 'Eliminar todas las descargas', 'Se eliminarán solo las copias sin conexión del NAS. Tu música importada y los archivos del NAS se conservan.', action: 'Eliminar descargas')) {
            await app.task('Eliminando descargas…', (token) async {
              for (final track in app.tracks.where((t) => t.cachedPath != null)) { token.check(); await app.downloads.remove(track); }
              app.messageToUser('Descargas eliminadas.');
            });
          }
        }, icon: const Icon(Icons.delete_sweep_outlined), label: const Text('Eliminar todas las descargas')),
        for (final track in app.tracks.where((t) => t.cachedPath != null)) ListTile(contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.offline_pin_outlined), title: Text(track.title), subtitle: Text(track.artist),
          trailing: IconButton(tooltip: 'Eliminar descarga', onPressed: () => app.guard(() async { await app.downloads.remove(track); await app.reload(); }), icon: const Icon(Icons.delete_outline))),
      ]),
      _card(context, 'Loftone · 1.0.0', [
        const Text('Audio: MP3, FLAC, WAV, M4A/AAC y OGG mediante libmpv. Los archivos protegidos por DRM no son compatibles. La decodificación depende del archivo y de las bibliotecas instaladas en cada sistema.'),
        const SizedBox(height: 14), const Text('Atajos: Ctrl + O para importar · Ctrl + espacio para reproducir o pausar · Ctrl + ← / → para anterior o siguiente. Usa Tab para navegar por los controles.'),
        const SizedBox(height: 14), TextButton(onPressed: () => showLicensePage(context: context, applicationName: 'Loftone', applicationVersion: '1.0.0'), child: const Text('Licencias de los componentes')),
      ]),
    ]);
  }
  Widget _card(BuildContext context, String title, List<Widget> children) => Card(margin: const EdgeInsets.only(bottom: 18), child: Padding(padding: const EdgeInsets.all(24),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 18), ...children])));
}
