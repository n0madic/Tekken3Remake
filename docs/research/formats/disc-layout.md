# CD, ISO 9660, and cross-track layout

## Raw data track

Japan Rev.1 and USA Track 1 contain raw 2,352-byte CD-ROM Mode 2 sectors. The sync pattern, address/mode bytes, duplicated XA subheader, and Primary Volume Descriptor at LBA 16 were checked. Ordinary ISO files such as the EXE and BNS use Form 1 sectors with a 2,048-byte payload at raw offset 24. Original Japan SLPS-01300 is stored as ECM and was read through virtual sectors without writing an unpacked image. It yields 270,799 raw sectors; the reconstructed ECC/EDC and ECM trailer checksum have not been validated.

Original Japan Track 1 has 270,799 virtual sectors; Japan Rev.1 has 270,795 (`636,909,840 / 2352`), and USA has 268,934 (`632,532,768 / 2352`). An ISO reader must strip raw Form 1 sectors to 2,048-byte payloads; a `.bin` file cannot be read as a plain 2,048-byte-sector ISO. That transformation does not apply to XAS as a whole: preserve each raw Mode 2 sector and use its XA submode to distinguish Form 1 and Form 2 payloads.

For original Japan, the ECM run types and in-memory virtual sector layout were checked. Its XAS ISO user-payload SHA-256 equals Rev.1, and the XA-subheader sequence matches for all 251,473 XAS sectors. This does not extend to the EXE/BNS or replace full ECM checksum validation.

## CUE and CDDA

Each CUE describes three tracks:

- Track 1: `MODE2/2352`, `INDEX 01 00:00:00`.
- Track 2: `AUDIO`, `INDEX 00 00:00:00`, `INDEX 01 00:02:00` (150-sector pregap).
- Track 3: `AUDIO` with the same pregap scheme.

APE Tracks 2/3 from original Japan were decoded to PCM through a pipe. Both decoded streams match raw CDDA Tracks 2/3 in Japan Rev.1 and USA byte for byte. The supplied `.ape` and `.ecm` files were not modified.

Track 2 and Track 3 files contain 11,778 and 11,923 CDDA frames of 2,352 bytes. The ISO 9660 entries `TEKKEN3.DA` and `TEKKEN3.DMY` address positions beyond Track 1. Their LBAs match INDEX 01 of the two audio tracks exactly:

| Release | End of Track 1 / start of next track | Entry | Address calculation | ISO entry size |
|---|---:|---|---|---:|
| Japan Rev.1 | 270795 | `DA` | 270795 + 150 = 270945 | 11628 × 2048 = 23,814,144 |
| Japan Rev.1 | 270795 | `DMY` | 270795 + 11778 + 150 = 282723 | 11773 × 2048 = 24,111,104 |
| USA | 268934 | `DA` | 268934 + 150 = 269084 | 11628 × 2048 = 23,814,144 |
| USA | 268934 | `DMY` | 268934 + 11778 + 150 = 280862 | 11773 × 2048 = 24,111,104 |

Each ISO entry length equals the number of audio frames after its 150-sector pregap multiplied by 2,048. The audio `.bin` files themselves store 2,352-byte frames. Therefore `DA/DMY` cannot be extracted with an ordinary “2,048 bytes per data-track sector” reader, nor by reading beyond the Track 1 file. A CUE-aware reader must switch to the appropriate audio track.

**Finding:** exact addresses, sector counts, and matching Japan/USA audio establish the connection between `DA/DMY` and Tracks 2/3. The game never opens these entries: the executable names only `\TEKKEN3.BNS;1` and `\TEKKEN3.XAS;1`, and it finds CD-DA positions with `DsGetToc` (`0x800A0B40`).

- Track 2 (`DA`, 157 s) is the only CD-DA music: music track 4 (STAFF ROLL) plays CD-DA entry 2 in both soundtrack variants ([sound.md](../code/sound.md#music)).
- Track 3 (`DMY`, 159 s) is digital silence in its entirety and is never played; it is a dummy track.

## Observed ISO layout

- Volume label: `TEKKEN3`.
- Japan Rev.1 root: `SLPS_013.00`, `SYSTEM.CNF`, `TEKKEN3.BNS`, `TEKKEN3.DA`, `TEKKEN3.DMY`, `TEKKEN3.XAS`.
- USA root: `SYSTEM.CNF` and directory `TEKKEN3`, which contains `SLUS_004.02`, `TEKKEN3.BNS`, `TEKKEN3.DA`, `TEKKEN3.DMY`, `TEKKEN3.XAS`.
- Boot strings: Japan `BOOT = cdrom:\SLPS_013.00;1`; USA `BOOT = cdrom:\TEKKEN3\SLUS_004.02;1`.

These values were read statically from the local images. Direct inspection of the XAS extent found Mode 2 and correctly repeated XA subheaders in every sector, with both Form 1 and Form 2 sectors in the range. Public Japan Rev.1 checksum comparison appears in the [disc catalog](../disc-variants.md).
