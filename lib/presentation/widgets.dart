import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/models.dart';

class LoftoneBackground extends StatelessWidget {
  final Widget child;
  const LoftoneBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) return child;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.45, -.9),
          radius: 1.45,
          colors: [Color(0xff17256a), Color(0xff090f2d), Color(0xff040716)],
          stops: [0, .42, 1],
        ),
      ),
      child: CustomPaint(painter: LoftoneStarsPainter(), child: child),
    );
  }
}

class LoftoneStarsPainter extends CustomPainter {
  const LoftoneStarsPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final haze = Paint()
      ..shader =
          const RadialGradient(colors: [Color(0x442b52ff), Color(0x00101a50)])
              .createShader(
                Rect.fromCircle(
                  center: Offset(size.width * .76, size.height * .18),
                  radius: size.width * .42,
                ),
              );
    canvas.drawRect(Offset.zero & size, haze);
    final star = Paint()..color = const Color(0x7798bfff);
    for (var i = 0; i < 58; i++) {
      final x = ((i * 97) % 997) / 997 * size.width;
      final y = ((i * 193 + 41) % 991) / 991 * size.height;
      final r = i % 9 == 0 ? 1.25 : .55;
      canvas.drawCircle(Offset(x, y), r, star);
    }
  }

  @override
  bool shouldRepaint(covariant LoftoneStarsPainter oldDelegate) => false;
}

class CosmicPromo extends StatelessWidget {
  final VoidCallback onPressed;
  const CosmicPromo({super.key, required this.onPressed});
  @override
  Widget build(BuildContext context) => Container(
    height: 210,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xff6655ff).withValues(alpha: .75)),
      gradient: const LinearGradient(
        colors: [Color(0xff101b58), Color(0xff151045), Color(0xff071431)],
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x442c54ff), blurRadius: 34, spreadRadius: -8),
      ],
    ),
    child: Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: GalaxyPainter())),
        Padding(
          padding: const EdgeInsets.fromLTRB(34, 28, 34, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'EXPLORA NUEVOS\nUNIVERSOS',
                style: TextStyle(
                  fontSize: 30,
                  height: .98,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onPressed,
                iconAlignment: IconAlignment.end,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff6743ff),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Descubrir'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class GalaxyPainter extends CustomPainter {
  const GalaxyPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .73, size.height * .48);
    for (var i = 8; i > 0; i--) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 - i * .35
        ..color = Color.lerp(
          const Color(0xff17dcff),
          const Color(0xffbd36ff),
          i / 8,
        )!.withValues(alpha: .16 + i * .045);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * .34);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 45.0 + i * 22,
          height: 11.0 + i * 7,
        ),
        paint,
      );
      canvas.restore();
    }
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..color = const Color(0xffd9fbff)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      Offset(size.width * .91, size.height * .16),
      15,
      Paint()..color = const Color(0xff5238a8),
    );
    canvas.drawCircle(
      Offset(size.width * .54, size.height * .78),
      8,
      Paint()..color = const Color(0xff071022),
    );
  }

  @override
  bool shouldRepaint(covariant GalaxyPainter oldDelegate) => false;
}

String timeLabel(Duration value) {
  final seconds = value.inSeconds.clamp(0, 359999);
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class CoverArt extends StatelessWidget {
  final Track? track;
  final double size;
  final double radius;
  const CoverArt({super.key, this.track, this.size = 56, this.radius = 14});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Carátula de ${track?.album ?? 'Loftone'}',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: track?.artwork != null
            ? Image.file(
                File(track!.artwork!),
                fit: BoxFit.cover,
                cacheWidth: (size * 2).round(),
                errorBuilder: (_, error, stack) => _fallback(),
              )
            : _fallback(),
      ),
    ),
  );
  Widget _fallback() {
    final seed = (track?.album ?? 'Loftone').codeUnits.fold(0, (a, b) => a + b);
    final color = HSLColor.fromAHSL(
      1,
      (seed * 17 % 360).toDouble(),
      .32,
      .31,
    ).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, .7)!],
        ),
      ),
      child: CustomPaint(
        painter: VinylPainter(),
        child: Center(
          child: Icon(
            Icons.music_note_rounded,
            size: size * .25,
            color: Colors.white.withValues(alpha: .85),
          ),
        ),
      ),
    );
  }
}

class VinylPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .61, size.height * .52);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: .13);
    for (var i = 1; i <= 8; i++) {
      canvas.drawCircle(center, size.width * (.15 + i * .055), paint);
    }
    canvas.drawLine(
      Offset(0, size.height * .8),
      Offset(size.width, size.height * .15),
      paint
        ..strokeWidth = size.width * .08
        ..color = Colors.white.withValues(alpha: .035),
    );
  }

  @override
  bool shouldRepaint(covariant VinylPainter oldDelegate) => false;
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    this.icon = Icons.library_music_outlined,
    required this.title,
    required this.subtitle,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .1),
            ),
            child: Icon(
              icon,
              size: 42,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    ),
  );
}

Future<String?> askName(
  BuildContext context,
  String title, {
  String initial = '',
  String label = 'Nombre',
}) async {
  final controller = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty) {
              Navigator.pop(context, controller.text.trim());
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
  // Dialog route animations may still reference its controller until unmounted.
  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return value;
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message, {
  String action = 'Confirmar',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(width: 430, child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
