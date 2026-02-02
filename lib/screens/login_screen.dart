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

  int _currentStep = 0;
  bool _isLoginMode = true;
  bool _isLoading = false;

  static const Color primaryOrange = Color(0xFFFAAC68);
  static const Color creamBg = Color.fromARGB(255, 237, 235, 230);

  Future<void> _handleDeveloperPasswordSubmit() async {
    final password = _developerPasswordController.text.trim();
    if (password.isEmpty) {
      SnackbarUtils.showErrorSnackBar(context, 'Please enter the developer password');
      return;
    }

    setState(() => _isLoading = true);

    final isValid = AuthService.validatePassword(password);

    setState(() => _isLoading = false);

    if (isValid) {
      setState(() => _currentStep = 1);
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
      String? deviceToken;
      try {
        deviceToken = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint('Failed to get FCM token: $e');
        // Continue without device token if permission is blocked
      }

      bool success;
      if (_isLoginMode) {
        success = await AuthService.login(username, password, deviceToken);
      } else {
        success = await AuthService.signup(username, password, deviceToken);
      }

      if (!success) {
        SnackbarUtils.showErrorSnackBar(
          context,
          _isLoginMode
              ? 'Invalid username or password'
              : 'Signup failed. Username may already exist.',
        );
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (_) {
      SnackbarUtils.showErrorSnackBar(context, 'An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toggleMode() => setState(() => _isLoginMode = !_isLoginMode);
  void _goBack() => setState(() => _currentStep = 0);

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: primaryOrange),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: primaryOrange, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: creamBg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 10,
              shadowColor: primaryOrange.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: primaryOrange.withOpacity(0.15),
                      child: const Icon(Icons.lock_outline, size: 40, color: primaryOrange),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      _currentStep == 0
                          ? 'Developer Access'
                          : (_isLoginMode ? 'Welcome Back' : 'Create Account'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primaryOrange,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      _currentStep == 0
                          ? 'Enter the developer password to continue'
                          : (_isLoginMode
                              ? 'Login to your account'
                              : 'Sign up to get started'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),

                    const SizedBox(height: 28),

                    if (_currentStep == 0) ...[
                      TextField(
                        controller: _developerPasswordController,
                        obscureText: true,
                        decoration: _inputDecoration(
                          'Developer Password',
                          Icons.vpn_key,
                        ),
                        onSubmitted: (_) => _handleDeveloperPasswordSubmit(),
                      ),
                    ] else ...[
                      TextField(
                        controller: _usernameController,
                        decoration: _inputDecoration('Username', Icons.person),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: _inputDecoration('Password', Icons.lock),
                        onSubmitted: (_) => _handleUserAuthSubmit(),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        children: [
                          TextButton(
                            onPressed: _goBack,
                            child: const Text('Back'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _toggleMode,
                            child: Text(
                              _isLoginMode
                                  ? 'Need an account?'
                                  : 'Already registered?',
                            ),
                          ),
                        ],
                      ),

                      if (_isLoginMode)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                    ],

                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : (_currentStep == 0
                                ? _handleDeveloperPasswordSubmit
                                : _handleUserAuthSubmit),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryOrange,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _isLoading
                            ? const LinearProgressIndicator(color: Colors.white)
                            : Text(
                                _currentStep == 0
                                    ? 'Continue'
                                    : (_isLoginMode ? 'Login' : 'Sign Up'),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
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

  // --- Forgot password dialog (UNCHANGED LOGIC) ---
  void _showForgotPasswordDialog() {
    final usernameController = TextEditingController();
    final tokenController = TextEditingController();
    final newPasswordController = TextEditingController();
    int forgotStep = 0;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(forgotStep == 0 ? 'Forgot Password' : 'Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (forgotStep == 0)
                    TextField(
                      controller: usernameController,
                      decoration: _inputDecoration('Username', Icons.person),
                    )
                  else ...[
                    TextField(
                      controller: tokenController,
                      decoration: _inputDecoration('Reset Token', Icons.key),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newPasswordController,
                      obscureText: true,
                      decoration: _inputDecoration('New Password', Icons.lock),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (forgotStep == 0) {
                      final token = await AuthService.requestPasswordReset(
                        usernameController.text.trim(),
                      );
                      if (token != null) {
                        setState(() {
                          tokenController.text = token;
                          forgotStep = 1;
                        });
                      } else {
                        SnackbarUtils.showErrorSnackBar(context, 'User not found');
                      }
                    } else {
                      final deviceToken = await FirebaseMessaging.instance.getToken();
                      if (deviceToken == null) {
                        SnackbarUtils.showErrorSnackBar(context, 'Failed to get device token');
                        return;
                      }
                      final success = await AuthService.resetPassword(
                        tokenController.text.trim(),
                        newPasswordController.text.trim(),
                        deviceToken,
                      );
                      if (success) {
                        SnackbarUtils.showSuccessSnackBar(
                          context,
                          'Password reset successfully',
                        );
                        Navigator.pop(context);
                      } else {
                        SnackbarUtils.showErrorSnackBar(
                          context,
                          'Invalid or expired token',
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: primaryOrange),
                  child: Text(forgotStep == 0 ? 'Send Token' : 'Reset Password'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
