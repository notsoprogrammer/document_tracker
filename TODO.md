# Refactor add_attendance_movs_screen for Certificates

## Tasks
- [x] Add new folder IDs to GoogleDriveService.dart for attendance, movs, certificates
- [ ] Add documentType field to Document.dart model
- [ ] Update add_attendance_movs_screen.dart: add 'Certificates' to types, update code gen for 'CT', pass documentType
- [ ] Update CachedDocumentService.dart: folder selection logic for Attendance & MOVs mode
- [ ] Test creating documents and verify correct folder uploads

# Set Compliance Deadline Time to 9 AM

## Tasks
- [x] Update incoming_documents_screen.dart: Change initialTime in showTimePicker for compliance deadline to default to 9 AM
- [x] Update add_document_screen.dart: Same change
- [x] Test the change
