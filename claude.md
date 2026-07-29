# Custom Video Player - Project Context

## Project Overview

Custom Video Player is an iOS library that provides a feature-rich video player with custom playback controls, subtitle and video quality selection, live streaming support, variable playback speed, Picture-in-Picture, AirPlay, lock-screen controls, A-B repeat loops and segment playlists, and robust error handling. The library is distributed via CocoaPods and Swift Package Manager.

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
│   │   ├── ViewController/   # Player, subtitle/quality selection, A-B loop and
│   │   │                     # segment playlist creation
│   │   ├── ViewModel/        # View models for business logic
│   │   └── Views/            # Custom UI components
│   ├── Service/              # Services for video playback
│   ├── Theme/
│   │   ├── Styling/          # Colors, fonts, images, spacing
│   │   └── Helpers/          # Theme-related utilities
│   └── Utilities/            # Extensions and helper utilities
├── Assets/                   # Color and image assets
└── Resources/                # Localized strings (en.lproj/Localizable.strings)
```

## Key Components

### Core Features

1. **Custom Playback Controls** - Custom UI for play/pause, seek, volume, etc.
2. **Video Playlist** - Support for multiple videos in a playlist
3. **Subtitle Selection** - Allows users to select from available subtitles
4. **Video Quality Selection** - Dynamic quality switching
5. **Live Stream Support** - HLS live streaming capabilities
6. **Error Handling** - Robust error detection and user feedback
7. **A-B Repeat Loop** - Loop between an A and a B point. Point B is detected by a
   boundary time observer the player schedules at that exact time, and the seek back to A
   uses zero tolerance, so the loop closes on the frame rather than on the next poll. The
   1 Hz periodic observer is kept only as a backstop for a loop activated while the play
   head is already past point B.
8. **Segment Playlists** - Play a sequence of segments (`A→B, then C→D`) in order, with
   optional looping of the whole playlist. Created in
   `SegmentPlaylistCreationViewController` (segments can be reordered and deleted, and
   `order` is renumbered to match), stored through `ABLoopManager.addSegmentPlaylist`, and
   advanced during playback by `shouldAdvanceSegment(at:)`. Segment ends are evaluated on
   the 1 Hz periodic observer rather than a boundary observer, because their boundaries
   move as the playlist advances.
9. **Timecode Input** - Enter timestamps in HH:MM:SS:FF form. The frame field is validated
   against the video's real frame rate, which is loaded asynchronously from the asset;
   `ABLoopConstants.defaultFrameRate` (30.0) applies only while that load is in flight or
   when the asset exposes no usable video track.
10. **Variable Playback Speed** - 0.5x–2.0x, cycled from the speed button
    (`PlaybackSpeed`), with `audioTimePitchAlgorithm = .timeDomain` so pitch stays natural.
    The selected rate is stored and applied only while playback is running — writing a
    non-zero `AVPlayer.rate` is what *starts* an `AVPlayer`.
11. **Picture-in-Picture** - Rebuilt whenever the player layer is recreated, since the
    controller is bound to the layer it was created with. Requires the host app to declare
    the `audio` background mode.
12. **AirPlay** - `AVRoutePickerView` in the controls plus `allowsExternalPlayback`.
13. **Now Playing / Remote Commands** - Lock screen and Control Center show the current
    video and drive play, pause, toggle and ±15s skip. `MPRemoteCommandCenter` is a
    process-wide singleton, so every target registered is handed back in `deinit`.
14. **Audio Session** - `.playback`/`.moviePlayback`, so playback is audible with the
    ring/silent switch engaged, with interruption and route-change handling.
15. **Accessibility & Localization** - VoiceOver labels, Dynamic Type via `UIFontMetrics`,
    and presentations gated on `UIAccessibility.isReduceMotionEnabled`; user-facing strings
    resolve through `CVPLocalized` against the library's own resource bundle
    (`Resources/en.lproj`).

### Main Classes

- `VideoPlayerCoordinator` - Entry point for initializing and presenting the player
- `VideoPlayerViewController` - Main player view controller
- `VideoPlayerViewModel` - Business logic for video playback
- `SubtitleSelectionViewController` - UI for subtitle selection
- `QualitySelectionViewController` - UI for quality selection
- `PlayerControlsView` - Custom playback control UI
- `ABLoopManager` - Manages A-B loops and segment playlists with persistence; all state is
  serialized on a single serial queue
- `ABLoopViewController` - UI for managing A-B loops and segment playlists
- `ABLoopCreationViewController` - UI for creating new A-B loops
- `SegmentPlaylistCreationViewController` - UI for creating segment playlists
- `ABLoopValidation` - Shared validation for timecodes, loop ranges, the video-duration
  bound and segment playlists; used by both creation flows
- `TimecodeInputView` - Custom input view for timecode entry at frame granularity
- `PlaybackSpeed` - The rates the speed control cycles through (in `PlayerControlsView`)
- `LocalizedString` / `CVPLocalized` - Localization lookup against the library's resource
  bundle (`Bundle.module` under SwiftPM, `ResourcesBundle` under CocoaPods)

## Data Models

All model types below are public *and* their stored properties are public, so a consuming
app can both construct and read them.

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
Represents a timestamp at frame granularity, against the frame rate it is given (defaults
to `ABLoopConstants.defaultFrameRate`):
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
    pointA: TimePoint,          // Start point
    pointB: TimePoint,          // End point
    name: String?,              // Optional name
    videoIdentifier: String?    // Owning video, when known; scopes clearLoopData(for:)
)
```
`videoIdentifier` is last, defaulted and decoded with `decodeIfPresent`, so loops archived
before it existed still load.

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
2. Switch to the "Segment Playlists" tab
3. Tap "+ Create Segment Playlist" to open `SegmentPlaylistCreationViewController`
4. Add segments one start/end pair at a time (both points can be set from the current
   playback time); segments can be reordered or deleted, and `order` is renumbered to match
