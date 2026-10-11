import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'application/app_controller.dart';
import 'presentation/app_screen.dart';

Future<void> main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  try {
    MediaKit.ensureInitialized();
    final app = await AppController.create();
    FlutterNativeSplash.remove();
    runApp(
      ProviderScope(
        overrides: [appProvider.overrideWith((ref) => app)],
        child: const MusicApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 20),
                    const Text(
                      'No se pudo abrir Loftone',
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Comprueba los permisos de la carpeta de datos y que la aplicación conserve sus bibliotecas DLL junto al ejecutable. Consulta el README para instalar las dependencias.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: main,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MusicApp extends ConsumerWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appProvider);
    final colors = ColorScheme.fromSeed(
      seedColor: app.dark ? const Color(0xff7657ff) : Color(app.accent),
      brightness: app.dark ? Brightness.dark : Brightness.light,
      surface: app.dark ? const Color(0xff080d22) : const Color(0xfff6f7fb),
    );
    return MaterialApp(
      title: 'Loftone',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colors,
        scaffoldBackgroundColor: app.dark
            ? const Color(0xff000000)
            : const Color(0xfffafafa),
        fontFamily: '-apple-system, BlinkMacSystemFont, Segoe UI, Roboto',
        appBarTheme: const AppBarTheme(centerTitle: false),
        tooltipTheme: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 450),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: app.dark 
              ? const Color(0xff1a1a1a)
              : const Color(0xfff0f0f0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: app.dark
              ? const Color(0xff1a1a1a)
              : const Color(0xfff5f5f5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide.none,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        dividerTheme: DividerThemeData(
          color: colors.outlineVariant.withValues(alpha: .15),
        ),
      ),
      home: const AppScreen(),
    );
  }
}
