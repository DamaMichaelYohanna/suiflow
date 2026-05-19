import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/network/offline_queue.dart';
import 'features/auth/auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Hive for offline storage
  await OfflineQueue.init();

  runApp(
    const ProviderScope(
      child: SuiverApp(),
    ),
  );
}

class SuiverApp extends StatelessWidget {
  const SuiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Suiver',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const AuthScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
