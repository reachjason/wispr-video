# Wispr Video

A menu-bar Mac app in the spirit of Wispr Flow — but for video. Press a hotkey,
record a talking-head clip from your webcam, and instantly get it exported in the
standard social-media sizes.

## Features

- **Menu-bar app** (no dock clutter) with a global hotkey: **⌥⌘V** to start/stop.
- **Live floating preview** with a recording timer while you shoot.
- **One recording → four exports**, center-cropped to fill each format:

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
├── AppDelegate.swift     # menu bar, hotkey, orchestration
├── HotKey.swift          # Carbon global hotkey
├── CameraRecorder.swift  # AVCaptureSession recording
├── VideoExporter.swift   # center-crop-to-fill to each format
├── RecorderPanel.swift   # floating preview + timer + stop
└── ExportView.swift      # SwiftUI results panel
Resources/
├── Info.plist            # bundle + camera/mic usage strings
└── WisprVideo.entitlements
build.sh                  # compile → bundle → sign → run
```
