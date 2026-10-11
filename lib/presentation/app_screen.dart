import 'dart:async';
import 'dart:ui';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/app_controller.dart';
import '../domain/models.dart';
import 'nas_screen.dart';
import 'settings_screen.dart';
import 'player_bar.dart';
import 'widgets.dart';

const pages = ['Inicio', 'Biblioteca', 'Álbumes', 'Artistas', 'Playlists', 'Favoritos', 'Synology NAS', 'Ajustes'];
const pageIcons = [Icons.home_rounded, Icons.library_music_rounded, Icons.album_rounded, Icons.mic_external_on_rounded,
  Icons.queue_music_rounded, Icons.favorite_rounded, Icons.dns_rounded, Icons.tune_rounded];

class AppScreen extends ConsumerStatefulWidget {
  const AppScreen({super.key});
  @override
  ConsumerState<AppScreen> createState() => _AppScreenState();
}
class _AppScreenState extends ConsumerState<AppScreen> {
  late final AppLifecycleListener lifecycle;
  bool dragging = false;
  @override
  void initState() {
    super.initState();
    lifecycle = AppLifecycleListener(onExitRequested: () async {
      await ref.read(appProvider).shutdown(); return AppExitResponse.exit;
    }, onInactive: () { unawaited(ref.read(appProvider).playback.persist()); });
  }
  @override
  void dispose() { lifecycle.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appProvider); final colors = Theme.of(context).colorScheme;
    return CallbackShortcuts(bindings: {
      const SingleActivator(LogicalKeyboardKey.space, control: true): () { unawaited(app.playback.toggle()); },
      const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () { unawaited(app.playback.next()); },
      const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () { unawaited(app.playback.previous()); },
      const SingleActivator(LogicalKeyboardKey.keyO, control: true): () { unawaited(importDialog(context, app)); },
    }, child: Focus(autofocus: true, child: Scaffold(body: DropTarget(
      onDragEntered: (_) => setState(() => dragging = true),
      onDragExited: (_) => setState(() => dragging = false),
      onDragDone: (details) { setState(() => dragging = false); importDialog(context, app, dropped: details.files.map((f) => f.path).toList()); },
      child: Stack(children: [Column(children: [Expanded(child: Row(children: [
        LayoutBuilder(builder: (context, box) => _sidebar(context, app, MediaQuery.sizeOf(context).width > 1040)),
        Expanded(child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(30, 24, 30, 12), child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TU ESPACIO PERSONAL', style: TextStyle(fontSize: 10, letterSpacing: 2.2, color: colors.onSurfaceVariant)),
              const SizedBox(height: 5), Text(pages[app.page], style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            ])),
            if (MediaQuery.sizeOf(context).width > 750) Padding(padding: const EdgeInsets.only(right: 14), child: Text('${app.tracks.length} canciones', style: TextStyle(color: colors.onSurfaceVariant))),
            FilledButton.icon(onPressed: app.busy ? null : () => importDialog(context, app), icon: const Icon(Icons.add, size: 20), label: const Text('Importar música')),
          ])),
          if (app.busy) Padding(padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 8), child: Column(children: [
            Row(children: [Expanded(child: Text(app.taskLabel, maxLines: 1, overflow: TextOverflow.ellipsis)),
              TextButton(onPressed: () => app.token?.cancel(), child: const Text('Cancelar'))]),
            LinearProgressIndicator(value: app.taskProgress, borderRadius: BorderRadius.circular(4)),
          ])),
          if (app.status.isNotEmpty) Container(margin: const EdgeInsets.fromLTRB(30, 4, 30, 8),
            padding: const EdgeInsets.fromLTRB(14, 2, 2, 2), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
              color: app.isError ? colors.errorContainer : colors.secondaryContainer),
            child: Row(children: [Icon(app.isError ? Icons.error_outline : Icons.check_circle_outline, size: 18), const SizedBox(width: 10),
              Expanded(child: Semantics(liveRegion: true, child: Text(app.status, maxLines: 3, overflow: TextOverflow.ellipsis))),
              if (app.status.length > 180) IconButton(tooltip: 'Ver detalles', icon: const Icon(Icons.open_in_new, size: 18), onPressed: () => showDialog<void>(context: context,
                builder: (context) => AlertDialog(title: const Text('Resultado de la operación'), content: SingleChildScrollView(child: SelectableText(app.status)),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))]))),
              IconButton(tooltip: 'Cerrar mensaje', onPressed: () => app.messageToUser(''), icon: const Icon(Icons.close, size: 18))])),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: KeyedSubtree(key: ValueKey(app.page), child: switch(app.page) {
            0 => _home(context, app), 6 => const NasScreen(), 7 => const SettingsScreen(),
            4 when app.selectedPlaylist == null => _playlists(context, app),
            2 || 3 when app.group == null => _groups(context, app),
            _ => _library(context, app),
          }))),
        ])),
      ])), const PlayerBar()]),
      if (dragging) Positioned.fill(child: IgnorePointer(child: Container(color: colors.primaryContainer.withValues(alpha: .95),
        child: const EmptyState(icon: Icons.file_download_outlined, title: 'Suelta tu música aquí', subtitle: 'Puedes soltar canciones o carpetas completas.')))),
    ])))));
  }

  Widget _sidebar(BuildContext context, AppController app, bool wide) {
    final colors = Theme.of(context).colorScheme;
    return Container(width: wide ? 200 : 80, decoration: BoxDecoration(
      color: app.dark ? const Color(0xff0a0a0a) : const Color(0xfff9f9f9),
      border: Border(right: BorderSide(color: colors.outlineVariant.withValues(alpha: .1)))),
      child: Column(children: [Padding(padding: EdgeInsets.fromLTRB(wide ? 16 : 16, 20, 16, 20), child: Row(children: [
        if (wide) Image.asset(app.dark ? 'assets/logo_loftone_white.png' : 'assets/logo_loftone.png', width: 44, height: 44)
        else Container(width: 40, height: 40, decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.primary, colors.primary.withValues(alpha: .7)]),
          borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.music_note_rounded, color: colors.onPrimary, size: 22)),
      ])),
      Expanded(child: ListView(padding: EdgeInsets.symmetric(horizontal: wide ? 10 : 8), children: [
        if (wide) Padding(padding: const EdgeInsets.fromLTRB(14, 8, 0, 12), child: Text('LIBRARY', style: TextStyle(fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant))),
        for (var i = 0; i < pages.length; i++) Padding(padding: const EdgeInsets.only(bottom: 4), child: Tooltip(message: wide ? '' : pages[i],
          child: Material(color: app.page == i ? colors.primary.withValues(alpha: .1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10), child: InkWell(borderRadius: BorderRadius.circular(10), onTap: () => app.navigate(i),
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: Row(mainAxisAlignment: wide ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
                Icon(pageIcons[i], size: 20, color: app.page == i ? colors.primary : colors.onSurfaceVariant),
                if (wide) ...[const SizedBox(width: 12), Text(pages[i], style: TextStyle(color: app.page == i ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: app.page == i ? FontWeight.w600 : FontWeight.w400, fontSize: 14))],
              ])))))),
        if (wide && app.playlists.isNotEmpty) ...[const SizedBox(height: 20), Padding(padding: const EdgeInsets.only(left: 14), child: Text('PLAYLISTS', style: TextStyle(fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant))),
          const SizedBox(height: 8), for (final playlist in app.playlists.take(8)) ListTile(dense: true, leading: const Icon(Icons.music_note, size: 18),
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)), onTap: () => app.navigate(4, playlist: playlist.id)),
        ],
      ])),
      Padding(padding: const EdgeInsets.all(16), child: wide ? Row(children: [Icon(Icons.music_note_outlined, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: 8), Expanded(child: Text('Your Music', style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant)))]) : const Icon(Icons.music_note_outlined, size: 16)),
    ]));
  }

  Widget _home(BuildContext context, AppController app) {
    final colors = Theme.of(context).colorScheme;
    final recent = [...app.tracks]..sort((a,b) => b.addedAt.compareTo(a.addedAt));
    final history = app.history.map((id) => app.tracks.where((t) => t.id == id).firstOrNull).whereType<Track>().toList();
    return ListView(padding: const EdgeInsets.fromLTRB(30, 10, 30, 30), children: [
      Container(height: 220, clipBehavior: Clip.antiAlias, decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: app.dark ? [const Color(0xff1a1a1a), const Color(0xff0a0a0a)] : [colors.primaryContainer.withValues(alpha: .8), colors.secondaryContainer.withValues(alpha: .6)])),
        child: Padding(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('WELCOME TO LOFTONE', style: TextStyle(letterSpacing: 1.8, fontSize: 11, fontWeight: FontWeight.w600, color: colors.primary)),
            const SizedBox(height: 14), Text('Your Music, Your Way', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.6)),
            const SizedBox(height: 12), const Text('Stream, organize, and enjoy your personal music library.', style: TextStyle(fontSize: 13, height: 1.5)),
            const SizedBox(height: 20), FilledButton.icon(onPressed: app.tracks.isEmpty ? () => importDialog(context, app) : () => app.playback.playTracks(recent),
              icon: Icon(app.tracks.isEmpty ? Icons.add : Icons.play_arrow, size: 18), label: Text(app.tracks.isEmpty ? 'Add Music' : 'Play Library')),
          ])),
      ),
      const SizedBox(height: 28), Wrap(spacing: 14, runSpacing: 14, children: [
        _stat(context, Icons.music_note, '${app.tracks.length}', 'Songs', () => app.navigate(1)),
        _stat(context, Icons.favorite_outline, '${app.tracks.where((t) => t.favorite).length}', 'Favorites', () => app.navigate(5)),
        _stat(context, Icons.cloud_done_outlined, '${app.tracks.where((t) => t.cachedPath != null).length}', 'Offline', () => app.navigate(7)),
      ]),
      const SizedBox(height: 28), _section(context, 'Recently Added', 'See All', () => app.navigate(1)),
      const SizedBox(height: 16),
      if (recent.isEmpty) Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), 
        color: app.dark ? const Color(0xff1a1a1a) : const Color(0xfff5f5f5)),
        child: Row(children: [Icon(Icons.music_note_outlined, size: 32, color: colors.primary), const SizedBox(width: 20),
          const Expanded(child: Text('Start building your library.\nDrag and drop music or tap Add Music.', style: TextStyle(height: 1.6, fontSize: 13)))]))
      else SizedBox(height: 220, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: recent.take(12).length,
        separatorBuilder: (_, index) => const SizedBox(width: 16), itemBuilder: (context, index) => _albumTile(context, recent[index], () => app.playback.playTracks(recent, start: index)))),
      if (history.isNotEmpty) ...[const SizedBox(height: 24), _section(context, 'Recently Played', 'Play All', () => app.playback.playTracks(history)),
        for (final track in history.take(6)) TrackRow(track: track, onPlay: () => app.playback.playTracks(history, start: history.indexOf(track)))],
    ]);
  }
  Widget _section(BuildContext context, String title, String action, VoidCallback callback) => Row(children: [
    Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600))), TextButton(onPressed: callback, child: Text(action))]);
  Widget _stat(BuildContext context, IconData icon, String value, String label, VoidCallback action) {
    final colors = Theme.of(context).colorScheme;
    return Card(margin: EdgeInsets.zero,
      child: InkWell(onTap: action, borderRadius: BorderRadius.circular(16), child: SizedBox(width: 180, child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: colors.primary, size: 22), const SizedBox(height: 12), Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
      ]))))
    );
  }
  Widget _albumTile(BuildContext context, Track track, VoidCallback action, {String? title, String? subtitle}) => SizedBox(width: 170,
    child: InkWell(onTap: action, borderRadius: BorderRadius.circular(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CoverArt(track: track, size: 170, radius: 17), const SizedBox(height: 12),
      Text(title ?? track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 3), Text(subtitle ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
    ])));

  Widget _search(AppController app) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Row(children: [
    Expanded(child: TextField(key: ValueKey('search-${app.page}-${app.group}-${app.selectedPlaylist}'),
      decoration: const InputDecoration(hintText: 'Buscar canción, artista o álbum', prefixIcon: Icon(Icons.search, size: 21)), onChanged: app.search)),
    const SizedBox(width: 12), if (app.page != 4) DropdownButton<String>(value: app.sort, underline: const SizedBox(),
      items: const [DropdownMenuItem(value: 'added', child: Text('Más recientes')), DropdownMenuItem(value: 'title', child: Text('Nombre')),
        DropdownMenuItem(value: 'artist', child: Text('Artista')), DropdownMenuItem(value: 'album', child: Text('Álbum')), DropdownMenuItem(value: 'duration', child: Text('Duración'))],
      onChanged: (v) => app.setSort(v!)),
  ]));

  Widget _library(BuildContext context, AppController app) {
    final tracks = app.visibleTracks; final playlist = app.activePlaylist;
    return Padding(padding: const EdgeInsets.fromLTRB(30, 14, 30, 10), child: Column(children: [
      if (app.group != null || playlist != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Row(children: [
        IconButton(tooltip: 'Volver', onPressed: () => app.navigate(app.page), icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 8), Expanded(child: Text(playlist?.name ?? app.group!.split('\u0000').last,
          style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (playlist != null) PopupMenuButton<String>(tooltip: 'Opciones de playlist', onSelected: (value) async {
          if (value == 'rename') { final name = await askName(context, 'Renombrar playlist', initial: playlist.name); if (name != null) await app.savePlaylist(name, existing: playlist); }
          if (value == 'download') await app.downloadTracks(tracks);
          if (value == 'delete' && context.mounted && await confirmAction(context, 'Eliminar playlist', 'Las canciones seguirán en la biblioteca.', action: 'Eliminar')) {
            await app.guard(() async { await app.repository.deletePlaylist(playlist.id); await app.reload(); app.navigate(4); });
          }
        }, itemBuilder: (_) => const [PopupMenuItem(value: 'rename', child: Text('Renombrar')), PopupMenuItem(value: 'download', child: Text('Descargar playlist')),
          PopupMenuItem(value: 'delete', child: Text('Eliminar playlist'))]),
        IconButton.filled(tooltip: 'Reproducir selección', onPressed: tracks.isEmpty ? null : () => app.playback.playTracks(tracks), icon: const Icon(Icons.play_arrow)),
      ])),
      _search(app),
      if (tracks.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [Text('${tracks.length} canciones', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const Spacer(), if (playlist != null) const Flexible(child: Text('Arrastra ≡ para ordenar', style: TextStyle(fontSize: 12))),
        if (playlist == null) TextButton.icon(onPressed: () => app.playback.playTracks(tracks), icon: const Icon(Icons.play_arrow, size: 18), label: const Text('Reproducir todo')),
      ])),
      Expanded(child: tracks.isEmpty ? EmptyState(icon: app.page == 5 ? Icons.favorite_border : Icons.library_music_outlined,
        title: app.query.isNotEmpty ? 'Sin resultados' : playlist != null ? 'Dale vida a esta playlist' : 'Aquí vivirá tu música',
        subtitle: app.query.isNotEmpty ? 'Prueba con otro título, artista o álbum.' : playlist != null ? 'Abre el menú de una canción en Biblioteca y elige «Añadir a playlist».' : 'Importa archivos o conecta tu Synology para empezar.',
        action: playlist == null && app.query.isEmpty ? OutlinedButton(onPressed: () => importDialog(context, app), child: const Text('Importar música')) : null)
        : playlist != null && app.query.isEmpty ? ReorderableListView.builder(buildDefaultDragHandles: false,
          itemCount: tracks.length, onReorderItem: app.reorderPlaylist, itemBuilder: (context, index) => TrackRow(key: ValueKey(tracks[index].id), track: tracks[index],
            reorderIndex: index, onPlay: () => app.playback.playTracks(tracks, start: index)))
        : ListView.builder(itemCount: tracks.length, itemBuilder: (context, index) => TrackRow(track: tracks[index], onPlay: () => app.playback.playTracks(tracks, start: index)))),
    ]));
  }

  Widget _groups(BuildContext context, AppController app) {
    final groups = <String,List<Track>>{};
    for (final track in app.visibleTracks) { groups.putIfAbsent(app.page == 2 ? '${track.artist}\u0000${track.album}' : track.artist, () => []).add(track); }
    final keys = groups.keys.toList()..sort();
    return Padding(padding: const EdgeInsets.fromLTRB(30, 14, 30, 20), child: Column(children: [
      _search(app), Expanded(child: keys.isEmpty ? const EmptyState(title: 'Una colección por descubrir', subtitle: 'Los álbumes y artistas aparecerán cuando importes tu música.')
        : GridView.builder(gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisExtent: 255, crossAxisSpacing: 22, mainAxisSpacing: 20),
          itemCount: keys.length, itemBuilder: (context, index) {
            final key = keys[index]; final items = groups[key]!;
            return Align(alignment: Alignment.topLeft, child: _albumTile(context, items.first, () => app.navigate(app.page, selectedGroup: key),
              title: key.split('\u0000').last, subtitle: '${items.length} canciones${app.page == 2 ? ' · ${items.first.artist}' : ''}'));
          })),
    ]));
  }
  Widget _playlists(BuildContext context, AppController app) => Padding(padding: const EdgeInsets.fromLTRB(30, 14, 30, 20), child: Column(children: [
    Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () async {
      final name = await askName(context, 'Nueva playlist'); if (name != null) await app.savePlaylist(name);
    }, icon: const Icon(Icons.add), label: const Text('Crear playlist'))), const SizedBox(height: 20),
    Expanded(child: app.playlists.isEmpty ? const EmptyState(icon: Icons.queue_music, title: 'Una playlist para cada momento', subtitle: 'Crea tu primera playlist y mezcla canciones locales y del NAS.')
      : ListView.separated(itemCount: app.playlists.length, separatorBuilder: (_, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) { final playlist = app.playlists[index]; return Card(child: ListTile(contentPadding: const EdgeInsets.all(14),
          leading: CoverArt(track: app.tracks.where((t) => playlist.trackIds.contains(t.id)).firstOrNull), title: Text(playlist.name),
          subtitle: Text('${playlist.trackIds.length} canciones'), trailing: const Icon(Icons.chevron_right), onTap: () => app.navigate(4, playlist: playlist.id))); })),
  ]));
}

