# Connectivity and Sync System Documentation

## Overview

This document describes the automatic offline queue and sync system implemented for the Flutter document tracking app. The system provides seamless offline functionality with automatic synchronization when connectivity is restored.

## Components

### 1. ConnectivityBanner Widget (`lib/widgets/connectivity_banner.dart`)

A reusable widget that displays connectivity status notifications.

**Features:**
- **Offline Banner**: Persistent red banner when device goes offline
- **Online Banner**: Temporary green banner when connectivity is restored (auto-dismisses after 3 seconds)
- **Smooth Animations**: Slide in/out transitions
- **Non-intrusive**: Overlays on top of screen content

**Usage:**
```dart
import '../widgets/connectivity_banner.dart';

@override
Widget build(BuildContext context) {
  return ConnectivityBanner(
    child: Scaffold(
      // Your screen content
    ),
  );
}
```

### 2. SyncBanner Widget (`lib/widgets/sync_banner.dart`)

A widget that displays sync status and progress at the top of screens.

**Features:**
- **Upload Progress**: Shows "Syncing X/Y items" during upload
- **Status Messages**: Displays sync completion or error messages
- **Auto-dismiss**: Success/error messages auto-dismiss after 3 seconds
- **Color-coded**: Blue for syncing, green for success, red for errors

**Usage:**
```dart
import '../widgets/sync_banner.dart';

@override
Widget build(BuildContext context) {
  return SyncBanner(
    child: Scaffold(
      // Your screen content
    ),
  );
}
```

### 3. EnhancedSyncService (`lib/services/enhanced_sync_service.dart`)

A service that manages sync operations and broadcasts status updates.

**Features:**
- **Stream-based Status**: Broadcasts sync status to all listeners
- **Queue Management**: Tracks pending uploads
- **Progress Tracking**: Reports X/Y items being processed
- **Error Handling**: Captures and reports sync errors

**Key Classes:**

#### SyncStatus
```dart
class SyncStatus {
  final bool isActive;      // Whether sync is in progress
  final String message;     // Status message to display
  final Color color;        // Banner color
  final int? progress;      // Current item index (0-based)
  final int? total;         // Total items to sync
}
```

**Usage:**
```dart
final syncService = EnhancedSyncService();
await syncService.initialize();

// Listen to sync status
syncService.syncStatusStream.listen((status) {
  print('Sync status: ${status.message}');
});

// Trigger sync
await syncService.syncPendingUploads();
```

### 4. ConnectivityService (`lib/services/connectivity_service.dart`)

Existing service that monitors network connectivity.

**Features:**
- **Real-time Monitoring**: Detects connectivity changes
- **Stream-based**: Broadcasts online/offline status
- **Reconnection Callbacks**: Triggers actions when back online

## Integration Guide

### Home Screen Integration

The home screen (`lib/screens/home_screen.dart`) has been integrated with the SyncBanner to show global sync status:

```dart
@override
Widget build(BuildContext context) {
  return SyncBanner(
    child: Scaffold(
      appBar: AppBar(
        title: const Text("FileTrack Hub"),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _syncAllDocuments,
            tooltip: 'Sync All Documents',
          ),
        ],
      ),
      body: // ... home screen content
    ),
  );
}
```

### Document Screens Integration

Document screens (`incoming_documents_screen.dart`, `outgoing_documents_screen.dart`) have been integrated with ConnectivityBanner:

```dart
@override
Widget build(BuildContext context) {
  return ConnectivityBanner(
    child: Scaffold(
      // Screen content
    ),
  );
}
```

## How It Works

### Offline Queue System

1. **Document Creation/Update**:
   - When offline, documents are saved to local SQLite database
   - A `needs_sync` flag is set to `true`
   - Files are stored locally

2. **Connectivity Monitoring**:
   - ConnectivityService continuously monitors network status
   - When connectivity is lost, ConnectivityBanner shows offline indicator
   - When connectivity is restored, ConnectivityBanner shows online indicator

3. **Automatic Sync**:
   - When connectivity is restored, EnhancedSyncService automatically triggers
   - Pending uploads are queued and processed sequentially
   - SyncBanner shows progress: "Syncing 1/5 items"
   - Each successful upload updates the progress indicator

4. **Status Updates**:
   - All sync operations broadcast status through streams
   - UI components listen and update in real-time
   - Users see live progress without manual intervention

### Sync Flow Diagram

