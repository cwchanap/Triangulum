# Privacy Permissions Setup for Triangulum

## Issue
The app crashes with `TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION` when trying to access motion sensors (accelerometer, gyroscope, magnetometer) because iOS requires explicit privacy permission declarations.

## Solution Steps

### 1. Add Privacy Permissions in Xcode

**Open Xcode and follow these steps:**

1. Open `Triangulum.xcodeproj` in Xcode
2. Select the `Triangulum` target in the project navigator
3. Go to the `Info` tab
4. Click the `+` button to add new entries
5. Add these **Custom iOS Target Properties**:

| Key | Value |
|-----|-------|
| `Privacy - Motion Usage Description` | `Triangulum uses motion sensors (accelerometer, gyroscope, and magnetometer) to provide real-time sensor data visualization and recording for scientific and educational purposes.` |
| `Privacy - Location When In Use Usage Description` | `Triangulum uses location services to provide GPS coordinates and altitude information alongside sensor readings for comprehensive environmental monitoring.` |

### 2. Alternative: Manual Info.plist Creation

If the above doesn't work, you can create an Info.plist file manually:

1. In Xcode, right-click on the `Triangulum` folder
2. Select `New File...`
3. Choose `Property List` 
4. Name it `Info.plist`
5. Add the following content:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSMotionUsageDescription</key>
	<string>Triangulum uses motion sensors (accelerometer, gyroscope, and magnetometer) to provide real-time sensor data visualization and recording for scientific and educational purposes.</string>
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Triangulum uses location services to provide GPS coordinates and altitude information alongside sensor readings for comprehensive environmental monitoring.</string>
</dict>
</plist>
```

### 3. Enable Motion Sensors in Code

After adding privacy permissions, you can re-enable the motion sensors by uncommenting the lines in `ContentView.swift`:

```swift
.onAppear {
    barometerManager.startBarometerUpdates()
    locationManager.startLocationUpdates()
    accelerometerManager.startAccelerometerUpdates()  // Uncomment this
    gyroscopeManager.startGyroscopeUpdates()          // Uncomment this
    magnetometerManager.startMagnetometerUpdates()    // Uncomment this
}
```

### 4. Test the Fix

1. Build and run the app on your device
2. The app should now request permission when first accessing motion sensors
3. Grant the permission when prompted
4. All sensor displays should work without crashing

## Privacy Permission Keys Explained

- `NSMotionUsageDescription` (Privacy - Motion Usage Description): Required for accessing accelerometer, gyroscope, and magnetometer
- `NSLocationWhenInUseUsageDescription` (Privacy - Location When In Use Usage Description): Required for GPS location services

## Troubleshooting

If you still get crashes:

1. **Check Settings**: Go to Settings > Privacy & Security > Motion & Fitness > Triangulum and ensure it's enabled
2. **Reset Permissions**: Delete and reinstall the app to reset permissions
3. **Check Build Settings**: Ensure the Info.plist file is properly referenced in your target's build settings

The updated sensor managers now include better error handling and will display helpful messages if permissions are denied.