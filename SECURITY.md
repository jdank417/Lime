# Security Policy

## Supported versions

Only the [latest release](https://github.com/jdank417/Lime/releases/latest) gets security fixes. Please update before reporting.

## Reporting a vulnerability

Please **don't open a public issue** for security problems.

Report it privately instead: on the repository's **Security** tab, click **Report a vulnerability**
([direct link](https://github.com/jdank417/Lime/security/advisories/new)). Include:

- what the problem is and what someone could do with it,
- steps or a file that reproduces it,
- the Lime and macOS versions you used.

You'll get a reply within a week. Once a fix is released, the advisory is published with credit to you, unless you'd rather stay anonymous.

## What Lime does, for context

- Lime runs entirely on your Mac. It makes no network requests, collects no data and has no third-party dependencies.
- It isn't sandboxed, so it can save converted files next to the originals and notice file drags anywhere on the Mac. It doesn't need Accessibility access.
- It reads and writes only the files you drop on it and the copies it makes. Originals are never changed.
- It runs a few tools built into macOS (`ditto`, `zip`, `tar`, `hdiutil`), passing file names as separate arguments, never through a shell.
- Releases are signed with a Developer ID and notarized by Apple. Check a download with
  `spctl --assess --type open --context context:primary-signature -v Lime.dmg`.
