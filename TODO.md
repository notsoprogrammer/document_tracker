# Add Navigation Arrows to Image Viewing Dialogs

## Tasks
- [x] Add navigation arrows to calendar_screen.dart _showImageViewer
- [x] Add navigation arrows to attendance_movs_screen.dart _showImageDialog
- [x] Add navigation arrows to incoming_documents_screen.dart _showImageDialog
- [x] Add navigation arrows to outgoing_documents_screen.dart _showImageDialog

## Implementation Details
- Add PageController to control PageView navigation
- Add left and right arrow buttons positioned on sides of dialog
- Arrows only visible when there are 2 or more images
- Handle previous/next page navigation on arrow press
