# Google Drive Integration Setup Guide

This guide will help you set up Google Drive integration for your Document Tracker app.

## Prerequisites

1. A Google account
2. Flutter development environment set up
3. Your app's package name (found in `android/app/build.gradle` or `android/app/src/main/AndroidManifest.xml`)

## Step 1: Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Create Project" or select an existing project
3. Give your project a name (e.g., "Document Tracker")
4. Click "Create"

## Step 2: Enable Google Drive API

1. In your Google Cloud project, go to "APIs & Services" > "Library"
2. Search for "Google Drive API"
3. Click on "Google Drive API" and enable it

## Step 3: Create OAuth 2.0 Credentials

### For Android:
1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
3. Choose "Android" as application type
4. Enter your package name (e.g., `com.example.document_tracker`)
5. For SHA-1 certificate fingerprint:
   - For development: Run `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`
   - For production: Get from your keystore
6. Click "Create"
7. Copy the Client ID (ends with `.apps.googleusercontent.com`)

### For iOS:
1. Click "Create Credentials" > "OAuth 2.0 Client IDs"
2. Choose "iOS" as application type
3. Enter your Bundle ID (found in `ios/Runner.xcodeproj/project.pbxproj` or `ios/Runner/Info.plist`)
4. Click "Create"
5. Copy the Client ID

### For Web (optional, for web deployment):
1. Click "Create Credentials" > "OAuth 2.0 Client IDs"
2. Choose "Web application" as application type
3. Add authorized origins: `http://localhost:3000` (for development)
4. Click "Create"
5. Copy the Client ID

## Step 4: Configure Your App

1. Open `lib/config/google_drive_config.dart`
2. Replace the placeholder values with your actual Client IDs:

```dart
class GoogleDriveConfig {
  // For Android
  static const String androidClientId = 'YOUR_ACTUAL_ANDROID_CLIENT_ID.apps.googleusercontent.com';

  // For iOS
  static const String iosClientId = 'YOUR_ACTUAL_IOS_CLIENT_ID.apps.googleusercontent.com';

  // For Web (if deploying to web)
  static const String webClientId = 'YOUR_ACTUAL_WEB_CLIENT_ID.apps.googleusercontent.com';
}
```

## Step 5: Configure Android

1. Open `android/app/build.gradle`
2. Add your SHA-1 certificate fingerprint to the manifest:

```gradle
android {
    defaultConfig {
        // Add this line with your SHA-1
        manifestPlaceholders['appAuthRedirectScheme'] = 'com.googleusercontent.apps.YOUR_CLIENT_ID_WITHOUT_SUFFIX'
    }
}
```

3. Open `android/app/src/main/AndroidManifest.xml`
4. Add these permissions and intent filters:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Add these permissions -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <application>
        <!-- Add this meta-data -->
        <meta-data
            android:name="com.google.android.gms.version"
            android:value="@integer/google_play_services_version" />

        <!-- Add this intent filter inside your activity -->
        <activity android:name=".MainActivity">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>

            <!-- Add this intent filter for Google Sign-In -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="com.googleusercontent.apps.YOUR_CLIENT_ID_WITHOUT_SUFFIX" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

## Step 6: Configure iOS

1. Open `ios/Runner/Info.plist`
2. Add these keys:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Add these keys -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>
            </array>
        </dict>
    </array>

    <key>NSPhotoLibraryUsageDescription</key>
    <string>This app needs access to your photo library to upload document images.</string>

    <key>NSCameraUsageDescription</key>
    <string>This app needs access to your camera to take document photos.</string>

    <!-- Other existing keys... -->
</dict>
</plist>
```

## Step 7: Test the Integration

1. Run your app
2. Try adding a document with images
3. The app should prompt for Google Sign-In
4. After signing in, images should upload to Google Drive

## Troubleshooting

### Common Issues:

1. **"Sign-in failed" error**:
   - Check that your Client IDs are correct
   - Verify SHA-1 fingerprint for Android
   - Ensure OAuth consent screen is configured

2. **"Access denied" error**:
   - Make sure Google Drive API is enabled
   - Check that OAuth scopes are correct

3. **Images not uploading**:
   - Verify internet connection
   - Check Google Drive permissions
   - Ensure folders can be created

### OAuth Consent Screen Setup:

1. Go to "APIs & Services" > "OAuth consent screen"
2. Choose "External" user type
3. Fill in app information
4. Add test users if needed
5. Submit for verification if publishing

## Security Notes

- Never commit your Client IDs to version control
- Use different credentials for development and production
- Regularly rotate your OAuth credentials
- Monitor API usage in Google Cloud Console

## Support

If you encounter issues:
1. Check the console logs for detailed error messages
2. Verify all configuration steps are completed
3. Ensure your Google Cloud project is properly set up
4. Test with a fresh Google account if needed

---

**Note**: This setup requires a Google Cloud project with billing enabled for production use. The free tier provides sufficient quota for development and small-scale usage.
