# App Icon Setup

To complete the app icon and splash screen setup:

## Step 1: Add Your Icon Image

Place a 512x512 PNG image named `icon.png` in this directory.

Requirements:
- Format: PNG
- Size: 512x512 pixels (minimum)
- Recommended: Square image with no transparency for best results
- The icon should represent a secure/encryption theme (lock, shield, etc.)

You can create or download a free icon from:
- https://icons8.com
- https://www.flaticon.com
- https://www.canva.com

## Step 2: Generate App Icons

After adding icon.png, run these commands from the project root:

```bash
flutter pub run flutter_launcher_icons:main
flutter pub run flutter_native_splash:create
```

This will:
- Generate launcher icons for Android and iOS
- Create a native splash screen with your icon

## Step 3: Test

Run the app to see your new icon and splash screen:

```bash
flutter run
```

The splash screen will show briefly when the app starts, and your icon will appear in the app drawer/home screen.
