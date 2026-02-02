# TODO: Update Authentication Methods for Optional Device Tokens

- [ ] Update lib/services/auth_service.dart: Change signup method to accept String? deviceToken and conditionally insert device token only if not null.
- [ ] Update lib/services/auth_service.dart: Change login method to accept String? deviceToken and conditionally insert device token only if not null.
- [ ] Update lib/services/auth_service.dart: Change resetPassword method to accept String? deviceToken and conditionally insert device token only if not null.
- [ ] Update lib/screens/login_screen.dart: Remove null token checks in _handleUserAuthSubmit and pass null to auth methods.
- [ ] Update lib/screens/login_screen.dart: Remove null token checks in forgot password dialog and pass null to auth methods.
- [ ] Update lib/services/supabase_service.dart: Change saveDeviceToken to accept String? and skip if null.
