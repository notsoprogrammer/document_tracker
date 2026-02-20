# TODO Refactor Progress

## Feature 1: Delete Drive images when record is deleted
- [x] 1. Add pending_drive_deletions table to SQLiteDatabaseService
- [x] 2. Add CRUD methods for pending_drive_deletions
- [x] 3. Update CachedDocumentService.deleteDocument to delete Drive files
- [x] 4. Update syncPendingDeletions to process Drive deletions

## Feature 2: Remove from upload queue when image/file removed from selection
- [x] 5. Update add_document_screen.dart (already uses UploadQueueManager.removeFromQueue)
- [x] 6. Update add_attendance_movs_screen.dart (already uses UploadQueueManager.removeFromQueue)
- [x] 7. Update edit_document_screen.dart (already uses UploadQueueManager.removeFromQueue)

## Feature 3: Persist upload queue to SQLite for offline resilience
- [x] 8. Add pending_uploads table to SQLiteDatabaseService
- [x] 9. Add CRUD methods for pending_uploads
- [x] 10. Update UploadQueueManager with SQLite persistence
- [x] 11. Update AutoSyncService to initialize upload queue

## ALL TASKS COMPLETED ✅
