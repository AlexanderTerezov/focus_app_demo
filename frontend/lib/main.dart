import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/auth_gate.dart';
import 'screens/register_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _initializeDesktopWindow();

  /// IMPORTANT !!! REMOVE LATER DON'T FORGET ///
  //const storage = FlutterSecureStorage();
  //await storage.deleteAll();

  runApp(const MyApp());
}

Future<void> _initializeDesktopWindow() async {
  if (kIsWeb) return;

  const desktopPlatforms = <TargetPlatform>{
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  };

  if (!desktopPlatforms.contains(defaultTargetPlatform)) return;

  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(minimumSize: Size(400, 600));

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      theme: ThemeData(brightness: Brightness.light, fontFamily: 'Nunito'),

      darkTheme: ThemeData(brightness: Brightness.dark, fontFamily: 'Nunito'),

      themeMode: ThemeMode.system,

      home: const AuthGate(),

      routes: {'/register': (_) => const RegisterScreen()},
    );
  }
}
