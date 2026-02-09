# TODO: Fix Document History Not Adding on Move

## Issue
When moving a document to outgoing (or incoming), the history entry for the move is added after the document sync, so it's not included in the synced data.

## Plan
1. Update MoveDocumentDialog to add move history entry before sync call
2. Update incoming_documents_screen.dart move callback to add move history before sync
3. Update outgoing_documents_screen.dart move callback to add move history before sync

## Files to Edit
- lib/widgets/move_document_dialog.dart
- lib/screens/incoming_documents_screen.dart
- lib/screens/outgoing_documents_screen.dart

## Completed Tasks
- [x] Updated MoveDocumentDialog to add move history entry before sync call
- [x] Updated incoming_documents_screen.dart move callback to add move history before sync
- [x] Updated outgoing_documents_screen.dart move callback to add move history before sync

## Testing
- Test moving documents from incoming to outgoing and vice versa
- Verify that history entries appear immediately and persist after sync
- Check that the move history includes remarks and timestamps
