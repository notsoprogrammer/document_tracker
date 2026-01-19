# Connectivity Banner Widget

A reusable Flutter widget that displays connectivity status notifications across your app.

## Features

- **Offline Banner**: Persistent red banner when device goes offline
- **Online Banner**: Temporary green banner when device comes back online (auto-dismisses after 3 seconds)
- **Smooth Animations**: Slide in/out transitions
- **Non-intrusive**: Overlays on top of screen content
- **Easy Integration**: Simple wrapper widget

## Usage

### 1. Import the Widget

```dart
import '../widgets/connectivity_banner.dart';
```

### 2. Wrap Your Screen

Wrap your `Scaffold` widget with `ConnectivityBanner`:

```dart
@override
Widget build(BuildContext context) {
  return ConnectivityBanner(
    child: Scaffold(
      appBar: AppBar(
        title: const Text("Your Screen Title"),
      ),
      body: YourScreenContent(),
    ),
  );
}
```

### 3. Complete Example

```dart
import 'package:flutter/material.dart';
import '../widgets/connectivity_banner.dart';

class YourScreen extends StatefulWidget {
  const YourScreen({super.key});

  @override
  State<YourScreen> createState() => _YourScreenState();
}

class _YourScreenState extends State<YourScreen> {
  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Your Screen"),
        ),
        body: Center(
          child: Text("Your content here"),
        ),
      ),
    );
  }
}
```

## How It Works

1. The widget listens to the `ConnectivityService` stream
2. When offline: Shows a persistent red banner at the top
3. When back online: Shows a temporary green banner that auto-dismisses after 3 seconds
4. Uses smooth slide animations for banner appearance/disappearance

## Integration in Existing Screens

### Before (Manual Connectivity Check)
```dart
import 'package:connectivity_plus/connectivity_plus.dart';

class MyScreen extends StatefulWidget {
  // ...
}

class _MyScreenState extends State<MyScreen> {
  late final Connectivity _connectivity = Connectivity();
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _connectivity.onConnectivityChanged.listen((result) {
      setState(() {
        _isOnline = result != ConnectivityResult.none;
      });
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    setState(() {
      _isOnline = result != ConnectivityResult.none;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ...
    );
  }
}
```

### After (Using ConnectivityBanner)
```dart
import '../widgets/connectivity_banner.dart';

class MyScreen extends StatefulWidget {
  // ...
}

class _MyScreenState extends State<MyScreen> {
  @override
  Widget build(BuildContext context) {
    return ConnectivityBanner(
      child: Scaffold(
        // ...
      ),
    );
  }
}
```

## Benefits

- ✅ **Consistent UX**: Same connectivity notification across all screens
- ✅ **Less Code**: No need to manually manage connectivity state in each screen
- ✅ **Automatic**: Handles all connectivity changes automatically
- ✅ **Visual Feedback**: Clear visual indicators for users
- ✅ **Non-blocking**: Doesn't interfere with screen functionality

## Screens to Update

You can integrate this widget into any screen that needs connectivity notifications:

- ✅ `outgoing_documents_screen.dart` (Already integrated as example)
- `incoming_documents_screen.dart`
- `flag_ceremony_documents_screen.dart`
- `home_screen.dart`
- `add_document_screen.dart`
- Any other screen where connectivity status is important

## Testing

To test the connectivity banner:

1. Run your app
2. Toggle airplane mode on your device
3. Observe the red "No Internet Connection" banner appearing
4. Toggle airplane mode off
5. Observe the green "Back Online" banner appearing and auto-dismissing after 3 seconds

## Notes

- The `ConnectivityService` must be initialized in `main.dart` (already done)
- The banner appears above all content using a `Stack` widget
- The banner respects safe areas (notches, status bars, etc.)
- No need to remove manual connectivity checks from screens - they won't conflict
