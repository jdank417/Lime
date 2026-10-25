<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="Lime app icon: a lime slice">
</p>

<h1 align="center">Lime</h1>

<p align="center">
  Convert and edit files right from Finder. Hold <kbd>⇧ Shift</kbd> while you drag a file and a glass wheel of formats appears under your pointer.
  <br>
  <a href="https://github.com/jdank417/Lime/releases/latest/download/Lime.dmg"><strong>Download for Mac</strong></a>
  ·
  <a href="https://github.com/jdank417/Lime/releases">All releases</a>
</p>

---

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

## Install

1. [Download **Lime.dmg**](https://github.com/jdank417/Lime/releases/latest/download/Lime.dmg).
2. Open it and drag **Lime** into **Applications**.
3. Open Lime. A lime slice appears in your menu bar, and the drag wheel is ready.

Lime needs **macOS 26 Tahoe** or later.

<details>
<summary><strong>"Apple could not verify Lime…" when opening it?</strong></summary>

Releases that aren't notarized by Apple yet show this the first time. To open Lime anyway:

1. Click **Done** on the warning.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message about Lime and click **Open Anyway**, then confirm.

You only need to do this once. If a release says it is notarized, you won't see the warning at all.
</details>

The first time you convert something on your Desktop or in Documents or Downloads, macOS asks whether Lime may access that folder. Lime needs this to save the new file next to the original.

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
| `Lime/Core` | Drag detection, the list of actions per file type, the job runner |
| `Lime/Converters` | The actual work: images, media, PDF, documents, archives, metadata. All local, using Apple's frameworks and the command-line tools built into macOS |
| `Lime/Editors` | The tool windows (Edit Photo, Trim, Crop, …) |
| `Lime/UI` | The glass wheel, the top-of-screen island, colors and shapes |
| `LimeTests` | Tests that run every converter and tool on generated files |

## Contributing

Bug reports and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md), and please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
To report a security problem, see [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 Jason Dank
