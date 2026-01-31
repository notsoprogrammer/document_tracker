# TODO: Secure Google Drive Service Account Key

## Plan to Move Service Account Key to Backend

### Information Gathered
- Service account key is currently in 'assets/image/gdrive_service_account.json', but code references 'assets/service_account_key.json'.
- Supabase function 'upload_to_drive' exists and uses key from environment variable 'GOOGLE_SERVICE_ACCOUNT_KEY'.
- Flutter app loads key directly for mobile builds, but uses Supabase for web uploads.
- To secure, make all operations use Supabase backend, remove key from Flutter project, update .gitignore.

### Plan
- Update GoogleDriveService to always use Supabase backend for all Google Drive operations.
- Remove service account key file from Flutter project.
- Update .gitignore to prevent committing the key file.
- Ensure Supabase function handles all necessary operations (upload is done, may need list if required).

### Dependent Files to Edit
- lib/services/google_drive_service.dart: Modify methods to always call Supabase backend.
- assets/image/gdrive_service_account.json: Remove file.
- .gitignore: Add entry for the key file.

### Followup Steps
- Test Google Drive operations still work via Supabase.
- Verify key is not in Git history.
- Ensure Supabase environment has the key set.

### Steps to Complete
- [x] Update GoogleDriveService to use Supabase for all operations
- [x] Remove the service account key file
- [x] Update .gitignore
- [ ] Test the changes
