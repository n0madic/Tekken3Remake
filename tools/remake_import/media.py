"""Music and movies → formats Godot plays natively (sound effects: sounds.py).

- **Music** (`--no-music` skips it): the XA streams of the music tracks the remake uses, from
  `TEKKEN3.XAS` (the executable's 50-row stream table and the track table, sound.md#music) or,
  for the staff roll, the disc's CD-DA track 2 (its file in the cue sheet or next to track 1, raw
  or in any format FFmpeg decodes: disc_image.py), decoded with FFmpeg (`psxstr` demuxer,
  `adpcm_xa`) and stored as Ogg Vorbis at the stream's rate. `music/music.json` maps each track
  to its ARRANGE and ARCADE stream with the loop flag and volume; the player loops the whole
  stream, as the XA driver restarts it.
- **Movies** (`--no-movies` skips them): the STR movies the remake plays, decoded with FFmpeg
  (`mdec`, `adpcm_xa`) into Ogg Theora + Vorbis at MOVIE_FPS, each frame shown from the first
  grid frame at or after the CD sector at which it arrives (150 sectors per second), in two
  qualities: `movies/<name>.large.ogv` for desktop builds and `movies/<name>.small.ogv` for web
  and mobile builds (each export preset excludes the other). `movies/movies.json` lists them,
  preferred first, with the picture size, volume and duration: `title` the opening movies,
  `ending` ending.ovl's list (the endings and the Theater's movies, with each decoded frame's
  first slot of the `fps` grid, which the captions follow). Their captions are
  `movies/captions.json` (captions.py), which also says which movie shows which caption set.

FFmpeg is looked for in every directory of the `PATH` (or given with `--ffmpeg`); the first one
with the Theora and Vorbis encoders is used. Without them the fallback needs no codec in the
engine: music becomes WAV (QOA at import; looping tracks get a `smpl` loop over the whole
stream) and a movie becomes `movies/<name>.bin`, its frames as JPEG with the sector at which
each arrives, plus the audio as `movies/<name>.wav`.
"""

from __future__ import annotations

import io
import json
import math
import os
import shutil
import struct
import subprocess
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path
from typing import NamedTuple

import captions
from common import Block, Disc, Output, log
from disc_image import ImageError
from compare_bns import SECTOR_BYTES
import inspect_xas

XA_TABLE = 0x80024FE4            # 50 × (start group, end group, channel)
XA_ROWS = 50
TRACK_TABLE = 0x8002523C         # per track 2 × (stream byte, loop | volume byte)
CD_DA = 0x80
LOOP = 0x80
VOLUME_MASK = 0x7F
STREAM_INTERLEAVE = 8
SECTORS_PER_SECOND = 150         # double-speed CD
STR_MAGIC, STR_TYPE = 0x0160, 0x8001
STR_HEADER = 24                  # user data offset of a raw Mode 2 sector
MOVIE_MAGIC = b"T3MV"
MOVIE_VERSION = 1
MOVIE_TAIL = 0.05                # seconds the last frame stays after it arrives
MOVIE_FPS = 30                   # Theora is constant-rate; frames arrive every 6–10 sectors
JPEG_QUALITY = 3                 # FFmpeg -q:v (2 best … 31 worst)
THEORA_QUALITIES = {             # libtheora -q:v (0 worst … 10 best) per movie variant
    "large": 8,                  # desktop: close to the MDEC frames (PSNR ≈ 40 dB on the opening)
    "small": 6,                  # web and mobile: ~40 % smaller, fine detail softened (≈ 36.5 dB)
}
VORBIS_QUALITY = 4               # libvorbis -q:a (−1 worst … 10 best), music and movie sound: ≈ 125 kbit/s from the
                                 # 4-bit XA-ADPCM source (≈ 300 kbit/s); q6 was ≈ 186
THEORA, VORBIS = "libtheora", "libvorbis"
TITLE_SECTORS = 0x800B9E38       # title.ovl (the opening movies): 16-byte rows: first, last XAS sector
TITLE_MOVIES = 0x800BA28C        # 16-byte descriptors: row, width, height, last frame, volume, flags
MOVIE_WHITE_END = 0x8            # descriptor flag: the screen turns white when the movie ends
MOVIE_CAPTIONS = 0xF00           # descriptor flags: the caption set shown over the movie (0 none)
DESCRIPTOR_FLAGS = 0x0A          # the flags' place in a 16-byte movie descriptor
ENDING_SECTORS = 0x800B9378      # ending.ovl (the endings and the Theater's movies): the same rows as the title's
ENDING_MOVIES = 0x800B97CC       # the same 16-byte descriptors as the title's
ENDING_MOVIE_COUNT = 25
CD_DA_RATE = 44100

