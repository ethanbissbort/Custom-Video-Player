# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This repository is a maintained fork of
[ajkmr7/Custom-Video-Player](https://github.com/ajkmr7/Custom-Video-Player).
Releases from `1.1.0` and earlier belong to the upstream project; `2.0.0` is the
first release published from this fork.

## [Unreleased]

## [2.0.0] - 2026-07-29

The first release published from this fork. Two features that shipped in name
only now actually work — the A-B repeat loop never activated at all, and segment
playlists had no way to create one — and the player gains the capabilities a
modern iOS video player is expected to have: variable speed, Picture-in-Picture,
AirPlay and lock-screen controls. Alongside that, a set of defects that silenced
audio, leaked a player per video switch, or trapped the host app are fixed, and
the library is now covered by 132 tests that run in CI.

### BREAKING

- **Minimum deployment target raised from iOS 11.0 to iOS 18.0.** Both
  `Package.swift` (`platforms: [.iOS(.v18)]`) and `CustomVideoPlayer.podspec`
  (`s.ios.deployment_target = '18.0'`) now require iOS 18. Consumers targeting
  anything below iOS 18 cannot integrate this version and should stay on
  upstream `1.1.0`.
- **`UIView.roundCorners(corners:cornerRadius:)` is no longer public.** The
  extension was injecting the method into every `UIView` of every app that
  linked the library, which was never part of the player's contract. Apps that
  called it must declare their own equivalent.

### Added

- **Variable playback speed.** A speed control cycles 0.5x, 0.75x, 1x, 1.25x,
  1.5x and 2x, with `audioTimePitchAlgorithm = .timeDomain` so the pitch stays
  natural. The chosen rate is a *selection*, not a transport command: picking a
  speed while paused does not start playback, and the rate is re-applied on
  resume, after scrubbing and after stall recovery, where `AVPlayer` silently
  resets it to 1.0.
- **Picture-in-Picture.** The button appears only where PiP is supported and a
  controller could be built over the current layer. The controller is rebuilt
  whenever the player layer is, because it is permanently bound to the layer it
  was created with. PiP still requires the *host* app to declare the `audio`
  background mode.
- **AirPlay**, via an `AVRoutePickerView` in the controls plus
  `allowsExternalPlayback` on the player.
- **Now Playing info and remote commands**, so the lock screen and Control
  Center show the current video and drive play, pause, toggle and ±15s skip.
  Targets are registered once and handed back in `deinit` — the command centre
  is a process-wide singleton shared with the host app.
- **Segment playlists are now reachable.** `SegmentPlaylistCreationViewController`
  builds a playlist one start/end pair at a time, with reordering and deletion
  (`order` is renumbered to match), optional playlist looping, and validation
  through `ABLoopValidation`. Previously the "+ Create Segment Playlist" button
  opened an alert that only described the feature, `addSegmentPlaylist` had zero
  callers, and the whole engine behind it was unreachable.
- **Accessibility support**: VoiceOver labels for the transport controls and for
  the A-B loop, subtitle and quality selection flows; Dynamic Type through
  `UIFontMetrics`; and presentations that respect
  `UIAccessibility.isReduceMotionEnabled`.
- **Localization.** `CVPLocalized(_:value:comment:)` resolves strings against the
  library's own resource bundle (`Bundle.module` under SwiftPM, `ResourcesBundle`
  under CocoaPods) — `NSLocalizedString` alone resolves against `Bundle.main`,
  the host app's bundle, so a library's strings would never be found. English
  base strings ship in `Resources/en.lproj`, wired into both distribution
  channels (`defaultLocalization` in `Package.swift`, `resource_bundles` in the
  podspec).
- **A test suite of 132 tests**, up from a single `XCTAssert(true)` stub: A-B
  loop activation and detection at both the manager and the delegate/caller
  level, `ABLoopManager` concurrency, persistence, legacy-archive decoding and
  the corrupt-blob quarantine policy, segment advancement and completion,
  validation bounds, `TimePoint` conversion/formatting/parsing and Codable
  round-trip, the seek math's NaN/indefinite/overflow cases, `M3U8Helper` variant
  parsing with regressions for every parser defect fixed below, and a
  public-API readability test that deliberately avoids `@testable` so the
  compiler itself is the regression guard.
