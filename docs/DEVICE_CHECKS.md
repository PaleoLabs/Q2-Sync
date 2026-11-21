# Checks to Do on a Real Q2

Q2 Sync was built before a Q2 was available. These items are based on
documentation (Shanling's Quick Start Guide and Q2 Pod's docs and user guide,
release 1.8.5) and still need confirming on a real device. Work through them
once for **Q2 Pod** and once for **stock** firmware, then update the matching
`DeviceProfile` in `Q2-Sync/Core/Device/DeviceProfile.swift`.

## 1. Songs scan and play

1. Sync a few albums, eject, unplug.
2. On the Q2: Library → Update Library → Scan music now (stock: Local Songs →
   Update Library → Scan music now).
3. Check:
   - [ ] Albums, artists and track order look right (tags, not folder names).
   - [ ] Multi-disc albums show as one album.
   - [ ] Album art shows.
   - [ ] Names with accents or non-English characters display correctly.
   - [ ] No “._” or broken entries appear.
   - [ ] Nothing from `.q2sync/Trash` appears (Q2 Pod hides it via
         `database.ignore`; **stock firmware may not**).

## 2. Playlist format

The current guess (`PlaylistFormat.documentedQ2Format`):

| Setting | Current value |
| --- | --- |
| Folder | `_explaylist_data/` at the card root |
| Extension | `.m3u` |
| Encoding | UTF-8, no byte-order mark |
| Line endings | CRLF |
| Header lines | `#EXTM3U`, and `#EXTINF:<seconds>,<Artist> - <Title>` per song |
| Paths | `/mnt/mmc/Music/<Artist>/<Album>/<file>` |

Steps:

1. On the Q2, make a playlist with 2–3 songs, including one with an accented
   or non-English name. Export it (Q2 Pod: Library → Playlists → Select
   Playlists… → Export; stock: the Playlists menu).
2. Connect the Q2 to the Mac (USB Storage) and look in `_explaylist_data/`.
3. Inspect the exported file without changing it:
   ```bash
   cd "/Volumes/<card>/_explaylist_data"
   file "<playlist>.m3u"
   xxd "<playlist>.m3u" | head -20
   ```
4. Compare it with the table above: encoding (UTF-8, GBK, UTF-16?), BOM,
   line endings (`0d 0a` = CRLF, `0a` = LF), path style (`/mnt/mmc/...` or
   `A:\...`), header lines.
5. Then test Q2 Sync's playlists: sync one playlist, and on the Q2 choose
   Library → Playlists → Import.
   - [ ] It imports, with every song playable.
   - [ ] Accented or non-English song names work.
   - [ ] Re-importing replaces the playlist instead of duplicating it.
6. If anything differs, change `PlaylistFormat` for that firmware and set
   `isVerifiedOnDevice: true`.

## 3. Menu wording

- [ ] Stock firmware: the exact menu path for importing playlists (the
      reminder currently says “open Playlists and choose Import”).
- [ ] Where each firmware shows its version (Q2 Pod: System settings → About,
      “CFW. Version”).

## 4. USB connection

- [ ] With the quick-access switch on **USB Storage**, the card mounts on the
      Mac and Q2 Sync recognises it as the same card as in a card reader (same
      volume ID).
- [ ] Eject from Q2 Sync works while the Q2 is connected.

## 5. Telling the firmware apart over USB

Neither firmware records its version on the card, so the only other way to
tell them apart is what the Q2 reports over USB (USB Storage mode).

Stock **V1.36**, read 2026-11-21 with `system_profiler SPUSBHostDataType`
and `ioreg`:

| Field | Value |
| --- | --- |
| USB vendor / product ID | `0x0525` / `0xa4a5` (Linux USB storage gadget) |
| USB manufacturer / product | `ingenic` / `composite-storage` |
| USB serial number | `ingenic-storage` |
| USB product version (`bcdDevice`) | `0x0100` |
| SCSI vendor / product / revision | `Linux` / `File-Stor Gadget` / `0510` |

- [ ] Read the same fields on Q2 Pod. If any differ, Q2 Sync can detect the
      firmware on connect. Q2 Pod's docs say its kernel is byte-identical to
      stock (both firmware files carry the same kernel checksum), so they're
      expected to match.
- [ ] Q2 Sync's device header says **Connected by USB** for the Q2 on a
      cable and **In a card reader** for the card in a reader.

## 6. Q2 Pod data on the card

- [ ] After rating a song, scrobbling and saving a radio favourite on the
      Q2, `.ratings.tsv`, `.scrobbler.log`, `.scrobble.ini` and
      `Radio/favourites.m3u` appear on the card (paths from Q2 Pod's docs).
- [ ] After **Restore…** onto a fresh card and a restart, Q2 Pod shows the
      restored ratings, favourites and EQ presets.

## 7. Installing firmware

- [ ] Stock firmware: the menu is **System Setting → System Update → TF card
      update** (the wording is assumed from Q2 Pod's docs, which reuse stock's
      System Update page).
- [ ] After a TF card update, is `update.tar` still on the card? (Q2 Pod's
      docs suggest it stays.) Q2 Sync offers to remove it when you confirm
      the update finished.
- [ ] Stock → Q2 Pod and Q2 Pod → stock both work with the file Q2 Sync
      copied.
