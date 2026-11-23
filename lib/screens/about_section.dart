import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../services/update_service.dart';
import '../widgets.dart';

const _downloadUrl = 'https://github.com/csuarezsm/CompraClara/releases/latest';

/// «Acerca de» común a las apps de IT Canarias.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snap) {
        final v = snap.data == null ? '' : '${snap.data!.version} (${snap.data!.buildNumber})';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Acerca de', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/brand/png/icono-play-512.png', width: 40, height: 40),
            ),
            title: const Text('CompraClara'),
            subtitle: Text('Versión $v\n© IT Canarias · itcanarias.com · info@itcanarias.com'),
            isThreeLine: true,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Buscar actualizaciones'),
            subtitle: const Text('La app también lo comprueba sola una vez al día'),
            onTap: () => UpdateService.checkNow(context),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.share_outlined),
            title: const Text('Compartir la app'),
            onTap: () => SharePlus.instance.share(ShareParams(
              text: 'CompraClara: la lista de la compra por secciones del súper y comparando precios. $_downloadUrl',
            )),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacidad'),
            onTap: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Privacidad'),
                content: const SingleChildScrollView(
                  child: Text(
                    'Tus listas, compras y precios se guardan en tu móvil. Las fotos de tickets y etiquetas '
                    'se leen en el propio móvil y no se envían a ningún sitio.\n\n'
                    'Solo si creas una cuenta: la copia en la nube se guarda en el servidor de IT Canarias '
                    'y, si activas «Contribuir con mis precios», se envían de forma anónima el código del '
                    'producto, la tienda, el precio y la fecha. Puedes borrar la cuenta en cualquier momento.\n\n'
                    'No vendemos ni compartimos tus datos con terceros.',
                  ),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
              ),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licencias'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'CompraClara',
              applicationVersion: v,
              applicationLegalese: '© IT Canarias',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.map_outlined),
            title: Text('Datos de supermercados'),
            subtitle: Text('© colaboradores de OpenStreetMap (licencia ODbL)'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.apps_outlined),
            title: const Text('Más apps de IT Canarias'),
            onTap: () => snack(context, 'Visita itcanarias.com para ver todas las apps'),
          ),
        ]);
      },
    );
  }
}