class MediaError(RuntimeError):
    pass


@dataclass(frozen=True)
class FFmpeg:
    path: str
    encoders: frozenset[str]

    def can_encode(self, *names: str) -> bool:
        return all(n in self.encoders for n in names)

    @property
    def ogg(self) -> bool:
        """Music as Ogg Vorbis and movies as Ogg Theora (otherwise WAV and JPEG frames)."""
        return self.can_encode(THEORA, VORBIS)

    def run(self, args: list[str]) -> None:
        result = subprocess.run([self.path, "-hide_banner", "-loglevel", "error", "-y", *args], capture_output=True)
        if result.returncode:
            raise MediaError(result.stderr.decode(errors="replace"))


def _encoders(path: str) -> frozenset[str]:
    """The encoder names an FFmpeg lists; none when it cannot be run."""
    try:
        result = subprocess.run([path, "-hide_banner", "-encoders"], capture_output=True, text=True)
    except OSError as e:
        log.warning("FFmpeg %s cannot be run: %s", path, e)
        return frozenset()
    if result.returncode:
        return frozenset()
    # " V....D libtheora  libtheora Theora (codec theora)": flags, then the encoder name.
    return frozenset(line.split()[1] for line in result.stdout.splitlines()
                     if len(line.split()) > 1 and len(line.split()[0]) == 6)


def find_ffmpeg(explicit: Path | None = None) -> FFmpeg:
    """The given FFmpeg, or the first one on the PATH that encodes Theora and Vorbis (else the first one)."""
    if explicit is not None:
        candidates = {explicit.resolve(): explicit}
    else:
        # Every PATH folder in turn; `which` adds the platform's executable suffixes (ffmpeg.exe).
        candidates = {}
        for folder in os.environ.get("PATH", "").split(os.pathsep):
            found_path = shutil.which("ffmpeg", path=folder or ".")
            if found_path is not None:
                candidates.setdefault(Path(found_path).resolve(), Path(found_path))
    found = [FFmpeg(str(path), _encoders(str(path))) for path in candidates.values()]
    found = [f for f in found if f.encoders]
    if not found:
        if explicit is not None:
            raise MediaError(f"--ffmpeg {explicit}: not a working FFmpeg")
        raise MediaError("FFmpeg is required for music and movies (or use --no-music --no-movies)")
    choice = next((f for f in found if f.ogg), found[0])
    if choice.ogg:
        log.info("FFmpeg %s: Ogg Vorbis music, Ogg Theora movies", choice.path)
    else:
        log.warning("FFmpeg %s has no %s / %s encoder: WAV music and JPEG-frame movies", choice.path, THEORA, VORBIS)
    return choice


def _xas(disc: Disc) -> tuple[object, int]:
    """The data track's raw sectors and the LBA of the XA file (TEKKEN3.XAS)."""
    if not disc.image.xa:
        raise MediaError(f"{disc.image.data_file.name} has no XA sectors (an ISO): use a raw or ECM image, "
                         "or convert with --no-music --no-movies")
    lba, _ = inspect_xas.locate(disc.image.sectors, disc.release.xas_path)
    return disc.image.sectors, lba


def _decode(tool: FFmpeg, raw: bytes, args: list[str]) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / "in.str"
        source.write_bytes(raw)
        tool.run(["-f", "psxstr", "-i", str(source), *args])


def _pcm(tool: FFmpeg, raw: bytes) -> tuple[bytes, int, int]:
    """16-bit PCM, rate and channel count of the XA audio in raw sectors."""
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "audio.wav"
        _decode(tool, raw, ["-map", "0:a:0", "-c:a", "pcm_s16le", str(out)])
        with wave.open(str(out), "rb") as w:
            return w.readframes(w.getnframes()), w.getframerate(), w.getnchannels()


