# Q2 Sync User Guide

Q2 Sync copies music from Apple Music on your Mac to your Shanling Q2, much like
Finder used to sync an iPod. This guide walks you through everything, step by
step. No technical knowledge needed. In the app, choose **Help › Q2 Sync
Help** (**⌘?**) to read it; it works offline and matches your version.

**What Q2 Sync can sync:** music stored as **local, DRM-free files** in the
Music app on your Mac, such as MP3, AAC, Apple Lossless (ALAC), WAV and AIFF
files you've ripped from CDs, bought (iTunes Store purchases have been
DRM-free since 2009) or downloaded. **It can't sync songs from an Apple Music
subscription**, even ones downloaded for offline listening, because Apple
protects them with DRM so they only play in Apple's apps. Songs that are only
in iCloud are skipped too. These are listed as "can't be synced".

**The most important thing first:** Q2 Sync only *reads* your Apple Music
library. It never changes, moves or deletes anything in your library or its
music files. It only copies music **to** your Q2. Your Music library stays
the source of truth, and the Q2 is simply one more device it syncs to.

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
12. [Keyboard shortcuts](#12-keyboard-shortcuts)

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
pick), Q2 Sync shows a warning on the Q2's General tab with the steps to
erase it in Disk Utility: choose **View → Show All Devices**, select the card
itself, click **Erase**, and pick Format **ExFAT** and Scheme **Master Boot
Record**. Erasing deletes everything on the card, and Q2 Sync never erases or
formats a card itself.

The Q2 also expects that one volume to be the only thing on the card and to
fill it. A card reused from a Raspberry Pi (or another Linux computer) needs
erasing too: it is Master Boot Record, but macOS shows only its small boot
partition (often named **bootfs**), and the rest of the card is a Linux
partition neither your Mac nor the Q2 can use. If a card has any other
partition, of any format or size, or its volume leaves part of the card
unused, the "Is this your Shanling Q2?" window says so ("This card has
another partition (124.4 GB) that the Q2 can't use. Only 534.8 MB of the
card's 124.95 GB can hold music."), with the same Disk Utility steps under **How to
Erase It**. Pressing Return then chooses **Later**; **Continue Anyway** is
still there if you mean to use the card as it is.

Through the Q2's USB cable the card's partitions can't be seen (the Q2 shows
the Mac only the card's volume), so Q2 Sync only checks them when the card is
in a card reader.

---

## 2. First launch

1. Open **Q2 Sync**.
2. A notice titled **Before You Start** explains that Q2 Sync never changes your
   Music library, and reminds you to keep a backup of your Mac (for
   example with Time Machine). Read it and click **I Understand**. You'll only
   see it once.
3. The first time macOS asks whether Q2 Sync may access **Apple Music**, click
   **Allow**. Q2 Sync needs this to *read* your library.
4. Until a Q2 is connected, the sidebar's **Devices** section shows **Connect
   Your Q2**, with the steps above and what happens next. Meanwhile you can
   browse your Music library.
5. When your Q2's card is connected, a window asks **"Is this your Shanling Q2?"**
   If you're in another app (or Q2 Sync's window is closed; it keeps running
   in the menu bar), a notification says **Set Up Your Q2?** and the window
   waits behind your other windows: click the notification to bring it
   forward. See [When Q2 Sync needs you](#when-q2-sync-needs-you).
   - Choose which firmware it runs: **Shanling (stock)** or **Q2 Pod**.
     Neither is selected to start with, and **Continue…** waits until you
     choose. If you're not sure: Q2 Pod looks like an iPod; stock is
     Shanling's own look.
   - This window pops up by itself only for a Q2 connected by USB cable. A
     card in a card reader (or any other drive) is listed in the sidebar under
     **Devices** instead: click **Set Up…** next to it. Once set up, your card
     is recognized either way.
   - Click **Continue…**. macOS shows the card in a window: make sure the card
     itself is selected, then click **Grant Access**. This lets Q2 Sync change
     files on this card only.
   - Clicked **Not My Q2** on a drive that is not your Q2? Q2 Sync won't ask
     about it again. Did it by mistake? Open **Q2 Sync › Settings** and
     click **Ask Again About "Not My Q2" Drives**.

From now on, Q2 Sync recognizes your card automatically and shows it under
**Devices** in the sidebar, like Finder does. It works with one card at a
time: if more than one card you've set up is connected (say your Q2 by USB
and a spare card in a reader), one is shown (the one you just set up or last clicked), and the
others are listed below it in grey. Click one to switch to it (not while a
sync or Verify Card is running).

Q2 Sync shows your card under its name in Finder. If you rename the card, the
new name appears the next time it connects, or straight away if it's connected
now. Your settings stay as they were. Don't rename it while a sync or Verify
Card is running.

### New versions of Q2 Sync

Q2 Sync checks GitHub for a new version when it starts, then once a day while
it runs. When one is out, a small window says so and stays on top of other
windows until you choose:

- **View on GitHub** opens the download page.
- **Later** closes the window. It's shown again the next time Q2 Sync starts,
  or a day later.
- **Skip This Version** stops it for that version. You'll still be told about
  newer ones.

If Q2 Sync is busy, for example syncing or waiting for you to answer
something in its window, the update window appears after you're done.

The menu bar item also shows **Get Q2 Sync …** until you've updated.

To check yourself, choose **Q2 Sync › Check for Updates…**, or **Check for
Updates…** in the menu bar item. To stop the automatic check, open **Q2 Sync ›
Settings** and turn off **Check for new versions automatically**.

Q2 Sync doesn't download or install updates. To update, download the new
`Q2-Sync-<version>.zip`, unzip it, quit Q2 Sync, and drag the new **Q2 Sync**
into your Applications folder, replacing the old one. Your settings and Q2s
are kept.

---

## 3. Choose what to sync

