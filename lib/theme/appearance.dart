import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/repository.dart';

/// Tema de color común a las apps de IT Canarias.
class AppTheme {
  const AppTheme(this.key, this.name, this.color, {this.forceDark = false});

  final String key;
  final String name;
  final Color color;
  final bool forceDark;
}

const appThemes = <AppTheme>[
  AppTheme('verde', 'Verde', Color(0xFF2E7D5B)),
  AppTheme('azul', 'Azul', Color(0xFF1E5AA8)),
  AppTheme('morado', 'Morado', Color(0xFF6A3FB5)),
  AppTheme('burdeos', 'Burdeos', Color(0xFF8C1D3A)),
  AppTheme('naranja', 'Naranja', Color(0xFFC2570C)),
  AppTheme('madera', 'Madera', Color(0xFF8A5A2B)),
  AppTheme('grafito', 'Grafito', Color(0xFF455A64)),
  AppTheme('noche', 'Noche', Color(0xFF1F2A44), forceDark: true),
  AppTheme('contraste', 'Alto contraste', Color(0xFFFFD400)),
];

/// Tema por defecto de CompraClara.
const defaultThemeKey = 'verde';

/// Ajustes de apariencia: tema, modo, tamaño de letra, contraste, negrita y animaciones.
class Appearance extends ChangeNotifier {
  Appearance(this._repo);

  final Repo _repo;

  String themeKey = defaultThemeKey;
  ThemeMode mode = ThemeMode.system;
  double textScale = 1.0;
  bool highContrast = false;
  bool bold = false;
  bool reduceMotion = false;

  AppTheme get theme => appThemes.firstWhere((t) => t.key == themeKey, orElse: () => appThemes.first);

  Future<void> load() async {
    themeKey = await _repo.getSetting('ui_theme') ?? defaultThemeKey;
    mode = switch (await _repo.getSetting('ui_mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    textScale = (double.tryParse(await _repo.getSetting('ui_text_scale') ?? '') ?? 1.0).clamp(0.85, 1.6);
    highContrast = await _repo.getSetting('ui_contrast') == '1';
    bold = await _repo.getSetting('ui_bold') == '1';
    reduceMotion = await _repo.getSetting('ui_reduce_motion') == '1';
  }

  Future<void> _save(String key, String? value) async {
    notifyListeners();
    await _repo.setSetting(key, value);
  }

  Future<void> setTheme(String key) {
    themeKey = key;
    return _save('ui_theme', key);
  }

  Future<void> setMode(ThemeMode m) {
    mode = m;
    return _save('ui_mode', switch (m) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', _ => 'system' });
  }

  Future<void> setTextScale(double v) {
    textScale = v.clamp(0.85, 1.6);
    return _save('ui_text_scale', textScale.toStringAsFixed(2));
  }

  Future<void> setHighContrast(bool v) {
    highContrast = v;
    return _save('ui_contrast', v ? '1' : '0');
  }

  Future<void> setBold(bool v) {
    bold = v;
    return _save('ui_bold', v ? '1' : '0');
  }

  Future<void> setReduceMotion(bool v) {
    reduceMotion = v;
    return _save('ui_reduce_motion', v ? '1' : '0');
  }

  Future<void> reset() async {
    themeKey = defaultThemeKey;
    mode = ThemeMode.system;
    textScale = 1.0;
    highContrast = false;
    bold = false;
    reduceMotion = false;
    notifyListeners();
    for (final k in ['ui_theme', 'ui_mode', 'ui_text_scale', 'ui_contrast', 'ui_bold', 'ui_reduce_motion']) {
      await _repo.setSetting(k, null);
    }
  }

  ThemeMode get effectiveMode => theme.forceDark ? ThemeMode.dark : mode;

  ThemeData build(Brightness b) {
    final contrast = highContrast || theme.key == 'contraste';
    ColorScheme scheme;
    if (theme.key == 'contraste') {
      scheme = b == Brightness.dark
          ? const ColorScheme.dark(
              primary: Color(0xFFFFD400),
              onPrimary: Colors.black,
              secondary: Color(0xFFFFD400),
              onSecondary: Colors.black,
              surface: Colors.black,
              onSurface: Colors.white,
              error: Color(0xFFFF6B6B),
              outline: Colors.white,
            )
          : const ColorScheme.light(
              primary: Colors.black,
              onPrimary: Color(0xFFFFD400),
              secondary: Colors.black,
              onSecondary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
              error: Color(0xFFB00020),
              outline: Colors.black,
            );
    } else {
      scheme = ColorScheme.fromSeed(
        seedColor: theme.color,
        brightness: b,
        contrastLevel: contrast ? 1.0 : 0.0,
      );
    }
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerTheme: DividerThemeData(color: contrast ? scheme.outline : null),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: b == Brightness.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
    );
  }

  /// Aplica tamaño de letra, negrita y animaciones a toda la app.
  Widget wrap(BuildContext context, Widget? child) {
    final mq = MediaQuery.of(context);
    final system = mq.textScaler.scale(14) / 14;
    return MediaQuery(
      data: mq.copyWith(
        textScaler: TextScaler.linear((system * textScale).clamp(0.8, 2.0)),
        boldText: mq.boldText || bold,
        disableAnimations: mq.disableAnimations || reduceMotion,
      ),
      child: child ?? const SizedBox.shrink(),
    );
  }
}