- CI now runs `xcodebuild test` against a dynamically resolved iPhone simulator;
  previously the workflow only ran `build-for-testing`, so no test ever executed.
  A second job installs pods and builds the example workspace, validating the
  CocoaPods consumer path.
- Mac Catalyst and iPad support for the example app (`SUPPORTS_MACCATALYST = YES`,
  `TARGETED_DEVICE_FAMILY = "1,2"`), with a CI job that builds for the Mac
  Catalyst destination.

### Changed

- **A-B loop end detection is now precise.** A boundary time observer scheduled
  by the player at point B closes the loop, instead of the 1 Hz periodic
  observer, which overshot by up to a full second and made the advertised frame
  accuracy meaningless. The periodic check remains only as a backstop for a loop
  activated while the play head is already past its end point.
- **The video frame rate is loaded asynchronously** with `load(_:)`. The previous
  synchronous `asset.tracks(withMediaType:)` accessor returns an empty array for
  a remote HLS asset, so every timecode was computed against the 30 fps fallback
  rather than the video's real rate.
- **The public model types are readable.** `TimePoint`, `ABLoop`,
  `PlaybackSegment`, `SegmentPlaylist`, `VideoLoopData`, `VideoPlayerConfig`,
  `VideoPlaylist` and `Video` were public types with public memberwise
  initializers but *internal* stored properties, so a consumer could construct a
  `Video` and then not read `video.url`. Their stored properties are now public,
  preserving each property's `let`/`var` mutability. Widening access is
  source-compatible.
- `ABLoop` carries an optional `videoIdentifier` so `clearLoopData(for:)` can
  scope itself correctly. The parameter is last and defaulted and decoding uses
  `decodeIfPresent`, so existing call sites compile and previously saved loops
  still load.
- All `ABLoopManager` state is serialized on its one serial queue, including the
  `videoLoopData` dictionary, which was previously mutated on the caller's thread
  while the neighbouring lines took the lock. Every public method takes the queue
  exactly once; the persistence helpers assume they are already on it, so there
  is no re-entrancy hazard.
- Device orientation is changed through `UIWindowScene.requestGeometryUpdate`
  plus `setNeedsUpdateOfSupportedInterfaceOrientations()`, replacing the
  undocumented `UIDevice.setValue(_:forKey: "orientation")` KVC — a private-API
  call that has been a no-op since iOS 16 and is an App Review rejection trigger.
- `fatalError` is gone from the library's runtime paths: a missing resource
  bundle now logs and falls back to the framework bundle instead of crashing the
  host app on first present. Diagnostics go through `os.Logger` rather than
  `print`, so the library no longer writes into the host app's console.
- `APIClientService` validates the HTTP status code and surfaces a non-2xx
  response as a failure, with a 15s request timeout. `URLSession` treats a 404 as
  a successful transfer, so an HTML error page was previously handed to the
  manifest parser.
- The A-B loop and speed controls are hidden on live content, where loop
  evaluation is gated off and a rate other than 1.0 just falls off the live edge.
  Both were fully interactive and did nothing.
- Distribution metadata points at this fork: `s.homepage` and `s.source`
  reference `ethanbissbort/Custom-Video-Player` instead of the upstream
  repository, so `pod install` resolves this fork's code rather than upstream's
  pre-fork sources. The podspec also declares `s.swift_version = '5.0'`, matching
  `swiftLanguageModes: [.v5]` in `Package.swift`; previously it declared none.

### Fixed

- **The A-B repeat loop never activated.** `didSelectABLoop` called
  `setActiveLoop(loop)` and then `setActiveSegmentPlaylist(nil)`, but each
  setter already clears the opposing mode and both dispatch onto the same serial
  queue. FIFO ordering guaranteed the second block nilled the loop the first had
  just set, so `currentActiveLoop` was always `nil`, `shouldLoop(at:)` always
  returned `nil`, and playback never looped. `didSelectSegmentPlaylist` was
  broken symmetrically. The redundant cross-clearing calls are removed.
- **Video played silently when the ring/silent switch was engaged.** The library
  never configured `AVAudioSession`; it now sets `.playback`/`.moviePlayback` on
  setup and releases the session with `.notifyOthersOnDeactivation` on teardown,
  every call wrapped in `do`/`catch` so a session failure degrades to silent
  playback rather than trapping the host app. Interruptions (call, Siri) pause
  and resume only what the interruption stopped, and an unplugged headphone
  route pauses instead of blasting audio out of the speaker.
