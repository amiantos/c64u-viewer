# C64 Ultimate Toolbox

A native macOS app for streaming, viewing, and controlling your [Commodore 64 Ultimate](https://www.commodore.net) device — with real-time CRT shader effects, REST API integration, and keyboard forwarding.

![C64U Viewer showing a game with CRT effects](screenshots/C64U%20Viewer%20Screenshot%203.png)

More screenshots: [General Settings](screenshots/C64U%20Viewer%20Screenshot%201.png) · [CRT Effects (Amber)](screenshots/C64U%20Viewer%20Screenshot%202.png)

## Features

- **Two connection modes** — Viewer Mode passively listens for streams; Toolbox Mode connects via REST API for full device control
- **Live video and audio** — Real-time UDP video and audio streaming with audio balance control
- **CRT shader effects** — Metal-based post-processing with scanlines, bloom, phosphor afterglow, shadow masks, barrel distortion, and vignette
- **8 built-in presets** — Clean, Home CRT, P3 Amber, P1 Green, Crisp, Warm Glow, Old TV, Arcade
- **Custom presets** — Save, modify, and delete your own CRT configurations
- **Toolbox controls** — Start/stop streams, load SID/PRG/CRT files, reset/reboot/power off, access the Ultimate menu
- **Keyboard forwarding** — Type on your Mac keyboard and have it appear on the C64, with an on-screen strip for C64-specific keys
- **Screenshot and video recording** — Capture the CRT-processed output with synchronized audio
- **Password support** — Connect to password-protected devices
- **Zero dependencies** — Pure Apple frameworks (Metal, Network, AVFoundation, SwiftUI)

## Requirements

- macOS 14.6 or later
- Xcode 26 (to build)
- A Commodore 64 Ultimate device on the local network
- Toolbox Mode requires firmware 3.11+ with REST API enabled

## Building

Open `C64 Ultimate Toolbox.xcodeproj` in Xcode and build. No package dependencies to resolve.

## Usage

### Viewer Mode

1. Start the VIC Stream and Audio Stream on your C64U, pointed at your Mac's IP address
2. Launch the app and click **Listen** under Viewer Mode
3. Click the video to access audio and CRT filter controls

### Toolbox Mode

1. Enable **FTP File Service** and **Web Remote Control Service** in your C64U's Network Services menu
2. Launch the app and enter your C64U's IP address under Toolbox Mode
3. Click **Connect** — streams start automatically
4. Click the video to access device controls, file runners, keyboard forwarding, and more

### Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Disconnect | ⌘D |
| Volume Up/Down | ⌘↑ / ⌘↓ |
| Mute | ⇧⌘M |
| Take Screenshot | ⇧⌘S |
| Start/Stop Recording | ⇧⌘R |

## How It Works

The app communicates with the C64U over multiple channels:

- **HTTP REST API** — Device info, stream control, file loading, machine control, keyboard injection (Toolbox Mode)
- **UDP port 11000** — Video stream (4-bit indexed color, converted to RGBA)
- **UDP port 11001** — Audio stream (16-bit stereo PCM at ~48kHz)

Video frames are assembled from UDP packets, converted from the C64's 4-bit palette to RGBA, then rendered through a Metal CRT shader pipeline at the window's native resolution.

## Links

- [Quick Start Guide](https://discuss.bradroot.me/t/c64u-viewer-quick-start-guide/80/1)
- [Devlog](https://discuss.bradroot.me/t/c64u-viewer-devlog/78/10)
- [Support Forum](https://discuss.bradroot.me/tag/c64u-viewer/35)

## License

[Mozilla Public License 2.0](LICENSE)
