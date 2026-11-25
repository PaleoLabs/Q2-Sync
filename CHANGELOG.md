# Changelog

Release notes for each Q2 Sync build. Downloads are on [Releases](https://github.com/PaleoLabs/Q2-Sync/releases).

## Unreleased

### Added
- **Sync Now and Eject in the Dock menu.** Right-click (or click and hold) Q2 Sync's Dock icon.
- **The About panel links to Q2 Sync on GitHub and to its license.**
- **Q2 Sync tells you when a new version is out.** It checks GitHub when it starts, then once a day, and a window that stays on top offers **View on GitHub**, **Later** or **Skip This Version**. The menu bar item then offers **Get Q2 Sync …**. **Check for Updates…** is in the **Q2 Sync** menu and the menu bar item, and **Settings** can turn the automatic check off. Nothing is downloaded or installed for you.
- **More menu commands and shortcuts.** **File › Refresh Music Library** (**⌘R**) and **Show in Finder** (**⇧⌘R**), **Edit › Find** (**⌘F**) for the filter on the Music tab or in the sync preview, **View** items for Artists to Playlists (**⌘1**–**⌘4**), your Q2 (**⌘5**), and **Window › Q2 Sync** (**⌘0**).
- **Device** menu: **Check for Firmware Updates** (Q2 Pod or Shanling stock, whichever your Q2 runs), **Back Up Q2 Pod Data**, **Restore Q2 Pod Data…** and **Show Card in Finder**.
- **Help** menu: **Show Sync Logs**, **Release Notes** and **Report a Problem…**.
- The menu bar item has **Q2 Sync Help** and **About Q2 Sync**, and shows **⌘,** beside **Settings…**.
- Right-click your Q2 in the sidebar for **Sync Now**, **Eject** and **Show in Finder**, or an artist or album for **Show in Finder**.
- **Shanling stock firmware can be checked too**: **Check Now** on the Settings tab shows the latest version on Shanling's download page.
- The user guide has a **Keyboard shortcuts** section.
- **The user guide is in the Help menu.** **Help › Q2 Sync Help** (**⌘?**) opens it in its own window, with the sections in a sidebar. It works offline and matches the version you're running. ([#52](https://github.com/PaleoLabs/Q2-Sync/issues/52))
- **Double-click a song to open Song Info, and again to close it.** **View › Show Song Info** (**⌘I**) shows or hides it too.

### Changed
- **The sidebar is always shown.** The button and menu item that hid it are gone, and dragging its edge no longer closes it, so you can't lose the way to your Q2 and your library. It also has a maximum width now, so it can't crowd out the rest of the window.
- **Setting up a new Q2 no longer preselects Q2 Pod.** Neither firmware is selected, **Shanling (stock)** is listed first, and **Continue…** waits until you choose. Q2s you've already set up keep their setting.
- **Sync Complete shows your next steps on the Q2 before you eject**, as a numbered list like the one in Install Firmware. Before, the steps appeared only after clicking **Eject** in that window, so ejecting any other way skipped them. The list includes the playlist and Cover Flow steps only when that sync calls for them.
- **Eject now ejects and closes the window.** **Done** (previously **Not Now**) closes it with the card still connected, **Verify Card…** sits on the left, and **Show Log** is a link. The eject question and the separate cover note are gone.
- The notification after an automatic sync now says to open Q2 Sync for next steps.
- **Ejecting from the menu bar item or a notification now confirms itself**: if Q2 Sync's window isn't in front, a notification says the card was ejected.

### Fixed
- **A narrow window no longer cuts off its contents at both sides**, for example with Song Info open. The window's smallest width is a little larger, the artist or album list narrows when space is short, and Song Info can't be dragged quite as wide.
- **A failed eject no longer goes unnoticed.** If Q2 Sync's window isn't in front, for example when you eject from the menu bar item or a notification, a notification says the card wasn't ejected and why.
- **Error messages now show over the window you're in.** If ejecting fails while a window such as Sync Complete, Install Firmware, Verify Card or **Did the Firmware Update Finish?** is open, the reason shows right away. The same goes for choosing the wrong folder while setting up a Q2. Before, the message appeared only after you closed that window.
- With a card reader, the step after a sync said to unplug the Q2. It now says to put the card back in your Q2.
- A failed eject no longer counts as your Q2 connecting again, which could start an automatic sync, ask whether to sync, or ask whether a firmware update had finished.

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
