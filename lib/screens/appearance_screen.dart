import 'package:flutter/material.dart';

import '../main.dart' show appearance;
import '../theme/appearance.dart';

/// Ajustes de apariencia: colores, modo, tamaño de letra y accesibilidad.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) {
        final a = appearance;
        final scheme = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        Widget title(String s) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Text(s, style: t.titleMedium),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Colores y letra')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              title('Color'),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final th in appThemes)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => a.setTheme(th.key),
                      child: SizedBox(
                        width: 76,
                        child: Column(children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: th.key == 'contraste' ? Colors.black : th.color,
                              border: Border.all(
                                color: a.themeKey == th.key ? scheme.onSurface : scheme.outlineVariant,
                                width: a.themeKey == th.key ? 3 : 1,
                              ),
                            ),
                            child: a.themeKey == th.key
                                ? Icon(Icons.check,
                                    color: th.key == 'contraste' ? const Color(0xFFFFD400) : Colors.white)
                                : null,
                          ),
                          const SizedBox(height: 4),
                          Text(th.name, textAlign: TextAlign.center, style: t.bodySmall),
                        ]),
                      ),
                    ),
                ],
              ),
              title('Modo'),
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.system, label: Text('Sistema'), icon: Icon(Icons.brightness_auto)),
                  ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro'), icon: Icon(Icons.dark_mode)),
                ],
                selected: {a.mode},
                onSelectionChanged: a.theme.forceDark ? null : (v) => a.setMode(v.first),
              ),
              if (a.theme.forceDark)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('El color «${a.theme.name}» siempre es oscuro.', style: t.bodySmall),
                ),
              title('Tamaño de letra: ${(a.textScale * 100).round()} %'),
              Slider(
                min: 0.85,
                max: 1.6,
                divisions: 15,
                value: a.textScale,
                label: '${(a.textScale * 100).round()} %',
                onChanged: a.setTextScale,
              ),
              Wrap(spacing: 8, runSpacing: 4, children: [
                for (final e in const {'Pequeña': 0.9, 'Normal': 1.0, 'Grande': 1.2, 'Muy grande': 1.4}.entries)
                  ChoiceChip(
                    label: Text(e.key),
                    selected: (a.textScale - e.value).abs() < 0.01,
                    onSelected: (_) => a.setTextScale(e.value),
                  ),
              ]),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Vista previa', style: t.labelLarge?.copyWith(color: scheme.primary)),
                    const SizedBox(height: 4),
                    Text('Leche entera 1 L', style: t.titleMedium),
                    Text('Lácteos y huevos · 0,95 €', style: t.bodyMedium),
                    const SizedBox(height: 8),
                    FilledButton(onPressed: () {}, child: const Text('Ir de compras')),
                  ]),
                ),
              ),
              title('Accesibilidad'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: a.highContrast,
                onChanged: a.setHighContrast,
                title: const Text('Alto contraste'),
                subtitle: const Text('Textos y bordes más marcados'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: a.bold,
                onChanged: a.setBold,
                title: const Text('Texto en negrita'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: a.reduceMotion,
                onChanged: a.setReduceMotion,
                title: const Text('Reducir animaciones'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: a.reset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Volver a la apariencia por defecto'),
              ),
            ],
          ),
        );
      },
    );
  }
}
