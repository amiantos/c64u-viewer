# C64U Viewer

A native macOS app for viewing the video and audio stream from a [Commodore 64 Ultimate](https://www.commodore.net) device, with real-time CRT shader effects.

![C64U Viewer showing a game with CRT effects](screenshots/C64U%20Viewer%20Screenshot%203.png)

More screenshots: [General Settings](screenshots/C64U%20Viewer%20Screenshot%201.png) · [CRT Effects (Amber)](screenshots/C64U%20Viewer%20Screenshot%202.png)

## Features

- **Live video and audio** — Receives the C64U's UDP video and audio streams directly
- **CRT shader effects** — Metal-based post-processing with scanlines, bloom, phosphor afterglow, shadow masks, barrel distortion, and vignette
- **8 built-in presets** — Clean, Home CRT, P3 Amber, P1 Green, Crisp, Warm Glow, Old TV, Arcade
- **Custom presets** — Save, modify, and delete your own CRT configurations
- **Multiple render resolutions** — 2x through 5x (768×544 to 1920×1360)
- **Screenshot and video recording** — Capture the CRT-processed output directly
- **Zero dependencies** — Pure Apple frameworks (Metal, Network, AVFoundation, SwiftUI)

## Requirements

- macOS 14.6 or later
- Xcode 26 (to build)
- A Commodore 64 Ultimate device on the local network

## Building

Open `C64U Viewer.xcodeproj` in Xcode and build. No package dependencies to resolve.

## Usage

1. Launch the app
2. Enter your C64U hostname (defaults to `c64u`)
3. Click **Connect** (or ⌘D)
4. Choose a CRT preset from the **Preset** menu
5. Adjust shader settings in **Settings** (⌘,)

### Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Connect/Disconnect | ⌘D |
| Volume Up/Down | ⌘↑ / ⌘↓ |
| Mute | ⇧⌘M |
| Take Screenshot | ⇧⌘S |
| Start/Stop Recording | ⇧⌘R |
| Pixel-Accurate Window | ⌘1 |

## How It Works

The app communicates with the C64U over three channels:

- **TCP port 64** — Control commands to start/stop streaming
- **UDP port 11000** — Video stream (4-bit indexed color, converted to RGBA)
- **UDP port 11001** — Audio stream (16-bit stereo PCM at ~48kHz)

Video frames are assembled from UDP packets, converted from the C64's 4-bit palette to RGBA, then rendered through a Metal CRT shader pipeline before display.

## Links

- [Quick Start Guide](https://discuss.bradroot.me/t/c64u-viewer-quick-start-guide/80/1)
- [Devlog](https://discuss.bradroot.me/t/c64u-viewer-devlog/78/10)
- [Support Forum](https://discuss.bradroot.me/tag/c64u-viewer/35)

## License

[Mozilla Public License 2.0](LICENSE)
