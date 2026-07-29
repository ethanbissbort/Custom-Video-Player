> # ⚠️ SUPERSEDED — HISTORICAL DOCUMENT
>
> **This document is out of date and is retained only as a record of the
> 2025-12-05 audit follow-up. Do not treat it as a current to-do list.**
>
> As of **2026-07-29** the items below are resolved, and the document omits the
> larger problems found afterwards — most notably that the A-B loop feature
> never activated at all, plus several crash risks, an observer leak, a dead
> rewind button, CRLF manifest parsing, an invalid SwiftPM resource glob, and
> the breaking iOS 11 → iOS 18 deployment-target change.
>
> **For the current state of this project, see
> [CHANGELOG.md](CHANGELOG.md).**

---

# Critical Fixes Required

This document outlines the critical issues found during the code audit that must be addressed immediately.

---

## 🔴 CRITICAL: Missing Font Method

**Priority:** CRITICAL - Will cause crashes
**Location:** `Custom-Video-Player/Classes/Theme/Styling/Font.swift`
**Status:** ✅ IMPLEMENTED

### Issue
The `FontUtility` class is missing the `helveticaNeueBold(ofSize:)` method, which is referenced in 11 locations across the codebase. This will cause runtime crashes when any UI component tries to use bold fonts.

### Affected Components
- TimecodeInputView (3 instances)
- ABLoopViewController (3 instances)
- ABLoopCreationViewController (4 instances)
- PlayerControlsView (1 instance)

### Fix Required

Add the following method to `FontUtility` class in `Font.swift`:

```swift
/// Returns a font with the HelveticaNeue-Bold style at the specified size.
///
/// - Parameter size: The size of the font.
/// - Returns: A UIFont object with the HelveticaNeue-Bold style.
static func helveticaNeueBold(ofSize size: CGFloat) -> UIFont {
    return UIFont(name: "HelveticaNeue-Bold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .bold)
}
```

### Testing After Fix
1. Launch the app
2. Open A-B Loop manager
3. Create a new A-B Loop
4. Verify all text displays correctly without crashes

---

## ⚠️ HIGH PRIORITY: Incomplete Runtime Error Handling

**Priority:** HIGH
**Location:** `Custom-Video-Player/Classes/Presentation/ViewController/VideoPlayerViewController+ErrorHandling.swift`
**Status:** ✅ IMPLEMENTED

### Issue
The file contains a TODO comment indicating incomplete error handling:
```swift
// TODO: Error handling when something happens in between while playing video
```

Current error handling only covers initial playback failures, not runtime interruptions.

### Recommended Implementation

Add notification observers in `VideoPlayerViewController.swift`:

```swift
// Add to viewDidLoad or setupPlayer
NotificationCenter.default.addObserver(
    self,
    selector: #selector(playerItemFailedToPlayToEndTime),
    name: .AVPlayerItemFailedToPlayToEndTime,
    object: playerItem
)

NotificationCenter.default.addObserver(
    self,
    selector: #selector(playerItemPlaybackStalled),
    name: .AVPlayerItemPlaybackStalled,
    object: playerItem
)

// Add handler methods
@objc private func playerItemFailedToPlayToEndTime(notification: Notification) {
    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
        handlePlayerError(error)
    }
}

@objc private func playerItemPlaybackStalled() {
    // Show buffering indicator or retry logic
    activityIndicatorView.startAnimating()
}

// Don't forget to remove observers in deinit
NotificationCenter.default.removeObserver(
    self,
    name: .AVPlayerItemFailedToPlayToEndTime,
    object: nil
)
NotificationCenter.default.removeObserver(
    self,
    name: .AVPlayerItemPlaybackStalled,
    object: nil
)
```

---

## ⚠️ MEDIUM PRIORITY: Thread Safety in ABLoopManager

**Priority:** MEDIUM
**Location:** `Custom-Video-Player/Classes/Service/ABLoopManager.swift`
**Status:** ✅ IMPLEMENTED

### Issue
The `shouldLoop(at:)` and `shouldAdvanceSegment(at:)` methods are called from a periodic observer, but there's no thread safety for accessing/modifying state.

### Recommended Implementation

Add a serial queue for state management:

```swift
public class ABLoopManager {
    private let stateQueue = DispatchQueue(label: "com.customvideoplayer.abloop.state")

    // Wrap state access in stateQueue
    public func setActiveLoop(_ loop: ABLoop?) {
        stateQueue.async { [weak self] in
            self?.currentActiveLoop = loop
            self?.currentSegmentPlaylist = nil
            self?.currentSegment = nil
        }
    }

    public func getActiveLoop() -> ABLoop? {
        return stateQueue.sync {
            return currentActiveLoop
        }
    }

    // Similar changes for other state access methods
}
```

---

## ℹ️ LOWER PRIORITY Issues

### Incomplete Segment Playlist UI
**Location:** `ABLoopViewController.swift:248-254`
**Issue:** Placeholder alert instead of actual UI
**Recommendation:** Implement proper segment playlist creation interface

### Empty Protocol Methods
**Locations:**
- `VideoPlayerViewController.swift:69-71`
- `QualitySelectionViewController.swift:56-58`

**Issue:** Empty `shouldForceLandscape()` methods
**Recommendation:** Either implement or remove these methods

---

## Verification Checklist

After implementing fixes:

- [x] Added `helveticaNeueBold` method to FontUtility
- [ ] Tested all UI components with bold fonts
- [x] Added runtime error handling for playback interruptions
  - [x] Added notification observer for AVPlayerItemFailedToPlayToEndTime
  - [x] Added notification observer for AVPlayerItemPlaybackStalled
  - [x] Added notification observer for AVPlayerItemDidPlayToEndTime
  - [x] Properly removed observers in deinit
- [ ] Tested error recovery with network interruptions
- [x] Added thread safety to ABLoopManager
  - [x] Added serial dispatch queue for state management
  - [x] Wrapped all state access methods with thread-safe operations
  - [x] Ensured delegate calls happen on main queue
- [ ] Tested A-B loop functionality under concurrent access
- [ ] Updated unit tests (if any)
- [ ] Performed integration testing
- [ ] Verified no new crashes in crash logs

---

## Additional Recommendations

1. **Add Unit Tests** for:
   - ABLoopManager state management
   - TimePoint calculations
   - M3U8Helper parsing

2. **Add Logging Framework** for better debugging:
   - Use os_log or a logging library
   - Log state transitions
   - Log error conditions

3. **Add Analytics** (optional):
   - Track playback errors
   - Monitor A-B loop usage
   - Measure quality selection patterns

---

**Last Updated:** 2025-12-05
