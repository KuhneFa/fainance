import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/models.dart';
import 'core/theme.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/upload/upload_screen.dart';

void main() async {
  // Stellt sicher dass Flutter vollständig initialisiert ist bevor
  // wir async-Code ausführen. Pflicht wenn du WidgetsBinding vor runApp nutzt.
  WidgetsFlutterBinding.ensureInitialized();

  // Deutsche Datumsformatierung initialisieren (für _dateFormat in den Screens)
  await initializeDateFormatting('de_DE');

  // StatusBar: heller Text auf dunklem Hintergrund passend zum Dark Theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

  // Nur Portrait-Modus erlauben — für den MVP sinnvoll,
  // Landscape-Layout kannst du später ergänzen
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const FinanceApp());
}


class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finance AI',
      debugShowCheckedModeBanner: false, // rotes "DEBUG"-Banner entfernen
      theme: AppTheme.dark,

      // ── Routing ──────────────────────────────────────────────────────────────
      // Named Routes: Navigation per String statt direkter Widget-Referenz.
      // Das entkoppelt die Screens voneinander.
      // Navigator.of(context).pushNamed('/dashboard', arguments: uploadId)
      initialRoute: '/',
      routes: {
        '/': (_) => const UploadScreen(),
        '/dashboard': (_) => const DashboardScreen(),
        '/insights': (_) => const InsightsScreen(),
      },

      // onGenerateRoute: Fallback für Routes die nicht in der Map sind.
      // Verhindert einen Crash bei unbekannten Routes.
      onUnknownRoute: (settings) => MaterialPageRoute(
        builder: (_) => Scaffold(
          body: Center(
            child: Text('Route nicht gefunden: ${settings.name}'),
          ),
        ),
      ),

      // Page Transitions: subtile Slide-Animation zwischen Screens
      // passend zum modernen UI-Stil
      onGenerateRoute: (settings) {
        final routes = {
          '/': (_) => const UploadScreen(),
          '/dashboard': (_) => const DashboardScreen(),
          '/insights': (_) => const InsightsScreen(),
        };

        final builder = routes[settings.name];
        if (builder == null) return null;

        return PageRouteBuilder(
          settings: settings,
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, animation, _, child) {
            // Slide von rechts nach links — Standard Mobile-Pattern
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 280),
        );
      },
    );
  }
}