<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Lime app icon: a lime slice">
</p>

<h1 align="center">Lime</h1>

<p align="center">
  <a href="https://github.com/jdank417/Lime/releases/latest"><img src="https://img.shields.io/github/v/release/jdank417/Lime?label=release&color=7cc721" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe%2B-000?logo=apple" alt="macOS 26 Tahoe or later">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/jdank417/Lime?color=blue" alt="MIT license"></a>
  <a href="https://github.com/jdank417/Lime/actions/workflows/release.yml"><img src="https://github.com/jdank417/Lime/actions/workflows/release.yml/badge.svg" alt="Release build"></a>
</p>

<p align="center">
  Convert and edit files right from Finder. Hold <kbd>⇧ Shift</kbd> while you drag a file and a glass wheel of formats appears under your pointer.
  <br>
  <a href="https://github.com/jdank417/Lime/releases/latest/download/Lime.dmg"><strong>Download for Mac</strong></a>
  ·
  <a href="https://github.com/jdank417/Lime/releases">All releases</a>
</p>

---

## Why Lime

Converting a file on a Mac usually means opening it in Preview, choosing **Export**, picking a format, finding a folder and clicking **Save**. With Lime it takes one drag: hold a key, drop the file on a format, and the new file appears next to the original.

## How it works

1. Start dragging any file in Finder (or on the desktop).
2. Hold <kbd>⇧ Shift</kbd>. A wheel of formats appears around the pointer.
3. Drop the file on a slice. The converted copy is saved right next to the original, which is never changed.

Hold <kbd>⌥ Option</kbd> instead and the wheel fills with **tools** for that kind of file: compress, crop, trim, edit metadata and more.
Let go in the middle of the wheel to cancel.

Everything happens on your Mac. Files are never uploaded anywhere.

## What it can do

### Convert (⇧ Shift)

| Files | Into |
| --- | --- |
| Images | PNG, JPG, HEIC, AVIF, TIFF, GIF, BMP, SVG, PDF, DOCX. Several at once can become one PDF or a collage. |
| Video | MP4, MOV, M4V, HEVC, animated GIF, or just the audio (M4A) |
| Audio | M4A, WAV, AIFF, FLAC, ALAC |
| PDF | PNG or JPG pages, TXT, RTF, DOCX |
| Documents | PDF, DOCX, DOC, RTF, TXT, HTML, ODT (from text, Markdown, Word, RTF, HTML, ODT) |
| Subtitles | SRT, VTT, plain text |
| Archives | Extract, or repack as ZIP or TAR.GZ (reads ZIP, TAR, GZ, BZ2, XZ, 7z, RAR and more) |
| Folders | ZIP, TAR.GZ, DMG |

### Tools (⌥ Option)

| Files | Tools |
| --- | --- |
| Photos | Compress (by quality or to an exact file size), Edit (exposure, contrast, highlights, shadows, warmth…), Crop, Annotate, Redact, Add background, Rotate, Metadata, Read QR codes |
| Video | Compress, Trim, Crop, Change speed, Split, Mute, Snapshot, Join several, Metadata |
| Audio | Compress, Trim, Normalize, Mono/stereo, Metadata |
| PDF | Compress, Organize pages, Split, Rotate, Merge several, Metadata |

Drag several files at once to convert or process them in one go. A small island at the top of the screen shows progress and has a button to show the result in Finder.

### Nice touches

- **Nothing gets overwritten.** If `photo.png` already exists, the new file is saved as `photo 2.png`.
- **Mixed files work too.** Drag an image, a PDF and a song together and the wheel offers ZIP or TAR.GZ.
- **Remove metadata before sharing.** The Metadata tool (⌥ Option) can strip the location, camera and other details from a photo, video, song or PDF. Drag several photos and the wheel has a one-step **Clean** slice.
- **Haptic feedback.** On a Force Touch trackpad you feel a light tap as you cross each slice.
- **Recent files.** The menu bar menu lists your last few results; click one to show it in Finder.
- **A smaller drag preview.** Finder's big drag preview shrinks to a small thumbnail so it doesn't cover the wheel.
- Press <kbd>Esc</kbd> to close Lime's window.

