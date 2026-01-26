import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../screens/home_screen.dart';
import '../services/auth_service.dart';
import '../services/connectivity_service.dart';

class AuthResult {
  final bool isAuthorized;
  final bool isOnline;

  const AuthResult(this.isAuthorized, this.isOnline);
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthResult>(
      future: _checkAuthWithConnectivity().timeout(
        const Duration(seconds: 5),
        onTimeout: () => const AuthResult(false, false),
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Text('Error loading authentication status'),
            ),
          );
        }

        final result = snapshot.data;
        if (result == null) return const LoginScreen();

        if (result.isAuthorized) {
          return const HomeScreen();
        } else if (!result.isOnline) {
          return const LoginScreen(offlineMessage: 'You’re offline, please connect to continue.');
        } else {
          return const LoginScreen();
        }
      },
    );
  }

  Future<AuthResult> _checkAuthWithConnectivity() async {
    final connectivityService = ConnectivityService();
    final isOnline = await connectivityService.isOnline;
    final isAuthorized = await AuthService.isAuthorized();

    return AuthResult(isAuthorized, isOnline);
  }
}