1. Click your Q2 in the sidebar, then the **Music** tab.
2. Q2 Sync reads your Music library when the window opens and whenever the
   Q2 connects. To re-read it (after adding music, say), click **Refresh
   Library** at the top right, or choose **File › Refresh Music Library**
   (**⌘R**).
3. **Sync music onto** your Q2 is ticked to start with. Under **Sync:**,
   choose one (on a new Q2, nothing is chosen yet, and **Sync** waits until
   you choose):
   - **Entire music library**: everything that can be copied, plus all your
     playlists.
   - **Selected artists, albums, genres, and playlists**: tick what you want
     in the **Artists**, **Albums**, **Genres** and **Playlists** tabs. Use the
     **Filter** box to find things quickly (**⌘F** puts the cursor there);
     click the **×** in it to clear the search.

**Don't want music on your Q2?** Untick **Sync music onto** your Q2 (for
example, to sync only audiobooks). Everything below it dims, and Q2 Sync no
longer reads your Apple Music library when it syncs, so it works even if Music
can't be read. Your ticks are kept for when you turn it back on. If the card
holds songs Q2 Sync put there, an orange note says so: nothing is removed
until you click **Apply**, and then only if you choose **Remove Them** in the
preview (auto-sync stops and asks). Music you copied onto the card another way
is never touched.

To tick everything in a tab at once, hold **⌘** and click an unticked box.
**⌘**-click a ticked box to untick everything. Only that tab changes. With
something in the **Filter** box, only the items shown change. This ticks what's
listed now, so an artist you add to your library later still needs ticking.

Everything you tick is combined: a song is synced if its artist, album, genre
or any of its playlists is ticked. When you tick an artist, their new albums
sync automatically next time.

The line at the bottom of the Music tab shows:

- how many songs your selection holds, how long they play for in total
  (for example "2h 35m" or "3d 4h"), and how much space they use;
- **"can't be synced"**: click it to see songs that won't be copied: songs
  only in iCloud (Q2 Sync never downloads them; if they're your own music,
  download them in Music first) and protected (DRM) songs, which includes
  every song from an Apple Music subscription;
At the bottom of your Q2's page, on every tab:

- the **capacity bar**: your music, audiobooks and podcast episodes (Q2
  Pod), what you've unticked, what this sync will add, **Other** (everything else: the Q2's own data such as its library and
  Cover Flow images, playlists and album covers, and music copied there
  another way; hover over it for this), and free space. A warning appears if
  your selection won't fit. If Other is large, a note
  says some of it may be songs copied onto the card another way: those that
  match your library are kept at the next sync rather than copied again, so
  less may be added (the sync preview checks exactly). If Q2 Sync can't read
  the card (grant access again on the General tab), the bar shows only used
  and free space.

Like Finder's iPod page, nothing you tick is saved straight away. As soon as
you change anything, the **Sync** button becomes **Revert** and **Apply**:

- **Apply** saves your choices for this Q2 and starts a sync (the preview
  below opens).
- **Revert** puts back the choices you had, and **Sync** returns.

Your changes stay while you switch between the Music, Audiobooks, Podcasts and General tabs. They
are thrown away, without asking, if you go to another page in the sidebar,
switch to another Q2, unplug the Q2 or quit Q2 Sync.

While a sync is under way the button reads **Stop**. Stopping keeps the
choices you applied.

### Audiobooks (Q2 Pod)

Q2 Sync copies audiobooks from **Apple Books**, the way Finder syncs them to
an iPod. They go in the card's `Audiobooks` folder, one folder per book, where
Q2 Pod lists them under **Library › Audiobooks**: they remember your place,
have chapters, and stay out of your music and shuffle.

1. Click your Q2 in the sidebar, then the **Audiobooks** tab.
2. The first time, click **Allow Access to Books…**. A window opens at Apple
   Books' folder, already selected: click **Allow Access**. Q2 Sync only reads
   it, and remembers the permission.
3. Tick **Sync audiobooks onto** your Q2, then under **Sync:** choose **All
   audiobooks** or **Selected audiobooks** and tick the books you want. The
   **Search Audiobooks** box finds books by title or author (**⌘F** puts the
   cursor there). **⌘**-click a box to tick or untick every book shown.
4. Click **Apply**, as for music.

- **Protected books can't be synced.** Most audiobooks bought in the Apple
  Books store are protected (DRM) and play only in Apple's apps. They're
  listed with a lock, and their boxes can't be ticked. Books you added
  yourself, such as DRM-free `.m4b` files, sync.
- **Only downloaded books are listed.** A book that's only in iCloud doesn't
  appear: download it in Apple Books first.
- **Very long books:** Q2 Pod can refuse a single file of around 40 hours.
  Books with a file over 35 hours are marked **May be too long**.
- A book you untick, or delete from Apple Books, is removed from the card at
  the next sync if you tick **Remove Them** in the preview. Q2 Sync only
  removes books it copied; anything else in `Audiobooks` is left alone.
- On **stock firmware**, the tab explains that audiobook sync needs Q2 Pod.
- To add audiobooks to Apple Books, open Books and choose **File › Add to
  Library**. The tab reads Apple Books when you open it, so a book you add
  while it's showing appears when you come back to the tab. A sync always
  reads Apple Books first, so it never misses a book.

### Browse your audiobooks

While any of your Q2s has **Sync audiobooks** on, the sidebar has an
**Audiobooks** section with **Books**, below Music Library (**View › Books**,
**⌘6**). It lists the audiobooks in Apple Books as they relate to your Q2,
even when the Q2 is unplugged:

- The **Q2** column shows a green check (**On Q2**), a grey arrow (**Next
  sync**: copied at the next sync), a dash (**Not chosen**), or an orange icon
  when the book can't be synced (protected, not downloaded, files missing or
  unreadable; hover for why).
- Click a column header (Title, Author, Length, Size) to sort. **Search** with
  the field in the toolbar (**⌘F** puts the cursor there).
