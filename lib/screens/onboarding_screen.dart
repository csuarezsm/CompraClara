import 'package:flutter/material.dart';

import '../data/demo.dart';
import '../main.dart' show repo, HomeShell;
import '../services/location_service.dart';

/// Primer uso: tienda habitual, zona y primeros artículos (o datos de ejemplo).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _page = PageController();
  final _store = TextEditingController();
  int _i = 0;
  bool _busy = false;
  bool _locate = true;

  @override
  void dispose() {
    _page.dispose();
    _store.dispose();
    super.dispose();
  }

  Future<void> _finish({bool demo = false}) async {
    setState(() => _busy = true);
    try {
      if (demo) {
        await loadDemoData(repo);
      } else if (_store.text.trim().isNotEmpty) {
        final s = await repo.addStore(_store.text.trim());
        if (_locate) {
          final pos = await LocationService.current();
          if (pos != null) {
            await repo.setStoreLocation(s.id, pos.lat, pos.lng);
            if (await repo.homeZone() == null) await repo.setHomeZone(pos.lat, pos.lng);
          }
        }
        await repo.createList('Compra semanal', storeId: s.id);
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
    Widget page(IconData icon, String title, String body, List<Widget> extra) => Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: Theme.of(context).colorScheme.primary),
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
                          Icons.shopping_basket_outlined,
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
                          'Se crea con 18 secciones que luego puedes ordenar según el recorrido real.',
                          [
                            TextField(
                              controller: _store,
                              onChanged: (_) => setState(() {}),
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Supermercado',
                                hintText: 'Mercadona Arrecife',
                                border: OutlineInputBorder(),
                              ),
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
                              child: Text(_store.text.trim().isEmpty ? 'Saltar' : 'Terminar'),
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
