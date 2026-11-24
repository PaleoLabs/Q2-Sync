# Changelog

Release notes for each Q2 Sync build. Downloads are on [Releases](https://github.com/PaleoLabs/Q2-Sync/releases).

## Unreleased

### Changed
- **Playlists stay in the Q2's import folder by default.** The setting "Only put new or changed playlists in the import folder" is now off by default, so every sync puts all your synced playlists in `_explaylist_data/`. This applies to Q2s you've already synced, unless you turned the setting on yourself.
- **With that setting on, Q2 Sync asks before taking playlists out.** If playlists from an earlier sync are still in the import folder, the sync window says how many and shows an **"I imported them on the Q2"** checkbox, unticked to start with. Unchanged playlists come out of the import folder only if you tick it. In 0.1.0, Q2 Sync assumed you had already imported them and took them out without asking.
- Automatic sync never ticks that box, and playlists waiting in the import folder don't start an automatic sync by themselves.

## 0.1.0 (2026-11-24)

The first public release. Sync the music files in your Mac's Music app to a Shanling Q2, the way Finder syncs an iPod. Works with Q2 Pod and Shanling stock firmware.