Future<void> importDialog(BuildContext context, AppController app, {List<String>? dropped}) async {
  bool copy = true;
  final choice = await showDialog<String>(context: context, builder: (context) => StatefulBuilder(builder: (context, setState) => AlertDialog(
    title: const Text('Tu música, a tu manera'), content: SizedBox(width: 500, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('MP3, FLAC, WAV, M4A / AAC y OGG', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 18),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Copiar a mi biblioteca'), subtitle: Text(copy
        ? 'Conserva tus canciones aunque muevas o elimines los originales.' : 'Añadir desde su ubicación: los archivos deben permanecer en esa ruta.'), value: copy, onChanged: (v) => setState(() => copy = v)),
      if (dropped != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('${dropped.length} archivos o carpetas seleccionados.')),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      if (dropped == null) OutlinedButton.icon(onPressed: () => Navigator.pop(context, 'folder'), icon: const Icon(Icons.folder_open), label: const Text('Elegir carpeta')),
      FilledButton.icon(onPressed: () => Navigator.pop(context, 'files'), icon: const Icon(Icons.audio_file_outlined), label: Text(dropped == null ? 'Elegir archivos' : 'Importar')),
    ])));
  if (choice == null) return;
  await app.guard(() async {
    List<String> paths = dropped ?? [];
    if (dropped == null && choice == 'folder') {
      final folder = await FilePicker.getDirectoryPath(dialogTitle: 'Seleccionar carpeta de música'); if (folder != null) paths = [folder];
    } else if (dropped == null) {
      final result = await FilePicker.pickFiles(dialogTitle: 'Importar música', type: FileType.custom, allowedExtensions: audioExtensions);
      paths = result.map((file) => file.path).whereType<String>().toList();
    }
    if (paths.isNotEmpty) await app.importPaths(paths, copy: copy);
  });
}