5. Optionally enable "Loop Playlist" to repeat the whole playlist, then save
6. Selecting a saved playlist plays its segments sequentially (A→B, then C→D, etc.)

Playlists are persisted per video by `ABLoopManager.addSegmentPlaylist(_:for:)`, which host
code can also call directly. A-B loops and segment playlists are mutually exclusive:
activating either clears the other.

## Development Guidelines

### Code Style
- Follow Swift naming conventions
- Use SnapKit for Auto Layout
- Maintain MVVM separation of concerns
- Keep view controllers lightweight by delegating logic to view models

### Testing
- SwiftPM test target `CustomVideoPlayerTests` in `Tests/CustomVideoPlayerTests` (132
  tests), run by CI via `xcodebuild test` against a dynamically resolved iOS simulator
- A second CI job runs `pod install` and builds the example workspace, covering the
  CocoaPods consumer path and the Mac Catalyst destination
- `PublicAPIReadabilityTests` deliberately uses a plain `import CustomVideoPlayer` rather
  than `@testable`, so the compiler is the regression guard for the public surface
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
- A-B loop data is persisted using UserDefaults via `ABLoopManager`. Every public method
  takes the manager's serial `stateQueue` exactly once and must never call another public
  method or nest `stateQueue.sync` — the `*Locked` helpers assume they are already on it
- Seeks use CMTime with `toleranceBefore`/`toleranceAfter` set to zero, so the seek is
  exact, and the seek back to point A is now triggered just as precisely — see the next
  point
- Point B is detected by a boundary time observer (`addBoundaryTimeObserver`, registered
  through `updateLoopBoundaryObserver()` in `VideoPlayerViewController`), which the player
  schedules at that exact time. Call `updateLoopBoundaryObserver()` on every change of the
  active loop, including deactivation; it removes any previous observer first
- The 1 Hz periodic time observer still runs, but for the seek bar, Now Playing info,
  segment advancement, and as a backstop for a loop activated past its end point — it is
  no longer what closes a loop
- Boundary observers live on the `AVPlayer` they were added to, so they must be removed
  before the player is replaced (`removeObservers()`, `resetPlayerItems()`, `deinit`)
- Timecode format follows industry standard: HH:MM:SS:FF (hours:minutes:seconds:frames)
- `getVideoFrameRate()` returns the rate resolved asynchronously by `loadVideoFrameRate()`
  (`asset.loadTracks(withMediaType:)` + `track.load(.nominalFrameRate)`), falling back to
  `ABLoopConstants.defaultFrameRate` (30.0) only while that load is in flight or when the
  asset exposes no usable video track. Do not reintroduce the synchronous
  `asset.tracks(withMediaType:)` accessor: it is deprecated, and for remote HLS it returns
  an empty array, which is what made the 30 fps fallback the normal path
- Live content gates several features off: the periodic and boundary observers, and the
  A-B loop and speed buttons (`enableLiveControls()`), are all skipped for it
- UIKit work reached from `AVPlayerItem` KVO or notifications must go through
  `runOnMainThread` — AVFoundation does not guarantee main-thread delivery
- The library must not `print`; use `os.Logger`, and never `fatalError` outside
  `init?(coder:)` stubs
- User-facing strings go through `CVPLocalized(_:value:comment:)`, never
  `NSLocalizedString` directly — the latter resolves against the host app's bundle
