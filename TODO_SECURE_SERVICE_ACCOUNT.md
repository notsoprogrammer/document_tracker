# TODO: Secure Google Drive Service Account Key

## Plan to Move Service Account Key to Backend

### Information Gathered
- Supabase function 'upload_to_drive' exists and uses GOOGLE_SERVICE_ACCOUNT_KEY environment variable
- Flutter web builds already use the Supabase function for uploads
- Mobile builds still load service account from assets/service_account_key.json
- The key file exists in assets/image/gdrive_service_account.json but code references assets/service_account_key.json

### Plan
- Modify GoogleDriveService to always use Supabase backend for all upload operations (mobile and web)
- Remove service account key from Flutter assets
- Update pubspec.yaml to remove asset reference
- Remove the key file from the project

### Dependent Files to Edit
- lib/services/google_drive_service.dart: Update all upload methods to use Supabase backend
- pubspec.yaml: Remove assets/service_account_key.json
- assets/service_account_key.json: Remove file

### Followup Steps
- Test uploads on both mobile and web platforms
- Verify Supabase environment has GOOGLE_SERVICE_ACCOUNT_KEY set

### Steps to Complete
- [ ] Update GoogleDriveService to use Supabase for all operations
- [ ] Remove the service account key file
- [ ] Update pubspec.yaml
- [ ] Test the changes
