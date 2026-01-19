# Document Tracker - Google Drive URL Fix

## Issue
Images/files uploaded to Google Drive were returning null URLs instead of proper web-accessible links.

## Root Cause
The upload methods were returning the Google Drive file ID instead of the webViewLink, and then attempting to generate a public URL from the ID using a deprecated method.

## Changes Made

### 1. Updated `uploadImageToDrive` method
- Modified to return `webViewLink` instead of `fileId`
- Added API call to fetch the file's webViewLink after making it public

### 2. Updated `uploadFileToDrive` method
- Modified to return `webViewLink` instead of `fileId`
- Added API call to fetch the file's webViewLink after making it public

### 3. Updated `cached_document_service.dart`
- Removed the call to `generatePublicUrl` in `processPendingUploads`
- Now directly uses the URL returned from upload methods

### 4. Updated `saveImageWithBackup` method
- Modified to directly get the URL from `uploadImageToDrive`
- Removed redundant URL generation step

## Files Modified
- `lib/services/google_drive_service.dart`
- `lib/services/cached_document_service.dart`

## Testing Required
- Test uploading images to Google Drive
- Test uploading documents to Google Drive
- Verify that URLs are properly accessible in web browsers
- Check that existing functionality still works

## Status
✅ Changes implemented
⏳ Testing pending

## Fix: Improve Interface When Deleting Records

### Issue
When users delete records in incoming/outgoing documents, the interface doesn't automatically refresh. Users need to click another expandable tile to see that the file is deleted. The flag ceremony screen works well when online but not when offline.

### Root Cause
- Delete operations were not triggering UI refresh
- Flag ceremony screen had different delete handling that worked online but not offline
- No loading indicators during delete operations

### Changes Made
- **Home Screen (`lib/screens/home_screen.dart`)**: Modified `_deleteDocument` to reload documents from database after deletion instead of just removing from local list
- **Incoming Documents Screen (`lib/screens/incoming_documents_screen.dart`)**: 
  - Added `didUpdateWidget` lifecycle method to handle document list changes from parent
  - Modified delete confirmation to show loading overlay and success/error messages
  - Added `_isDeleting` state variable and loading overlay UI
- **Outgoing Documents Screen (`lib/screens/outgoing_documents_screen.dart`)**: 
  - Added `didUpdateWidget` lifecycle method to handle document list changes from parent
  - Modified delete confirmation to show loading overlay and success/error messages
  - Added `_isDeleting` state variable and loading overlay UI
- **Flag Ceremony Documents Screen (`lib/screens/flag_ceremony_documents_screen.dart`)**: 
  - Modified delete confirmation to use same pattern as other screens (loading overlay instead of navigation)
  - Added `_isDeleting` state variable and loading overlay UI
  - Now works consistently both online and offline

### Files Modified
- `lib/screens/home_screen.dart`
- `lib/screens/incoming_documents_screen.dart`
- `lib/screens/outgoing_documents_screen.dart`
- `lib/screens/flag_ceremony_documents_screen.dart`

### Status
✅ Changes implemented and tested

## Fix: Correct First History Entry for Incoming Documents

### Issue
The first history entry saved to Supabase for incoming documents was incorrectly using the outgoing format ("Created and forwarded to ${json['from_or_to']} c/o ${json['addressed_to']}") instead of "Document Received".

### Root Cause
The initial history entry was only added in the Document.fromJson method when fetching from the database, but not when creating new documents. This meant that when saving a new document, no initial history entry was inserted into the history_entries table.

### Changes Made
- Modified `Document` constructor to add initial history entry based on document type:
  - For incoming documents: "Document Received"
  - For outgoing documents: "Created and forwarded to $fromOrTo c/o $assignedTo"
- This ensures the correct first entry is saved to Supabase when creating new documents

### Files Modified
- `lib/models/document.dart`

### Status
✅ Changes implemented and tested

## UI Improvements: Upload Indicators and Offline Visual Markers

### Issue
- Upload status indicators were inconsistent across screens
- No visual distinction for offline-created records
- No pull-to-refresh functionality in document screens
- Duplicate "View Image" buttons in outgoing screen
- Missing "Complete" state for upload indicators in incoming screen

### Changes Made

#### 1. Modified Document Constructor (`lib/models/document.dart`)
- Added initial history entry logic for new documents

#### 2. Updated Home Screen (`lib/screens/home_screen.dart`)
- Added RefreshIndicator for pull-to-refresh
- Added global upload status indicator showing current uploads
- Modified folder buttons to show document counts and unsynced badges
- Added onRefresh callbacks to all document screens

#### 3. Updated Incoming Documents Screen (`lib/screens/incoming_documents_screen.dart`)
- Changed offline record background color to Colors.yellow[100]
- Added RefreshIndicator wrapper
- Added "Complete" state to upload status indicator

#### 4. Updated Outgoing Documents Screen (`lib/screens/outgoing_documents_screen.dart`)
- Changed offline record background color to Colors.yellow[100]
- Added RefreshIndicator wrapper
- Changed subtitle to Column layout for better upload indicator placement
- Removed duplicate "View Image" button

#### 5. Updated Flag Ceremony Documents Screen (`lib/screens/flag_ceremony_documents_screen.dart`)
- Changed offline record background color to Colors.yellow[100]
- Added RefreshIndicator wrapper

### Benefits
- ✅ Consistent upload status indicators across all screens
- ✅ Visual markers for offline-created records (yellow background)
- ✅ Pull-to-refresh functionality in all document folders
- ✅ Improved UI layout for upload indicators
- ✅ Removed duplicate buttons

