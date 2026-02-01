# Password Reset Refactor TODO

- [x] Modify lib/screens/login_screen.dart: In _showForgotPasswordDialog, after getting token, set tokenController.text = token, set forgotStep = 1, remove sendPasswordResetNotification call. Add deviceToken to resetPassword call.
- [x] Remove sendPasswordResetNotification and related methods from lib/services/notification_service.dart (optional, if not used elsewhere).
- [x] Test the simplified flow to ensure it works.

# Notification Token Generation on Settings Change

- [x] Add _getAndSaveToken() method in NotificationService to retrieve and save FCM token if username exists.
- [x] Modify setNotificationPreferences() to call _getAndSaveToken() when any notification preference is enabled (set to true).
- [x] Test token generation when changing notification settings for users who initially denied notifications.
