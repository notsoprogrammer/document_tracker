# TODO List

## Current Task - COMPLETED
- [x] 1. Analyze the issue and understand the codebase
- [x] 2. Create and confirm the plan with user
- [x] 3. Add required imports to calendar_screen.dart (kIsWeb from flutter/foundation.dart)
- [x] 4. Add helper methods:
   - _extractFileId() - extracts file ID from Google Drive URLs
   - _buildDownloadUrl() - builds download URL for web
   - _buildPreviewUrl() - builds preview URL for mobile/desktop
   - _viewFile() - main method to open files properly
- [x] 5. Modify file click handler in _showDocumentDetails() to use _viewFile()

## Summary
The calendar screen now properly handles opening PDF files by:
1. Extracting the Google Drive file ID from various URL formats
2. Building appropriate URLs based on platform (web vs mobile/desktop)
3. Opening files using the same method as incoming_documents_screen