### Settings

Open Lime from the menu bar and choose **Settings** to:

- use <kbd>⌃ Control</kbd> instead of Shift, or <kbd>⌘ Command</kbd> instead of Option,
- make the wheel smaller or larger, pick clear or frosted glass, and choose its highlight color,
- save new files next to the original, in Downloads, or in a folder you choose,
- set the photo quality for JPG, HEIC and AVIF,
- play a sound or show the result in Finder when a job finishes,
- open Lime at login, or hide its menu bar icon.

## Install

1. [Download **Lime.dmg**](https://github.com/jdank417/Lime/releases/latest/download/Lime.dmg).
2. Open it and drag **Lime** into **Applications**.
3. Open Lime. A lime slice appears in your menu bar, and the drag wheel is ready.

Lime needs **macOS 26 Tahoe** or later.

Releases are signed with a Developer ID and notarized by Apple, so Lime opens without any warning.

<details>
<summary><strong>Built it yourself and see "Apple could not verify Lime…"?</strong></summary>

DMGs you build without a Developer ID certificate aren't notarized. To open one anyway:

1. Click **Done** on the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about Lime and click **Open Anyway**, then confirm.

You only need to do this once.
</details>

The first time you convert something on your Desktop or in Documents or Downloads, macOS asks whether Lime may access that folder. Lime needs this to save the new file next to the original.

## FAQ

<details>
<summary><strong>Does Lime upload my files?</strong></summary>

No. All conversions run on your Mac using Apple's frameworks and the command-line tools built into macOS. Lime makes no network calls.
</details>

<details>
<summary><strong>Why does macOS ask whether Lime can access my Desktop, Documents or Downloads?</strong></summary>

Lime saves the new file in the same folder as the original, and macOS asks before an app writes to those folders. If you said no by accident, turn Lime back on in **System Settings → Privacy & Security → Files & Folders**.
</details>

<details>
<summary><strong>How do I drag a file normally?</strong></summary>

Just don't hold <kbd>⇧ Shift</kbd> or <kbd>⌥ Option</kbd>. The wheel only appears while one of them is held. If it's already open, release over the center to cancel. To turn Lime off for a while, click the lime slice in the menu bar and uncheck **Lime Enabled**.
</details>

<details>
<summary><strong>The wheel doesn't appear. What should I check?</strong></summary>

- Lime is running: the lime slice is in the menu bar, or you can open Lime from Applications.
- **Lime Enabled** is checked in the menu bar menu.
- You're holding the keys chosen in **Settings**. If you switched to <kbd>⌃ Control</kbd> or <kbd>⌘ Command</kbd>, Shift and Option won't open the wheel.
- You're dragging a file or folder, not text or a link.

Still stuck? [Open an issue](https://github.com/jdank417/Lime/issues/new/choose) with your macOS version and what you dragged.
</details>

<details>
<summary><strong>Does Lime need Accessibility or Input Monitoring permission?</strong></summary>

No. Lime only checks which keys are held and what's being dragged, so it doesn't need either permission.
</details>

## Build from source

You need Xcode 26 or later.

```bash
git clone https://github.com/jdank417/Lime.git
cd Lime
open Lime.xcodeproj
```

Press **⌘R** to run. To run the tests:

```bash
xcodebuild test -project Lime.xcodeproj -scheme Lime -destination 'platform=macOS'
```

To build your own DMG, run `scripts/build-dmg.sh`. See [docs/RELEASING.md](docs/RELEASING.md) for signing, notarizing and publishing a release.

### How the code is laid out

| Folder | What's in it |
| --- | --- |
| `Lime/Core` | Drag detection, the list of actions per file type, the job runner, settings |
| `Lime/Converters` | The actual work: images, media, PDF, documents, archives, metadata. All local, using Apple's frameworks and the command-line tools built into macOS |
| `Lime/Editors` | The tool windows (Edit Photo, Trim, Crop, …) |
| `Lime/UI` | The glass wheel, the top-of-screen island, the main window (Home, Settings, About), colors and shapes |
| `LimeTests` | Tests that run every converter and tool on generated files |

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), and please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
To report a security problem, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Jason Dank
