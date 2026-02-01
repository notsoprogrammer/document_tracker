import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
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

  void _showForgotPasswordDialog() {
    final usernameController = TextEditingController();
    final tokenController = TextEditingController();
    final newPasswordController = TextEditingController();
    int forgotStep = 0; // 0: enter username, 1: enter token + new password

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(forgotStep == 0 ? 'Forgot Password' : 'Reset Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (forgotStep == 0) ...[
                      const Text(
                        'Enter your username to receive a password reset token.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: usernameController,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ] else ...[
                      const Text(
                        'Enter the reset token you received and your new password.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: tokenController,
                        decoration: const InputDecoration(
                          labelText: 'Reset Token',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: newPasswordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (forgotStep == 0) {
                      // Request reset token
                      final username = usernameController.text.trim();
                      if (username.isEmpty) {
                        SnackbarUtils.showErrorSnackBar(context, 'Please enter username');
                        return;
                      }

                      final resetToken = await AuthService.requestPasswordReset(username);
                      if (resetToken != null) {
                        // Send notification with token
                        await NotificationService().sendPasswordResetNotification(username, resetToken);
                        setState(() => forgotStep = 1);
                      } else {
                        SnackbarUtils.showErrorSnackBar(context, 'User not found');
                      }
                    } else {
                      // Reset password
                      final token = tokenController.text.trim();
                      final newPassword = newPasswordController.text.trim();

                      if (token.isEmpty || newPassword.isEmpty) {
                        SnackbarUtils.showErrorSnackBar(context, 'Please fill all fields');
                        return;
                      }

                      final success = await AuthService.resetPassword(token, newPassword);
                      if (success) {
                        SnackbarUtils.showSuccessSnackBar(context, 'Password reset successfully');
                        Navigator.of(context).pop();
                      } else {
                        SnackbarUtils.showErrorSnackBar(context, 'Invalid or expired token');
                      }
                    }
                  },
                  child: Text(forgotStep == 0 ? 'Send Token' : 'Reset Password'),
                ),
              ],
            );
          },
        );
      },
    );
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
                      if (_isLoginMode) ...[
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: const Text('Forgot Password?'),
                          ),
                        ),
                      ],
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
