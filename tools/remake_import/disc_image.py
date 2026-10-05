"""Disc image formats the converter reads (docs/remake-plan.md, "Discs").

A disc is its data track, seen as raw 2352-byte Mode 2 sectors, and its audio tracks:

- a `.cue` sheet: its tracks' files, one per track or shared at the tracks' INDEX positions. A
  file the sheet names but that is missing is looked for compressed next to it under the same
  name (`.bin.ecm`, `.ecm`, `.ape`, `.flac`, `.wav`), as compressed sets keep the original sheet;
- a data track alone: raw `.bin`/`.img` (2352-byte sectors), `.ecm` (read in place,
  compare_japan_revisions.ECMImage), or `.iso` (2048-byte sectors: only the Form 1 files; the XA
  music and the movies are Form 2 and not in such an image). Its audio tracks are looked for by
  the Redump naming, `(Track 1)` → `(Track n)`;
- a `.chd`: extracted to BIN/CUE in a temporary folder by MAME's `chdman`, when on the PATH.

Audio tracks are raw 16-bit stereo PCM files, or any format FFmpeg decodes (APE, FLAC, WAV).
"""

from __future__ import annotations

import hashlib
import logging
import mmap
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from compare_bns import SECTOR_BYTES
from compare_japan_revisions import ECMImage

PAYLOAD_BYTES = 2048
SYNC = b"\x00" + b"\xff" * 10 + b"\x00"
ECM_MAGIC = b"ECM\0"
COMPRESSED_SUFFIXES = (".ecm", ".ape", ".flac", ".wav")
TRACK_FILE = re.compile(r"^\s*FILE\s+(?:\"(.+)\"|(\S+))\s+\S+\s*$", re.I)
TRACK_LINE = re.compile(r"^\s*TRACK\s+(\d+)\s+(\S+)", re.I)
INDEX_LINE = re.compile(r"^\s*INDEX\s+(\d+)\s+(\d+):(\d+):(\d+)", re.I)
FRAMES_PER_SECOND = 75
MODE2_FORM1_SUBHEADER = b"\x00\x00\x08\x00" * 2
RAW_SUFFIXES = (".bin", ".raw", ".img")
HASH_CHUNK = 1 << 22
CHD_SHEET = "disc.cue"                 # the sheet chdman writes in the extraction folder

log = logging.getLogger("remake_import")


class ImageError(Exception):
    """The image cannot be read (format, missing track files, missing tools)."""


class IsoSectors:
    """A 2048-byte-sector ISO seen as raw Mode 2 Form 1 sectors (sync, header and subheader
    synthesised, no EDC/ECC): what the ISO 9660 reader needs."""

    def __init__(self, data: mmap.mmap) -> None:
        self.data = data

    def __len__(self) -> int:
        return len(self.data) // PAYLOAD_BYTES * SECTOR_BYTES

    def __getitem__(self, key: slice) -> bytes:
        start, stop, _ = key.indices(len(self))
        out = bytearray()
        while start < stop:
            sector, offset = divmod(start, SECTOR_BYTES)
            raw = (SYNC + bytes(3) + b"\x02" + MODE2_FORM1_SUBHEADER
                   + self.data[sector * PAYLOAD_BYTES:(sector + 1) * PAYLOAD_BYTES] + bytes(280))
            take = min(stop - start, SECTOR_BYTES - offset)
            out += raw[offset:offset + take]
            start += take
        return bytes(out)


@dataclass(frozen=True)
class AudioTrack:
    """An audio track: its file and its bytes there (from its pregap; `end` None: to the end)."""

    path: Path
    start: int = 0
    end: int | None = None


