# Contributing to Q2 Sync

Thanks for your interest! Bug reports, device test results and pull requests
are all welcome.

## Reporting a bug

Open an issue with:

- your macOS version and Q2 Sync version (or commit),
- the Q2's firmware (Q2 Pod version or Shanling stock version),
- what you did, what you expected, and what happened.

Please don't attach your music library, playlists or card contents. A few
example file names are enough.

## Ideas and plans

Planned features and known issues live in
[GitHub Issues](https://github.com/PaleoLabs/Q2-Sync/issues). Comment on
one you'd like to see, or open a new one with your idea. Each change that
fixes an issue closes it from its commit.

## Testing on a real Q2

Some behavior, mostly on Shanling's stock firmware, still needs checking on a
device. [docs/DEVICE_CHECKS.md](docs/DEVICE_CHECKS.md) lists what's open;
reports of what you saw on your Q2 are very helpful.

## Pull requests

1. Read the [Code Guide](docs/CODE_GUIDE.md) first. It explains the layout,
   and the safety rules every change must keep:
   - never write to the Apple Music library or `~/Music`,
   - every change on the card goes through `PathGuard`,
   - `Q2-Sync/Core` stays free of SwiftUI so it can be unit tested.
2. Add or update tests in `Tests/Q2SyncCoreTests` and run `swift test`.
3. Keep user-facing wording plain and friendly, like the rest of the app.
4. Unit tests must never touch the real Music library; use
   `FixtureLibrarySource`.

## License

Q2 Sync is licensed under the [GNU GPL v3.0](LICENSE). By submitting a
contribution, you agree that it's licensed under the same terms.
