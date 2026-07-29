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

### Changed

- **BREAKING: minimum deployment target raised from iOS 11.0 to iOS 18.0.**
  Both `Package.swift` (`platforms: [.iOS(.v18)]`) and
  `CustomVideoPlayer.podspec` (`s.ios.deployment_target = '18.0'`) now require
  iOS 18. Consumers targeting anything below iOS 18 cannot integrate this
  version and should stay on upstream `1.1.0`.
- Distribution metadata now points at this fork. `s.homepage` and `s.source`
  in the podspec reference `ethanbissbort/Custom-Video-Player` instead of the
  upstream repository, so `pod install` resolves this fork's code rather than
  upstream's pre-fork sources.
- The podspec declares `s.swift_version = '5.0'`, matching
  `swiftLanguageModes: [.v5]` in `Package.swift`. Previously the podspec
  declared no Swift version at all.

### Added

- A test suite (45 tests) covering A-B loop activation semantics and loop
  detection around point B, `ABLoopManager` persistence across instances,
  `TimePoint` timecode conversion/formatting/parsing and Codable round-trip,
  loop duration and containment, segment ordering, and `M3U8Helper` variant
  parsing including regression tests for the sort-comparator and CRLF fixes.
- CI now runs `xcodebuild test` against a dynamically resolved iPhone
  simulator. Previously the workflow only ran `build-for-testing`, so no test
  ever executed.
- Mac Catalyst and iPad support for the example app
  (`SUPPORTS_MACCATALYST = YES`, `TARGETED_DEVICE_FAMILY = "1,2"`), with a CI
  job that builds the workspace for the Mac Catalyst destination.

### Fixed

- **The A-B repeat loop never activated.** `didSelectABLoop` called
  `setActiveLoop(loop)` and then `setActiveSegmentPlaylist(nil)`, but each
  setter already clears the opposing mode and both dispatch onto the same
  serial queue. FIFO ordering guaranteed the second block nilled the loop the
  first had just set, so `currentActiveLoop` was always `nil`, `shouldLoop(at:)`
  always returned `nil`, and playback never looped. `didSelectSegmentPlaylist`
  was broken symmetrically. The redundant cross-clearing calls are removed.
- Crash risks:
  - `NameableAsset` force-unwrapped `UIColor(named:)!` / `UIImage(named:)!`;
    a missing asset now falls back safely instead of trapping.
  - `CMTime.durationText` converted non-finite or negative seconds (indefinite
    or live `CMTime`) to `Int`, trapping on NaN; it is now guarded.
  - `M3U8Helper` sorted variants with a non-strict (`>=`) comparator, violating
    strict weak ordering; it now uses `>`.
  - `VideoPlayerViewModel` indexed the video list and playback bitrates without
    bounds checks; out-of-range subscripts are now guarded.
- Observer leak on video switch: KVO, notification, and periodic time observers
  were not removed before the player item was discarded.
- The rewind button had no target-action wired, so seek-backward did nothing.
- `M3U8Helper` split manifests on `\n` only, so CRLF-delimited streams parsed
  incorrectly; rows are now split on any newline.
- Invalid SwiftPM resource declaration: the target used
  `resources: [.copy("Assets/*")]`, but `.copy` takes a real path rather than a
  glob. Xcode 16 failed the build with `Found unhandled resource`, and `.copy`
  would not compile the asset catalogs. The two catalogs are now declared
  individually with `.process`.

[Unreleased]: https://github.com/ethanbissbort/Custom-Video-Player/compare/2.0.0...HEAD
[2.0.0]: https://github.com/ethanbissbort/Custom-Video-Player/releases/tag/2.0.0
