import 'package:flutter/material.dart';

import '../data/demo.dart';
import '../main.dart' show repo;
import '../services/backup_service.dart';
import '../services/location_service.dart';
import '../util.dart';
import '../widgets.dart';
import 'about_section.dart';
import 'appearance_screen.dart';

/// Alérgenos (clave de Open Food Facts -> nombre).
const allergenNames = {
  'gluten': 'Gluten',
  'milk': 'Leche / lactosa',
  'eggs': 'Huevo',
  'nuts': 'Frutos de cáscara',
  'peanuts': 'Cacahuete',
  'soybeans': 'Soja',
  'fish': 'Pescado',
  'crustaceans': 'Crustáceos',
  'molluscs': 'Moluscos',
  'celery': 'Apio',
  'mustard': 'Mostaza',
  'sesame-seeds': 'Sésamo',
  'sulphur-dioxide-and-sulphites': 'Sulfitos',
  'lupin': 'Altramuz',
};

/// Dietas (etiqueta de Open Food Facts -> nombre).
const dietNames = {
  'vegan': 'Vegana',
  'vegetarian': 'Vegetariana',
  'no-gluten': 'Sin gluten',
  'no-lactose': 'Sin lactosa',
  'organic': 'Ecológica',
};

class _SettingsData {
  _SettingsData(this.radius, this.zone, this.budget, this.allergens, this.diets, this.lastBackup);

  final double radius;
  final ({double lat, double lng})? zone;
  final double? budget;
  final Set<String> allergens;
  final Set<String> diets;
  final String? lastBackup;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double? _dragging;

  Future<_SettingsData> _load() async => _SettingsData(
        await repo.radiusKm(),
        await repo.homeZone(),
        await repo.monthlyBudget(),
        await repo.avoidAllergens(),
        await repo.diets(),
        await repo.getSetting('last_backup'),
      );

  Future<void> _setZoneHere() async {
    final pos = await LocationService.current();
    if (!mounted) return;
    if (pos == null) {
      snack(context, 'No se pudo obtener la ubicación. Activa el GPS y da permiso a la app.');
      return;
    }
    await repo.setHomeZone(pos.lat, pos.lng);
    if (mounted) snack(context, 'Zona habitual guardada');
  }

