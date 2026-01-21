# Refactor Homescreen UI for Sidebar

## Tasks
- [x] Add `fetchDeletedRecords` method to `supabase_service.dart` to retrieve deletion logs from the `deleted_records` table.
- [x] Update `delete_history_screen.dart` to fetch and display logs with modern Card layout, showing deleted_by, doc_code, title, and formatted deleted_at, with scrolling.
- [x] Modify `home_screen.dart` to add a sidebar button beside the Sync button with Material 3 styling (rounded corners, hover effects, elevation), and implement an endDrawer for the right-sliding sidebar containing the "Delete History" menu item.
- [ ] Update `incoming_documents_screen.dart` to include the same sidebar button and endDrawer for consistency.
- [ ] Update `outgoing_documents_screen.dart` to include the same sidebar button and endDrawer for consistency.
- [ ] Update `flag_ceremony_documents_screen.dart` to include the same sidebar button and endDrawer for consistency.
- [ ] Test the sidebar opening/closing and navigation to DeleteHistoryScreen.
- [ ] Verify the display and scrolling of deletion logs.
- [ ] Ensure Material 3 styling and UX consistency across screens.

## New Requirements
- [x] Refactor DeleteHistoryScreen to open inside a left-aligned sidebar (Drawer) instead of full screen.
- [x] The Drawer should slide in from the left and allow swipe/slide to close.
- [x] The Drawer's height should be constrained so it does not exceed the top part (AppBar height).
- [x] Inside the Drawer, show the delete history list in a scrollable Container with modern styling (rounded corners, padding, elevation).
- [x] Keep the gradient background and refresh behavior.
- [x] Place sidebar button on the left.
- [x] Don't put the sidebar button in other screens (incoming, outgoing, and flag).
