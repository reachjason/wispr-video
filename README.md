# Wispr Video

A menu-bar Mac app in the spirit of Wispr Flow — but for video. Press a hotkey,
record a talking-head clip from your webcam, and instantly get it exported in the
standard social-media sizes.

## Features

- **Menu-bar app** (no dock clutter) with global hotkeys:
  - **⌥⌘V** — record webcam (talking head).
  - **⌥⌘L** — record Loom-style: your **screen + a circular webcam bubble + mic**, composited live.
- **3-second countdown**, live floating preview, and a recording timer.
- **Configurable webcam-bubble corner** for Loom mode (menu → Loom Camera Bubble).
- **Pick which formats to export** — only the ones you choose are saved; the raw
  original is always kept.
- **Exports** center-cropped to fill each format:

  | Format | Resolution | Use |
  |---|---|---|
  | Vertical 9:16  | 1080 × 1920 | Reels / TikTok / Shorts |
  | Portrait 4:5   | 1080 × 1350 | Instagram feed portrait |
  | Square 1:1     | 1080 × 1080 | Instagram / Facebook square |
  | Landscape 16:9 | 1920 × 1080 | YouTube / X / LinkedIn |

- Exports land in `~/Movies/WisprVideo/<timestamp>/` as H.264 `.mp4` files.
- **Local-only** — nothing is ever uploaded.

## Build & run

Requires the Swift toolchain (Xcode or Command Line Tools) on macOS 13+.

```bash
./build.sh run
```

This compiles the sources, assembles `build/Wispr Video.app`, ad-hoc signs it, and
launches it. On first launch macOS will ask for camera and microphone access.

## Project layout

```
Sources/WisprVideo/
├── main.swift            # entry point (accessory app)
├── AppDelegate.swift     # menu bar, hotkeys, orchestration
├── HotKey.swift          # Carbon multi-hotkey center
├── Settings.swift        # persisted settings (bubble corner)
├── CameraRecorder.swift  # webcam AVCaptureSession recording
├── LoomRecorder.swift    # screen + camera bubble + mic compositing (ScreenCaptureKit)
├── VideoExporter.swift   # center-crop-to-fill to each format
├── RecorderPanel.swift   # floating preview + countdown + timer + stop
└── ExportView.swift      # SwiftUI format picker + results panel
Resources/
├── Info.plist            # bundle + camera/mic usage strings
├── AppIcon.icns          # generated app icon
├── HowToOpen.txt         # first-launch instructions bundled in the DMG
└── WisprVideo.entitlements
build.sh                  # compile → bundle → sign → run (dev)
tools/package-dmg.sh      # universal build → distributable .dmg
tools/make-icon.sh        # regenerate AppIcon.icns
```
