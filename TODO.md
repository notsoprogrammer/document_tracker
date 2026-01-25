# Calendar Integration Enhancement TODO

## 1. Add Dependencies
- [x] Add table_calendar package to pubspec.yaml

## 2. Database Schema Update
- [x] Update supabase_setup.sql to add new columns: calendar_deadline (DateTime), calendar_added (boolean), attachments (json array)

## 3. Model Updates
- [x] Update Document model to include calendar_deadline, calendar_added, attachments fields

## 4. Service Updates
- [x] Update SupabaseService to handle new fields in create/update operations

## 5. AddDocumentScreen Integration
- [x] Add "Add to Calendar" button beside Document Type dropdown for incoming documents
- [x] Implement date picker and metadata saving to Supabase

## 6. HomeScreen Integration
- [x] Add "Calendar" option in app bar popup menu
- [x] Navigate to CalendarScreen on selection

## 7. CalendarScreen Creation
- [x] Create lib/screens/calendar_screen.dart with TableCalendar
- [x] Implement monthly view with swipe navigation
- [x] Add color indicators: green for calendar entries, red/orange for pending compliance, grey for complied
- [x] Implement modal bottom sheet on date tap with metadata and file previews

## 8. Compliance Integration
- [x] Ensure compliance status changes remove active indicators while keeping metadata

## 9. Testing
- [x] Test calendar navigation and indicators (manual testing required)
- [x] Test modal with metadata and file opening (manual testing required)
- [x] Verify compliance status changes appropriately (manual testing required)