```
[User Action] → [Save Locally] → [Mark needs_sync=true]
                                         ↓
                              [Connectivity Restored]
                                         ↓
                              [EnhancedSyncService Triggered]
                                         ↓
                              [Process Upload Queue]
                                         ↓
                    [Upload 1/N] → [Upload 2/N] → ... → [Upload N/N]
                         ↓              ↓                     ↓
                    [Update UI]   [Update UI]          [Complete]
                                                            ↓
                                                  [Show Success Banner]
                                                            ↓
                                                  [Auto-dismiss after 3s]
```

## Screens with Integration

### ✅ Integrated Screens

1. **Home Screen** (`lib/screens/home_screen.dart`)
   - Has SyncBanner for global sync status
   - Shows upload progress for all pending items

2. **Incoming Documents Screen** (`lib/screens/incoming_documents_screen.dart`)
   - Has ConnectivityBanner for offline/online notifications
   - Manual connectivity checks removed

3. **Outgoing Documents Screen** (`lib/screens/outgoing_documents_screen.dart`)
   - Has ConnectivityBanner for offline/online notifications
   - Manual connectivity checks removed

### 📋 Screens to Integrate (Optional)

You can add ConnectivityBanner to these screens following the same pattern:

- `lib/screens/flag_ceremony_documents_screen.dart`
- `lib/screens/add_document_screen.dart`
- `lib/screens/add_flag_ceremony_screen.dart`
- `lib/screens/flag_ceremony_screen.dart`

## Testing the System

### Test Offline Functionality

1. **Create Document Offline**:
   - Turn on airplane mode
   - Create a new document
   - Observe: Document saved locally, red "No Internet Connection" banner appears

2. **Restore Connectivity**:
   - Turn off airplane mode
   - Observe: Green "Back Online" banner appears
   - Observe: Blue "Syncing 1/X items" banner appears
   - Observe: Progress updates as items sync
   - Observe: Green "Sync complete" banner appears and auto-dismisses

3. **Multiple Offline Actions**:
   - Turn on airplane mode
   - Create multiple documents (e.g., 5 documents)
   - Turn off airplane mode
   - Observe: "Syncing 1/5", "Syncing 2/5", etc.

### Test Error Handling

1. **Simulate Sync Error**:
   - Create document offline
   - Restore connectivity but with poor network
   - Observe: Error messages in sync banner
   - Observe: Failed items remain in queue for retry

## Configuration

### Customizing Banner Colors

Edit `lib/services/enhanced_sync_service.dart`:

```dart
static SyncStatus get syncing => SyncStatus(
  isActive: true,
  message: 'Syncing...',
  color: Colors.blue.shade700,  // Change color here
);
```

### Customizing Auto-dismiss Duration

Edit `lib/widgets/sync_banner.dart`:

```dart
Future.delayed(const Duration(seconds: 3), () {  // Change duration here
  if (mounted) {
    _animationController.reverse();
  }
});
```

### Customizing Animation Speed

Edit `lib/widgets/connectivity_banner.dart` or `lib/widgets/sync_banner.dart`:

```dart
_animationController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 300),  // Change duration here
);
```

## Benefits

✅ **Seamless Offline Experience**: Users can work without internet
✅ **Automatic Sync**: No manual intervention required
✅ **Visual Feedback**: Clear indicators for connectivity and sync status
✅ **Progress Tracking**: Users see exactly what's being synced
✅ **Error Handling**: Failed syncs are reported and can be retried
✅ **Consistent UX**: Same behavior across all screens
✅ **Non-blocking**: Users can continue working during sync

## Troubleshooting

### Banner Not Showing

- Ensure ConnectivityService is initialized in `main.dart`
- Check that the widget is wrapped with ConnectivityBanner or SyncBanner
- Verify stream subscriptions are active

### Sync Not Triggering

- Check EnhancedSyncService initialization
- Verify connectivity is actually restored
- Check for errors in console logs

### Progress Not Updating

- Ensure EnhancedSyncService is broadcasting status updates
- Check that SyncBanner is listening to the stream
- Verify the sync operation is actually processing items

## Future Enhancements

Potential improvements to consider:

1. **Retry Logic**: Automatic retry for failed syncs with exponential backoff
2. **Batch Uploads**: Upload multiple items in parallel for faster sync
3. **Conflict Resolution**: Handle conflicts when same document edited offline and online
4. **Sync History**: Log of all sync operations for debugging
5. **Manual Sync Control**: Allow users to pause/resume sync
6. **Selective Sync**: Let users choose which items to sync
7. **Background Sync**: Continue syncing even when app is in background

## Support

For issues or questions:
1. Check console logs for error messages
2. Verify all services are properly initialized
3. Test connectivity monitoring with airplane mode
4. Review this documentation for integration patterns