class TrackRow extends ConsumerWidget {
  final Track track;
  final VoidCallback onPlay;
  final int? reorderIndex;
  const TrackRow({super.key, required this.track, required this.onPlay, this.reorderIndex});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider); final colors = Theme.of(context).colorScheme;
    final selected = app.playback.current?.id == track.id;
    return Material(color: selected ? colors.primary.withValues(alpha: .08) : Colors.transparent, borderRadius: BorderRadius.circular(12),
      child: InkWell(onTap: onPlay, borderRadius: BorderRadius.circular(12), child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        child: LayoutBuilder(builder: (context, bounds) => Row(children: [
          if (reorderIndex != null) Padding(padding: const EdgeInsets.only(right: 12), child: ReorderableDragStartListener(index: reorderIndex!, child: const Tooltip(message: 'Arrastrar para reordenar', child: Icon(Icons.drag_handle, size: 20)))),
          CoverArt(track: track, size: 46, radius: 10), const SizedBox(width: 14),
          Expanded(flex: 4, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? colors.primary : colors.onSurface)), const SizedBox(height: 4),
            Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))])),
          if (bounds.maxWidth > 650) Expanded(flex: 3, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)))),
          Tooltip(message: track.cachedPath != null ? 'Disponible sin conexión' : !track.available ? 'Archivo no disponible; vuelve a conectar o localízalo' : track.remote ? 'Synology NAS' : track.managed ? 'Copia conservada en tu biblioteca' : 'Archivo en su ubicación original',
            child: Icon(track.cachedPath != null ? Icons.offline_pin_outlined : !track.available ? Icons.error_outline : track.remote ? Icons.cloud_outlined : Icons.computer_outlined,
              size: 16, color: !track.available && track.cachedPath == null ? colors.error : colors.onSurfaceVariant)),
          if (bounds.maxWidth > 450) Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text(timeLabel(Duration(milliseconds: track.durationMs)), style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
          IconButton(tooltip: track.favorite ? 'Quitar de favoritos' : 'Añadir a favoritos', onPressed: () => app.favorite(track),
            icon: Icon(track.favorite ? Icons.favorite : Icons.favorite_border, size: 19, color: track.favorite ? colors.primary : colors.onSurfaceVariant)),
          PopupMenuButton<String>(tooltip: 'Opciones de ${track.title}', icon: const Icon(Icons.more_horiz), onSelected: (value) => _action(context, app, value), itemBuilder: (_) => [
            const PopupMenuItem(value: 'queue', child: Text('Añadir a la cola')), const PopupMenuItem(value: 'playlist', child: Text('Añadir a playlist')),
            const PopupMenuItem(value: 'edit', child: Text('Editar metadatos')),
            if (!track.remote) const PopupMenuItem(value: 'locate', child: Text('Localizar archivo')),
            if (track.remote && track.cachedPath == null) const PopupMenuItem(value: 'download', child: Text('Descargar para escuchar sin conexión')),
            if (track.cachedPath != null) const PopupMenuItem(value: 'uncache', child: Text('Eliminar descarga')),
            if (app.activePlaylist != null) const PopupMenuItem(value: 'removePlaylist', child: Text('Quitar de esta playlist')),
            const PopupMenuItem(value: 'remove', child: Text('Quitar de la biblioteca')),
          ]),
        ])))));
  }
  Future<void> _action(BuildContext context, AppController app, String action) async {
    switch (action) {
      case 'queue': await app.playback.add(track);
      case 'download': await app.downloadTracks([track]);
      case 'uncache': await app.guard(() async { await app.downloads.remove(track); await app.reload(); });
      case 'removePlaylist': await app.playlistRemove(app.activePlaylist!, track);
      case 'remove': if (await confirmAction(context, 'Quitar canción', 'Se quitará de la biblioteca y las playlists. El archivo se conserva.', action: 'Quitar')) await app.removeTrack(track);
      case 'locate': await app.guard(() async {
        final result = await FilePicker.pickFile(dialogTitle: 'Localizar la canción original', type: FileType.custom, allowedExtensions: audioExtensions);
        final path = result?.path; if (path != null) { await app.local.relocate(track, path); await app.reload(); }
      });
      case 'edit': if (context.mounted) await _edit(context, app);
      case 'playlist': if (context.mounted) {
        await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(title: const Text('Añadir a playlist'),
        content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: ListView(shrinkWrap: true, children: [for (final playlist in app.playlists) ListTile(leading: const Icon(Icons.queue_music), title: Text(playlist.name),
            onTap: () { Navigator.pop(dialogContext); app.playlistAdd(playlist, track); })])),
          TextButton.icon(onPressed: () async {
            Navigator.pop(dialogContext); final name = await askName(context, 'Nueva playlist');
            if (name != null) { await app.savePlaylist(name); final playlist = app.activePlaylist; if (playlist != null) await app.playlistAdd(playlist, track); }
          }, icon: const Icon(Icons.add), label: const Text('Crear playlist')),
        ])), actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar'))]));
      }
    }
  }
  Future<void> _edit(BuildContext context, AppController app) async {
    final fields = [TextEditingController(text: track.title), TextEditingController(text: track.artist), TextEditingController(text: track.album), TextEditingController(text: track.trackNumber.toString())];
    final result = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Editar metadatos'),
      content: SizedBox(width: 430, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Los cambios se guardan en la biblioteca. El archivo original no se modifica.'), const SizedBox(height: 20),
        for (var i = 0; i < fields.length; i++) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: fields[i],
          decoration: InputDecoration(labelText: ['Título', 'Artista', 'Álbum', 'Número de pista'][i]), keyboardType: i == 3 ? TextInputType.number : TextInputType.text)),
      ]))), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () { if (fields[0].text.trim().isNotEmpty) Navigator.pop(context, true); }, child: const Text('Guardar'))]));
    if (result == true) await app.editTrack(track, {'title': fields[0].text.trim(), 'artist': fields[1].text.trim(), 'album': fields[2].text.trim(), 'trackNumber': int.tryParse(fields[3].text) ?? 0});
    Future<void>.delayed(const Duration(seconds: 1), () { for (final field in fields) { field.dispose(); } });
  }
}