def _vorbis(tool: FFmpeg, pcm: bytes, rate: int, channels: int) -> bytes:
    with tempfile.TemporaryDirectory() as tmp:
        source, dest = Path(tmp) / "in.wav", Path(tmp) / "out.ogg"
        source.write_bytes(wav_bytes(pcm, rate, channels))
        tool.run(["-i", str(source), "-c:a", VORBIS, "-q:a", str(VORBIS_QUALITY), str(dest)])
        return dest.read_bytes()


def wav_bytes(pcm: bytes, rate: int, channels: int, loop: tuple[int, int] | None = None) -> bytes:
    """A 16-bit WAV, with a `smpl` forward loop (end exclusive) when given."""
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)
    data = bytearray(buffer.getvalue())
    if loop is not None:
        start, end = loop
        body = struct.pack("<9I", 0, 0, round(1e9 / rate), 60, 0, 0, 0, 1, 0)
        body += struct.pack("<6I", 0, 0, start, end - 1, 0, 0)
        data += b"smpl" + struct.pack("<I", len(body)) + body
        struct.pack_into("<I", data, 4, len(data) - 8)
    return bytes(data)


def convert_music(disc: Disc, out: Output, tool: FFmpeg, tracks: list[int]) -> None:
    rows = [disc.exe_u32(XA_TABLE + 12 * i, 3) for i in range(XA_ROWS)]
    image, lba = _xas(disc)
    table = {}
    done: set[int] = set()
    for track in tracks:
        variants = []
        for variant in range(2):
            stream_byte, flags = disc.exe_u8(TRACK_TABLE + 4 * track + 2 * variant, 2)
            cd_da = bool(stream_byte & CD_DA)
            kind = "cdda" if cd_da else "xa"
            name = f"{kind}_{stream_byte & ~CD_DA:02d}.{'ogg' if tool.ogg else 'wav'}"
            if stream_byte not in done:
                if cd_da:
                    # The staff roll's audio track of the disc (its own image file).
                    pcm, rate, channels = _cd_da(disc, tool, stream_byte & ~CD_DA), CD_DA_RATE, 2
                else:
                    start, end, channel = rows[stream_byte]
                    raw = b"".join(image[(lba + s + channel) * SECTOR_BYTES:(lba + s + channel + 1) * SECTOR_BYTES]
                                   for s in range(start, end + 1, STREAM_INTERLEAVE))
                    pcm, rate, channels = _pcm(tool, raw)
                frames = len(pcm) // (2 * channels)
                if tool.ogg:
                    out.write(f"music/{name}", _vorbis(tool, pcm, rate, channels))
                else:
                    out.write(f"music/{name}", wav_bytes(pcm, rate, channels, (0, frames) if flags & LOOP else None))
                done.add(stream_byte)
                log.info("music track %d: %s stream %d, %.1f s", track, kind, stream_byte & ~CD_DA, frames / rate)
            variants.append({"file": name, "loop": bool(flags & LOOP), "volume": flags & VOLUME_MASK})
        table[str(track)] = variants
    out.write_json("music/music.json", {"tracks": table})


def _cd_da(disc: Disc, tool: FFmpeg, number: int) -> bytes:
    """An audio track of the disc as 16-bit stereo PCM."""
    try:
        return disc.image.audio_pcm(number, tool.path)
    except ImageError as e:
        raise MediaError(f"CD-DA track {number}: {e}") from e