### Files Modified
- `lib/models/document.dart`
- `lib/screens/home_screen.dart`
- `lib/screens/incoming_documents_screen.dart`
- `lib/screens/outgoing_documents_screen.dart`
- `lib/screens/flag_ceremony_documents_screen.dart`

### Status
✅ Changes implemented
⏳ Testing pending

## Fix: Automatic UI Refresh After Document Deletion

### Issue
When deleting documents in incoming/outgoing/flag ceremony screens, the UI didn't automatically refresh. Users had to click another expandable tile or navigate away and back to see the deletion reflected. The flag ceremony screen worked well when online but had issues when offline.

### Root Cause
Child screens (incoming/outgoing/flag ceremony) received the documents list as a static parameter from the parent (home_screen). When documents were deleted, the parent's list was updated, but child screens didn't automatically rebuild to reflect the changes.

### Changes Made

#### 1. Modified `lib/screens/home_screen.dart`
- Updated `_deleteDocument` method to reload documents from database after deletion
- Changed from manually removing item from list to calling `_loadDocuments()` for consistency
- This ensures the parent always has the latest data from the database

#### 2. Modified `lib/screens/incoming_documents_screen.dart`
- Added `didUpdateWidget` lifecycle method to detect when documents list changes from parent
- Clears expanded tiles when list updates to avoid index issues
- Changed delete button to async and await deletion completion
- Removed local `setState` after deletion (no longer needed as parent handles refresh)

#### 3. Modified `lib/screens/outgoing_documents_screen.dart`
- Added `didUpdateWidget` lifecycle method to detect when documents list changes from parent
- Clears expanded tiles when list updates to avoid index issues
- Changed delete button to async and await deletion completion
- Removed local `setState` after deletion (no longer needed as parent handles refresh)

#### 4. Modified `lib/screens/flag_ceremony_documents_screen.dart`
- Added `didUpdateWidget` lifecycle method to detect when documents list changes from parent
- Updates local `_filteredDocuments` when parent's documents list changes
- Reapplies active filters after receiving updated data
- Clears expanded tiles when list updates to avoid index issues
- Changed delete button to async and await deletion completion
- Removed manual removal from `_filteredDocuments` (handled by didUpdateWidget)

### How It Works
1. User clicks delete button in any document screen
2. Delete dialog closes and deletion function is called (awaited)
3. Parent's `_deleteDocument` deletes from database and calls `_loadDocuments()`
4. Parent rebuilds with updated documents list
5. Child screen's `didUpdateWidget` detects the change
6. Child screen automatically rebuilds with the new list
7. UI immediately reflects the deletion (both online and offline)

### Benefits
- ✅ Immediate UI feedback after deletion
- ✅ Works consistently in both online and offline modes
- ✅ No need to manually click other tiles to see changes
- ✅ Maintains data consistency between parent and child screens
- ✅ Proper lifecycle management prevents index-out-of-bounds errors

### Files Modified
- `lib/screens/home_screen.dart`
- `lib/screens/incoming_documents_screen.dart`
- `lib/screens/outgoing_documents_screen.dart`
- `lib/screens/flag_ceremony_documents_screen.dart`

### Status
✅ Changes implemented
⏳ Testing pending

## Additional Fix: Prevent Multiple Simultaneous File Operations

### Issue
Users could trigger multiple image/file picking operations simultaneously, leading to potential conflicts and poor UX.

### Changes Made
- Added `_isPickingImage` and `_isPickingFile` boolean flags to track picking states
- Modified button `onPressed` callbacks to disable buttons when already picking or uploading
- Added progress indicators that show "Capturing image..." and "Selecting file..." during operations
- Ensured flags are properly reset on success or failure

### Files Modified
- `lib/screens/add_flag_ceremony_screen.dart`

### Status
✅ Changes implemented
⏳ Testing pending

## New Feature: Prevent Navigation Until Upload Complete

### Issue
Users could navigate back to home screen before file uploads to Google Drive/Supabase were complete, leading to incomplete document saving.

### Changes Made
- Modified save buttons in add screens to await document creation and upload completion
- Added `_isSaving` boolean flag to track saving state
- Disabled save button during saving/uploading process
- Added progress indicator (CircularProgressIndicator) on save button during operation
- Added status text "Saving document and uploading files..." below the button
- Ensured navigation only occurs after all uploads are complete or failed
- Added upload progress tracking with UploadQueueManager listener
- Added detailed progress bar showing upload completion percentage
- Added upload status messages (e.g., "Uploading 2 file(s)...", "All uploads completed")
- Modified home screen to reload documents after add screens return since documents are saved internally

### Files Modified
- `lib/screens/add_document_screen.dart`
- `lib/screens/add_flag_ceremony_screen.dart`
- `lib/screens/home_screen.dart`

### Status
✅ Changes implemented
⏳ Testing pending

## Fix: Prevent Duplicate Document Codes

### Issue
Document codes were not unique enough, causing "duplicate key value violates unique constraint" errors when saving to Supabase.

### Root Cause
Code generation only included date and time up to minutes, allowing duplicates within the same minute.

### Changes Made
- Updated `_generateCode` methods to include seconds and milliseconds for uniqueness
- Incoming/Outgoing codes now: `IDL$year-$month-$day-$hour$minute$second-$millisecond`
- Flag Ceremony codes now: `FR/FL-$month-$day-$year-$hour$minute$second-$millisecond`

### Files Modified
- `lib/screens/add_document_screen.dart`
- `lib/screens/add_flag_ceremony_screen.dart`

### Status
✅ Changes implemented
⏳ Testing pending
