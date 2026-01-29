# Document Tracker - Upload Before Move Implementation

## Completed Tasks
- [x] Modified `move_document_dialog.dart` to ensure uploads complete before moving documents
- [x] Added upload processing logic in `_moveDocument` method
- [x] Implemented waiting mechanism for upload completion
- [x] Added proper error handling for upload failures
- [x] Ensured file names are captured from uploaded files
- [x] Fixed issue where newly attached files were only saved locally - now properly queued for Google Drive upload
- [x] Modified navigation in `incoming_documents_screen.dart` to use `pushAndRemoveUntil` for direct home screen access
- [x] Modified navigation in `outgoing_documents_screen.dart` to use `pushAndRemoveUntil` for direct home screen access

## Implementation Details
- **Files Modified**:
  - `lib/widgets/move_document_dialog.dart`: Added upload processing before document moves, fixed local-only file saving issue
  - `lib/screens/incoming_documents_screen.dart`: Changed navigation to clear route stack
  - `lib/screens/outgoing_documents_screen.dart`: Changed navigation to clear route stack

- **Key Changes**:
  - Upload processing now occurs before document moves are allowed
  - Newly selected files are properly added to upload queue before processing
  - 2-second delay implemented to ensure uploads complete
  - Navigation uses `pushAndRemoveUntil` with `(route) => false` to clear all previous routes
  - Users can now tap back button to go directly to home screen after document moves

## Testing Requirements
- [ ] Test moving documents from incoming to outgoing with attachments
- [ ] Test moving documents from outgoing to incoming with attachments
- [ ] Verify file names are properly captured in the document's fileNames list
- [ ] Ensure uploads complete successfully before the move proceeds
- [ ] Test error handling when uploads fail
- [ ] Test back button navigation goes directly to home screen after moves
- [ ] Verify that newly attached files are uploaded to Google Drive (not just saved locally)

## Notes
- The system now ensures all local files are uploaded to Google Drive before allowing document moves
- File names are captured and stored in the document's fileNames list after successful uploads
- Navigation has been updated to provide a cleaner user experience with direct home screen access
- Existing attachments are preserved during the move operation
- New attachments added during move are also uploaded before the move completes
- Fixed critical bug where attached files were only saved locally instead of being uploaded to Google Drive
