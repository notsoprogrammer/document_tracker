# Notification Debug Tasks

- [x] Add test notification button to home_screen.dart for immediate testing
- [x] Modify scheduleComplianceNotifications to schedule multiple reminders (1 day, 5 hours, at deadline)
- [x] Handle past notification times by scheduling immediate notifications or skipping gracefully
- [x] Add more debug logging in notification_service.dart for scheduling attempts
- [x] Request SCHEDULE_EXACT_ALARM permission explicitly on Android API 31+
- [ ] Test with future deadlines to verify scheduling works
- [x] Create notification_history_screen.dart for viewing notification logs
- [x] Add notification history to home_screen menu
- [x] Mark notifications as completed when document status changes to Completed
- [x] Update cancelAll to mark cancelled notifications in history
