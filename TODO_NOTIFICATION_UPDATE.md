# Notification Update on Compliance Change

Implement logic to update notifications_history when compliance deadline or assignee is updated.

## Requirements
- When compliance_deadline or compliance_assignee is updated on a document with status 'For Compliance'
- Insert new immediate notification with status 'updated'
- Delete existing scheduled notifications for the document
- Re-insert fresh scheduled notifications based on new deadline

## Implementation Plan
1. Modify SupabaseService.updateDocument to detect compliance updates
2. Add updateComplianceNotifications method to handle notification updates
3. Ensure audit integrity with 'updated' status
4. Test the implementation
