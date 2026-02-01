# Password Reset Refactor TODO

- [x] Modify lib/screens/login_screen.dart: In _showForgotPasswordDialog, after getting token, set tokenController.text = token, set forgotStep = 1, remove sendPasswordResetNotification call. Add deviceToken to resetPassword call.
- [x] Remove sendPasswordResetNotification and related methods from lib/services/notification_service.dart (optional, if not used elsewhere).
- [x] Test the simplified flow to ensure it works.
