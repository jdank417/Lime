## What this changes

<!-- What does it do, and why? Link any related issue. -->

## Checklist

- [ ] Tests pass: `xcodebuild test -project Lime.xcodeproj -scheme Lime -destination 'platform=macOS'`
- [ ] New formats or tools have a test in `LimeTests/ToolTests.swift`
- [ ] No new dependencies, network requests or uploads; everything stays on the user's Mac
- [ ] Originals are never changed; results go through `Output.url`