@dataclass
class DiscImage:
    """An opened disc: `sectors` is the data track as raw 2352-byte sectors (sliceable)."""

    path: Path                          # what was given (a sheet, a track, a CHD)
    data_file: Path                     # the data track's file
    sectors: object
    xa: bool                            # False for an ISO: no Form 2 sectors (music, movies)
    audio: dict[int, AudioTrack] = field(default_factory=dict)
    _handles: list = field(default_factory=list)
    _extraction: tempfile.TemporaryDirectory | None = None   # a CHD's BIN/CUE (_chd)

    def sha256(self) -> str:
        """The SHA-256 of the data track's file (as stored: an ECM file's own bytes)."""
        digest = hashlib.sha256()
        with self.data_file.open("rb") as stream:
            for chunk in iter(lambda: stream.read(HASH_CHUNK), b""):
                digest.update(chunk)
        return digest.hexdigest()

    def audio_pcm(self, number: int, ffmpeg: str | None) -> bytes:
        """Audio track `number` as 16-bit stereo 44.1 kHz PCM from its pregap (as a raw track file
        holds it), in whole sectors."""
        track = self.audio.get(number)
        if track is None:
            raise ImageError(f"audio track {number} of {self.path.name} not found")
        if track.path.suffix.lower() in RAW_SUFFIXES:
            with track.path.open("rb") as stream:
                stream.seek(track.start)
                data = stream.read() if track.end is None else stream.read(track.end - track.start)
        else:
            if ffmpeg is None:
                raise ImageError(f"audio track {number} ({track.path.name}) needs FFmpeg to decode")
            result = subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-i", str(track.path),
                                     "-f", "s16le", "-ac", "2", "-ar", "44100", "-"], capture_output=True)
            if result.returncode:
                raise ImageError(f"FFmpeg cannot decode {track.path.name}: {result.stderr.decode(errors='replace')}")
            data = result.stdout[track.start:track.end]
        return data[:len(data) // SECTOR_BYTES * SECTOR_BYTES]

    def close(self) -> None:
        for handle in reversed(self._handles):
            handle.close()
        self._handles.clear()
        if self._extraction is not None:
            self._extraction.cleanup()
            self._extraction = None


def _existing(path: Path) -> Path | None:
    """`path`, or its compressed form next to it (`X.bin` → `X.bin.ecm`, `X.ecm`, `X.ape`, …)."""
    candidates = [path, path.with_name(path.name + ".ecm")]
    candidates += [path.with_suffix(suffix) for suffix in COMPRESSED_SUFFIXES]
    return next((c for c in candidates if c.exists()), None)


def _cue_tracks(sheet: Path) -> tuple[Path, dict[int, AudioTrack]]:
    """The data track's file and the audio tracks of a sheet: one file per track, or tracks
    sharing a file at their INDEX positions (the data track first)."""
    tracks: list[dict] = []
    current = None
    for line in sheet.read_text(errors="replace").splitlines():
        if m := TRACK_FILE.match(line):
            named = sheet.parent / (m.group(1) or m.group(2))
            current = _existing(named)
            if current is None:
                raise ImageError(f"{sheet.name}: track file {named.name} not found (nor compressed)")
        elif (m := TRACK_LINE.match(line)) and current is not None:
            tracks.append({"number": int(m.group(1)), "kind": m.group(2).upper(), "file": current, "index": {}})
        elif (m := INDEX_LINE.match(line)) and tracks:
            minutes, seconds, frames = (int(g) for g in m.groups()[1:])
            position = ((minutes * 60 + seconds) * FRAMES_PER_SECOND + frames) * SECTOR_BYTES
            tracks[-1]["index"][int(m.group(1))] = position
    data = [t for t in tracks if t["kind"] != "AUDIO"]
    if len(data) != 1:
        raise ImageError(f"{sheet.name}: expected one data track, found {len(data)}")
    if data[0]["index"].get(1, 0):
        raise ImageError(f"{sheet.name}: the data track does not start its file")

    def start(t: dict) -> int:
        return t["index"].get(0, t["index"].get(1, 0))

    audio = {}
    for k, t in enumerate(tracks):
        if t["kind"] != "AUDIO":
            continue
        # A file's first track starts it (its pregap included, as in a track of its own).
        first = all(u["file"] != t["file"] for u in tracks[:k])
        following = next((u for u in tracks[k + 1:] if u["file"] == t["file"]), None)
        audio[t["number"]] = AudioTrack(t["file"], 0 if first else start(t), start(following) if following else None)
    return data[0]["file"], audio


def _neighbour_tracks(track1: Path) -> dict[int, AudioTrack]:
    """The audio tracks next to a data track by the Redump naming, `(Track 1)` → `(Track n)`."""
    audio = {}
    if "(Track 1)" not in track1.name:
        return audio
    base = track1.name.removesuffix(".ecm")
    for number in range(2, 100):
        found = _existing(track1.with_name(base.replace("(Track 1)", f"(Track {number})")))
        if found is None:
            break
        audio[number] = AudioTrack(found)
    return audio


def _chd(path: Path) -> tempfile.TemporaryDirectory:
    """A CHD extracted by chdman to `disc.cue` and its tracks in a temporary folder, removed when
    the image closes."""
    chdman = shutil.which("chdman")
    if chdman is None:
        raise ImageError(f"{path.name}: a CHD needs MAME's chdman on the PATH (or convert it to BIN/CUE)")
    temp = tempfile.TemporaryDirectory(prefix="t3chd")
    log.info("extracting %s with chdman", path.name)
    result = subprocess.run([chdman, "extractcd", "-i", str(path), "-o", str(Path(temp.name) / CHD_SHEET)],
                            capture_output=True)
    if result.returncode:
        temp.cleanup()
        raise ImageError(f"chdman cannot extract {path.name}: {result.stderr.decode(errors='replace')}")
    return temp


def open_image(path: Path) -> DiscImage:
    """Opens a disc image of any supported format; the caller closes it."""
    if not path.exists():
        raise ImageError(f"disc image not found: {path}")
    extraction = _chd(path) if path.suffix.lower() == ".chd" else None
    try:
        return _open(path, extraction)
    except BaseException:
        if extraction is not None:
            extraction.cleanup()
        raise


def _open(path: Path, extraction: tempfile.TemporaryDirectory | None) -> DiscImage:
    """The image from its sheet (a CHD's extracted one), or its data track."""
    if extraction is not None:
        data, audio = _cue_tracks(Path(extraction.name) / CHD_SHEET)
    elif path.suffix.lower() == ".cue":
        data, audio = _cue_tracks(path)
    else:
        data, audio = path, _neighbour_tracks(path)
    stream = data.open("rb")
    view = mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ)
    handles = [stream, view]
    if view[:4] == ECM_MAGIC:
        sectors, xa = ECMImage(view), True
    elif view[:12] == SYNC and len(view) % SECTOR_BYTES == 0:
        sectors, xa = view, True
    elif len(view) % PAYLOAD_BYTES == 0:
        sectors, xa = IsoSectors(view), False
    else:
        for handle in reversed(handles):
            handle.close()
        raise ImageError(f"{data.name}: not a raw 2352-byte-sector, ECM or ISO data track")
    return DiscImage(path, data, sectors, xa, audio, handles, extraction)
