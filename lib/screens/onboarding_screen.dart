import 'package:flutter/material.dart';

import '../data/demo.dart';
import '../main.dart' show repo, HomeShell;
import '../data/models.dart';
import '../services/location_service.dart';
import 'store_picker_screen.dart';

/// Primer uso: tienda habitual, zona y primeros artículos (o datos de ejemplo).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  Store? _picked;
  int _i = 0;
  bool _busy = false;
  bool _locate = true;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish({bool demo = false}) async {
    setState(() => _busy = true);
    try {
      if (demo) {
        await loadDemoData(repo);
      } else {
        if (_locate && await repo.homeZone() == null) {
          final pos = await LocationService.current();
          if (pos != null) await repo.setHomeZone(pos.lat, pos.lng);
        }
        if (_picked != null) await repo.createList('Compra semanal', storeId: _picked!.id);
      }
      await repo.setSetting('onboarded', '1');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
  }

  void _next() => _page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget page(IconData? icon, String title, String body, List<Widget> extra) => Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon == null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset('assets/brand/png/icono-play-512.png', width: 96, height: 96),
                    )
                  : Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(title, style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(body, style: t.bodyLarge, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ...extra,
            ],
          ),
        );
    return Scaffold(
      body: SafeArea(
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _page,
                      onPageChanged: (i) => setState(() => _i = i),
                      children: [
                        page(
                          null,
                          'Bienvenido a CompraClara',
                          'Tu lista de la compra ordenada por las secciones de tu supermercado, '
                              'con tus precios y comparando tiendas cercanas.',
                          [FilledButton(onPressed: _next, child: const Text('Empezar'))],
                        ),
                        page(
                          Icons.view_week_outlined,
                          'Compra por secciones',
                          'En la tienda eliges la sección, ves solo lo que te toca allí, '
                              'lo marcas como cogido y pasas a la siguiente.\n\n'
                              'Añade artículos escribiendo, por voz, escaneando el código o leyendo el ticket.',
                          [FilledButton(onPressed: _next, child: const Text('Siguiente'))],
                        ),
                        page(
                          Icons.storefront_outlined,
                          '¿Cuál es tu supermercado habitual?',
                          'Elígelo de la lista de cercanos. Se crea con 18 secciones que luego puedes ordenar según el recorrido real.',
                          [
                            if (_picked != null)
                              ListTile(
                                leading: const Icon(Icons.storefront),
                                title: Text(_picked!.name),
                                subtitle: Text(_picked!.address),
                              ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final s = await pickStoreFromCatalog(context);
                                if (s != null) setState(() => _picked = s);
                              },
                              icon: const Icon(Icons.near_me_outlined),
                              label: Text(_picked == null ? 'Buscar supermercados cerca' : 'Cambiar'),
                            ),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _locate,
                              onChanged: (v) => setState(() => _locate = v ?? true),
                              title: const Text('Guardar mi ubicación como zona habitual'),
                              subtitle: const Text('Para comparar solo supermercados cercanos'),
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: () => _finish(),
                              child: Text(_picked == null ? 'Saltar' : 'Terminar'),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () => _finish(demo: true),
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('Probar con datos de ejemplo'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var k = 0; k < 3; k++)
                          Container(
                            margin: const EdgeInsets.all(4),
                            width: k == _i ? 18 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: k == _i
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
