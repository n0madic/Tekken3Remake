"""The attract demonstration (enbu.ovl, modes.md#enbu-attract-demonstration).

`enbu.ovl` (BNS 0) carries the demonstration's motion bank (type 98) and three scripts;
each demonstration `n` has its own model archive `enbmdl<n + 1>.arc` (BNS 1–3): pairs of a
`.kmd` model (member `2·pair`) and its TIM sequence (member `2·pair + 1`), chosen per costume
slot through the pair table.

Output:

- `motion/enbu.*`: the demonstration's bank (as every motion bank, with its camera reel);
- `enbu/enbu.json`: per demonstration the fighters' starting costume slots, the script as
  `[frame, kind, a, b, c]` events, and the model of every costume slot it uses; the camera
  reel's stream offsets;
- `characters/enbu<n>_<slot>/`: the models (character.py format).
"""

from __future__ import annotations

from common import Block, Disc, Output, log
from move_text import arc_members
import character
import motion_bake

MODEL_ARCHIVES = (1, 2, 3)              # enbmdl1–3.arc
BANK = 0x800DDE34                       # the demonstration's motion bank inside enbu.ovl
SCRIPTS = 0x800B945C                    # three scripts of 0x1C2 bytes (45 ten-byte events)
SCRIPT_STRIDE = 0x1C2
EVENT_BYTES = 10
END_EVENT = -1
PAIR_TABLE = 0x800B99A4                 # u8 pair per (demonstration, costume slot), 45 per row
PAIRS_PER_DEMO = 45
NO_PAIR = 0xFF
# FUN_800D3D64's first frame: the costume slots the two fighters start with, per demonstration.
START_COSTUMES = ((0x0C, 0x00), (0x0D, 0x01), (0x17, 0x1E))
COSTUME_EVENTS = (0, 1)                 # event kinds that change fighter 0 / 1's costume
REEL_FIRST_ID, REEL_STEP = 0x2B, 2      # FUN_80067358: reel entry k plays camera id 0x2B + 2k
CAMERA_ID_BASE = 0x2B                   # bank section 7 holds the ids from 0x2B on
STREAM_KIND = 2
CERTAIN = 0xFFF                         # a choice weight no 12-bit random number exceeds


def read_script(ovl: Block, number: int) -> list[list[int]]:
    events = []
    base = SCRIPTS + SCRIPT_STRIDE * number
    for i in range(SCRIPT_STRIDE // EVENT_BYTES):
        event = ovl.s16s(base + EVENT_BYTES * i, EVENT_BYTES // 2)
        events.append(event)
        if event[1] == END_EVENT:
            return events
    raise ValueError(f"demonstration {number}: script has no end event")


def camera_reel(choices: list[list[int]]) -> list[int]:
    """Section-8 offsets of the reel's streams in order (CameraChoose of ids 0x2B, 0x2D, …).

    Each reel id's list must start with a stream of weight 0xFFF, which CameraChoose takes for
    every random number; the reel ends before an id whose list is not such a stream.
    """
    reel = []
    k = 0
    while True:
        index = REEL_FIRST_ID + REEL_STEP * k - CAMERA_ID_BASE + 1
        if index >= len(choices):
            return reel
        kind, weight, script = choices[index]
        if kind != STREAM_KIND or weight < CERTAIN or script >= 0 or script == -1:
            return reel
        reel.append(script & 0xFFFF)
        k += 1


def convert(disc: Disc, out: Output) -> list[str]:
    """Converts the demonstrations; returns the names of the models written."""
    ovl = disc.blocks()["enbu"]
    bank_size = ovl.u32s(BANK + 4, 15)[14]
    bank = motion_bake.convert_bank(disc, out, "enbu", ovl.read(BANK, bank_size))
    models: list[str] = []
    demos = []
    for number, record in enumerate(MODEL_ARCHIVES):
        script = read_script(ovl, number)
        members = arc_members(disc.bns(record))
        pairs = ovl.u8s(PAIR_TABLE + PAIRS_PER_DEMO * number, PAIRS_PER_DEMO)
        slots = sorted(set(START_COSTUMES[number]) | {e[2] for e in script if e[1] in COSTUME_EVENTS})
        costume_models = {}
        for slot in slots:
            pair = pairs[slot]
            if pair == NO_PAIR:
                raise ValueError(f"demonstration {number}: costume slot {slot} has no model")
            name = f"enbu{number}_{slot}"
            character.convert_model(disc, out, name, slot, members[2 * pair],
                                    character.load_textures(members[2 * pair + 1]))
            costume_models[str(slot)] = name
            models.append(name)
        demos.append({
            "number": number,
            "start_costumes": list(START_COSTUMES[number]),
            "script": script,
            "models": costume_models,
        })
        log.info("demonstration %d: %d events, %d models", number, len(script), len(slots))
    out.write_json("enbu/enbu.json", {
        "bank": "enbu",
        "camera_reel": camera_reel(motion_bake.camera_choices(bank)),
        "demonstrations": demos,
    })
    return models
