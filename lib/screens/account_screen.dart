import 'package:flutter/material.dart';

import '../main.dart' show repo;
import '../services/cloud_service.dart';
import '../util.dart';
import '../widgets.dart';

class _AccountData {
  _AccountData(this.email, this.url, this.share, this.community, this.autoBackup, this.lastSync, this.lastBackup);

  final String? email;
  final String url;
  final bool share;
  final bool community;
  final bool autoBackup;
  final String? lastSync;
  final String? lastBackup;
}

/// Cuenta, copia en la nube y precios compartidos.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _busy = false;

  Future<_AccountData> _load() async => _AccountData(
        await CloudService.email(),
        await CloudService.baseUrl(),
        await CloudService.sharePrices(),
        await CloudService.useCommunity(),
        (await repo.getSetting('auto_cloud_backup')) != '0',
        await repo.getSetting('last_sync'),
        await repo.getSetting('last_cloud_backup'),
      );

  Future<void> _do(Future<String?> Function() f) async {
    setState(() => _busy = true);
    try {
      final msg = await f();
      if (msg != null && mounted) snack(context, msg);
    } catch (e) {
      if (mounted) snack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _auth(bool register) async {
    final email = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(register ? 'Crear cuenta' : 'Entrar'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Correo'),
          ),
          TextField(
            controller: pass,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(labelText: register ? 'Contraseña (mínimo 8)' : 'Contraseña'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(register ? 'Crear' : 'Entrar')),
        ],
      ),
    );
    if (ok != true) return;
    await _do(() async {
      if (register) {
        await CloudService.register(email.text.trim(), pass.text);
      } else {
        await CloudService.login(email.text.trim(), pass.text);
      }
      return register ? 'Cuenta creada' : 'Sesión iniciada';
    });
  }

  String _when(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    if (d == null) return 'nunca';
    return '${dateEs(isoDate(d))} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta y nube')),
      body: Stack(children: [
        RepoBuilder<_AccountData>(
          load: _load,
          builder: (context, d) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (d.email == null) ...[
                const Text(
                  'Con una cuenta guardas tus datos en la nube (para cambiar de móvil) y puedes '
                  'compartir y recibir precios de otros usuarios cerca de ti. La app funciona igual sin cuenta.',
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => _auth(true), child: const Text('Crear cuenta')),
                OutlinedButton(onPressed: () => _auth(false), child: const Text('Ya tengo cuenta')),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(d.email!),
                  subtitle: const Text('Sesión iniciada'),
                ),
                const Divider(height: 24),
                Text('Copia en la nube', style: Theme.of(context).textTheme.titleMedium),
                Text('Última copia: ${_when(d.lastBackup)}'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: d.autoBackup,
                  onChanged: (v) => repo.setSetting('auto_cloud_backup', v ? '1' : '0'),
                  title: const Text('Copia automática diaria'),
                ),
                Wrap(spacing: 8, children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _do(() async {
                      await CloudService.uploadBackup();
                      return 'Copia subida';
                    }),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Subir copia ahora'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirm(context,
                          title: 'Restaurar desde la nube',
                          message: 'Se sustituyen los datos de este móvil por los de la copia en la nube.',
                          okLabel: 'Restaurar');
                      if (!ok) return;
                      await _do(() async => 'Restaurados ${await CloudService.restoreBackup()} registros');
                    },
                    icon: const Icon(Icons.cloud_download_outlined),
                    label: const Text('Restaurar'),
                  ),
                ]),
                const Divider(height: 32),
                Text('Precios compartidos', style: Theme.of(context).textTheme.titleMedium),
                const Text(
                  'Se envían solo el código del producto, la tienda, el precio y la fecha, sin tu nombre '
                  'ni tus listas. Solo se reciben precios de tiendas dentro de tu distancia máxima.',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: d.share,
                  onChanged: (v) => repo.setSetting('share_prices', v ? '1' : '0'),
                  title: const Text('Contribuir con mis precios'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: d.community,
                  onChanged: (v) => repo.setSetting('use_community', v ? '1' : '0'),
                  title: const Text('Usar precios de la comunidad'),
                  subtitle: const Text('Las tiendas que no tengas se añaden con la etiqueta «comunidad»'),
                ),
                Text('Última sincronización: ${_when(d.lastSync)}'),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _do(CloudService.sync),
                  icon: const Icon(Icons.sync),
                  label: const Text('Sincronizar precios ahora'),
                ),
                const Divider(height: 32),
                TextButton(
                  onPressed: () => _do(() async {
                    await CloudService.logout();
                    return 'Sesión cerrada';
                  }),
                  child: const Text('Cerrar sesión'),
                ),
                TextButton(
                  onPressed: () async {
                    final ok = await confirm(context,
                        title: 'Borrar la cuenta',
                        message: 'Se borran la cuenta y la copia en la nube. Los datos de este móvil no se tocan.',
                        okLabel: 'Borrar cuenta');
                    if (ok) {
                      await _do(() async {
                        await CloudService.deleteAccount();
                        return 'Cuenta borrada';
                      });
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('Borrar la cuenta'),
                ),
              ],
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Servidor'),
                subtitle: Text(d.url),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final v = await promptText(context, title: 'Dirección del servidor', initial: d.url);
                  if (v != null) await repo.setSetting('cloud_url', v.trim());
                },
              ),
              TextButton(
                onPressed: () => _do(() async =>
                    await CloudService.health() ? 'Servidor disponible' : 'El servidor no responde'),
                child: const Text('Probar conexión'),
              ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
      ]),
    );
  }
}
