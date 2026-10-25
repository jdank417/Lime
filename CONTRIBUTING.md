# Contributing to Lime

Thanks for helping out! A few notes to make it smooth. Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting a bug

Security problems are different: report them privately as described in [SECURITY.md](SECURITY.md).

Open an issue with:

- your macOS version,
- the kind of file you dragged (format, and roughly how big),
- what you expected and what happened instead.

If a conversion fails, the message in the island at the top of the screen helps a lot.

## Making a change

1. Fork the repo and create a branch from `main`.
2. Open `Lime.xcodeproj` in Xcode 26 or later and make your change.
3. Run the tests and make sure they pass:

   ```bash
   xcodebuild test -project Lime.xcodeproj -scheme Lime -destination 'platform=macOS'
   ```

4. Open a pull request describing what changed and why.

### Adding a format or tool

- The work itself goes in `Lime/Converters`, as plain functions that take a file URL and return the new file's URL. Use `Output.url(for:ext:suffix:)` so results land next to the original without overwriting anything.
- Add it to the wheel in `ActionCatalog` (`Lime/Core/Actions.swift`). Use `.each` for one result per file, `.all` for one result from several files, or a `tool` with a view in `Lime/Editors` if it needs a window.
- Add a test in `LimeTests/ToolTests.swift` that runs it on a generated file.

Lime only uses what ships with macOS (no bundled binaries or network calls), and everything stays on the user's Mac. Please keep it that way.
