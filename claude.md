# Custom Video Player - Project Context

## Project Overview

Custom Video Player is an iOS library that provides a feature-rich video player with custom playback controls, subtitle and video quality selection, live streaming support, and robust error handling. The library is distributed via CocoaPods and Swift Package Manager.

## Technology Stack

- **Language**: Swift
- **Minimum iOS Version**: iOS 11.0
- **Dependencies**:
  - SnapKit (5.0.0+) - Auto Layout DSL
- **Distribution**: CocoaPods, Swift Package Manager

## Architecture

The project follows an MVVM (Model-View-ViewModel) architecture with Coordinator pattern for navigation.

### Directory Structure

```
Custom-Video-Player/
├── Classes/
│   ├── Coordinator/          # Navigation coordination
│   ├── Presentation/
│   │   ├── ViewController/   # View controllers for player, subtitle, and quality selection
│   │   ├── ViewModel/        # View models for business logic
│   │   └── Views/            # Custom UI components
│   ├── Service/              # Services for video playback
│   ├── Theme/
│   │   ├── Styling/          # Colors, fonts, images, spacing
│   │   └── Helpers/          # Theme-related utilities
│   └── Utilities/            # Extensions and helper utilities
└── Assets/                   # Color and image assets
```

## Key Components

### Core Features

1. **Custom Playback Controls** - Custom UI for play/pause, seek, volume, etc.
2. **Video Playlist** - Support for multiple videos in a playlist
3. **Subtitle Selection** - Allows users to select from available subtitles
4. **Video Quality Selection** - Dynamic quality switching
5. **Live Stream Support** - HLS live streaming capabilities
6. **Error Handling** - Robust error detection and user feedback
7. **A-B Repeat Loop** - Loop between precise A and B points with frame-level accuracy
8. **Segment Playlists** - Create playlists of video segments for custom viewing sequences
9. **Timecode Input** - Enter precise timestamps down to frame number (HH:MM:SS:FF)

### Main Classes

- `VideoPlayerCoordinator` - Entry point for initializing and presenting the player
- `VideoPlayerViewController` - Main player view controller
- `VideoPlayerViewModel` - Business logic for video playback
- `SubtitleSelectionViewController` - UI for subtitle selection
- `QualitySelectionViewController` - UI for quality selection
- `PlayerControlsView` - Custom playback control UI
- `ABLoopManager` - Manages A-B loops and segment playlists with persistence
- `ABLoopViewController` - UI for managing A-B loops and segment playlists
- `ABLoopCreationViewController` - UI for creating new A-B loops
- `TimecodeInputView` - Custom input view for frame-accurate timecode entry

## Data Models

### VideoPlaylist
```swift
VideoPlaylist(
    title: String,
    videos: [Video]
)
```

### Video
```swift
Video(
    url: String,          // Video URL (supports HLS streams)
    title: String,        // Display title
    isLiveContent: Bool   // Indicates if content is live streaming
)
```

### VideoPlayerConfig
Configuration object to initialize the player with a playlist.

### A-B Loop Models

#### TimePoint
Represents a precise timestamp with frame-level accuracy:
```swift
TimePoint(
    hours: Int,
    minutes: Int,
    seconds: Int,
    frames: Int,
    frameRate: Double
)
```

#### ABLoop
Represents a single A-B loop:
```swift
ABLoop(
    id: UUID,
    pointA: TimePoint,    // Start point
    pointB: TimePoint,    // End point
    name: String?         // Optional name
)
```

#### PlaybackSegment
Represents a segment in a segment playlist:
```swift
PlaybackSegment(
    id: UUID,
    startPoint: TimePoint,
    endPoint: TimePoint,
    order: Int,
    name: String?
)
```

#### SegmentPlaylist
Represents a playlist of segments for sequential playback:
```swift
SegmentPlaylist(
    id: UUID,
    name: String,
    segments: [PlaybackSegment],
    videoIdentifier: String,
    isLooping: Bool       // Loop entire playlist
)
```

## Usage Pattern

### Basic Video Playback
1. Create a `VideoPlaylist` with videos
2. Create a `VideoPlayerConfig` with the playlist
3. Initialize `VideoPlayerCoordinator` with navigation controller
4. Call `coordinator.invoke(videoPlayerConfig: config)`

### Using A-B Loop Features
1. Tap the "A-B" button in the player controls
2. Create a new A-B loop by:
   - Entering timecodes manually (HH:MM:SS:FF format)
   - Using "Set to Current Time" buttons for point A and B
3. Saved loops are automatically persisted per video
4. Activate a loop by selecting it from the list
5. Deactivate by tapping "Stop Loop"

### Using Segment Playlists
1. Access the A-B Loop manager
2. Switch to "Segment Playlists" tab
3. Create a segment playlist with multiple A-B points
4. Segments play sequentially (A→B, then C→D, etc.)
5. Optional: Enable looping to repeat the entire playlist

## Development Guidelines

### Code Style
- Follow Swift naming conventions
- Use SnapKit for Auto Layout
- Maintain MVVM separation of concerns
- Keep view controllers lightweight by delegating logic to view models

### Testing
- Example app available in `Example/` directory
- Run example: `cd Example && pod install && open Custom-Video-Player.xcworkspace`

### Extension Points
- Custom themes via Theme/Styling classes
- Custom controls by extending PlayerControlsView
- Additional video formats supported by AVPlayer

## Resources

### Documentation
- [Part 1 — Custom Control Setup](https://ajkmr7.medium.com/crafting-the-ultimate-ios-video-player-part-1-mastering-custom-control-setup-30732b12ab37)
- [Part 2 — Subtitle Handling](https://ajkmr7.medium.com/demystifying-subtitle-handling-in-ios-apps-a-swift-avplayer-tutorial-1d60eab06f87)
- [Part 3 — Video Quality Selection](https://ajkmr7.medium.com/crafting-the-ultimate-ios-video-player-part-3-exploring-video-quality-selection-670b38f06962)
- [Part 4 — Live Content Support](https://ajkmr7.medium.com/crafting-the-ultimate-ios-video-player-part-4-elevating-your-player-with-live-content-support-cc21fa50c1a6)
- [Bonus — Watch Party Integration](https://ajkmr7.medium.com/watchcrafting-the-ultimate-ios-video-player-bonus-watch-party-integration-13be7e7685bb)

### Special Branches
- `watch-party` - Implementation of Watch Party feature

## Build & Distribution

### CocoaPods
Podspec: `CustomVideoPlayer.podspec`
Latest tag: 1.1.0

### Swift Package Manager
Package manifest: `Package.swift`
Supports iOS 11.0+

## Notes for AI Assistance

- When modifying UI components, ensure SnapKit constraints are properly configured
- Video playback uses AVPlayer/AVPlayerLayer
- Live content requires `isLiveContent: true` flag
- HLS (.m3u8) streams are the primary format
- Error handling is centralized in `VideoPlayerViewController+ErrorHandling.swift`
- Delegate pattern used in `VideoPlayerViewController+Delegate.swift`
- A-B loop data is persisted using UserDefaults via `ABLoopManager`
- Frame-accurate seeking uses CMTime with tolerance set to zero
- Timecode format follows industry standard: HH:MM:SS:FF (hours:minutes:seconds:frames)
- Video frame rate is automatically detected from AVAsset track properties
- Periodic time observer checks for loop/segment transitions every second
