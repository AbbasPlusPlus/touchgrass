# macOS break-app technical landscape (verified on macOS 26.6.2, 2026-08-27)

Claims marked ✔ were measured with compiled probes, in and out of the App Sandbox.

## Key decisions
| Decision | Recommendation |
|---|---|
| Overlay | `NSPanel` `.borderless + .nonactivatingPanel`, `level = .screenSaver` (1000), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `orderFrontRegardless()`, one panel per `NSScreen` |
| Blur | `NSVisualEffectView(.behindWindow)` — never screenshot+blur (Screen Recording TCC nag) |
| Meeting detection | CoreMediaIO + CoreAudio `IsRunningSomewhere` — ✔ no permission, no prompt, sandbox OK |
| Video playback | `IOPMCopyAssertionsByProcess` → `PreventUserIdleDisplaySleep`/`NoDisplaySleepAssertion` — ✔ identical in sandbox |
| Focus/DND | `INFocusStatusCenter` (macOS 12+). `~/Library/DoNotDisturb/DB` hack is ✔ dead on 26 |
| Menu bar | `NSStatusItem` + custom `NSPanel`, not `MenuBarExtra` |
| Distribution | Notarized Developer ID (+ Sparkle); MAS later via dual entitlements if wanted |

## Overlay window gotchas
- `isFloatingPanel = true` resets `level` to `.floating` — set `level` LAST.
- Override `constrainFrameRect(_:to:)` to return frameRect, else AppKit clamps below menu bar (visible strip).
- `canBecomeKey` must be overridden true for borderless panels.
- `hidesOnDeactivate = false`, `canHide = false`; re-assert order on `windowDidResignKey`, space change, wake, screen-params change.
- No supported way to draw over *another app's* native fullscreen Space. `.fullScreenAuxiliary` = "same space as", not "on top of". Practical: `.canJoinAllSpaces` + high level + `orderFrontRegardless` works most of the time; detect fullscreen and defer the break as fallback.
- Don't use `.maximumWindow` (above cursor level → cursor hidden). `CGShieldingWindowLevel` covers VoiceOver.
- `NSVisualEffectView` incompatible with window `alphaValue` fades → fade a child overlay view, or fade the whole panel with a solid/wallpaper background instead.
- Reduce Transparency kills blur → design flat fallback.
- Capture exclusion: `NSWindow.sharingType = .none` ignored by ScreenCaptureKit on 15+;  uses SkyLight SPI `CGSSetWindowCaptureExcludeShape`.
- Strict mode: `presentationOptions` only apply while app is active; swallowing Cmd-Tab/Esc needs `CGEventTap` (Accessibility + Input Monitoring, not sandbox). Handle `kCGEventTapDisabledByTimeout` after lock/sleep.
- Mouse click-through regressions on 15.3 and 26.3 — test per OS release.

## Multi-display
- Observe `NSApplication.didChangeScreenParametersNotification`, debounce ~200 ms, diff sets of screens by `CGDisplayCreateUUIDFromDisplayID` (indices reshuffle). Ghost-screen storms exist.
- `NSScreen.main` lies with fullscreen apps; pick screen under mouse.
- Use `screen.frame` for overlay, respect `safeAreaInsets.top` (notch) for content.
- Render rich animation on one display, blanks elsewhere (perf).
- Wallpaper: `NSWorkspace.shared.desktopImageURL(for: screen)`.

## Detection APIs
### Camera (CoreMediaIO)
`kCMIOHardwarePropertyDevices` → `kCMIODevicePropertyDeviceIsRunningSomewhere` (use wildcard scope/element), `kCMIODevicePropertyTransportType` to filter virtual cams, `CMIOObjectAddPropertyListenerBlock` for push. ✔ No TCC prompt, no usage string, no orange dot. ✔ Sandbox: needs `com.apple.security.device.camera` or device list is silently EMPTY.
Ref: sindresorhus/is-camera-on (MIT), Aerial `CameraUsageMonitor.swift`, deseven/iCanHazRepose `MeetingDetector.swift`.

### Mic (CoreAudio)
Iterate `kAudioHardwarePropertyDevices`, filter input devices via `kAudioDevicePropertyStreamConfiguration` (input scope), read `kAudioDevicePropertyDeviceIsRunningSomewhere` on input scope. ✔ No permission, no entitlement even sandboxed.
Bugs: Bluetooth mics (AirPods!) report always 0 (Apple-acknowledged bug). Aggregate devices (BlackHole, Krisp) pin "running".
**Better (macOS 14.4+):** process objects `kAudioHardwarePropertyProcessObjectList` ('prs#') → `kAudioProcessPropertyBundleID` ('pbid'), `kAudioProcessPropertyIsRunningInput` ('piri'), `IsRunningOutput` ('piro'). ✔ Works with no permission → know WHICH bundle uses the mic → whitelist dictation apps. Listeners unreliable; use device-level listeners as trigger then query process list.