  Future<void> _run(Future<void> Function() f, String errorPrefix) async {
    try {
      await f();
    } catch (e) {
      if (mounted) snack(context, '$errorPrefix: $e');
    }
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: RepoBuilder<_SettingsData>(
        load: _load,
        builder: (context, d) {
          final radius = _dragging ?? d.radius;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Colores y letra'),
                subtitle: const Text('Tema de color, claro u oscuro, tamaño de letra y contraste'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const AppearanceScreen())),
              ),
              const Divider(height: 32),
              _title('Distancia máxima para comparar'),
              const Text(
                'Solo se comparan los supermercados a menos de esta distancia de donde estás. '
                'Así, si estás en Lanzarote no se mezclan precios de Gran Canaria.',
              ),
              Text('${radius.round()} km',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              Slider(
                min: 1,
                max: 100,
                divisions: 99,
                value: radius.clamp(1, 100),
                label: '${radius.round()} km',
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: (v) async {
                  await repo.setRadiusKm(v);
                  if (mounted) setState(() => _dragging = null);
                },
              ),
              Wrap(spacing: 8, children: [
                for (final km in const [5, 10, 20, 40])
                  ActionChip(label: Text('$km km'), onPressed: () => repo.setRadiusKm(km.toDouble())),
              ]),
              const Divider(height: 32),
              _title('Zona habitual'),
              const Text('Punto de referencia cuando el móvil no da tu ubicación. Fíjala estando en casa.'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(d.zone == null ? Icons.location_off_outlined : Icons.home_outlined),
                title: Text(d.zone == null ? 'Sin zona habitual' : 'Zona habitual guardada'),
                subtitle: d.zone == null
                    ? null
                    : Text('${d.zone!.lat.toStringAsFixed(4)}, ${d.zone!.lng.toStringAsFixed(4)}'),
              ),
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(
                  onPressed: _setZoneHere,
                  icon: const Icon(Icons.my_location),
                  label: const Text('Usar mi ubicación actual'),
                ),
                if (d.zone != null)
                  TextButton(onPressed: () => repo.setHomeZone(null, null), child: const Text('Quitar')),
              ]),
              const Divider(height: 32),
              _title('Presupuesto mensual'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.savings_outlined),
                title: Text(d.budget == null ? 'Sin presupuesto' : money(d.budget)),
                subtitle: const Text('Aviso al acercarte y al pasarte, contando las compras del mes'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final v = await promptText(context,
                      title: 'Presupuesto mensual (€)',
                      initial: d.budget == null ? '' : d.budget!.toStringAsFixed(0),
                      hint: '300',
                      okLabel: 'Guardar');
                  if (v == null) return;
                  await repo.setMonthlyBudget(parseNum(v));
                },
              ),
              if (d.budget != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () => repo.setMonthlyBudget(null), child: const Text('Quitar presupuesto')),
                ),
              const Divider(height: 32),
              _title('Alergias e intolerancias'),
              const Text('Se avisa en los artículos que las contengan (datos de Open Food Facts al escanear).'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 2, children: [
                for (final e in allergenNames.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: d.allergens.contains(e.key),
                    onSelected: (v) {
                      final s = {...d.allergens};
                      v ? s.add(e.key) : s.remove(e.key);
                      repo.setAvoidAllergens(s);
                    },
                  ),
              ]),
              _title('Dieta'),
              const Text('Se avisa en los artículos que no consten como aptos.'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 2, children: [
                for (final e in dietNames.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: d.diets.contains(e.key),
                    onSelected: (v) {
                      final s = {...d.diets};
                      v ? s.add(e.key) : s.remove(e.key);
                      repo.setDiets(s);
                    },
                  ),
              ]),
              const Divider(height: 32),
              _title('Copia de seguridad'),
              Text(d.lastBackup == null
                  ? 'Nunca has hecho una copia. Guárdala en Drive o envíatela por correo.'
                  : 'Última copia: ${dateEs(d.lastBackup!)}'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.backup_outlined),
                title: const Text('Hacer copia de seguridad'),
                subtitle: const Text('Archivo con todos tus datos para guardarlo donde quieras'),
                onTap: () => _run(BackupService.shareBackup, 'No se pudo crear la copia'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restore),
                title: const Text('Restaurar copia'),
                subtitle: const Text('Sustituye los datos de este móvil por los del archivo'),
                onTap: () async {
                  final ok = await confirm(context,
                      title: 'Restaurar copia',
                      message: 'Se borrarán los datos actuales de este móvil y se cargarán los de la copia.',
                      okLabel: 'Elegir archivo');
                  if (!ok) return;
                  try {
                    final n = await BackupService.restoreFromFile();
                    if (n != null && mounted) snack(this.context, 'Copia restaurada ($n registros)');
                  } catch (e) {
                    if (mounted) snack(this.context, 'No se pudo restaurar: $e');
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_chart_outlined),
                title: const Text('Exportar compras (CSV)'),
                subtitle: const Text('Para Excel: fecha, tienda, artículo, cantidad, precio e importe'),
                onTap: () => _run(BackupService.sharePurchasesCsv, 'No se pudo exportar'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.price_change_outlined),
                title: const Text('Exportar precios (CSV)'),
                onTap: () => _run(BackupService.sharePricesCsv, 'No se pudo exportar'),
              ),
              const Divider(height: 32),
              _title('Datos de prueba'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.science_outlined),
                title: const Text('Cargar datos de ejemplo'),
                subtitle: const Text('Supermercados ficticios (3 en Lanzarote y 1 en Gran Canaria), '
                    'artículos con precios, compras anteriores y listas'),
                onTap: () => loadDemoWithFeedback(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                title: const Text('Borrar todos los datos'),
                onTap: () async {
                  final ok = await confirm(context,
                      title: 'Borrar todos los datos',
                      message: 'No se puede deshacer. Haz antes una copia si la necesitas.',
                      okLabel: 'Borrar todo');
                  if (ok) {
                    await repo.clearAll();
                    if (mounted) snack(this.context, 'Datos borrados');
                  }
                },
              ),
              const Divider(height: 32),
              const AboutSection(),
            ],
          );
        },
      ),
    );
  }
}

Future<void> loadDemoWithFeedback(BuildContext context) async {
  final ok = await confirm(context,
      title: 'Cargar datos de ejemplo',
      message: 'Se añaden supermercados, artículos, precios, compras y listas ficticios a lo que ya tengas. '
          'Puedes borrarlo todo después desde Ajustes.',
      okLabel: 'Cargar');
  if (!ok || !context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    await loadDemoData(repo);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
  if (context.mounted) snack(context, 'Datos de ejemplo cargados');
}
