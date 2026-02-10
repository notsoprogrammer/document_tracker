# Refactor EditDocumentScreen and UploadQueueManager

## Requirements
- [x] Completed uploads are removed from the queue.
- [x] Listeners are properly disposed to avoid setState() after dispose.
- [x] Sync does not re-process completed items.

## Deliverables
- [x] Patch `EditDocumentScreen.dispose()` to remove listeners.
- [x] Patch `_onUploadStatusChanged` to check `mounted`.
- [x] Patch `UploadQueueManager.markCompletedAndRemove` to fully remove completed items.
- [x] Patch `CachedDocumentService.processPendingUploads` to skip completed items.
- [ ] Verify logs show one upload per file, no duplication, and no setState() after dispose errors.

## Changes Made
1. **EditDocumentScreen** (`lib/screens/edit_document_screen.dart`):
   - Added `dispose()` method to remove listener from UploadQueueManager.
   - Added `if (!mounted) return;` check in `_onUploadStatusChanged` before calling `setState`.

2. **UploadQueueManager** (`lib/services/upload_queue_manager.dart`):
   - Modified `updateStatus` to notify listeners only if the status actually changed.
   - `markCompletedAndRemove` already removes items from queue after completion.

3. **CachedDocumentService** (`lib/services/cached_document_service.dart`):
   - Modified `processPendingUploads` to filter only items with status 'pending' or 'failed', skipping 'completed' items.

## Verification Steps
- Test uploading files in EditDocumentScreen.
- Check logs for single uploads per file.
- Ensure no setState() after dispose errors.
- Confirm completed uploads are removed from queue.