### Video playback / fullscreen
- `IOPMCopyAssertionsByProcess` keys: `AssertType`, `AssertName`, `Process Name`, `AssertPID`. Types: `PreventUserIdleDisplaySleep`, `NoDisplaySleepAssertion`. Ignore `UserIsActive`, `InternalPreventDisplaySleep`. Names: "Playing audio", "Video Wake Lock" (Chromium), "com.apple.Music.playback". Poll 2–5 s; gate with `IOPMCopyAssertionsStatus`. Denylist Amphetamine/Caffeine/jigglers.
- During a break hold our own `IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep…)` ✔.
- Fullscreen heuristic: `CGWindowListCopyWindowInfo` (✔ no permission for metadata; `kCGWindowName` withheld, don't need it) → `kCGWindowLayer == 0 && IsOnscreen && bounds ≈ CGDisplayBounds(display)` (±40 pt). Trigger on `NSWorkspace.didActivateApplicationNotification`. `CGSGetActiveSpace` ✔ broken on 26. `frame == visibleFrame` is a bad heuristic.
- `NSWorkspace.frontmostApplication`, `menuBarOwningApplication`, `runningApplications` free.
- 's bundle lists: us.zoom.xos, com.microsoft.teams(2), com.cisco.webex*, com.tinyspeck.slackmacgap, com.apple.FaceTime, com.discordapp.Discord, com.skype.skype, com.apple.avconferenced, + ~30 browsers, + dictation denylist (superwhisper, Wispr Flow, Aqua Voice, VoiceInk), + caffeinators.

### Recommended detection policy (from OpenOats spec)
camera on → pause immediately; mic on + known meeting app running → pause after 5 s; mic alone → don't pause (dictation); 3 s hysteresis on camera-off; resume only when all clear. Per-device + per-app opt-outs.

### Focus / DND
`INFocusStatusCenter.default.focusStatus.isFocused` with entitlements `com.apple.developer.focus-status` + `com.apple.developer.usernotifications.communication`, `NSFocusStatusUsageDescription`. Poll 10–15 s. Ref: bartreardon/infocus. Also offer `SetFocusFilterIntent`.

### Screen sharing
No public API.  dlopens SkyLight `CGSIsScreenWatcherPresent` + `CGSRegisterNotifyProc`. Public substitute: capture-app bundle list + power assertions + Zoom share toolbar window.

## Idle / sleep / lock
- `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)` ✔ no permission; can separate keyDown vs mouseMoved idle (typing detection without Accessibility!).
- Idle ≠ away: AND with power-assertion check.
- Notifications: `NSWorkspace` will/didSleep, screensDidSleep/Wake, session resign/become; Distributed `com.apple.screenIsLocked/Unlocked`, `com.apple.screensaver.didstart/didstop`. Seed lock state via `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`.
- Timers stop during sleep; use wall-clock deadlines, recompute on wake. Hold `ProcessInfo.beginActivity(.userInitiated, .latencyCritical)` to dodge App Nap.

## Menu bar / infra
- `NSStatusItem.button.attributedTitle` with `monospacedDigitSystemFont`; keep countdown static text (Tahoe SwiftUI status-item animation lag). Ref: jasonlong/mater (MIT) for status item + attached panel.
- Settings window from accessory app: `Window(id:)` scene + activate `.regular` before open, or Ice's pattern.
- Launch at login: `SMAppService.mainApp.register()`; handle error 125 (unregister then register).
- Hotkeys: sindresorhus/KeyboardShortcuts 3.x (Carbon RegisterEventHotKey, no Accessibility).
- Sounds: `AVAudioPlayer` (hold strong ref) or `NSSound`. Animation: SwiftUI PhaseAnimator/KeyframeAnimator, `NSAnimationContext` for window fades, Rive if needed.
- Updates: Sparkle ≥2.9.6 (fixes for dockless apps); don't codesign `--deep`.

## Reference repos (license)
MIT/BSD copyable: deseven/iCanHazRepose (overlay+meeting+timer, 170-line detector), yagizdo/standlock (best architecture, tests), korenskoy/RecessEyes (overlay gotchas), homielab/timemate (screen-change rebuild, SleepPreventer), oxremy/BlinkMore (stay-on-top playbook), ivoronin/TomatoBar (timer state machine), Rectangle (ScreenDetection, LaunchOnLogin), exelban/stats (menu bar widgets, updater), MonitorControl (shade window), KeepingYouAwake (dual entitlements pattern), macadmins/nudge (interrupt policy), Stretchly (BSD; defaultSettings.js as requirements doc), jasonlong/mater.
GPL — technique only: AltTab (PreviewPanel constrainFrameRect, Screens.swift, SystemPermissions.swift), Ice (MenuBarAppearanceManager per-display panels), BreakTimer (settings.ts model), sane-break, OverSight.
