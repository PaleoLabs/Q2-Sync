# Changelog

Release notes for each Q2 Sync build. Downloads are on [Releases](https://github.com/PaleoLabs/Q2-Sync/releases).

## Unreleased

### Changed
- **Sync Complete shows your next steps on the Q2 before you eject**, as a numbered list like the one in Install Firmware. Before, the steps appeared only after clicking **Eject** in that window, so ejecting any other way skipped them. The list includes the playlist and Cover Flow steps only when that sync calls for them.
- **Eject now ejects and closes the window.** **Done** (previously **Not Now**) closes it with the card still connected, **Verify Card…** sits on the left, and **Show Log** is a link. The eject question and the separate cover note are gone.
- The notification after an automatic sync now says to open Q2 Sync for next steps.

### Fixed
- With a card reader, the step after a sync said to unplug the Q2. It now says to put the card back in your Q2.

## 0.2.0 (2026-11-24)

### Changed
- **Playlists stay in the Q2's import folder by default.** The setting "Only put new or changed playlists in the import folder" is now off by default, so every sync puts all your synced playlists in `_explaylist_data/`. This applies to Q2s you've already synced, unless you turned the setting on yourself.
- **With that setting on, Q2 Sync asks before taking playlists out.** If playlists from an earlier sync are still in the import folder, the sync window says how many and shows an **"I imported them on the Q2"** checkbox, unticked to start with. Unchanged playlists come out of the import folder only if you tick it. In 0.1.0, Q2 Sync assumed you had already imported them and took them out without asking.
- Automatic sync never ticks that box, and playlists waiting in the import folder don't start an automatic sync by themselves.

### Added
- **Q2 Sync leaves the Dock when you close its window** and stays in the menu bar, so it still notices your Q2 connecting. **Open Q2 Sync** in the menu bar item brings the window and the Dock icon back. The first time, a notice explains this, with **Keep in Menu Bar**, **Quit Q2 Sync** and **Don't show again**; **Settings › Show Menu Bar Tip Again** brings it back. ([#49](https://github.com/PaleoLabs/Q2-Sync/issues/49))

### Removed
- **The "Show Q2 Sync in the menu bar" setting.** The menu bar icon is always shown now, since it's the way back to Q2 Sync while its window is closed. If you had hidden it, it comes back.

## 0.1.0 (2026-11-24)

The first public release. Sync the music files in your Mac's Music app to a Shanling Q2, the way Finder syncs an iPod. Works with Q2 Pod and Shanling stock firmware.
