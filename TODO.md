# Flag Ceremony Documents Screen Update

## Completed Tasks
- [x] Updated flag ceremony documents screen to use expandable tiles showing only type (similar to incoming/outgoing screens)
- [x] Added buttons at bottom of expanded tiles (Delete, View Image, View File)
- [x] Kept search and filter functionality unchanged
- [x] Modified Document model to skip adding history entries for flag ceremony documents
- [x] Modified SupabaseService to skip creating history entries in database for flag ceremony documents
- [x] Added copy code functionality when tile is expanded
- [x] Added proper detail rows with icons in expanded content

## Summary
The flag ceremony documents screen now matches the UI and behavior of incoming/outgoing documents screens with:
- Expandable tiles showing document type as title
- Code displayed in subtitle with copy button when expanded
- Detailed information in expanded content with icons
- Action buttons at bottom (Delete, View Image, View File)
- Search and filter functionality preserved
- No history tracking for flag ceremony documents
