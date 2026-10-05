"""Sound banks (VAB) → WAV samples at the game's playback rate, with a table of tone gains.

The fight plays sound codes (sound.md#sound-code): bits 14–15 select the bank (1 the combat bank,
VAB 0; 2 the system bank, VAB 1; 3 the fighter's own voice bank), bits 4–5 the program and bits
0–3 the tone, played at key `60 + tone`, which is always the tone's own key. So every tone of
every program becomes one WAV (`sounds/<bank>/<program>_<tone>.wav`), resampled to nothing: the
samples are written at the rate libsnd plays them (`spu_pitch`, bit-exact with SsPitchFromNote),
with the VAG's loop as a `smpl` loop.

`sounds/sounds.json`:

- `volumes`: the 16 key-on volumes selected by sound code bits 6–9;
- `banks`: per bank, `tones` keyed `"<program>_<tone>"` with the file, the gain
  `master · program · tone / 127³` (libsnd's voice volume without the key-on volume) and the
  tone and program pans (0–127, 64 centre);
- `voice_banks`: costume slot → the name of its voice bank. A costume's voices are its `.vh`
  (BNS 72 + 4s) with the body in member 2 of its `.arc` (BNS 73 + 4s); identical banks are
  written once, named after the first slot that uses them.
"""

from __future__ import annotations

import hashlib
import struct

from common import Disc, Output, log
from move_text import arc_members
import decode_vab_sample as vab
from media import wav_bytes

EXE_VABS = {                     # bank name → (VH address, body address) in the executable image
    "combat": (0x80025AAC, 0x800D3C8C),     # VAB 0
    "system": (0x80026CCC, 0x8011063C),     # VAB 1
}
VOLUMES = 0x80027B58             # 16 key-on volumes by sound code bits 6–9
VH_TABLES = 0x820                # header (0x20) + 128 program records (16 bytes)
PROGRAMS = 128
PROGRAM_BYTES = 16
TONE_BYTES = 32
TONES_PER_PROGRAM = 16
VOLUME_MAX = 127


def vh_size(head: bytes) -> int:
    programs = struct.unpack_from("<H", head, 0x12)[0]
    return VH_TABLES + programs * TONES_PER_PROGRAM * TONE_BYTES + 0x200


def convert_bank(out: Output, name: str, header: bytes, body: bytes) -> dict:
    master = header[0x18]
    defined = [p for p in range(PROGRAMS) if header[0x20 + PROGRAM_BYTES * p]]
    tones = {}
    for rank, program in enumerate(defined):
        record = 0x20 + PROGRAM_BYTES * program
        count, program_volume, program_pan = header[record], header[record + 1], header[record + 4]
        for tone in range(count):
            attr = VH_TABLES + rank * TONES_PER_PROGRAM * TONE_BYTES + TONE_BYTES * tone
            tone_volume, tone_pan = header[attr + 2], header[attr + 3]
            vag = struct.unpack_from("<h", header, attr + 22)[0]
            if vag <= 0:
                continue
            pitch = vab.spu_pitch(vab.BASE_KEY + tone, header[attr + 4], header[attr + 5])
            rate = round(vab.SPU_BASE_RATE * pitch / 4096)
            pcm, loop = vab.decode_spu_adpcm(vab.sample_bytes(header, body, vag))
            file = f"{name}/{program}_{tone}.wav"
            out.write(f"sounds/{file}", wav_bytes(struct.pack(f"<{len(pcm)}h", *pcm), rate, 1, loop))
            gain = master * program_volume * tone_volume / VOLUME_MAX ** 3
            tones[f"{program}_{tone}"] = {"file": file, "gain": round(gain, 5), "pan": [tone_pan, program_pan],
                                          "rate": rate}
    return {"tones": tones}


def convert(disc: Disc, out: Output, costume_slots: list[int]) -> None:
    banks = {}
    for name, (vh_addr, body_addr) in EXE_VABS.items():
        head = disc.exe_bytes(vh_addr, VH_TABLES)
        size = vh_size(head)
        total = struct.unpack_from("<I", head, 0x0C)[0]
        banks[name] = convert_bank(out, name, disc.exe_bytes(vh_addr, size), disc.exe_bytes(body_addr, total - size))
    voice_banks = {}
    seen: dict[str, str] = {}
    for slot in costume_slots:
        header = disc.bns(72 + 4 * slot)
        body = arc_members(disc.bns(73 + 4 * slot))[2]
        digest = hashlib.sha256(header + body).hexdigest()
        if digest not in seen:
            name = f"voice_{slot:02d}"
            banks[name] = convert_bank(out, name, header, body)
            seen[digest] = name
        voice_banks[str(slot)] = seen[digest]
    out.write_json("sounds/sounds.json", {
        "volumes": disc.exe_u8(VOLUMES, 16),
        "banks": banks,
        "voice_banks": voice_banks,
    })
    log.info("sounds: %d banks, %d tones", len(banks), sum(len(b["tones"]) for b in banks.values()))
