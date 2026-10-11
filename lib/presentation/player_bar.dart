import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_controller.dart';
import '../application/playback_controller.dart';
import 'widgets.dart';

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final player = app.playback;
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xff091126).withValues(alpha: .96)
            : colors.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xff3452a3).withValues(alpha: .7)
                : colors.outlineVariant.withValues(alpha: .4),
          ),
        ),
        boxShadow: Theme.of(context).brightness == Brightness.dark
            ? const [
                BoxShadow(
                  color: Color(0x55234cff),
                  blurRadius: 28,
                  spreadRadius: -12,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth > 820;
          final info = InkWell(
            onTap: player.current == null
                ? null
                : () => showNowPlaying(context),
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                CoverArt(track: player.current, size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        player.current?.title ?? 'Tu próxima canción te espera',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        player.current?.artist ?? 'Importa música para empezar',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (wide && player.current != null)
                  IconButton(
                    tooltip: 'Ampliar canción',
                    onPressed: () => showNowPlaying(context),
                    icon: const Icon(Icons.open_in_full, size: 18),
                  ),
              ],
            ),
          );
          final controls = PlaybackButtons(player: player);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(flex: wide ? 3 : 4, child: info),
                  Expanded(flex: wide ? 4 : 5, child: controls),
                  if (wide)
                    Expanded(
                      flex: 3,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: player.muted
                                ? 'Activar sonido'
                                : 'Silenciar',
                            onPressed: player.toggleMute,
                            icon: Icon(
                              player.muted
                                  ? Icons.volume_off_outlined
                                  : Icons.volume_up_outlined,
                              size: 20,
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Slider(
                              value: player.muted ? 0 : player.volume,
                              min: 0,
                              max: 100,
                              label: '${player.volume.round()} %',
                              semanticFormatterCallback: (v) =>
                                  'Volumen ${v.round()} por ciento',
                              onChanged: player.setVolume,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cola de reproducción',
                            onPressed: () => showQueue(context),
                            icon: const Icon(Icons.queue_music_rounded),
                          ),
                        ],
                      ),
                    ),
                  if (!wide)
                    IconButton(
                      tooltip: 'Cola y volumen',
                      onPressed: () => showQueue(context),
                      icon: const Icon(Icons.queue_music_rounded),
                    ),
                ],
              ),
              SeekBar(player: player),
            ],
          );
        },
      ),
    );
  }
}

class PlaybackButtons extends StatelessWidget {
  final PlaybackController player;
  final bool large;
  const PlaybackButtons({super.key, required this.player, this.large = false});
  @override
  Widget build(BuildContext context) {
    final enabled = player.current != null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: player.shuffle
              ? 'Desactivar aleatorio'
              : 'Reproducción aleatoria',
          isSelected: player.shuffle,
          onPressed: player.toggleShuffle,
          icon: const Icon(Icons.shuffle_rounded, size: 20),
        ),
        IconButton(
          tooltip: 'Anterior (Ctrl + ←)',
          onPressed: enabled ? player.previous : null,
          icon: const Icon(Icons.skip_previous_rounded, size: 28),
        ),
        IconButton.filled(
          tooltip: player.playing
              ? 'Pausar (Ctrl + espacio)'
              : 'Reproducir (Ctrl + espacio)',
          onPressed: enabled && !player.loading ? player.toggle : null,
          iconSize: large ? 40 : 28,
          padding: EdgeInsets.all(large ? 20 : 12),
          icon: player.loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  player.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
        ),
        IconButton(
          tooltip: 'Siguiente (Ctrl + →)',
          onPressed: enabled ? () => player.next() : null,
          icon: const Icon(Icons.skip_next_rounded, size: 28),
        ),
        IconButton(
          tooltip:
              'Repetición: ${switch (player.repeat) {
                'one' => 'una canción',
                'all' => 'toda la cola',
                _ => 'desactivada',
              }}',
          isSelected: player.repeat != 'off',
          onPressed: player.cycleRepeat,
          icon: Icon(
            player.repeat == 'one'
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            size: 20,
          ),
        ),
      ],
    );
  }
}

class SeekBar extends StatefulWidget {
  final PlaybackController player;
  const SeekBar({super.key, required this.player});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? dragging;
  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final max = player.duration.inMilliseconds.toDouble();
    return Row(
      children: [
        SizedBox(
          width: 45,
          child: Text(
            timeLabel(
              Duration(
                milliseconds: (dragging ?? player.position.inMilliseconds)
                    .round(),
              ),
            ),
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: (dragging ?? player.position.inMilliseconds.toDouble())
                  .clamp(0, max > 0 ? max : 1),
              max: max > 0 ? max : 1,
              onChanged: max <= 0 ? null : (v) => setState(() => dragging = v),
              semanticFormatterCallback: (v) =>
                  'Posición ${timeLabel(Duration(milliseconds: v.round()))}',
              onChangeEnd: (v) async {
                await player.seek(Duration(milliseconds: v.round()));
                if (mounted) setState(() => dragging = null);
              },
            ),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(
            timeLabel(player.duration),
            style: const TextStyle(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

void showNowPlaying(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final app = ref.watch(appProvider);
        final player = app.playback;
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'AHORA SUENA',
                          style: TextStyle(letterSpacing: 3, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar vista ampliada',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, box) => CoverArt(
                      track: player.current,
                      size: box.maxWidth.clamp(100, 320),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    player.current?.title ?? 'Sin canción',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${player.current?.artist ?? ''} · ${player.current?.album ?? ''}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  SeekBar(player: player),
                  PlaybackButtons(player: player, large: true),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: player.muted ? 'Activar sonido' : 'Silenciar',
                        onPressed: player.toggleMute,
                        icon: Icon(
                          player.muted ? Icons.volume_off : Icons.volume_up,
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        child: Slider(
                          value: player.volume,
                          max: 100,
                          label: '${player.volume.round()} %',
                          onChanged: player.setVolume,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ver cola',
                        onPressed: () => showQueue(context),
                        icon: const Icon(Icons.queue_music),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

void showQueue(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final app = ref.watch(appProvider);
        final player = app.playback;
        return Dialog(
          child: SizedBox(
            width: 580,
            height: 620,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Cola de reproducción',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar cola',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Silencio',
                        onPressed: player.toggleMute,
                        icon: Icon(
                          player.muted ? Icons.volume_off : Icons.volume_up,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: player.volume,
                          max: 100,
                          onChanged: player.setVolume,
                        ),
                      ),
                      Text('${player.volume.round()} %'),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: player.queue.isEmpty
                        ? const EmptyState(
                            title: 'La cola está vacía',
                            subtitle: 'Reproduce una canción o añádela desde su menú.',
                          )
                        : ReorderableListView.builder(
                            itemCount: player.queue.length,
                            onReorderItem: player.reorder,
                            buildDefaultDragHandles: false,
                            itemBuilder: (context, index) {
                              final id = player.queue[index];
                              final track = app.tracks
                                  .where((t) => t.id == id)
                                  .firstOrNull;
                              return ListTile(
                                key: ValueKey(id),
                                selected: index == player.index,
                                leading: CoverArt(track: track, size: 42),
                                title: Text(
                                  track?.title ?? 'Canción no disponible',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(track?.artist ?? ''),
                                onTap: () => player.jump(index),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Quitar de la cola',
                                      onPressed: () => player.remove(id),
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Tooltip(
                                        message: 'Arrastrar para reordenar',
                                        child: Icon(Icons.drag_handle),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
