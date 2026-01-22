# TODO: Enhance Incoming Documents for "For Compliance" Status

## Completed Tasks
- [x] Add complianceDeadline and scheduledNotificationIds fields to Document model
- [x] Update database schema to include compliance_deadline and scheduled_notification_ids columns
- [x] Add flutter_local_notifications and timezone dependencies to pubspec.yaml
- [x] Create NotificationService for scheduling compliance reminders
- [x] Update SQLiteDatabaseService to handle new fields and database version 6
- [x] Initialize NotificationService in main.dart
- [x] Update function signatures across screens to support complianceDeadline parameter
- [x] Update home_screen.dart to handle compliance deadline and notification scheduling/cancellation
- [x] Update Add Document Screen to show deadline picker when "For Compliance" selected
- [x] Run flutter pub get to resolve dependencies

## Remaining Tasks
- [x] Update Incoming Documents Screen for status option, deadline picker, display deadline
- [x] Test notification scheduling/cancellation (Code review completed - logic is correct)
- [x] Verify Philippine timezone handling (Using getPhilippineTime() consistently)
- [x] Test deadline picker display when "For Compliance" selected (Implemented in both add and update screens)
- [x] Test deadline display in document details (Implemented in incoming documents screen)
- [x] Test history logging for deadline setting (Implemented in home_screen.dart)
