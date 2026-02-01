# Refactor Document Tracker App for User Auth and Device Tokens

## Tasks
- [ ] Update Supabase Schema (`supabase_setup.sql`): Create `users` table and alter `device_tokens` table
- [ ] Add bcrypt dependency to `pubspec.yaml`
- [ ] Refactor `lib/services/auth_service.dart`: Implement signup/login with password hashing
- [ ] Refactor `lib/services/supabase_service.dart`: Update device token methods for new schema
- [ ] Refactor `lib/services/notification_service.dart`: Pass username to saveDeviceToken
- [ ] Update Supabase Edge Function (`supabase/functions/send_compliance_notifications/index.ts`): Ensure query works with new schema
- [ ] Test signup/login flows
- [ ] Provide Android/Kotlin code snippets for signup/login

## Migration Steps
- Alter existing `device_tokens` table to add new columns (user_id, username nullable initially)
- Run updated schema to create `users` table and modify `device_tokens`
