import 'dart:io';

import 'package:image/image.dart' as image;

void main() {
  final sourceFile = File('assets/logo_loftone_white.png');
  final source = image.decodePng(sourceFile.readAsBytesSync());
  if (source == null) {
    throw StateError('No se pudo leer ${sourceFile.path}.');
  }

  // El logo blanco tiene transparencia: lo componemos sobre un fondo oscuro
  // cuadrado para que el icono se lea bien en el dock y en la barra de tareas.
  final background = image.ColorRgba8(8, 10, 22, 255);
  final padding = (source.width * .12).round();
  final side = source.width + padding * 2;
  final canvas = image.Image(width: side, height: side);
  image.fillRect(canvas, x1: 0, y1: 0, x2: side, y2: side, color: background);
  image.compositeImage(canvas, source, dstX: padding, dstY: padding);

  const macSizes = [16, 32, 64, 128, 256, 512, 1024];
  for (final size in macSizes) {
    final icon = image.copyResize(
      canvas,
      width: size,
      height: size,
      interpolation: image.Interpolation.cubic,
    );
    File('macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(image.encodePng(icon));
  }

  const windowsSizes = [16, 24, 32, 48, 64, 128, 256];
  final windowsIcon = image.copyResize(
    canvas,
    width: windowsSizes.first,
    height: windowsSizes.first,
    interpolation: image.Interpolation.cubic,
  );
  for (final size in windowsSizes.skip(1)) {
    windowsIcon.addFrame(image.copyResize(
      canvas,
      width: size,
      height: size,
      interpolation: image.Interpolation.cubic,
    ));
  }
  File('windows/runner/resources/app_icon.ico')
    ..createSync(recursive: true)
    ..writeAsBytesSync(image.encodeIco(windowsIcon));

  const iosIcons = {
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  iosIcons.forEach((name, size) {
    final icon = image.copyResize(
      canvas,
      width: size,
      height: size,
      interpolation: image.Interpolation.cubic,
    );
    File('ios/Runner/Assets.xcassets/AppIcon.appiconset/$name')
      ..createSync(recursive: true)
      ..writeAsBytesSync(image.encodePng(icon));
  });
}
