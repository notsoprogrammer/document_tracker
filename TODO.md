# Refactor Homescreen UI for Sidebar

## Tasks
- [ ] Add `fetchDeletedRecords` method to `supabase_service.dart` to retrieve deletion logs from the `deleted_records` table.
- [ ] Update `delete_history_screen.dart` to fetch and display logs with modern Card layout, showing deleted_by, doc_code, title, and formatted deleted_at, with scrolling.
- [ ] Modify `home_screen.dart` to add a sidebar button beside the Sync button with Material 3 styling (rounded corners, hover effects, elevation), and implement an endDrawer for the right-sliding sidebar containing the "Delete History" menu item.
- [ ] Update `incoming_documents_screen.dart` to include the same sidebar button and endDrawer for consistency.
- [ ] Update `outgoing_documents_screen.dart` to include the same sidebar button and endDrawer for consistency.
- [ ] Update `flag_ceremony_documents_screen.dart` to include the same sidebar button and endDrawer for consistency.
- [ ] Test the sidebar opening/closing and navigation to DeleteHistoryScreen.
- [ ] Verify the display and scrolling of deletion logs.
- [ ] Ensure Material 3 styling and UX consistency across screens.
