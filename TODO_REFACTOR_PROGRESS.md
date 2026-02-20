# TODO Refactor Progress

## Feature 1: Delete Drive images when record is deleted
- [x] 1. Add pending_drive_deletions table to SQLiteDatabaseService
- [x] 2. Add CRUD methods for pending_drive_deletions
- [ ] 3. Update CachedDocumentService.deleteDocument to queue Drive files for deletion
- [ ] 4. Update syncPendingDeletions to process Drive deletions

## Feature 2: Remove from upload queue when image/file removed from selection
- [x] 5. Update add_document_screen.dart - remove from queue when deleting images via viewer
- [x] 6. Update add_document_screen.dart - remove from queue when removing document chips
- [x] 7. Update add_attendance_movs_screen.dart - remove from queue when deleting images via viewer
- [x] 8. Update add_attendance_movs_screen.dart - remove from queue when removing document chips
- [ ] 9. Check edit_document_screen.dart for similar patterns

## Feature 3: Persist upload queue to SQLite for offline resilience
- [x] 10. Add pending_uploads table to SQLiteDatabaseService
- [x] 11. Add CRUD methods for pending_uploads
- [x] 12. Update UploadQueueManager with SQLite persistence (initialize, add, remove, update status)
- [ ] 13. Initialize UploadQueueManager on app startup in AutoSyncService

## Completed Changes Summary:

### lib/services/sqlite_database_service_mobile.dart:
- Updated database version to 23
- Added pending_uploads table with columns: id, document_code, file_path, is_image, local_path, status, retry_count, timestamp
- Added pending_drive_deletions table with columns: id, file_id, document_code, created_at
- Added CRUD methods: addPendingUpload, getPendingUploads, getPendingUploadsByDocument, removePendingUpload, removePendingUploadByDocumentAndPath, updatePendingUploadStatus, resetStuckUploads, addPendingDriveDeletion, getPendingDriveDeletions, deletePendingDriveDeletionRecord, deletePendingDriveDeletionByFileId

### lib/services/upload_queue_manager.dart:
- Added SQLite persistence using conditional import (sqlite_database_service for mobile, sqlite_database_service_web for web)
- Added initialize() method to load pending uploads from SQLite on startup
- Updated addToQueue() to persist to SQLite
- Updated removeFromQueue() to remove from SQLite
- Updated updateStatus() to update SQLite
- Updated markCompletedAndRemove() to remove from SQLite

### lib/screens/add_document_screen.dart:
- Added UploadQueueManager().removeFromQueue() when deleting images in viewer
- Added UploadQueueManager().removeFromQueue() when removing document chips

### lib/screens/add_attendance_movs_screen.dart:
- Added UploadQueueManager().removeFromQueue() when deleting images in viewer
- Added UploadQueueManager().removeFromQueue() when removing document chips
