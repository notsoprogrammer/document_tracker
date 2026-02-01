import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _developerPasswordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  int _currentStep = 0; // 0: developer password, 1: username/password
  bool _isLoginMode = true; // true for login, false for signup
  bool _isLoading = false;

  Future<void> _handleDeveloperPasswordSubmit() async {
    final password = _developerPasswordController.text.trim();
    if (password.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Please enter the developer password');
      return;
    }

    setState(() => _isLoading = true);

    // Validate developer password
    final isValid = AuthService.validatePassword(password);
    setState(() => _isLoading = false);
    if (isValid) {
      // Move to username/password step
      setState(() {
        _currentStep = 1;
      });
    } else {
      SnackbarUtils.showErrorSnackBar(context, 'Incorrect developer password');
    }
  }

  Future<void> _handleUserAuthSubmit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Get FCM token
      final deviceToken = await FirebaseMessaging.instance.getToken();
      if (deviceToken == null) {
        SnackbarUtils.showErrorSnackBar(context, 'Failed to get device token');
        setState(() => _isLoading = false);
        return;
      }

      bool success;
      if (_isLoginMode) {
        success = await AuthService.login(username, password, deviceToken);
        if (!success) {
          SnackbarUtils.showErrorSnackBar(context, 'Invalid username or password');
          setState(() => _isLoading = false);
          return;
        }
      } else {
        success = await AuthService.signup(username, password, deviceToken);
        if (!success) {
          SnackbarUtils.showErrorSnackBar(context, 'Signup failed. Username may already exist.');
          setState(() => _isLoading = false);
          return;
        }
      }

      // Success - navigate to home
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      SnackbarUtils.showErrorSnackBar(context, 'An error occurred. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
    });
  }

  void _goBack() {
    setState(() {
      _currentStep = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _currentStep == 0
                          ? 'Enter Developer Password'
                          : (_isLoginMode ? 'Login' : 'Sign Up'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_currentStep == 0) ...[
                      // Developer Password Step
                      TextField(
                        controller: _developerPasswordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Developer Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        onSubmitted: (_) => _handleDeveloperPasswordSubmit(),
                      ),
                    ] else ...[
                      // Username/Password Step
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                        onSubmitted: (_) => _handleUserAuthSubmit(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: _goBack,
                              child: const Text('Back'),
                            ),
                          ),
                          TextButton(
                            onPressed: _toggleMode,
                            child: Text(_isLoginMode ? 'Need to sign up?' : 'Already have account?'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : (_currentStep == 0 ? _handleDeveloperPasswordSubmit : _handleUserAuthSubmit),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : Text(_currentStep == 0 ? 'Continue' : (_isLoginMode ? 'Login' : 'Sign Up')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _developerPasswordController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
