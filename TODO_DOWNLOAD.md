# TODO: Add Download Function & Button to showImageDialog

## Task: Add download function & button in all showImageDialog (incoming, outgoing, calendar, attendance_movs, flag)

### Screens to modify:
- [ ] 1. lib/screens/outgoing_documents_screen.dart
- [ ] 2. lib/screens/incoming_documents_screen.dart
- [ ] 3. lib/screens/attendance_movs_screen.dart
- [ ] 4. lib/screens/flag_ceremony_documents_screen.dart
- [ ] 5. lib/screens/calendar_screen.dart

### Implementation approach:
1. Add a download button (IconButton with Icons.download) to each showImageDialog
2. Add a helper method `_downloadImage` that:
   - Extracts file ID from image URL using GoogleDriveService
   - Builds direct download URL
   - Opens with url_launcher

### Status:
- [ ] Plan confirmed by user
