# Delete Functionality Refactoring - Implementation Checklist

## Completed Tasks ✅

### 1. Database Schema Updates
- [x] Added `deleted_records` table to `supabase_setup.sql`
  - Fields: id, deleted_by, doc_code, title, deleted_at
  - Added indexes for performance

### 2. Service Layer Updates
- [x] Updated `SupabaseService` (`lib/services/supabase_service.dart`)
  - Added `logDeletedRecord()` method to insert deletion logs

- [x] Updated `CachedDocumentService` (`lib/services/cached_document_service.dart`)
  - Modified `deleteDocument()` to:
    - Fetch document details before deletion
    - Log deletion to Supabase when online
    - Get username from AuthService
  - Added import for AuthService

### 3. Shared Delete Utility
- [x] Created `lib/utils/delete_utils.dart`
  - Implemented `confirmAndDeleteRecord()` function
  - Features:
    - Shows confirmation dialog
    - Requires user to type 'y' or 'n'
    - Only deletes if 'y' is typed
    - Handles deletion through CachedDocumentService
    - Returns boolean indicating success

### 4. Screen Updates
- [x] Updated `IncomingDocumentsScreen` (`lib/screens/incoming_documents_screen.dart`)
  - Added imports for delete_utils and cached_document_service
  - Removed old `_confirmDelete()` method
  - Updated delete button to use `confirmAndDeleteRecord()`
  - Handles UI refresh after deletion

- [x] Updated `OutgoingDocumentsScreen` (`lib/screens/outgoing_documents_screen.dart`)
  - Added imports for delete_utils and cached_document_service
  - Removed old `_confirmDelete()` and `_showDeleteConfirmation()` methods
  - Updated delete button to use `confirmAndDeleteRecord()`
  - Handles UI refresh after deletion

- [x] Updated `FlagCeremonyDocumentsScreen` (`lib/screens/flag_ceremony_documents_screen.dart`)
  - Added imports for delete_utils and cached_document_service
  - Removed old `_confirmDelete()` method
  - Updated delete button to use `confirmAndDeleteRecord()`
  - Handles UI refresh after deletion

## Next Steps 🔄

### 5. Testing & Verification
- [ ] Test deletion flow in Incoming Documents screen
- [ ] Test deletion flow in Outgoing Documents screen
- [ ] Test deletion flow in Flag Ceremony Documents screen
- [ ] Verify y/n confirmation works correctly
- [ ] Verify deletion logs are created in Supabase
- [ ] Test offline deletion (should work locally, log when back online)
- [ ] Verify username is correctly captured in deletion logs

### 6. Database Migration
- [ ] Run the updated `supabase_setup.sql` script on Supabase to create the `deleted_records` table
- [ ] Verify table and indexes are created successfully

## Implementation Notes

### Key Features Implemented:
1. **Centralized Delete Logic**: All delete operations now use the shared `confirmAndDeleteRecord()` utility
2. **Y/N Confirmation**: Users must explicitly type 'y' to confirm or 'n' to cancel
3. **Deletion Logging**: All deletions are logged to `deleted_records` table with:
   - deleted_by (username from AuthService)
   - doc_code (document code)
   - title (document title)
   - deleted_at (automatic timestamp)
4. **Offline Support**: Deletions work offline and will log to Supabase when connection is restored

### Files Modified:
- `supabase_setup.sql`
- `lib/services/supabase_service.dart`
- `lib/services/cached_document_service.dart`
- `lib/utils/delete_utils.dart` (new file)
- `lib/screens/incoming_documents_screen.dart`
- `lib/screens/outgoing_documents_screen.dart`
- `lib/screens/flag_ceremony_documents_screen.dart`

### Technical Details:
- Delete confirmation dialog uses StatefulBuilder for reactive UI
- TextField validates input (only accepts 'y' or 'n')
- Submit button triggers validation and proceeds accordingly
- Service layer handles both local and remote deletion
- Deletion logs are only created when online