- **UIKit work off the main thread.** `AVPlayerItem` KVO and notifications are
  not guaranteed to arrive on main — for HLS they routinely do not — yet the
  handlers added subviews and installed SnapKit constraints. Every UI-touching
  handler body is now marshalled to main.
- **The buffering spinner could never be dismissed.** A stall started the
  activity indicator and nothing stopped it, because `stopAnimating()` was gated
  behind `!didSetupControls`, which is false after the first load. Playback
  recovery is now observed through `playbackLikelyToKeepUp`/`playbackBufferEmpty`.
- **An `AVPlayerLayer` and its `AVPlayer` leaked on every video switch.** The
  layer was never detached, and a layer retains its player, so each switch
  stacked another layer and kept every previous player alive. KVO, notification
  and periodic time observers were likewise not removed before the item was
  discarded.
- An active A-B loop survived a video switch and kept firing against the new
  video's timeline; switching videos now clears it.
- Two data-loss paths in `ABLoopManager`: `Dictionary(uniqueKeysWithValues:)`
  trapped at player construction on a stored blob holding two entries with the
  same video identifier, and a decode failure left the dictionary empty so the
  next mutation overwrote every saved loop with it. Duplicate keys are now
  resolved by keeping the richer entry, and an unreadable blob is quarantined
  under a backup key rather than overwritten.
- A loop whose point B sits past the end of the asset could be saved: it looked
  valid in the list, activated without complaint, and could never fire.
  `ABLoopValidation` — 208 lines that had no callers, next to a weaker inline
  copy — is now wired into both creation flows, including the duration bound.
- "Set to Current Time" could use a stale timestamp, because `updateCurrentTime`
  had no caller.
- Crash risks:
  - `NameableAsset` force-unwrapped `UIColor(named:)!` / `UIImage(named:)!`;
    a missing asset now falls back safely instead of trapping.
  - `CMTime.durationText` converted non-finite or negative seconds (indefinite
    or live `CMTime`) to `Int`, trapping on NaN; it is now guarded, as are the
    same conversions in `getForwardTime`, `getBackwardTime` and
    `getFormattedTime`, which also reject finite-but-huge values that overflow
    `Int64` once scaled.
  - `M3U8Helper` sorted variants with a non-strict (`>=`) comparator, violating
    strict weak ordering; it now uses `>`.
  - `VideoPlayerViewModel` indexed the video list and playback bitrates without
    bounds checks; out-of-range subscripts are now guarded.
- A forward seek on an indefinite duration (a live stream) returned nothing, so
  the skip-forward button did nothing; it now seeks ahead and lets the player pin
  the request to its seekable range.
- The rewind button had no target-action wired, so seek-backward did nothing.
- Manifest parsing:
  - Rows were split on `\n` only, so CRLF-delimited manifests left a trailing
    `\r` on the last attribute of every line; rows are now split on any newline.
  - Attributes were split on every comma, so a quoted `CODECS="avc1…,mp4a…"`
    list fragmented the row and its fragments were mistaken for attributes,
    dropping the variant entirely. Splitting is now quote-aware.
  - `BANDWIDTH` matched any attribute *containing* that name, so a variant
    listing `AVERAGE-BANDWIDTH` first advertised its average as the peak
    bitrate. Attribute names are now matched exactly.
  - "Auto" was prepended unconditionally, so an unparseable or empty manifest
    still produced a one-entry quality list — and because the settings button
    keys off a non-empty list, the player presented a working-looking quality
    menu containing a single bogus row. "Auto" is now added only when at least
    one real variant was parsed.
- Invalid SwiftPM resource declaration: the target used
  `resources: [.copy("Assets/*")]`, but `.copy` takes a real path rather than a
  glob. Xcode 16 failed the build with `Found unhandled resource`, and `.copy`
  would not compile the asset catalogs. The two catalogs are now declared
  individually with `.process`.

[Unreleased]: https://github.com/ethanbissbort/Custom-Video-Player/compare/2.0.0...HEAD
[2.0.0]: https://github.com/ethanbissbort/Custom-Video-Player/releases/tag/2.0.0
