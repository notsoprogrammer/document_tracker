import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/snackbar_utils.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  bool _isPasswordStep = true;
  bool _isLoading = false;

  Future<void> _handlePasswordSubmit() async {
    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Please enter a password');
      return;
    }

    setState(() => _isLoading = true);

    // Validate password
    final isValid = AuthService.validatePassword(password);
    setState(() => _isLoading = false);
    if (isValid) {
      // Mark as authorized and move to username
      await AuthService.setAuthorized(true);
      setState(() {
        _isPasswordStep = false;
      });
    } else {
      SnackbarUtils.showErrorSnackBar(context, 'Incorrect password');
    }
  }

  Future<void> _handleUsernameSubmit() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Please enter a username');
      return;
    }

    setState(() => _isLoading = true);
    await AuthService.setUsername(username);
    setState(() => _isLoading = false);

    // Proceed to app
    if (mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
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
                      _isPasswordStep ? 'Enter Developer Password' : 'Set Username',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (_isPasswordStep) ...[
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
                        onSubmitted: (_) => _handlePasswordSubmit(),
                      ),
                    ] else ...[
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
                        onSubmitted: (_) => _handleUsernameSubmit(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : (_isPasswordStep ? _handlePasswordSubmit : _handleUsernameSubmit),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator()
                            : Text(_isPasswordStep ? 'Continue' : 'Finish Setup'),
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
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }
}