def _frame_sectors(raw: bytes) -> list[int]:
    """The sector index at which each video frame of an STR range arrives (its first chunk)."""
    arrivals = []
    last = None
    for i in range(len(raw) // SECTOR_BYTES):
        base = i * SECTOR_BYTES
        if raw[base + 18] & 0x20:                       # Form 2: audio
            continue
        magic, kind, _chunk, _chunks, frame = struct.unpack_from("<HHHHI", raw, base + STR_HEADER)
        if magic == STR_MAGIC and kind == STR_TYPE and frame != last:
            arrivals.append(i)
            last = frame
    return arrivals


class _Movie(NamedTuple):
    """A movie of an overlay's list: its XAS sectors and its descriptor."""

    first: int
    last: int
    width: int
    height: int
    last_frame: int
    volume: int
    flags: int

    @property
    def key(self) -> tuple[int, int, int]:
        return self.first, self.last, self.last_frame


def _movie(block: Block, descriptors: int, sectors: int, number: int) -> _Movie:
    row, _, width, height, last_frame, volume, _, flags = struct.unpack_from("<BBhhhBBH", block.read(descriptors + 16 * number, 16))
    first, last = block.u32s(sectors + 16 * row, 2)
    return _Movie(first, last, width, height, last_frame, volume, flags)


def _movie_sectors(disc: Disc, movie: _Movie) -> tuple[bytes, list[int]]:
    """A movie's raw sectors and the sector at which each of its frames arrives."""
    image, lba = _xas(disc)
    raw = image[(lba + movie.first) * SECTOR_BYTES:(lba + movie.last + 1) * SECTOR_BYTES]
    return raw, _frame_sectors(raw)[:movie.last_frame]


def _convert_listed(out: Output, tool: FFmpeg, name: str, movie: _Movie, raw: bytes, arrivals: list[int]) -> dict:
    """A movie of an overlay's list converted (`_movie_sectors`); returns its movies.json entry."""
    files, duration = convert_movie(out, tool, name, raw, arrivals)
    return {"name": name, **files, "width": movie.width, "height": movie.height, "volume": movie.volume,
            "duration": round(duration, 3), "white_end": bool(movie.flags & MOVIE_WHITE_END)}


def convert_title_movies(disc: Disc, out: Output, tool: FFmpeg) -> None:
    title = disc.blocks()["title"]
    index = []
    for number in range(2):
        movie = _movie(title, TITLE_MOVIES, TITLE_SECTORS, number)
        index.append(_convert_listed(out, tool, f"title_{number}", movie, *_movie_sectors(disc, movie)))
    out.write_json("movies/movies.json", {"title": index})


def convert_ending_movies(disc: Disc, out: Output, tool: FFmpeg) -> None:
    """ending.ovl's movie list (FUN_8010D474): the endings and the Theater's movies; entries that
    are the title's movies (the same sectors and length) point at their files."""
    blocks = disc.blocks()
    index = _read_json(out, "movies/movies.json")
    known = {_movie(blocks["title"], TITLE_MOVIES, TITLE_SECTORS, number).key: entry
             for number, entry in enumerate(index.get("title", []))}
    ending = []
    slots: dict[tuple[int, int, int], list[int]] = {}
    for number in range(ENDING_MOVIE_COUNT):
        movie = _movie(blocks["ending"], ENDING_MOVIES, ENDING_SECTORS, number)
        if movie.key not in slots:
            raw, arrivals = _movie_sectors(disc, movie)
            if movie.key not in known:
                known[movie.key] = _convert_listed(out, tool, f"ending_{number}", movie, raw, arrivals)
            slots[movie.key] = _grid_starts(arrivals)
        ending.append({**known[movie.key], "fps": MOVIE_FPS, "frame_slots": slots[movie.key]})
    index["ending"] = ending
    out.write_json("movies/movies.json", index)
    count = captions.write((disc.raw or disc).blocks()["ending"], ending_caption_sets(blocks["ending"]), out, "movies")
    log.info("movie captions: %d", count)


def ending_caption_sets(ending: Block) -> list[int]:
    """The caption set of each movie of ending.ovl's list (its descriptor's flags; 0 none), from
    the overlay in Japan Rev.1's layout."""
    return [(ending.u16s(ENDING_MOVIES + 16 * n + DESCRIPTOR_FLAGS, 1)[0] & MOVIE_CAPTIONS) >> 8
            for n in range(ENDING_MOVIE_COUNT)]


def _read_json(out: Output, name: str) -> dict:
    path = out.root / name
    return json.loads(path.read_text()) if path.exists() else {}


def convert_movie(out: Output, tool: FFmpeg, name: str, raw: bytes, arrivals: list[int]) -> tuple[dict, float]:
    """One STR movie up to its last frame (`arrivals`: `_frame_sectors` up to it); returns its files
    for movies.json and its duration."""
    duration = arrivals[-1] / SECTORS_PER_SECOND + MOVIE_TAIL
    pcm, rate, channels = _pcm(tool, raw)
    pcm = pcm[:min(len(pcm) // (2 * channels), round(duration * rate)) * 2 * channels]
    if tool.ogg:
        files = {"video": [f"{name}.{variant}.ogv" for variant in THEORA_QUALITIES]}
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            _grid_frames(tool, raw, arrivals, duration, folder)
            (folder / "audio.wav").write_bytes(wav_bytes(pcm, rate, channels))
            for variant, quality in THEORA_QUALITIES.items():
                out.write(f"movies/{name}.{variant}.ogv", _theora(tool, folder, quality))
    else:
        files = {"frames": f"{name}.bin", "audio": f"{name}.wav"}
        out.write(f"movies/{name}.bin", _frame_container(tool, raw, arrivals))
        out.write(f"movies/{name}.wav", wav_bytes(pcm, rate, channels))
    log.info("movie %s: %d frames, %.1f s", name, len(arrivals), duration)
    return files, duration


def _grid_frames(tool: FFmpeg, raw: bytes, arrivals: list[int], duration: float, folder: Path) -> None:
    """The movie's frames decoded into `folder` on the MOVIE_FPS grid (`grid_<slot>.png`): each
    decoded frame from its grid slot."""
    _decode(tool, raw, ["-map", "0:v:0", "-frames:v", str(len(arrivals)), str(folder / "%05d.png")])
    starts = _grid_starts(arrivals)
    frame = 0
    for slot in range(math.ceil(duration * MOVIE_FPS)):
        while frame + 1 < len(starts) and starts[frame + 1] <= slot:
            frame += 1
        _link(folder / f"{frame + 1:05d}.png", folder / f"grid_{slot:06d}.png")


def _theora(tool: FFmpeg, folder: Path, quality: int) -> bytes:
    """Ogg Theora + Vorbis of the grid frames and `audio.wav` in `folder` (`_grid_frames`)."""
    dest = folder / f"movie_{quality}.ogv"
    tool.run(["-framerate", str(MOVIE_FPS), "-i", str(folder / "grid_%06d.png"), "-i", str(folder / "audio.wav"),
              "-map", "0:v", "-map", "1:a", "-c:v", THEORA, "-q:v", str(quality),
              "-c:a", VORBIS, "-q:a", str(VORBIS_QUALITY), str(dest)])
    return dest.read_bytes()


def _grid_starts(arrivals: list[int]) -> list[int]:
    """Each decoded frame's first MOVIE_FPS grid slot: the first at or after the sector at which it
    arrives (integer arithmetic, so a frame arriving on a grid line is not late)."""
    return [-(-sector * MOVIE_FPS // SECTORS_PER_SECOND) for sector in arrivals]


def _link(source: Path, dest: Path) -> None:
    """A hard link (no privileges needed, unlike symbolic links on Windows), else a copy."""
    try:
        os.link(source, dest)
    except OSError:
        shutil.copyfile(source, dest)


def _frame_container(tool: FFmpeg, raw: bytes, arrivals: list[int]) -> bytes:
    """The fallback "T3MV" container: the frames as JPEG with the sector at which each arrives."""
    with tempfile.TemporaryDirectory() as tmp:
        frames_dir = Path(tmp)
        _decode(tool, raw, ["-map", "0:v:0", "-q:v", str(JPEG_QUALITY), "-frames:v", str(len(arrivals)),
                            str(frames_dir / "%05d.jpg")])
        jpegs = [(frames_dir / f"{i + 1:05d}.jpg").read_bytes() for i in range(len(arrivals))]
    width, height = _jpeg_size(jpegs[0])
    table = bytearray(MOVIE_MAGIC + struct.pack("<IHHII", MOVIE_VERSION, width, height, len(jpegs), SECTORS_PER_SECOND))
    offset = len(table) + 12 * len(jpegs)
    for jpeg, sector in zip(jpegs, arrivals):
        table += struct.pack("<III", offset, len(jpeg), sector)
        offset += len(jpeg)
    return bytes(table) + b"".join(jpegs)


def _jpeg_size(jpeg: bytes) -> tuple[int, int]:
    i = 2
    while i < len(jpeg):
        marker, length = jpeg[i + 1], struct.unpack_from(">H", jpeg, i + 2)[0]
        if 0xC0 <= marker <= 0xC3:
            height, width = struct.unpack_from(">HH", jpeg, i + 5)
            return width, height
        i += 2 + length
    raise MediaError("JPEG without a frame header")
