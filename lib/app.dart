import 'package:flutter/material.dart';
import 'widgets/auth_wrapper.dart';
import 'theme/app_theme.dart';

class DocTrackerApp extends StatelessWidget {
  const DocTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        final clampedScaler = mediaQuery.textScaler.clamp(minScaleFactor: 0.6, maxScaleFactor: 0.9);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedScaler),
          child: MaterialApp(
            title: 'FileTrack Hub',
            theme: AppTheme.build(),
            home: const AuthWrapper(),
            routes: {
              '/home': (context) => const AuthWrapper(), // Since AuthWrapper handles showing HomeScreen
            },
          ),
        );
      },
    );
  }
}