- Double-click a book (or click **Book Info** in the toolbar, or press
  **⌘I**, or right-click it and choose **Show Info**) for a panel with its
  status, author, length, size and files in order, with **Show in Finder**.
  Right-click books for **Show in Finder** too.
- The bottom of the sidebar shows how many books you have and their size,
  how many can't be synced, and whether Apple Books looks healthy (see
  [The bottom of the sidebar](#the-bottom-of-the-sidebar)).
- The list is read when you open it. If you add a book to Apple Books while
  it's showing, click **Refresh Audiobooks** at the top right to see it.

If a Q2's record of the card is from before this version, the list asks you
to connect it once so Q2 Sync can see which books are on it.

### Podcasts (Q2 Pod)

Q2 Sync copies the episodes the **Podcasts** app has downloaded to your Mac.
They go in the card's `Podcasts` folder, one folder per show, where Q2 Pod
lists them under **Library › Podcasts**: they remember your place and stay
out of your music and shuffle. Each file is named with the episode's date and
title, for example `Podcasts/The Daily/2026-11-27 - The Election.mp3`, the
same way the q2-podcasts app on the Q2 names them.

1. Click your Q2 in the sidebar, then the **Podcasts** tab.
2. The first time, click **Allow Access to Podcasts…**. A window opens at the
   Podcasts app's folder, already selected: click **Allow Access**. Q2 Sync
   only reads it, and remembers the permission.
3. Tick **Sync podcasts onto** your Q2, then under **Sync:** choose **All
   shows** or **Selected shows** and tick the shows you want. Each show lists
   its downloaded episodes under it. The **Search Podcasts** box finds shows
   and episodes (**⌘F** puts the cursor there). **⌘**-click a box to tick or
   untick every show listed.
4. Tick **Unplayed only** to leave out episodes the Podcasts app has marked
   played. Episodes you're partway through still sync.
5. Click **Apply**, as for music.

- **Only downloaded episodes are listed.** Q2 Sync doesn't download
  episodes: download them in the Podcasts app (by default it downloads the
  latest episodes of each show you follow).
- **Video and protected episodes can't be synced.** They're listed dimmed;
  click **can't be synced** at the bottom of the tab for the list. Video
  podcasts aren't synced yet. Protected episodes, such as some from paid
  subscriptions, only play in Apple's apps.
- **Played on the Q2 isn't played on the Mac.** Q2 Sync only reads the
  Podcasts app, never changes it, so an episode you finish on the Q2 stays
  unplayed on your Mac (see the [FAQ](#11-frequently-asked-questions)).
- An episode the Podcasts app no longer has downloaded, a show you untick, or
  a played episode while **Unplayed only** is on is removed from the card at
  the next sync if you tick **Remove Them** in the preview. The preview says
  why for each one. Q2 Sync only removes episodes it copied: anything else in
  `Podcasts`, such as episodes the q2-podcasts app downloaded, is left alone.
  If an episode is already on the card under the same name (from
  q2-podcasts, say), Q2 Sync counts it as on the card and doesn't copy it
  again.
- On **stock firmware**, the tab explains that podcast sync needs Q2 Pod.
- A sync always reads the Podcasts app first, so it never misses an episode.

### Browse your podcasts

While any of your Q2s has **Sync podcasts** on, the sidebar has a
**Podcasts** section with **Episodes** (**View › Episodes**, **⌘7**). It
lists the downloaded episodes as they relate to your Q2, even when the Q2 is
unplugged:

- Columns: **Show**, **Title**, **Date**, **Played** (Played or In
  progress), **Size** and **Q2**. Click a column header to sort. **Search**
  with the field in the toolbar (**⌘F** puts the cursor there).
- The **Q2** column shows a green check (**On Q2**), a grey arrow (**Next
  sync**), a dash (**Not chosen**: its show isn't ticked, or it's played
  while **Unplayed only** is on), or **Video** / **Protected** when it can't
  be synced. It follows the settings you've applied, not changes you haven't
  applied yet.
- Double-click an episode (or click **Episode Info** in the toolbar, or press
  **⌘I**, or right-click it and choose **Show Info**) for a panel with its
  status and file, with **Show in Finder**.
- The bottom of the sidebar shows how many episodes there are, their size,
  how many can't be synced, and whether the Podcasts app looks healthy.
- The list is read when you open it. If the Podcasts app downloads an
  episode while it's showing, click **Refresh Podcasts** at the top right.

### Photos (Q2 Pod)

Q2 Sync copies photos from your **Photos** library to the card's `Photos`
folder, where Q2 Pod shows them under **Photos**. Each album gets its own
folder (`Photos/Holiday/2026-07-01 IMG_1234.jpg`), which Q2 Pod shows as an
album; its **All Photos** shows every photo on the card.

1. Click your Q2 in the sidebar, then the **Photos** tab.
2. The first time, click **Allow Access to Photos…** and allow it in the
   macOS prompt. Q2 Sync only reads your library, and never changes it. If
   you choose **Limit Access** there, Q2 Sync only sees the photos you
   picked (the tab says so, with **Change…**).
3. Tick **Sync photos onto** your Q2, then choose:
   - **All photos and albums:** every album of yours, plus the photos in no
     album, loose in `Photos` so they show in All Photos.
   - **Selected albums:** only the albums you tick. **Favorites**, **Recently
     Added**, **Media Types** (Selfies, Portrait, Live Photos, Panoramas,
     Screenshots and more) and **Hidden** are listed with your own albums.
     The **Search Albums** box finds albums; **⌘**-click a box to tick or
     untick every album in that group.
4. Options:
   - **Automatically include photos from** (Selected albums only): also copy
     the photos taken in the last week, month, 2, 3 or 6 months or year,
     loose in `Photos`, unless a ticked album already brings them.
   - **Only favorites:** only photos marked as favourites, within the albums
     chosen.
   - **Include full-resolution photos:** copy each photo at its original
     size instead of a copy sized for the Q2's screen. It takes far more
     space, and big photos open slowly on the Q2.
5. Click **Apply**, as for music. The bottom of the tab shows how many
   photos will be on the card and about how much space they take.

- **Copied for the Q2's screen.** Photos are made into JPEGs that fit
  750 × 580 (about 120 KB each), the right way up, with your edits and
  without location data. Photos stored only in iCloud are downloaded as
  they're copied, so the first sync can take a while.
- **500 photos per album.** Q2 Pod shows at most 500 photos in an album
  and in All Photos, and at most 200 albums. Everything is still copied; the
  sync preview warns you, and the tab marks albums over 500 with an orange
  triangle.
- **A photo in two albums is copied twice**, once in each album's folder.
- **Hidden photos** are copied only when you tick the **Hidden** album,
  never by All photos and albums.
- **People and Recently Deleted aren't listed.** macOS doesn't let other
  apps read them. Videos aren't synced yet.
- **Edited a photo, or changed Include full-resolution photos?** The next
  sync replaces those photos on the card.
- A photo you deleted in Photos, an album you untick, or a photo that's no
  longer a favourite while **Only favorites** is on is removed from the card
  at the next sync if you tick **Remove Them** in the preview. The preview
  says why for each one. Q2 Sync only removes photos it copied: anything
  else in `Photos` is left alone.
- **Copy photos from** only offers your Photos library for now. Choosing a
  folder instead comes later.
- On **stock firmware**, the tab explains that photo sync needs Q2 Pod.
- A sync always reads your Photos library first, so it never misses a photo.

### Browse your photos

While any of your Q2s has **Sync photos** on, the sidebar has a **Photos**
section with **Albums** (**View › Albums**, **⌘8**). It shows your library as
it relates to your Q2, even when the Q2 is unplugged:

- On the left, **All Photos** and your albums, each with how many of its
  photos are on your Q2 ("12 of 40"), and a check when it's chosen on the
  Photos tab.
- On the right, the album's photos: **Name**, **Date**, **Size** (in pixels)
  and **Q2**, with a heart for favourites. Click a column header to sort.
  **Search** by file name with the field in the toolbar (**⌘F**).
- The **Q2** column shows a green check (**On Q2**), a grey arrow (**Next
  sync**) or a dash (**Not chosen**). A photo in two albums is on the Q2 if
  either copy is. It follows the settings you've applied, not changes you
  haven't applied yet.
- Double-click a photo (or click **Photo Info** in the toolbar, or press
  **⌘I**, or right-click it and choose **Show Info**) for a panel with a
  preview, its status, date, size and the albums it's in. The preview uses
  what's on this Mac; nothing is downloaded from iCloud for it.
- The bottom of the sidebar shows how many photos and albums there are, how
  long the library took to read, and whether Photos looks healthy.
- The library is read when you first open it. A big library takes a while:
  after changing albums in Photos, click **Refresh Photos** at the top right.

### Browse your Music library

The **Music Library** section of the sidebar (Artists, Albums, Genres,
Playlists) shows your library as it relates to your Q2, even when the Q2 is
unplugged:

- a green **checkmark**: on your Q2; a teal **half circle**: partly on it;
  a grey **arrow**: chosen, and copied at the next sync; nothing: not chosen.
- an orange **lock**: some (outline) or all (filled) of these songs can't be
  copied.
- Hover over an icon for the numbers, or select the row: each song's
  **On Q2** column shows a green check (on your Q2), a grey arrow (comes at
  the next sync), a dash (not chosen), or an orange icon when the song can't
  be synced (iCloud only, copy-protected, file missing…; hover for why, or
  open **Song Info**). For a missing file it says where it went: in the
  Trash, on a drive that isn't connected, or moved or deleted.
- An artist's songs are listed album by album (albums in A–Z order, as on
  the Q2), each album in track order. A genre's songs are listed by album
  artist, then album, then track. Click a column header to sort another way;
  click **#** to go back to the album or playlist order. Drag column headers
  to reorder them or their edges to resize them; Q2 Sync remembers.
- Drag the divider between the list and the songs to resize the list; Q2
  Sync remembers the width.
- Double-click a song (or click **Song Info** in the toolbar, choose
  **View › Show Song Info** (**⌘I**), or right-click a song and choose
  **Show Info**) to open a panel on the right with everything about the
  selected song: artwork, whether it can be copied and whether it's on your
  Q2, its tags (year, genre, composer…), its file (kind, size, bit rate,
  sample rate, where it is on your Mac, with **Show in Finder**), and plays
  and dates from Music. The panel follows your selection and stays open until
  you double-click a song again, click **Song Info** again or choose **View ›
  Hide Song Info** (**⌘I**).
- Hover over a song's title to see where its file is on your Mac, or
  right-click songs for **Show in Finder** and **Copy Path**. **File › Show
  in Finder** (**⇧⌘R**) does the same for the selected songs. A **File**
  column is also available: right-click the column headers to show it, or to
  show and hide other columns.
- Right-click an artist or album for **Show in Finder**. It's dimmed when the
  songs are too spread out to show in one Finder window, as for most genres
  and playlists.
- **Search** with the field in the toolbar (**⌘F** puts the cursor there).
  The list keeps the items whose name matches what you type (on Albums, the
  album artist counts too), and those holding a matching song: by title,
  artist, album artist or album. An item found by its name shows all its
  songs; one found only through its songs shows just those. Every word has to
  match, in any order ("help beatles"), and capitals and accents don't
  matter. The song counts and marks on the left still cover the whole item.
  Clear the field to see everything again; switching to another list clears
  it too.

These marks come from Q2 Sync's record of the card from the last time it was
connected; the window's subtitle says which Q2 and when. If the card was
changed elsewhere since (on the Q2 itself or another Mac), they catch up the
next time you connect it.

**Export a song list.** Choose **File › Export Song List…** to save a CSV (for
Excel or Numbers) of the songs on your Q2 and those chosen for the next sync,
with title, artist, album, genre, year, length, size and format, and whether
each is **On Q2** or **Next sync**. It uses the same record of the card as the
marks above, so it works without the Q2 connected.

### The bottom of the sidebar

On your Q2's page, the bottom of the sidebar has one line for each place
this Q2 syncs from, with its count on the right, for example
**Music** 9,890 songs. The icon in front shows its state: a green shield
when it looks healthy, a spinner while it's being read, and a red shield
when something's wrong, with the reason underneath. Hold the pointer over
a line to see how long the last read took. Click a line to
browse it (Artists, Books, Episodes or Albums). On those pages, the bottom of the
sidebar has more detail about that place instead.

**"Looks healthy"** means Q2 Sync trusts what it read. If something is
wrong, the line says **needs attention** in red, with the reason under it,
and the next sync leaves that kind of content on the card as it is:

- **Music:** the library has no songs, its media folder isn't there (for
  example, an external drive isn't connected), or more than 10% of the song
  files are missing. The sync stops.
- **Books:** Apple Books' folder can't be reached, or more than 10% of the
  books this Q2 syncs have missing files. Audiobooks on the card aren't
  changed.
- **Podcasts:** the Podcasts app's database or downloads folder is missing.
  Podcasts on the card aren't changed. No downloaded episodes at all is fine:
  the Podcasts app deletes played downloads by default.
- **Photos:** Q2 Sync isn't allowed to read your Photos library. Photos on
  the card aren't changed. An empty library is fine.

---

## 4. Run a sync

1. Click **Sync** (or **Apply**, if you've just changed your choices).
2. Q2 Sync reads your Music library, Apple Books and the Podcasts app
   (whichever this Q2 syncs; the sheet names each as it reads it), checks
   the card, and shows a **preview**: one
   sentence saying what the sync will do (for example "This sync will update
   3 playlists. Everything else you chose is already on the card."), and how much space
   will be free. If something needs your choice (songs you no longer sync,
   or music that's only on the card), a box below it asks.
   Click **Details** for the counts and every change, song by song. The
   counts have a header row with the actions (**Add**, **Update**,
   **Rename**, **Remove**, **Can't Sync**), then one row per kind of
   content with something to do (**Songs**, **Audiobooks**, **Podcasts**, **Playlists**,
   **Album Covers**), with an icon and a number under each action. The
   counts say only what this sync will do. A count of 0 is greyed out, and
   a dash means the action doesn't apply (audiobooks are never renamed,
   for example); hold the pointer over a dash or a 0 to see why. A line
   below the counts says what's already on the card, what you no longer
   sync that will stay on it, and what's only on the card. The lists
   below follow the same order, after the sections that need a choice. Q2
   Sync remembers whether you left Details open. While Details is open, the
   **Filter list** box at the right of the Details line (**⌘F**) narrows the
   lists by song, artist, album or path; the counts stay the same.
3. **Nothing changes until you click Sync** (or **Sync and Remove …**, see
   below) on the preview. Click **Cancel** to leave the card as it is.
4. **Removing what you unticked:** songs, audiobooks and podcast episodes
   you no longer sync that are still on the card share one line, in its own box, with one
   **Remove It** / **Remove Them** checkbox. Nothing is removed unless you
   tick it. Unticked, the box is orange and says what you no longer sync
   will stay on the card; ticked, it turns red and says it will be deleted
   from the card, and the button reads **Sync and Remove** with the number
   of items. While the box is unticked, the Remove count under Details
   reads 0 and the line below the counts says what will stay; tick it and
   the count shows what will be removed. Removed songs, books and episodes are deleted from the card only.
   Each podcast episode to remove says why: no longer downloaded in
   Podcasts, its show isn't chosen any more, played (with **Unplayed
   only** on), or podcasts turned off for this Q2.
   They're still in your library, so ticking them again puts them back at
   the next sync. If that's more than 20% of the songs on the card, you'll
   be asked to confirm.
   With **Only put new or changed playlists in the import folder** on, the
   same box may also ask about playlists still waiting in the import folder.
   Tick **I imported them on the Q2** only if you did (see
   [Update the library on your Q2](#6-update-the-library-on-your-q2)).
5. Click **Sync**. A progress bar shows what's being copied, with an
   estimate such as "About 12 minutes remaining" once it has measured the
   copying speed (after about 10 seconds). If album covers are on, they're
   added after the music: the window then reads **Adding Album Covers…**,
   with its own progress bar, "Cover 12 of 950", and its own estimate once
   a few covers are done. Until then, the line under the bar notes "then
   950 album covers". You can click
   **Cancel** at any time; songs already copied stay, and the next sync carries
   on where it stopped.
6. When it's done, you'll see **Sync Complete** with numbered steps for what
   to do next on your Q2 (see
   [Update the library on your Q2](#6-update-the-library-on-your-q2)). Read
   them, then choose:
   - **Eject**: ejects the card and closes the window.
   - **Done**: closes the window and keeps the card connected, for example to
     sync again.
   - **Verify Card…**: checks every song on the card first (see "Verify the
     card" below; eject when it's done).

   The window only closes on **Eject** if the card was ejected; if it
   couldn't be, a message says why. If you eject it another way (the menu bar
   or a notification) while the window is open, the steps stay there until you
   click **Done**.

Every sync is recorded in a log. Click the **Show Log** link on the result, or
go to your Q2's **General** tab → **Show Sync Logs**.

**Where things go on the card:** music goes in `Music/Artist/Album/`,
playlists in `_explaylist_data/`, and Q2 Sync's own records in a hidden
`.q2sync` folder. Q2 Sync never touches the Q2's own files and folders.

**Album covers (on by default):** Apple Music often keeps artwork
in its own library rather than inside the song files, so the Q2 would show no
cover. With **Add album covers** on (your Q2's **General** tab), Q2 Sync puts a
`cover.jpg` in each album folder, made from the album's artwork in Apple
Music (resized to at most 1000 pixels, in a format the Q2 reads quickly).
The preview lists them under **Album Covers**.
- Your library is only read, never changed.
- A `cover.jpg` or `folder.jpg` you put there yourself is never replaced.
- When an album leaves the card, its cover goes too.
- Turn it on any time: the next sync adds covers for everything already on
  the card. Turn it off and the next sync removes the covers Q2 Sync added
  (listed under **Remove Covers** in the preview).

**Refresh Cover Flow after covers change (Q2 Pod).** Cover Flow keeps its
own cache of covers, so after a sync that adds or removes covers (for
example after turning the setting on or off), the Sync Complete window adds
steps to (the Q2's General tab also lists these last under **After Each
Sync**):

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
lists them under **On Card Only**, in three groups:

- **On Card Only**: songs Q2 Sync synced earlier whose track
  has since left Apple Music. The card may hold the only copy.
- **Not Put There by Q2 Sync**: music copied by hand or by another app.
- **Already in Your Library**: copies of songs your library has (see below).

Nothing happens to them unless you choose. The box at the top of the preview
has one pop-up per group:
**Leave All on Card** (the default), **Move All to Mac**, **Delete All from
Card**, or **Choose Individually**. Only with
**Choose Individually** (which opens Details) does each album and song get
its own pop-up (an album
whose songs differ shows **Mixed**). Songs are listed by album; click an album
to see its songs. Hover over a song to see its path on the card, or
right-click it to copy the path. The choices are:

| Choice | What happens |
| --- | --- |
| **Leave on Card** (default) | Nothing. |
| **Move to Mac** | Copied to your **Downloads › Q2 Recovered** folder, then deleted from the card once the copy is checked. If the copy can't be made, the song stays on the card. |
| **Delete from Card** | Deleted for good. You'll be asked to confirm. |

A line under the heading counts what you've chosen (deletes in red), and
the **Sync** button says how many files it will delete.

**Music you copied to the card yourself** (in Finder, say) is recognized on
the first sync. A file in the card's `Music` folder that's the same song as
one you sync (same title, artist and length) and exactly the same file (same
size) isn't copied again: Q2 Sync takes it over and moves it into its own
folder layout. Other copies of songs you sync (a different encoding, or
outside the `Music` folder) are listed under **Already in Your Library**;
clear them all at once with **Delete All from Card** (Move to Mac isn't
offered there, since your library already has them).

**About "Move to Mac":** Q2 Sync never puts files into your Music library. It
copies them to **Downloads › Q2 Recovered**, keeping their folders, and lists
them in `RECOVERED.txt`. To add them to Apple Music, open Music and choose
**File › Import…**. Songs already in your library aren't copied again, and
nothing in the Q2 Recovered folder is ever overwritten.

**Older versions** of Q2 Sync could move songs to a trash folder on the card.
If you used that, the folder is still there: in Finder, open the card, press
**⌘⇧.** (Command-Shift-period) to show hidden folders, and delete
`.q2sync/Trash` (including the `database.ignore` file in it).

---

## 6. Update the library on your Q2

After every sync, your Q2 needs to scan the card before new music shows up.
The Sync Complete window lists the steps that apply to that sync: the
playlist step only when playlists are ready to import, and the Cover Flow
steps only when covers changed. Your Q2's **General** tab lists them all under
**After Each Sync** while the card is connected.

1. Eject the card in Q2 Sync, then unplug the Q2 (with a card reader, put the
   card back in the Q2).
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

**Only put new or changed playlists in the import folder (off by
default):** off, every playlist stays in the card's playlist folder and Q2
Sync never takes one out, so the Q2's Import reads them all each time. That
is the safe choice: no playlist can miss an Import. Turn it on (your Q2's
**General** tab, under **Playlists**) if Import takes too long for you. Each
sync then adds only playlists that are new or changed. Q2 Sync can't see
whether you ran Import on the Q2, so when playlists from an earlier sync are
still in the folder, the sync window says how many and shows a
**I imported them on the Q2** checkbox. Tick it only if you ran Import since
that sync: the unchanged ones are then taken out. Leave it unticked and they
stay. Auto-sync never ticks it for you. Playlists already on the Q2 stay there either way. The sync result
tells you how many are ready to import. If you reset the Q2 or use a new
card, click **Put All Up for Import** under **Playlists** before syncing.

**Which playlists go on the card:** your own regular, smart and Genius
playlists, and Apple's music smart playlists (My Top Rated, Recently Played,
Recently Added, Top 25 Most Played…). Built-in lists that aren't songs
(Purchased, Movies, Podcasts, Voice Memos) and folders themselves are left
out. If two playlists share a name and one is in a folder, it's named after
the folder on the Q2, e.g. **Decades - 1980's Music**.

Q2 Sync shows these steps after each sync, for your Q2's firmware.

---

## 7. Auto-sync

Q2 Sync can notice when your Q2 connects. On your Q2's **General** tab, under
**Auto-Sync**, choose **When this Q2 connects**:

- **Ask Me (Notification)** (default): a notification asks whether to sync.
  Click **Sync Now**. (Not while Q2 Sync's window is in front: you're already
  looking at your Q2 then.) macOS asks once whether Q2 Sync may show
  notifications, the first time it has one to show.
- **Sync Automatically**: syncs straight away.
- **Do Nothing**: you sync by hand.

Automatic syncs follow every safety rule. They **never remove songs and never
eject**. If anything needs your decision (the first sync with a card, songs
you unticked, songs gone from your library, or not enough space), they stop
with the preview waiting in Q2 Sync, and notify you (see below). When an
automatic sync finishes,
a notification has **Eject** and **Verify Card** buttons. The steps for your Q2
are in the Sync Complete window, so open Q2 Sync to read them (**Verify Card**
closes that window; the steps are also under **After Each Sync** while the card
is connected).

### When Q2 Sync needs you

Some moments need your decision: an automatic sync stopped for review, a new
Q2 to set up, the **Did the Firmware Update Finish?** question, or a finished
sync that left files on the card that aren't in your library. Q2 Sync handles
them all the same way, like other Mac apps, and **never takes focus from the
app you're using**:

- **Q2 Sync is in front:** the window shows it straight away, with no
  notification.
- **You're in another app, or the window is closed:** a notification says what
  needs you, and Q2 Sync's window opens *behind* your other windows (the Dock
  icon comes back), with the preview or question ready. Click the notification
  (or **Open Q2 Sync**) to bring it forward.
- **Notifications are off for Q2 Sync:** its Dock icon also bounces, so you
  still find out. When Q2 Sync can't carry on without you (a sync stopped for
  review, setup, the firmware question), it keeps bouncing until you click
  Q2 Sync; for files on the card that aren't in your library, it bounces once.

**Tip:** so you can't miss these, set Q2 Sync's notifications to
**Persistent** in **System Settings › Notifications › Q2 Sync**. They then
stay on screen until you click or dismiss them.

For auto-sync to work, Q2 Sync must be running. It stays in the **menu bar**
when you close its window. To start it automatically, open **Q2 Sync ›
Settings** and turn on **Open Q2 Sync at login**. While auto-sync is on and
Q2 Sync doesn't open at login, the Q2's General tab also shows an **Open at
Login** button under **When this Q2 connects**. Q2 Sync doesn't ask anywhere
else.

The **menu bar item** shows whether your Q2 is connected and lets you **Sync
Now**, **Eject**, **Open Q2 Sync**, open **Settings**, the help or the About
panel, or **Quit**. It's always shown. While Q2 Sync has a Dock icon, the Dock
menu (right-click the icon) has **Sync Now** and **Eject** too.

While Q2 Sync's window is closed, its **Dock icon is hidden** and the app lives
only in the menu bar; **Open Q2 Sync** there brings the window and the Dock icon
back. The first time you close the window, Q2 Sync explains this and offers
**Keep in Menu Bar** or **Quit Q2 Sync**. Tick **Don't show again** to close the
window quietly from then on; to see it again, click **Show Menu Bar Tip Again**
in Settings.

On a Mac with a notch, or with many menu bar items, the Q2 Sync icon can be
hidden behind the notch. Quit other menu bar apps or use a menu bar manager to
make room, or open Q2 Sync from the Applications folder.

---

## 8. Firmware: install, switch and update

Q2 Sync can put **Q2 Pod** or **Shanling's stock firmware** on your card, so
you can switch between them or update. Open your Q2's **General** tab and
click **Install Firmware…** (or choose **Device → Install Firmware…**).

1. Pick **Q2 Pod** or **Shanling (stock)**. The firmware your Q2 runs now
   (as set on its General tab) is picked to start with, to update it; pick
   the other to switch. Q2 Sync shows the latest version of each: Q2 Pod's
   from GitHub, stock's from Shanling's download page.
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

**Q2 Pod:** on your Q2's **General** tab, under **Firmware Updates**, turn on
**Check GitHub for new Q2 Pod releases**. Q2 Sync checks at most once a day
when your Q2 connects (or when you click **Check Now**) and tells you about new
releases, with their notes and a link.

- Q2 Sync can't see which version your Q2 runs, so type it in under
  **Installed version** (on the Q2: **System settings → About**, shown as
  "CFW. Version"). Then it can tell you whether you're up to date.
- If you leave it blank, Q2 Sync tells you about each new release once; click
  **Dismiss** to hide it until the next one.

- When a new release is out, click **Update to …** to put it on the card.

**Shanling stock:** not checked automatically. Click **Check Now** under
**Firmware Updates** to see the latest version on Shanling's download page,
then compare it with yours (on the Q2: **System Setting → About**). **Install
V…** puts it on the card. Your Q2 can also check by itself: **System Setting →
System Update → Network update**.

**Device › Check for Firmware Updates** checks whichever firmware your Q2 runs,
even with automatic checking off. While the other firmware is on the card and
you haven't said whether the Q2 installed it, it's dimmed: answer **Did the
Firmware Update Finish?**, or click **Mark as Installed** or **Remove from
Card** on the General tab.

---

## 9. Verify the card and back up Q2 Pod data

### Verify the card

microSD cards can damage files without warning. On your Q2's **General**
tab, under **Card**, click **Verify Card…** (or **Device → Verify Card…**, or
**Verify Card…** on the Sync Complete window).
Q2 Sync reads every song it put on the card and compares it, byte for byte,
with the song on your Mac. Nothing changes while it checks.

- Damaged or missing songs are listed. Click **Copy Songs Again** to fix
  them (this goes through the same checks as a sync).
- When everything checks out (or the songs are copied again successfully),
  click **Eject** to eject the card right from the results, or **Done** to
  keep it connected.
- Songs changed on your Mac since copying aren't checked: your next sync
  updates them.
- Read your library first (the arrow at the top right).
- Checking a full card over USB takes a while; a card reader is faster.

### Back up Q2 Pod's data

> **Not yet tested on a real Q2.** Back up and restore pass their unit tests,
> but haven't been tried on a device yet. Treat them as experimental, and
> please report anything odd (see [Contributing](../CONTRIBUTING.md)).

Q2 Pod keeps some of your data on the card: song ratings, listens waiting to
be scrobbled, scrobbling and radio settings, EQ presets, custom App Store
sources and Rockbox settings. On your Q2's **General** tab, under **Q2 Pod
Data**, click **Back Up Now** to copy them to the backup folder:
**Downloads › Q2 Sync Backups** unless you click **Change…** next to
**Backup folder** and choose another (one folder for all your Q2s; not your
Music folder or the card). **Use Default** goes back to Downloads. If the
folder you chose is on a drive that isn't connected, Back Up Now waits until
it is (or until you choose another). To put them on a card (for example a new one), click
**Restore…**, choose a backup and tick what to restore, then restart the Q2.
Both are also in the **Device** menu.

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
- **Eject** in the menu bar item, or
- **Device › Eject** (**⌘E**), or right-click your Q2 in the sidebar, or
- **Eject** in the Dock menu (right-click Q2 Sync's Dock icon).

If Q2 Sync's window isn't in front (you ejected from the menu bar item, the
Dock menu or a notification, say), a notification tells you whether the card was ejected;
click it to open Q2 Sync.

If ejecting fails, Q2 Sync says so and the card stays connected. Close any
Finder windows showing the card and try again.

Ejecting or plugging in a different drive (another card, a USB stick)
while a sync runs doesn't affect the Q2 being synced, and the sidebar shows
the change straight away.

---

## 11. Frequently asked questions

**Which version of Q2 Sync do I have?** Choose **Q2 Sync › About Q2 Sync**.
It shows the version and build, for example `Version 0.1 (142 · 0e7d893)`.
Mention it when you report a problem. The same panel links to Q2 Sync on
GitHub and to its license. For a newer version, see
[New versions of Q2 Sync](#new-versions-of-q2-sync).

**Why can't this audiobook be synced?**
It's protected (DRM), or its files can't be read. (A book that isn't
downloaded doesn't appear at all: download it in Apple Books.) Hover over
the reason on the **Audiobooks** tab. Most audiobooks from the Apple Books
store are protected and only play in Apple's apps; a DRM-free copy you add to
Apple Books (**File › Add to Library**) syncs.

**I played an episode on the Q2. Why is it still unplayed on my Mac?**
Q2 Sync only reads the Podcasts app: Apple doesn't offer a way for other
apps to change it, and its library syncs with your iPhone through iCloud, so
writing to it could cause trouble. Mark the episode played on your Mac or
iPhone instead. With Apple's default setting (**Remove Played Downloads**),
the Podcasts app removes the download within about a day, and the next sync
removes the episode from the card if you tick **Remove Them**. With
**Unplayed only** on, a played episode is removed at the next sync straight
away.

**Why can't this podcast episode be synced?**
It's a video episode (video podcasts aren't synced yet) or it's protected,
like some episodes from paid subscriptions. An episode that isn't downloaded
doesn't appear at all: download it in the Podcasts app.

**Can Q2 Sync change my Apple Books library?**
No. It only reads Apple Books' folder, with a read-only permission you give
once.

**Can Q2 Sync damage my Apple Music library?**
No. It only reads your library, and macOS itself prevents it from writing to
your Music folder. It still makes sense to keep a backup of your Mac, as with
any app.

**Does the Music app need to be open?**
No. Q2 Sync reads your library through a macOS service that starts by itself
when it's needed. Music you add or change shows up after **Refresh Library**,
or at your next sync.

**It says "The Music library isn't responding".**
Reading your library normally takes a few seconds; after 30 seconds, Q2 Sync
stops waiting and says so, and nothing is synced. Click **Try Again** (at the
bottom of the sidebar). If it keeps happening, open the Music app, or restart
your Mac. To restart just the library service instead, run
`killall AMPLibraryAgent` in Terminal (macOS starts it again by itself).

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
catalog can't be copied. To get a song onto your Q2, buy it (the iTunes
Store sells DRM-free files) or add your own copy to the Music app.

**I unticked an album but it's still on my Q2.**
Removals are always your choice. Tick **Remove Them** in the preview.

**I deleted a song in Apple Music. What happens to the copy on the card?**
It's listed under **On Card Only**, so you
can move it to your Mac or delete it.

**What happens to music I copied onto the card myself?**
It's left alone unless you choose otherwise under **On Card Only**. Q2 Sync
never overwrites it.

**My new music doesn't show on the Q2.**
Run **Update Library** on the Q2 (see section 6).

**The card is full.**
The capacity bar warns you. Untick some music, or allow removals in the preview.
Q2 Sync always leaves 200 MB free for the Q2's own use.

**What are the `.q2sync` and `_explaylist_data` folders on the card?**
`.q2sync` holds Q2 Sync's record of what it copied.
`_explaylist_data` holds playlists for the Q2 to import. Please don't edit
`.q2sync/manifest.json`. If it ever gets damaged, delete it: the next sync
rebuilds it without copying identical songs again.

**Can I rename my card?**
Yes. In Finder, Control-click the card in the sidebar, choose **Rename**, type
the new name and press Return. Q2 Sync recognizes the card by its unique ID, not
its name. Renaming doesn't erase anything; erasing the card in Disk Utility
does, and Q2 Sync then sees it as a new card.

**Can I use the same card with another Mac?**
Yes. The record of what's on the card lives on the card itself.

**Where are the logs?**
Choose **Help › Show Sync Logs**, or click **Show Sync Logs** on your Q2's
**General** tab.

**I clicked "Not My Q2" by mistake.**
**Q2 Sync › Settings → Ask Again About "Not My Q2" Drives**.

---

## 12. Keyboard shortcuts

| Shortcut | What it does |
| --- | --- |
| **⌘0** | Open the Q2 Sync window |
| **⌘1** to **⌘4** | Show Artists, Albums, Genres or Playlists |
| **⌘5** | Show your Q2 |
| **⌘6** | Show Books (when the sidebar has an Audiobooks section) |
| **⌘7** | Show Episodes (when the sidebar has a Podcasts section) |
| **⌘8** | Show Albums (when the sidebar has a Photos section) |
| **⌘R** | Refresh the Music library |
| **⇧⌘R** | Show the selected songs in Finder |
| **⌘F** | Search your library, or filter the Music tab or the sync preview |
| **⌘**-click a checkbox | On the Music tab, tick or untick every item shown |
| **⌘I** | Show or hide Song Info, Book Info on Books, Episode Info on Episodes, or Photo Info on Albums |
| **⇧⌘S** | Sync Now |
| **⌘E** | Eject |
| **⌘,** | Settings |
| **⌘?** | This guide |
| **⌘Q** | Quit Q2 Sync |
