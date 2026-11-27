# Changelog

Release notes for each Q2 Sync build. Downloads are on [Releases](https://github.com/PaleoLabs/Q2-Sync/releases).

## Unreleased

### Added
- **Audiobooks from Apple Books (Q2 Pod).** A new **Audiobooks** tab on your Q2's page syncs all your audiobooks or only the ones you tick, like Finder does for an iPod. Each book gets its own folder in the card's `Audiobooks` folder, where Q2 Pod remembers your place and shows chapters. The first time, allow Q2 Sync to read Apple Books' folder (read-only). Protected (DRM) and not-downloaded books are listed with the reason and can't be ticked. Books you untick are removed only if you choose **Remove Them** in the preview, and only books Q2 Sync copied. The capacity bar shows audiobooks. Not on stock firmware. ([#48](https://github.com/PaleoLabs/Q2-Sync/issues/48))
- **Sync music on or off, like Finder.** The Music tab starts with a **Sync music onto** your Q2 checkbox. Untick it to sync only audiobooks: Q2 Sync then doesn't read your Apple Music library at all, and the songs and playlists it put on the card are removed only if you choose **Remove Them** in the preview. Your ticks are kept for when you turn it back on. Q2s you've already set up keep syncing music.
- **Search your audiobooks.** A **Search Audiobooks** box on the Audiobooks tab finds books by title or author, and **⌘**-click ticks or unticks every book shown.
- **Tick or untick a whole list at once.** On the Music tab, **⌘**-click a checkbox and every item in that tab takes its new state. With a filter, only the items shown change. ([#59](https://github.com/PaleoLabs/Q2-Sync/issues/59))

### Changed
- **Revert and Apply, like Finder.** Ticking boxes or choosing Entire music library on your Q2's page no longer saves straight away. **Sync** becomes **Revert** and **Apply**: Apply saves your choices and starts the sync, Revert puts back what you had. Changes you haven't applied are thrown away if you leave your Q2's page, switch to another Q2, unplug it or quit. While a sync runs, the button reads **Stop**.
- **The capacity bar and Sync button are at the bottom of every tab** of your Q2's page, not only Music. The button lines up with the bar, as in Finder.
- **The Music and Audiobooks tabs are laid out like Finder's**: the **Sync … onto** checkbox on its own line, then **Sync:** with the choices one under the other. **Sync** is available when only audiobooks are chosen.
- **The Settings tab is now General, and comes first**, as in Finder: General | Music | Audiobooks. Your Q2's page opens on it. **View › Show Q2 Settings** is now **Show Q2 General**. Q2 Sync's own Settings (**⌘,**) keeps its name. ([#66](https://github.com/PaleoLabs/Q2-Sync/issues/66))
- **Hints for ⌘-click.** The first-time note on the Music tab and the **Deselect All** button's hover text mention it.
- **One Remove choice in the sync preview.** Everything you no longer sync that's still on the card (songs, audiobooks) is on one line with one **Remove It** / **Remove Them** checkbox, instead of a linked checkbox per kind. ([#65](https://github.com/PaleoLabs/Q2-Sync/issues/65))
- **The Remove choice is hard to miss.** It sits in its own box, tinted red when ticked and orange when not, with a line saying what will happen ("Will be deleted from the card…" or "Will stay on the card unless you tick Remove Them"). The button reads **Sync and Remove N** when the sync takes anything off the card. ([#63](https://github.com/PaleoLabs/Q2-Sync/issues/63))
- **A shorter sync preview with more room for the list.** Under **Details**, each kind of content with something to do (Songs, Audiobooks, Playlists, Album Covers) gets one row, with Add, Update, Rename, Remove and Can't Sync lined up down the sheet. A dash means the action doesn't apply. New playlists and audiobooks count as Add, changed ones as Update. The sheet is taller, and the list gets the space. ([#64](https://github.com/PaleoLabs/Q2-Sync/issues/64))

### Fixed
- **"1 album cover", not "1 album covers".** Counts of one now read correctly in the sync window, the Sync Complete summary, the sync preview ("1 song you no longer sync is still on the card"), the Music tab and the library status. ([#55](https://github.com/PaleoLabs/Q2-Sync/issues/55))
- **Time remaining while removing.** When a sync removes songs from the card, the progress bar and time estimate now follow the removals ("Removing 120 of 3,083 · then 2.96 GB to copy") instead of sitting at "Estimating time remaining…" and an empty bar until copying starts. ([#62](https://github.com/PaleoLabs/Q2-Sync/issues/62))
- **The sync preview stays centred in the window** when you open Details, instead of growing downward.

## 0.3.1 (2026-11-25)

### Added
- **Search your library.** A search field in the toolbar on Artists, Albums, Genres and Playlists finds items by their name, or by a song's title, artist or album. **Edit › Find** (**⌘F**) puts the cursor there. ([#58](https://github.com/PaleoLabs/Q2-Sync/issues/58))

### Fixed
- **Opening your Q2's page no longer blanks the sidebar.** When the note under the capacity bar about "Other" files was showing, the sidebar and the top and bottom of the page could disappear, including after cancelling an auto-sync from its notification.
- **A renamed card shows its new name.** Rename your Q2's card in Finder, whether or not it's connected to Q2 Sync at the time, and the sidebar, menus and notifications use the new name. Before, they kept the name from when you set it up.

## 0.3.0 (2026-11-25)

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
