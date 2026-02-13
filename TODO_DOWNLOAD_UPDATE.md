# Download Functionality Update - TODO

## Task: Apply attendance_movs download functionality to flag, incoming, outgoing, and calendar screens

### Progress:
- [x] 1. Update lib/screens/flag_ceremony_documents_screen.dart
- [x] 2. Update lib/screens/incoming_documents_screen.dart
- [x] 3. Update lib/screens/outgoing_documents_screen.dart
- [x] 4. Update lib/screens/calendar_screen.dart





### Changes Required Per File:
1. Add missing imports (device_info_plus, path_provider, flutter_image_gallery_saver)
2. Add `_getAndroidVersion()` helper method
3. Update `_downloadImage()` method with:
   - Android version-specific permission handling
   - Gallery saving using FlutterImageGallerySaver
   - Loading indicators
   - Temp file cleanup
4. Ensure `_showImageDialog()` has download button properly configured
