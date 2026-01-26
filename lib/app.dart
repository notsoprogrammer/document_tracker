import 'package:flutter/material.dart';
import 'widgets/auth_wrapper.dart';

class DocTrackerApp extends StatelessWidget {
  const DocTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        final mediaQuery = MediaQuery.of(context);
        // Clamp textScaler between 0.8 and 1.4 for controlled accessibility scaling
        final clampedScaler = mediaQuery.textScaler.clamp(minScaleFactor: 0.6, maxScaleFactor: 1.0);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: clampedScaler),
          child: MaterialApp(
            title: 'FileTrack Hub',
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF1976D2),
                brightness: Brightness.light,
              ),
              textTheme: const TextTheme(
                displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400, height: 1.12),
                displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400, height: 1.16),
                displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400, height: 1.22),
                headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, height: 1.25),
                headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400, height: 1.29),
                headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, height: 1.33),
                titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, height: 1.27),
                titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.5, letterSpacing: 0.15),
                titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.43, letterSpacing: 0.1),
                bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5, letterSpacing: 0.15),
                bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.43, letterSpacing: 0.25),
                bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.33, letterSpacing: 0.4),
                labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, height: 1.43, letterSpacing: 0.1),
                labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.33, letterSpacing: 0.5),
                labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, height: 1.45, letterSpacing: 0.5),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              appBarTheme: const AppBarTheme(
                elevation: 0,
                centerTitle: true,
                backgroundColor: Color(0xFF1976D2),
                foregroundColor: Colors.white,
              ),
            ),
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
