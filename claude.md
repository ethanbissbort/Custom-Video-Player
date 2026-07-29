# Custom Video Player - Project Context

## Project Overview

Custom Video Player is an iOS library that provides a feature-rich video player with custom playback controls, subtitle and video quality selection, live streaming support, and robust error handling. The library is distributed via CocoaPods and Swift Package Manager.

## Technology Stack

- **Language**: Swift
- **Minimum iOS Version**: iOS 18.0
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
7. **A-B Repeat Loop** - Loop between an A and a B point. Accuracy is limited: loop
   detection runs inside a periodic time observer with a 1-second interval, so point B
   overshoots by up to a second before the seek back to A fires. The seek itself uses
   zero tolerance, but the *detection* is not frame-accurate.
8. **Segment Playlists** - ⚠️ **Not yet implemented.** The model layer
   (`SegmentPlaylist`, `PlaybackSegment`), storage (`ABLoopManager.addSegmentPlaylist`)
   and playback advancement (`shouldAdvanceSegment(at:)`) exist, but there is no UI path
   to create one: the "+ Create Segment Playlist" button opens an explanatory
   `UIAlertController` and nothing else, and `addSegmentPlaylist` has zero callers in the
   codebase. Sequential `A→B, then C→D` playback therefore cannot be reached by a user.
9. **Timecode Input** - Enter timestamps in HH:MM:SS:FF form. See the frame-rate caveat
   under "Notes for AI Assistance" — the frame field is only as accurate as the detected
   frame rate, which falls back to 30.0 for HLS.

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
Represents a timestamp at frame granularity (subject to the frame-rate detection caveat
below):
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

⚠️ **Not reachable from the UI.** The "Segment Playlists" tab lists persisted playlists
and the playback engine will advance through them, but there is no way to create one:
tapping "+ Create Segment Playlist" presents an alert describing the feature and
dismisses. `ABLoopManager.addSegmentPlaylist(_:for:)` is public but has no callers, so
the only way to populate a playlist today is programmatically from host code.

The intended flow, once a creation UI exists, is:

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
- SwiftPM test target `CustomVideoPlayerTests` in `Tests/CustomVideoPlayerTests` (45
  tests), run by CI via `xcodebuild test` against an iOS simulator
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

This repository is a fork of `ajkmr7/Custom-Video-Player`. The podspec's `homepage` and
`source` point at `ethanbissbort/Custom-Video-Player`; the MIT `LICENSE` retains Ajay
Kumar's 2023 copyright and both the original author and the fork maintainer are listed in
`s.author`.

### CocoaPods
Podspec: `CustomVideoPlayer.podspec`
Podspec version: 2.0.0

**No git tags exist in this repository.** `git tag` returns nothing, so neither the
podspec's `:tag => s.version.to_s` nor the SwiftPM `from: "2.0.0"` will resolve until a
`2.0.0` tag is pushed. See `CHANGELOG.md`.

### Swift Package Manager
Package manifest: `Package.swift`
swift-tools-version 6.0, `swiftLanguageModes: [.v5]`, platform `.iOS(.v18)`
Supports iOS 18.0+ (raised from iOS 11.0 — a breaking change for existing consumers)

## Notes for AI Assistance

- When modifying UI components, ensure SnapKit constraints are properly configured
- Video playback uses AVPlayer/AVPlayerLayer
- Live content requires `isLiveContent: true` flag
- HLS (.m3u8) streams are the primary format
- Error handling is centralized in `VideoPlayerViewController+ErrorHandling.swift`
- Delegate pattern used in `VideoPlayerViewController+Delegate.swift`
- A-B loop data is persisted using UserDefaults via `ABLoopManager`
- Seeks use CMTime with `toleranceBefore`/`toleranceAfter` set to zero, so the *seek* is
  exact — but see the next point: what triggers the seek is not
- Periodic time observer checks for loop/segment transitions once per second
  (`CMTime(seconds: 1, ...)` in `VideoPlayerViewController`). Point B is therefore
  detected up to ~1s late; the feature is not frame-accurate end-to-end
- Timecode format follows industry standard: HH:MM:SS:FF (hours:minutes:seconds:frames)
- `getVideoFrameRate()` reads `playerItem?.asset.tracks(withMediaType: .video)`
  synchronously. For HLS (`.m3u8`) streams — the primary format here — that returns an
  empty array, so `ABLoopConstants.defaultFrameRate` (30.0) is the normal path, not an
  edge case. Frame numbers in timecodes are computed against that assumed 30 fps
