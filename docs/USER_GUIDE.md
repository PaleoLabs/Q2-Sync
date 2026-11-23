# Q2 Sync User Guide

Q2 Sync copies music from Apple Music on your Mac to your Shanling Q2, much like
Finder used to sync an iPod. This guide walks you through everything, step by
step. No technical knowledge needed.

**What Q2 Sync can sync:** music stored as **local, DRM-free files** in the
Music app on your Mac, such as MP3, AAC, Apple Lossless (ALAC), WAV and AIFF
files you've ripped from CDs, bought (iTunes Store purchases have been
DRM-free since 2009) or downloaded. **It can't sync songs from an Apple Music
subscription**, even ones downloaded for offline listening, because Apple
protects them with DRM so they only play in Apple's apps. Songs that are only
in iCloud are skipped too. These are listed as "can't be synced".

**The most important thing first:** Q2 Sync only *reads* your Apple Music
library. It never changes, moves or deletes anything in your library or its
music files. It only copies music **to** your Q2.

---

## Contents

1. [Connect your Q2 (USB Storage)](#1-connect-your-q2-usb-storage)
2. [First launch](#2-first-launch)
3. [Choose what to sync](#3-choose-what-to-sync)
4. [Run a sync](#4-run-a-sync)
5. [Music that's only on the card](#5-music-thats-only-on-the-card)
6. [Update the library on your Q2](#6-update-the-library-on-your-q2)
7. [Auto-sync](#7-auto-sync)
8. [Firmware: install, switch and update](#8-firmware-install-switch-and-update)
9. [Verify the card and back up Q2 Pod data](#9-verify-the-card-and-back-up-q2-pod-data)
10. [Eject safely](#10-eject-safely)
11. [Frequently asked questions](#11-frequently-asked-questions)

---

## 1. Connect your Q2 (USB Storage)

1. Turn on your Q2.
2. Swipe **down** from the top of the Q2's screen to open the quick-access menu.
3. Set the USB switch to **USB Storage** (not USB Audio or USB DAC).
4. Connect the Q2 to your Mac with its USB-C cable.

The Q2's microSD card appears on your Mac like a USB stick. You can also put
the card in a card reader instead.

> **Tip:** Only insert or remove the microSD card while the Q2 is fully shut
> down (not just asleep), or the card can be damaged.

The card must be formatted **exFAT** or **FAT32** (Shanling prefers exFAT)
on a **Master Boot Record** partition table. New cards usually are. If your
card uses another scheme (such as the GUID Partition Map Disk Utility may
pick), Q2 Sync shows a warning on the Q2's Settings tab with the steps to
erase it in Disk Utility: choose **View → Show All Devices**, select the card
itself, click **Erase**, and pick Format **ExFAT** and Scheme **Master Boot
Record**. Erasing deletes everything on the card, and Q2 Sync never erases or
formats a card itself.

---

## 2. First launch

1. Open **Q2 Sync**.
2. A notice titled **Before You Start** explains that Q2 Sync never changes your
   Music library, and reminds you to keep a backup of your Mac (for
   example with Time Machine). Read it and click **I Understand**. You'll only
   see it once.
3. The first time macOS asks whether Q2 Sync may access **Apple Music**, click
   **Allow**. Q2 Sync needs this to *read* your library.
4. When your Q2's card is connected, a window asks **"Is this your Shanling Q2?"**
   - Choose which firmware it runs: **Q2 Pod** or **Shanling (stock)**. If
     you're not sure: Q2 Pod looks like an iPod; stock is Shanling's own look.
   - This window pops up by itself only for a Q2 connected by USB cable. A
     card in a card reader (or any other drive) is listed in the sidebar under
     **Devices** instead: click **Set Up…** next to it. Once set up, your card
     is recognised either way.
   - Click **Continue…**. macOS shows the card in a window: make sure the card
     itself is selected, then click **Grant Access**. This lets Q2 Sync change
     files on this card only.
   - Clicked **Not My Q2** on a drive that is not your Q2? Q2 Sync won't ask
     about it again. Did it by mistake? Open **Q2 Sync › Settings** and
     click **Ask Again About Drives Marked "Not My Q2"**.

From now on, Q2 Sync recognises your card automatically and shows it under
**Devices** in the sidebar, like Finder does.

---

## 3. Choose what to sync

1. Click your Q2 in the sidebar, then the **Music** tab.
2. Q2 Sync reads your Music library when the window opens and whenever the
   Q2 connects. To re-read it (after adding music, say), click **Refresh
   Library** at the top right.
3. Choose one:
   - **Entire music library**: everything that can be copied, plus all your
     playlists.
   - **Selected artists, albums, genres, and playlists**: tick what you want
     in the **Artists**, **Albums**, **Genres** and **Playlists** tabs. Use the
     **Filter** box to find things quickly.

Everything you tick is combined: a song is synced if its artist, album, genre
or any of its playlists is ticked. When you tick an artist, their new albums
sync automatically next time.

The bar at the bottom shows:

- how many songs and how much space your selection uses;
- **"can't be synced"**: click it to see songs that won't be copied: songs
  only in iCloud (Q2 Sync never downloads them; if they're your own music,
  download them in Music first) and protected (DRM) songs, which includes
  every song from an Apple Music subscription;
- the **capacity bar**: your music, music you've unticked, what this sync will
  add, other files, and free space. A warning appears if your selection won't
  fit.

Your choices are saved for this Q2 automatically.

### Browse your Music library

The **Music Library** section of the sidebar (Artists, Albums, Genres,
Playlists) shows your library as it relates to your Q2, even when the Q2 is
unplugged:

- a **checkmark**: on your Q2; a **half circle**: partly on it; a blue
  **arrow**: chosen, and copied at the next sync; nothing: not chosen.
- an orange **lock**: some (outline) or all (filled) of these songs can't be
  copied.
- Hover over an icon for the numbers, or select the row: each song shows
  **On Q2** or **Next sync** in the **Q2** column, and its status icon says
  why it can't be copied.
- An artist's songs are listed album by album (albums in A–Z order, as on
  the Q2), each album in track order. A genre's songs are listed by album
  artist, then album, then track. Click a column header to sort another way.
- Drag the divider between the list and the songs to resize the list; Q2
  Sync remembers the width.
- Click **Song Info** in the toolbar (or right-click a song and choose
  **Show Info**) to open a panel on the right with everything about the
  selected song: artwork, whether it can be copied and whether it's on your
  Q2, its tags (year, genre, composer…), its file (kind, size, bit rate,
  sample rate, where it is on your Mac, with **Show in Finder**), and plays
  and dates from Music. Click it again to close the panel.
- Hover over a song's title to see where its file is on your Mac, or
  right-click songs for **Show in Finder** and **Copy Path**. A **File**
  column is also available: right-click the column headers to show it, or to
  show and hide other columns.

These marks come from Q2 Sync's record of the card from the last time it was
connected; the window's subtitle says which Q2 and when. If the card was
changed elsewhere since (on the Q2 itself or another Mac), they catch up the
next time you connect it.

---

## 4. Run a sync

1. Click **Sync**.
2. Q2 Sync reads your library, checks the card, and shows a **preview** of every
   change: songs to **Add**, **Update** or **Rename**, songs **Already on card**,
   and songs that **Can't sync**.
3. **Nothing changes until you click Sync** on the preview. Click **Cancel**
   to leave the card as it is.
4. **Removing songs you unticked:** these are listed under **Remove**, but
   nothing is removed unless you tick **Remove the … songs you no longer
   sync**. By default they go to a trash folder on the card rather than being
   deleted. If that's more than 20% of the songs on the card, you'll be asked
   to confirm.
5. Click **Sync**. A progress bar shows what's being copied, with an
   estimate such as "About 12 minutes remaining" once it has measured the
   copying speed (after about 10 seconds). You can click
   **Cancel** at any time; songs already copied stay, and the next sync carries
   on where it stopped.
6. When it's done, you'll see **Sync Complete** with three choices:
   **Eject** the card, **Verify Card…** to check every song on it first (see
   "Verify the card" below; eject when it's done), or keep it connected
   (**Not Now**).

Every sync is recorded in a log. Click **Show Log** on the result, or go to
your Q2's **Settings** tab → **Show Sync Logs**.

**Where things go on the card:** music goes in `Music/Artist/Album/`,
playlists in `_explaylist_data/`, and Q2 Sync's own records in a hidden
`.q2sync` folder. Q2 Sync never touches the Q2's own files and folders.

**Album covers (optional, off by default):** Apple Music often keeps artwork
in its own library rather than inside the song files, so the Q2 would show no
cover. Turn on **Add album covers** on your Q2's **Settings** tab and Q2 Sync puts a
`cover.jpg` in each album folder, made from the album's artwork in Apple
Music (resized to at most 1000 pixels, in a format the Q2 reads quickly).
The preview lists them under **Album Covers**.
- Your library is only read, never changed.
- A `cover.jpg` or `folder.jpg` you put there yourself is never replaced.
- When an album leaves the card, its cover goes too.
- Turn it on any time: the next sync adds covers for everything already on
  the card. Turn it off and the next sync removes the covers Q2 Sync added
  (listed under **Remove Album Covers** in the preview).

**Refresh Cover Flow after covers change (Q2 Pod).** Cover Flow keeps its
own cache of covers, so after a sync that adds or removes covers (for
example after turning the setting on or off), Q2 Sync reminds you to:

1. Update the library as usual (Library → Update Library → Scan music now).
   Refreshing Cover Flow doesn't rescan your music.
2. Choose **System settings → Display → Coverflow → Refresh Coverflow**. It
   also redoes the album covers in Library. (Since Q2 Pod 1.4.3 there's no
   Refresh tile at the end of Cover Flow; this setting replaces it.)
3. Open **Cover Flow**: the covers rebuild then.

If covers don't rebuild:
- The card needs at least **16 MB free**; below that, nothing is built.
- An album showing a **grey disc** had artwork that restarted the Q2 while
  Cover Flow was preparing it. Refresh Coverflow tries it again; if it keeps
  happening, check that album's cover file.
- As a last resort you can delete the hidden `.coverflow` folder at the root
  of the card from your Mac (press ⌘⇧. in Finder to see it). Q2 Pod's docs
  call it the cover cache but don't say deleting it equals a refresh, so
  use the menu option first.

---

## 5. Music that's only on the card

If the card has music that isn't part of what you sync (for example songs you
copied by hand, or songs you've since deleted from Apple Music), the preview
lists them under **On the Card Only**. Nothing happens to them unless you
choose. For each file, pick:

| Choice | What happens |
| --- | --- |
| **Leave on Card** (default) | Nothing. |
| **Copy to Mac** | A copy goes to your **Downloads › Q2 Recovered** folder. The file stays on the card. |
| **Move to Card Trash** | Moved into the card's hidden trash folder (you can still get it back). |
| **Delete from Card** | Deleted for good. You'll be asked to confirm. |

Use **Set all to** to choose for every file at once.

**About "Copy to Mac":** Q2 Sync never puts files into your Music library. It
copies them to **Downloads › Q2 Recovered**, keeping their folders, and lists
them in `RECOVERED.txt`. To add them to Apple Music, open Music and choose
**File › Import…**. Songs already in your library aren't copied again, and
nothing in the Q2 Recovered folder is ever overwritten.

**Emptying the card's trash:** in Finder, open the card, press
**⌘⇧.** (Command-Shift-period) to show hidden folders, and delete `.q2sync/Trash`.

---

## 6. Update the library on your Q2

After every sync, your Q2 needs to scan the card before new music shows up:

1. Eject the card in Q2 Sync, then unplug the Q2.
2. On the Q2:

| Firmware | Steps |
| --- | --- |
| **Q2 Pod** | **Library → Update Library → Scan music now** |
| **Shanling stock** | **Local Songs → Update Library → Scan music now** |

3. To bring in your playlists:

| Firmware | Steps |
| --- | --- |
| **Q2 Pod** | **Library → Playlists → Import** (in the Classic theme, under **Select Playlists…**) |
| **Shanling stock** | Open **Playlists** and choose **Import** |

Importing a playlist with the same name replaces the old one. The Q2 keeps up
to 100 playlists. If you unticked a playlist, delete it on the Q2 too: removing
its file from the card doesn't remove a playlist you already imported.

**Importing takes a while.** The Q2 reads every song in every playlist and
shows no progress while it does, so big playlists can look frozen for
several minutes. Leave it until it finishes.

**Only changed playlists (on by default):** so you don't wait for every
playlist each time, each sync leaves in the card's playlist folder only the
playlists that are new or changed, and takes out the ones you imported after
the previous sync. Playlists already on the Q2 stay there. The sync result
tells you how many are ready to import. If you skipped an import, reset the
Q2 or use a new card, click **Put All Up for Import** on your Q2's
**Settings** tab (under **Playlists**) before syncing. Turn the setting off
to keep every playlist in the folder.

**Which playlists go on the card:** your own regular, smart and Genius
playlists, and Apple's music smart playlists (My Top Rated, Recently Played,
Recently Added, Top 25 Most Played…). Built-in lists that aren't songs
(Purchased, Movies, Podcasts, Voice Memos) and folders themselves are left
out. If two playlists share a name and one is in a folder, it's named after
the folder on the Q2, e.g. **Decades - 1980's Music**.

Q2 Sync shows these steps after each sync, for your Q2's firmware.

---

## 7. Auto-sync

Q2 Sync can notice when your Q2 connects. On your Q2's **Settings** tab, under
**Auto-Sync**, choose **When this Q2 connects**:

- **Ask Me (Notification)** (default): a notification asks whether to sync.
  Click **Sync Now**.
- **Sync Automatically**: syncs straight away.
- **Do Nothing**: you sync by hand.

Automatic syncs follow every safety rule. They **never remove songs and never
eject**. If anything needs your decision (the first sync with a card, songs
you unticked, songs gone from your library, or not enough space), they stop,
open the preview in Q2 Sync, and notify you. When an automatic sync finishes,
a notification has an **Eject** button.

For auto-sync to work, Q2 Sync must be running. It stays in the **menu bar**
when you close its window. To start it automatically, open
**Q2 Sync › Settings** and turn on **Open Q2 Sync at login**.

The **menu bar item** shows whether your Q2 is connected and lets you **Sync
Now**, **Eject**, **Open Q2 Sync**, open **Settings** or **Quit**. You can hide
it in Settings.

---

## 8. Firmware: install, switch and update

Q2 Sync can put **Q2 Pod** or **Shanling's stock firmware** on your card, so
you can switch between them or update. Open your Q2's **Settings** tab and
click **Install Firmware…** (or choose **Device → Install Firmware…**).

1. Pick **Q2 Pod** or **Shanling (stock)**. Q2 Sync shows the latest version
   of each: Q2 Pod's from GitHub, stock's from Shanling's download page.
2. Click **Download and Copy to Card**. Q2 Sync downloads it, checks it's
   genuine Shanling Q2 firmware of the kind you picked (Q2 Pod must also match
   GitHub's checksum), makes sure the card has room (about twice the file,
   as the Q2 unpacks it next to itself), and copies it to the card as
   `update.tar`. Your music isn't touched.
3. Follow the steps it shows: eject (if the card is in a card reader, put it
   back in the Q2), make sure the Q2 is charged, then on the Q2 choose
   **System settings → System Update → TF card update** and confirm. Leave
   the card in until the Q2 restarts by itself.
4. Next time you connect the Q2, Q2 Sync asks **Did the Firmware Update
   Finish?** Click **Yes, It's Updated** to switch its settings to the new
   firmware (and remove the leftover `update.tar`), **Not Yet** to be asked
   again, or **Don't Install It** to remove the file. The card can't tell Q2
   Sync which firmware is installed, which is why it asks.

If the download can't be found (for example, Shanling changed its page),
download the firmware yourself and click **Choose File…**, or drop the zip or
`update.tar` onto the window. It's checked the same way.

If the Q2 won't start up after an update, see Q2 Pod's
[restoring stock firmware](https://github.com/DiamondBond/q2-pod#restoring-stock-firmware)
instructions.

### Update notices

**Q2 Pod:** on your Q2's **Settings** tab, under **Firmware Updates**, turn on
**Check GitHub for new Q2 Pod releases**. Q2 Sync checks at most once a day
when your Q2 connects (or when you click **Check Now**) and tells you about new
releases, with their notes and a link.

- Q2 Sync can't see which version your Q2 runs, so type it in under
  **Installed version** (on the Q2: **System settings → About**, shown as
  "CFW. Version"). Then it can tell you whether you're up to date.
- If you leave it blank, Q2 Sync tells you about each new release once; click
  **Dismiss** to hide it until the next one.

- When a new release is out, click **Update to …** to put it on the card.

**Shanling stock:** not checked automatically. **Install Firmware…** always
finds Shanling's latest, and your Q2 can also check by itself: **System
Setting → System Update → Network update**.

---

## 9. Verify the card and back up Q2 Pod data

### Verify the card

microSD cards can damage files without warning. On your Q2's **Settings**
tab, under **Card**, click **Verify Card…** (or **Device → Verify Card…**, or
**Verify Card…** on the Sync Complete window).
Q2 Sync reads every song it put on the card and compares it, byte for byte,
with the song on your Mac. Nothing changes while it checks.

- Damaged or missing songs are listed. Click **Copy Songs Again** to fix
  them (this goes through the same checks as a sync).
- Songs changed on your Mac since copying aren't checked: your next sync
  updates them.
- Read your library first (the arrow at the top right).
- Checking a full card over USB takes a while; a card reader is faster.

### Back up Q2 Pod's data

Q2 Pod keeps some of your data on the card: song ratings, listens waiting to
be scrobbled, scrobbling and radio settings, EQ presets, custom App Store
sources and Rockbox settings. On your Q2's **Settings** tab, under **Q2 Pod
Data**, click **Back Up Now** to copy them to **Downloads › Q2 Sync
Backups**. To put them on a card (for example a new one), click
**Restore…**, choose a backup and tick what to restore, then restart the Q2.

- Restoring **Listens not yet scrobbled** is off by default: those listens
  may already have been sent, and would be sent twice.
- The Q2's own settings are stored inside the Q2, not on the card, so a
  Mac can't back them up. A firmware update doesn't touch the card.

---

## 10. Eject safely

Always eject before unplugging:

- click **Eject** on the result after a sync, or
- the eject button next to your Q2 in the sidebar, or the **Eject** button on
  its page, or
- **Eject** in the menu bar item.

If ejecting fails, Q2 Sync says so and the card stays connected. Close any
Finder windows showing the card and try again.

---

## 11. Frequently asked questions

**Can Q2 Sync damage my Apple Music library?**
No. It only reads your library, and macOS itself prevents it from writing to
your Music folder. It still makes sense to keep a backup of your Mac, as with
any app.

**Why are some songs "can't be synced"?**
They're either protected by DRM or only in iCloud (not downloaded to your Mac).

- **Apple Music subscription songs** are always protected, even when you've
  downloaded them for offline listening, so they can never be copied to a Q2
  (or any other non-Apple player). The same goes for iTunes Store purchases
  from before 2009 that were never upgraded to iTunes Plus.
- **Your own music that's only in iCloud** (uploaded or matched through
  iTunes Match or Sync Library) can be synced once it's on your Mac: download
  it in Music first. Q2 Sync never downloads songs itself.

**Does Q2 Sync work with an Apple Music subscription?**
Only for the music files you own. Your subscription doesn't stop Q2 Sync from
syncing your local, DRM-free files, but songs added from the Apple Music
catalogue can't be copied. To get a song onto your Q2, buy it (the iTunes
Store sells DRM-free files) or add your own copy to the Music app.

**I unticked an album but it's still on my Q2.**
Removals are always your choice. Tick **Remove the … songs you no longer sync**
in the preview.

**I deleted a song in Apple Music. What happens to the copy on the card?**
It's listed under **On the Card Only** with the note "no longer in your
library", so you can copy it back to your Mac or remove it.

**What happens to music I copied onto the card myself?**
It's left alone unless you choose otherwise under **On the Card Only**. Q2 Sync
never overwrites it.

**My new music doesn't show on the Q2.**
Run **Update Library** on the Q2 (see section 6).

**The card is full.**
The capacity bar warns you. Untick some music, or allow removals in the preview.
Q2 Sync always leaves 200 MB free for the Q2's own use.

**What are the `.q2sync` and `_explaylist_data` folders on the card?**
`.q2sync` holds Q2 Sync's record of what it copied, plus the card's trash.
`_explaylist_data` holds playlists for the Q2 to import. Please don't edit
`.q2sync/manifest.json`. If it ever gets damaged, delete it: the next sync
rebuilds it without copying identical songs again.

**Can I use the same card with another Mac?**
Yes. The record of what's on the card lives on the card itself.

**Where are the logs?**
Your Q2's **Settings** tab → **Show Sync Logs**.

**I clicked "Not My Q2" by mistake.**
**Q2 Sync › Settings → Ask Again About Drives Marked "Not My Q2"**.
