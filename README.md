# C64 Ultimate Toolbox

A native macOS companion app for your [Commodore 64 Ultimate](https://www.commodore.net) device — browse and manage files, write BASIC programs, view a live CRT display, and control your device from your Mac.

![C64 Ultimate Toolbox screenshot showing all panels](screenshots/C64%20Ultimate%20Toolbox%20Screenshot%201.png)

More screenshots: [File manager](screenshots/C64%20Ultimate%20Toolbox%20Screenshot%201.png) · [BASIC Scratchpad](screenshots/C64%20Ultimate%20Toolbox%20Screenshot%202.png)

Demo Video (Recorded for App Review): [https://youtu.be/_2wJO2wOGm8](https://youtu.be/_2wJO2wOGm8)

## Features

- **Two connection modes** — Viewer Mode passively listens for streams; Toolbox Mode connects via REST API and FTP for full device control
- **File manager** — Browse, upload, download, rename, and delete files on your device. Create D64, D71, D81, and DNP disk images. Mount and unmount drives. Drag and drop from Finder.
- **BASIC scratchpad** — Write Commodore BASIC programs on your Mac and send them directly to your C64U. Includes sample programs to get started.
- **Remote debug monitor** — Interactive monitor for reading/writing memory and inspecting machine state
- **Live video and audio** — Real-time UDP video and audio streaming with audio balance control
- **CRT shader effects** — Metal-based post-processing with scanlines, bloom, phosphor afterglow, shadow masks, barrel distortion, and vignette
- **8 built-in presets** — Clean, Home CRT, P3 Amber, P1 Green, Crisp, Warm Glow, Old TV, Arcade
- **Custom presets** — Save, modify, and delete your own CRT configurations
- **Device control** — Start/stop streams, load SID/MOD/PRG/CRT files, mount disk images, reset/reboot/power off, pause/resume, access the Ultimate menu
- **Keyboard forwarding** — Type on your Mac keyboard and have it appear on the C64, with an on-screen strip for C64-specific keys
- **Auto device discovery** — Automatically scans your network to find Ultimate devices with service status and password indicators
- **Screenshot and video recording** — Capture the CRT-processed output with synchronized audio
- **Password support** — Connect to password-protected devices with saved credentials
- **Zero dependencies** — Pure Apple frameworks (Metal, Network, AVFoundation, AppKit)

## Requirements

- macOS 26 or later
- Xcode 26 (to build from source)
- A Commodore 64 Ultimate device on the local network
- Toolbox Mode requires FTP File Service and Web Remote Control Service enabled on the device

## Download
- [Download C64 Ultimate Toolbox v2.0 for macOS 26 and later](https://amiantos.s3.amazonaws.com/c64-ultimate-toolbox-v2.0.zip)
- Or, [Purchase C64 Ultimate Toolbox on the App Store](https://apps.apple.com/us/app/c64-ultimate-toolbox/id6760209871?mt=12) for automatic updates.

## Download (For Older Macs)
- [Download C64 Ultimate Toolbox v1.0 for macOS 14.6 and later](https://amiantos.s3.amazonaws.com/c64-ultimate-toolbox-v1.0.zip)

## Building

Open `C64 Ultimate Toolbox.xcodeproj` in Xcode and build. No package dependencies to resolve.

## Usage

### Viewer Mode

1. Start the VIC Stream and Audio Stream on your C64U, pointed at your Mac's IP address
2. Launch the app and click **Listen** under Viewer Mode
3. Use the inspector panel to adjust CRT effects, volume, and audio balance

⚠️ For more detailed setup help check this: [Quick Start Guide](https://discuss.bradroot.me/t/c64-ultimate-toolbox-quick-start-guide/80)

### Toolbox Mode

1. Enable **FTP File Service** and **Web Remote Control Service** in your C64U's Network Services menu
2. Launch the app — your device should appear automatically under Discovered Devices
3. Click your device to connect — streams start automatically
4. Use the sidebar file manager to browse and transfer files, and the toolbar for device control

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
- **FTP** — File browsing, upload, download, and management (Toolbox Mode)
- **UDP port 11000** — Video stream (4-bit indexed color, converted to RGBA)
- **UDP port 11001** — Audio stream (16-bit stereo PCM at ~48kHz)

Video frames are assembled from UDP packets, converted from the C64's 4-bit palette to RGBA, then rendered through a Metal CRT shader pipeline at the window's native resolution.

## Links

- [Quick Start Guide](https://discuss.bradroot.me/t/c64-ultimate-toolbox-quick-start-guide/80)
- [Devlog](https://discuss.bradroot.me/t/c64u-viewer-c64-ultimate-toolbox-devlog/78)
- [Support Forum](https://discuss.bradroot.me/tags/c/projects/13/c64-ultimate-toolbox/36)

## License

[Mozilla Public License 2.0](LICENSE)
