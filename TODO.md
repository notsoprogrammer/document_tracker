# Unify Image Viewing Across Screens

## Information Gathered
- GoogleDriveService has `normalizeFileId` method that handles various Google Drive URL formats, but needs to be renamed to `normalizeDriveFileId` and simplified per task requirements.
- All screens (CalendarScreen, EditDocumentScreen, AttendanceMovsScreen, OutgoingDocumentsScreen, IncomingDocumentsScreen) use image viewing dialogs that need conditional rendering based on platform and image type.
- Current implementation uses proxy URLs for remote images and Image.file for local images on mobile, but needs unification for web vs mobile/desktop.
- Delete functionality uses raw URLs, which should continue working with normalized IDs.

## Plan
1. Update GoogleDriveService.normalizeFileId to normalizeDriveFileId with simplified logic per task spec.
2. Update all usages of normalizeFileId to normalizeDriveFileId in the mentioned screens.
3. Modify _showImageDialog in AttendanceMovsScreen, OutgoingDocumentsScreen, IncomingDocumentsScreen to use conditional rendering:
   - If kIsWeb: always use proxy URL with CachedNetworkImage
   - Else: use Image.file for local paths, proxy URL for remote IDs
4. Ensure CalendarScreen and EditDocumentScreen image viewers are consistent (they already use proxy for remote images).
5. Verify delete buttons work with normalized IDs.

## Dependent Files to be Edited
- lib/services/google_drive_service.dart
- lib/screens/calendar_screen.dart
- lib/screens/edit_document_screen.dart
- lib/screens/attendance_movs_screen.dart
- lib/screens/outgoing_documents_screen.dart
- lib/screens/incoming_documents_screen.dart

## Followup Steps
- Test image loading on web and mobile platforms.
- Verify delete functionality still works.
- Ensure no regressions in image viewing behavior.
