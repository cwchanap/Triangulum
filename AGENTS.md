# Triangulum Agent Guidelines

This file contains build commands and code style guidelines for agentic coding assistants working on the Triangulum iOS app.

## Build/Lint/Test Commands
- **Build**: `xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug`
- **Clean Build**: `xcodebuild clean -project Triangulum.xcodeproj -scheme Triangulum`
- **Run**: Use Xcode (⌘+R) on simulator or device
- **Unit Tests**: `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum -destination 'platform=iOS Simulator,name=iPhone 15'`
- **Single Test**: `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:TriangulumTests/TestClassName/testMethodName`
- **UI Tests**: Run TriangulumUITests target in Xcode
- **Lint**: No specific linter; rely on Xcode build warnings and Swift compiler checks

## Code Style Guidelines
- **Imports**: Group by framework (SwiftUI, SwiftData), third-party (CoreLocation, PhotosUI), local; standard Swift imports
- **Formatting**: 4-space indentation, trailing commas in multi-line arrays/dicts; follow Swift style guide
- **Types**: Structs for value types/views, classes for managers/models; enums for sensor types with displayName
- **Naming**: PascalCase for types (e.g., LocationManager); camelCase for variables/functions (e.g., startLocationUpdates); UPPER_SNAKE_CASE for constants
- **Error Handling**: Use do-catch for throwing functions; prefer Result types for async; provide meaningful messages; avoid force unwraps
- **Concurrency**: Use @MainActor for UI; DispatchQueue for background; Task/await for async operations
- **Organization**: Use MARK comments for sections (e.g., // MARK: - Delegate)
- **Other**: @Published for ObservableObject; @StateObject over @ObservedObject; optional binding; no emojis unless requested