# Security policy

Q2 Sync writes to a memory card and reads your Music library, so we take
security and data-safety problems seriously.

## Supported versions

Only the **latest release** is supported. Please check that a problem still
happens in the newest version from
[Releases](https://github.com/PaleoLabs/Q2-Sync/releases) before reporting it.

## Reporting a vulnerability

Please **don't open a public issue** for a security problem. Report it
privately instead:

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability** (GitHub's private reporting).

Include what you did, what you expected, what happened, your macOS and Q2 Sync
versions, and, if you can, the steps to reproduce it. Please don't attach your
music library, playlists or card contents.

This is a small volunteer project, so replies are best effort. We'll
acknowledge a report as soon as we can, work on a fix for confirmed problems,
and credit you in the release notes unless you'd rather we didn't.

## What counts

Examples of problems we want to hear about privately:

- Q2 Sync writing, moving or deleting anything outside the confirmed card (the
  path guard is meant to make this impossible).
- Any change to your Apple Music library or `~/Music`.
- A downloaded firmware file being accepted without passing its checks.
- Data about you or your library being sent anywhere (the only network use is
  downloading firmware).
- A way to make Q2 Sync damage files on a card without you asking.

Ordinary bugs, such as a song not syncing, belong in
[Issues](https://github.com/PaleoLabs/Q2-Sync/issues).

## Using Q2 Sync safely

- Keep a backup of your Mac and of anything on the card that matters.
- Download Q2 Sync only from this repository's Releases, and check the SHA-256
  checksum listed there.
