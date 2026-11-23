import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:quick_actions/quick_actions.dart';

import 'data/repository.dart';
import 'screens/catalog_screen.dart';
import 'services/cloud_service.dart';
import 'services/update_service.dart';
import 'theme/appearance.dart';
import 'screens/lists_screen.dart';
import 'screens/more_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/stores_screen.dart';
import 'screens/ticket_screen.dart';

/// Acceso global a los datos (todo es local en el móvil).
late Repo repo;

/// Apariencia (tema, modo, letra) común a las apps de IT Canarias.
late Appearance appearance;

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  repo = await Repo.open();
  appearance = Appearance(repo);
  await appearance.load();
  final onboarded = await repo.getSetting('onboarded') != null;
  runApp(CompraClaraApp(showOnboarding: !onboarded));
}

class CompraClaraApp extends StatelessWidget {
  const CompraClaraApp({super.key, required this.showOnboarding});

  final bool showOnboarding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
      title: 'CompraClara',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: appearance.build(Brightness.light),
      darkTheme: appearance.build(Brightness.dark),
      themeMode: appearance.effectiveMode,
      themeAnimationDuration: appearance.reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
      builder: appearance.wrap,
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: showOnboarding ? const OnboardingScreen() : const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _setupQuickActions();
    CloudService.autoSync();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) UpdateService.checkOnStart(ctx);
    });
  }

  /// Accesos directos al mantener pulsado el icono de la app.
  void _setupQuickActions() {
    const qa = QuickActions();
    qa.initialize((type) {
      final nav = navigatorKey.currentState;
      if (nav == null) return;
      switch (type) {
        case 'scan':
          scanProduct(nav.context);
        case 'ticket':
          nav.push(MaterialPageRoute(builder: (_) => const TicketScreen()));
        case 'lists':
          setState(() => _index = 0);
      }
    });
    qa.setShortcutItems(const [
      ShortcutItem(type: 'lists', localizedTitle: 'Mis listas'),
      ShortcutItem(type: 'scan', localizedTitle: 'Escanear producto'),
      ShortcutItem(type: 'ticket', localizedTitle: 'Leer ticket'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ListsScreen(),
          CatalogScreen(),
          StoresScreen(),
          MoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Listas',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Artículos',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Súpers',
          ),
          NavigationDestination(
            icon: Icon(Icons.apps_outlined),
            selectedIcon: Icon(Icons.apps),
            label: 'Más',
          ),
        ],
      ),
    );
  }
}
