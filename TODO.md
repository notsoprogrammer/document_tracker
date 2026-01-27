# Unified Document Workflow Implementation

## Tasks
- [x] Update document filtering logic to use `flowStage` instead of `incoming` boolean
- [x] Add "Forward Document" button in IncomingDocumentsScreen to transition documents
- [x] Create CirculatedDocumentsScreen for documents with 'circulated' flowStage
- [x] Update home screen to include Circulated Documents button
- [x] Ensure proper badge/tag display for documents that originated as incoming but are now outgoing
- [x] Verify audit trail logging works correctly

## Files to Edit
- lib/screens/incoming_documents_screen.dart (add forward button, update filtering)
- lib/screens/outgoing_documents_screen.dart (update filtering, add badge for originated incoming)
- lib/screens/home_screen.dart (add circulated button)
- lib/screens/circulated_documents_screen.dart (new file)
- lib/models/document.dart (ensure forwardDocument method is correct)

## Followup Steps
- [ ] Test document transitions and UI flow
- [ ] Verify history logging
- [ ] Ensure no duplicate records
