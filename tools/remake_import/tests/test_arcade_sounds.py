"""The arcade's sound conversion on a synthetic sound board: a small H8 program image and wave ROM, no game data."""

from __future__ import annotations

import json
import shutil
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_c352 as c352
import arcade_sound_vm as vm
import arcade_sounds as sounds
import media
from common import Output

WAVE_SPACE = 1 << 16
SEQUENCES_AT, WAVES_AT, RECORDS_AT, SCRIPTS_AT = 0x8100, 0x8400, 0x8500, 0x9000
OP_MASKED, OP_STEP_BASE, OP_STEP_SIZE, OP_WORD, OP_INIT, OP_JUMP, OP_END, OP_NOTE, OP_ALU, OP_COMPARE, OP_START = \
    0x04, 0x06, 0x2D, 0x1B, 0x1D, 0x10, 0x15, 0x20, 0x1E, 0x1F, 0x0D
TRACK_VOICE = 0x11
FIRST_TRACK = 0x80
PITCH = 0x1000
WAVE_VAR = 0x10
LOOPED_SEQUENCE, SECTIONS_SEQUENCE, ONE_SHOT_SEQUENCE, COPY_SEQUENCE, DIRECT_SEQUENCE, POLLER_SEQUENCE, PLAYER_SEQUENCE = \
    1, 2, 3, 4, 5, 0x20, 0x100
POLLER_CHANNEL = 1
BEAT = 8                                    # ticks per script step
NOTE_WAIT, BAR_WAIT = 1, 3                  # a note's step, the step that reads the wait and its count
NOTE_TICKS = (2 + NOTE_WAIT) * BEAT
BAR_TICKS = (2 + BAR_WAIT) * BEAT
POLL_WAIT = 20
PLAYER_STEP, PLAYER_VOICE = 4, 5
FORWARD_WAVE, LOOPED_WAVE, REVERSE_WAVE, LINKED_WAVE, BYTE_WAVE = 0, 1, 2, 3, 4
SAMPLE_BYTES = 0x40


def steps(ticks: int) -> bytes:
    """A script step of this many ticks."""
    return bytes((OP_STEP_SIZE, 0x09, ticks, OP_STEP_BASE, 0x07, vm.TIME_PER_TICK))


def setup_track(voice: int, wave: int) -> bytes:
    """Steps of BEAT ticks; the first track on `voice` with `wave`."""
    return steps(BEAT) + bytes((
        OP_MASKED, FIRST_TRACK, TRACK_VOICE, voice,
        OP_INIT, FIRST_TRACK, 0x00, 0xFF,
        OP_WORD, FIRST_TRACK, 0x00, wave & 0xFF, wave >> 8,
    ))


def jump(target: int) -> bytes:
    return bytes((OP_JUMP, target & 0xFF, target >> 8, 0))


COMPARE_BYTES = 10


def if_equal(variable: int, value: int, when_true: int, when_false: int) -> bytes:
    return bytes((OP_COMPARE, 0x20, variable, value, when_true & 0xFF, when_true >> 8, 0, when_false & 0xFF, when_false >> 8, 0))


def set_var(variable: int, value: int) -> bytes:
    return bytes((OP_ALU, 0x20, variable, value))


def wait(count: int) -> bytes:
    """`count` steps more after the one that reads it."""
    return bytes((0x80 | count,))


def note(number: int = 0x30) -> bytes:
    return bytes((OP_NOTE, FIRST_TRACK, number))


class Board:
    """A program image: the directory, the wave records and scripts placed one after the other."""

    def __init__(self) -> None:
        self.image = bytearray(1 << 17)
        self.next_script = SCRIPTS_AT
        struct.pack_into("<2H", self.image, vm.DIR_SEQUENCES, SEQUENCES_AT, WAVES_AT)
        for table, at in ((vm.DIR_PITCH, 0x8700), (vm.DIR_ENVELOPES, 0x8710), (vm.DIR_PANS, 0x8720), (vm.DIR_MODULATIONS, 0x8730)):
            struct.pack_into("<H", self.image, table, at)
        for semitone in range(0x81):
            struct.pack_into(">H", self.image, vm.FREQ_TABLE + 2 * semitone, 0x4000)
        for step in range(0x100):
            self.image[vm.ATTENUATION + step] = 0xFF - step
        self.records_at = RECORDS_AT
        self.wave_rom = np.zeros(WAVE_SPACE, np.uint8)
        self.add_script(0, bytes((OP_END,)))           # the driver starts sequence 0 as it boots

    def add_wave(self, number: int, flags: int, start: int, end: int, loop: int = 0, pieces: tuple[tuple[int, int, int, int], ...] = ()) -> None:
        struct.pack_into("<H", self.image, WAVES_AT + 2 * number, self.records_at)
        struct.pack_into("<6H", self.image, self.records_at, PITCH, 0, flags, start, end, loop)
        for i, piece in enumerate(pieces):
            struct.pack_into("<4H", self.image, self.records_at + sounds.RECORD_BYTES + sounds.LINK_PIECE_BYTES * i, *piece)
        self.records_at += sounds.RECORD_BYTES + sounds.LINK_PIECE_BYTES * (len(pieces) + 1)

    def add_script(self, sequence: int, code: bytes) -> int:
        at = self.next_script
        struct.pack_into("<HB", self.image, SEQUENCES_AT + 3 * sequence, at, 0)
        self.image[at:at + len(code)] = code
        self.next_script = at + len(code)
        return at

    def alias(self, sequence: int, other: int) -> None:
        at = SEQUENCES_AT + 3 * other
        self.image[SEQUENCES_AT + 3 * sequence:SEQUENCES_AT + 3 * sequence + 3] = self.image[at:at + 3]

    def program(self) -> bytes:
        return bytes(self.image)


def board() -> Board:
    b = Board()
    b.wave_rom[:SAMPLE_BYTES] = np.arange(SAMPLE_BYTES, dtype=np.uint8) * 3
    b.add_wave(FORWARD_WAVE, 0, 0, SAMPLE_BYTES - 1)
    b.add_wave(LOOPED_WAVE, sounds.FLAG_LOOP, 0, SAMPLE_BYTES - 1, 0x10)
    b.add_wave(REVERSE_WAVE, sounds.FLAG_REVERSE, SAMPLE_BYTES - 1, 0)
    b.add_wave(LINKED_WAVE, sounds.FLAG_LINK, 0, 0xF, 0, ((0, 0, 0x20, 0x2F),))
    b.add_wave(BYTE_WAVE, sounds.FLAG_MULAW, 0, 3)

    head = setup_track(0, LOOPED_WAVE)
    at = b.next_script + len(head)
    b.add_script(LOOPED_SEQUENCE, head + note() + wait(NOTE_WAIT) + note() + wait(NOTE_WAIT) + jump(at))

    b.add_script(ONE_SHOT_SEQUENCE, setup_track(0, FORWARD_WAVE) + note() + wait(NOTE_WAIT) + bytes((OP_END,)))
    return b


def add_sectioned(b: Board) -> None:
    """A melody that tests the gate variable at each bar, and a poller on another channel: a BGM's shape."""
    head = steps(1)
    poller = b.next_script
    test = poller + len(head)
    go = test + COMPARE_BYTES + len(wait(0)) + len(jump(0))
    b.add_script(POLLER_SEQUENCE, head + if_equal(sounds.SECTION_VAR, 1, go, test + COMPARE_BYTES) + wait(0) + jump(test)
                 + wait(POLL_WAIT) + set_var(sounds.SECTION_GATE_VAR, 1) + wait(0) + bytes((OP_END,)))
    head = (setup_track(0, LOOPED_WAVE) + set_var(sounds.SECTION_VAR, 0) + set_var(sounds.SECTION_GATE_VAR, 0)
            + bytes((OP_START, POLLER_CHANNEL, POLLER_SEQUENCE & 0xFF, POLLER_SEQUENCE >> 8)))
    intro = b.next_script + len(head)
    bar = note() + wait(BAR_WAIT)
    test = intro + len(bar)
    section = test + COMPARE_BYTES
    b.add_script(SECTIONS_SEQUENCE, head + bar + if_equal(sounds.SECTION_GATE_VAR, 1, section, intro)
                 + note(0x34) + wait(BAR_WAIT) + note(0x36) + wait(BAR_WAIT) + jump(section))


def add_direct(b: Board) -> None:
    """A melody that tests the section variable itself at each bar, with no poller (Jin's BGM 0x1D has that shape)."""
    head = setup_track(0, LOOPED_WAVE) + set_var(sounds.SECTION_VAR, 0) + set_var(sounds.SECTION_GATE_VAR, 0)
    intro = b.next_script + len(head)
    bar = note() + wait(BAR_WAIT)
    section = intro + len(bar) + COMPARE_BYTES
    b.add_script(DIRECT_SEQUENCE, head + bar + if_equal(sounds.SECTION_VAR, 1, section, intro)
                 + note(0x34) + wait(BAR_WAIT) + note(0x36) + wait(BAR_WAIT) + jump(section))


def add_player(b: Board) -> None:
    """A player sequence: the wave its variable names, on voice 5, and held for a while."""
    code = steps(PLAYER_STEP) + bytes((OP_MASKED, FIRST_TRACK, TRACK_VOICE, PLAYER_VOICE, OP_INIT, FIRST_TRACK, 0x00, 0xFF,
                                       OP_WORD, FIRST_TRACK, 0x80, WAVE_VAR)) + note() + wait(0) + bytes((OP_END,))
    b.add_script(PLAYER_SEQUENCE, code)


class WaveRecordTest(unittest.TestCase):
    def setUp(self) -> None:
        self.b = board()
        self.program = self.b.program()
        self.rom = self.b.wave_rom.tobytes()

    def test_forward_sample_decodes_every_byte(self) -> None:
        pcm, loop = sounds.decode_wave(self.program, self.rom, FORWARD_WAVE)
        self.assertEqual(len(pcm), SAMPLE_BYTES)
        self.assertIsNone(loop)
        self.assertEqual(int(pcm[1]), 3 << 8)

    def test_loop_is_a_frame_of_the_sample(self) -> None:
        self.assertEqual(sounds.decode_wave(self.program, self.rom, LOOPED_WAVE)[1], 0x10)

    def test_reverse_sample_plays_backwards(self) -> None:
        pcm, _ = sounds.decode_wave(self.program, self.rom, REVERSE_WAVE)
        self.assertEqual(len(pcm), SAMPLE_BYTES)
        forward, _ = sounds.decode_wave(self.program, self.rom, FORWARD_WAVE)
        self.assertTrue(np.array_equal(pcm, forward[::-1]))

    def test_linked_sample_reads_to_its_last_piece(self) -> None:
        pcm, loop = sounds.decode_wave(self.program, self.rom, LINKED_WAVE)
        self.assertEqual(len(pcm), 0x30)
        self.assertIsNone(loop)

    def test_mulaw_uses_the_chips_table(self) -> None:
        pcm, _ = sounds.decode_wave(self.program, self.rom, BYTE_WAVE)
        self.assertTrue(np.array_equal(pcm, c352.mulaw_table()[self.b.wave_rom[:4]]))

    def test_rate_comes_from_the_frequency_register(self) -> None:
        # 0x4000 of 65,536 per sample of 88,200 Hz, whatever the semitone in this table.
        self.assertEqual(sounds.wave_rate(self.program, FORWARD_WAVE), c352.SAMPLE_RATE // 4)


class ChipTest(unittest.TestCase):
    def chip(self) -> c352.Chip:
        wave = np.zeros(WAVE_SPACE, np.uint8)
        wave[:0x100] = 0x40
        return c352.Chip(wave)

    def key_on(self, chip: c352.Chip, flags: int, end: int = 0x20, freq: int = 0x10000 - 1) -> c352.Voice:
        chip.write(c352.REG_VOLUME_FRONT, 0xFF80)
        chip.write(c352.REG_FREQ, freq)
        chip.write(c352.REG_START, 0)
        chip.write(c352.REG_END, end)
        chip.write(c352.REG_LOOP, 0x10)
        chip.write(c352.REG_FLAGS, flags | c352.KEY_ON)
        chip.write(c352.REG_KEYS, c352.VOICES)
        return chip.voices[0]

    def test_a_sample_ends_at_its_end_register(self) -> None:
        chip = self.chip()
        voice = self.key_on(chip, 0)
        self.assertTrue(voice.flags & c352.BUSY)
        chip.advance(0x10)
        self.assertTrue(voice.flags & c352.BUSY)
        chip.advance(0x20)
        self.assertFalse(voice.flags & c352.BUSY)

    def test_a_loop_marks_its_history_and_goes_on(self) -> None:
        chip = self.chip()
        voice = self.key_on(chip, c352.LOOP)
        chip.advance(0x40)
        self.assertTrue(voice.flags & c352.BUSY)
        self.assertTrue(voice.flags & c352.LOOP_HISTORY)
        self.assertGreaterEqual(voice.pos & 0xFFFF, 0x10)

    def test_the_two_front_volumes_ramp_towards_their_bytes(self) -> None:
        chip = self.chip()
        self.key_on(chip, 0, end=0xFF)
        mix = chip.advance(0xC0)
        self.assertLess(abs(int(mix[0, 0])), abs(int(mix[-1, 0])))       # the ramps start at 0
        self.assertGreater(abs(int(mix[-1, 0])), abs(int(mix[-1, 1])))   # 0xFF against 0x80

    def test_without_rendering_the_volumes_are_reached_at_once(self) -> None:
        chip = self.chip()
        chip.render = False
        voice = self.key_on(chip, 0, end=0xFF)
        self.assertIsNone(chip.advance(4))
        self.assertEqual(voice.level, [0xFF, 0x80])


class SectionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.b = board()
        add_sectioned(self.b)
        self.program = self.b.program()
        self.space = c352.WaveSpace(self.b.wave_rom)

    def test_a_looping_sequence_finds_its_period(self) -> None:
        plan = sounds.analyse_section(self.program, self.space, LOOPED_SEQUENCE, 0)
        self.assertIsNotNone(plan)
        self.assertEqual(plan.end - plan.loop_start, 2 * NOTE_TICKS)
        self.assertEqual(plan.entry, 1)

    def test_a_sequence_that_ends_does_not_loop(self) -> None:
        plan = sounds.analyse_section(self.program, self.space, ONE_SHOT_SEQUENCE, 0)
        self.assertIsNone(plan.loop_start)
        self.assertGreater(plan.end, plan.entry)

    def test_the_intro_has_a_cue_per_bar(self) -> None:
        plan = sounds.analyse_section(self.program, self.space, SECTIONS_SEQUENCE, 0)
        repeating = [cue for cue in plan.cues[sounds.SECTION_GATE_VAR] if cue >= plan.loop_start]
        self.assertEqual(plan.end - plan.loop_start, BAR_TICKS)
        self.assertEqual(len(repeating), 1)

    def test_a_section_starts_at_a_bar_after_its_delay(self) -> None:
        intro = sounds.analyse_section(self.program, self.space, SECTIONS_SEQUENCE, 0)
        section = sounds.analyse_section(self.program, self.space, SECTIONS_SEQUENCE, 1)
        self.assertIsNotNone(section)
        self.assertGreater(section.delay, 0)
        self.assertEqual(section.end - section.loop_start, 2 * BAR_TICKS)
        # The jump is at one of the intro's bars.
        self.assertEqual((section.entry - intro.cues[sounds.SECTION_GATE_VAR][0]) % BAR_TICKS, 0)
        self.assertEqual(section.jumps[-1].variable, sounds.SECTION_GATE_VAR)

    def test_the_next_write_waits_until_the_sequence_has_settled(self) -> None:
        # In BGM 0x1B channel 0 jumps on the section variable a tick before channels 1 and 2: writing the next
        # number at once left those two in the intro.
        machine = sounds.Machine(self.program, self.space)
        writes: list[tuple[int, int]] = []
        machine.vm.set_var = lambda index, value: writes.append((machine.at, value))   # type: ignore[method-assign]
        first = sounds.Jump(10, 0, sounds.SECTION_VAR, 10 + sounds.GATE_GRACE_TICKS)
        second = sounds.Jump(20, 5, sounds.SECTION_GATE_VAR, 20)
        entry = sounds._to_section(machine, LOOPED_SEQUENCE, (first, second))
        start = sounds.SCRIPT_READY_TICKS
        self.assertEqual(writes, [(start, 1), (start + first.settled, 2)])
        self.assertEqual(entry, start + first.settled + second.ticks)

    def test_the_poller_is_found_and_its_tests_are_no_cues(self) -> None:
        chain = sounds.explore_sections(self.program, self.space, SECTIONS_SEQUENCE)
        self.assertEqual(chain.pollers, frozenset({POLLER_CHANNEL}))
        intro = sounds.analyse_section(self.program, self.space, SECTIONS_SEQUENCE, 0, chain)
        self.assertEqual(intro.cues[sounds.SECTION_VAR], [])

    def test_a_melody_that_tests_the_section_itself_jumps_at_its_next_bar(self) -> None:
        # Issue n0madic/Tekken3Remake#31: such BGMs (Jin's, Nina's …) were left in their intro.
        add_direct(self.b)
        program = self.b.program()
        chain = sounds.explore_sections(program, self.space, DIRECT_SEQUENCE)
        self.assertEqual(len(chain.jumps), 1)
        self.assertEqual((chain.jumps[0].variable, chain.jumps[0].delay), (sounds.SECTION_VAR, 0))
        self.assertEqual(chain.pollers, frozenset())
        intro = sounds.analyse_section(program, self.space, DIRECT_SEQUENCE, 0, chain)
        section = sounds.analyse_section(program, self.space, DIRECT_SEQUENCE, 1, chain)
        self.assertEqual(intro.cues[sounds.SECTION_GATE_VAR], [])
        self.assertEqual((section.entry - intro.cues[sounds.SECTION_VAR][0]) % BAR_TICKS, 0)
        self.assertLessEqual(chain.jumps[0].ticks, BAR_TICKS)
        self.assertEqual(section.end - section.loop_start, 2 * BAR_TICKS)

    def test_no_section_where_the_script_has_none(self) -> None:
        self.assertIsNone(sounds.analyse_section(self.program, self.space, LOOPED_SEQUENCE, 1))

    def test_a_loop_mixes_to_its_ticks_and_repeats_after_its_seam(self) -> None:
        plan = sounds.analyse_section(self.program, self.space, LOOPED_SEQUENCE, 0)
        mix = sounds.render_section(self.program, self.space, plan)
        self.assertEqual(len(mix), (plan.end - plan.entry) * c352.TICK_SAMPLES)
        self.assertGreater(float(np.abs(mix).max()), 0.0)

    def test_the_render_is_deterministic(self) -> None:
        plan = sounds.analyse_section(self.program, self.space, LOOPED_SEQUENCE, 0)
        first = sounds.render_section(self.program, self.space, plan)
        second = sounds.render_section(self.program, self.space, plan)
        self.assertTrue(np.array_equal(first, second))

    def test_output_is_half_rate_16_bit(self) -> None:
        mix = np.full((1000, 2), 1 << c352.MIX_GAIN_SHIFT, dtype=np.int64)
        pcm = sounds.to_output(mix)
        self.assertEqual(pcm.shape, (500, 2))
        self.assertEqual(pcm.dtype, np.dtype("<i2"))
        self.assertEqual(int(pcm[250, 0]), round(sounds.MASTER_GAIN))

    def test_output_clips_rather_than_wraps(self) -> None:
        mix = np.full((1000, 2), 1 << 30, dtype=np.int64)
        self.assertEqual(int(sounds.to_output(mix).max()), 32767)

    def test_cues_merge_the_tests_of_one_bar_and_skip_the_jump(self) -> None:
        self.assertEqual(sounds._cues([100, 101, 200, 201, 300, 500], 100, 400), [200, 300])

    def test_scripts_at_one_address_share_their_group(self) -> None:
        self.b.alias(COPY_SEQUENCE, LOOPED_SEQUENCE)
        groups = sounds.sequence_groups(self.b.program(), [LOOPED_SEQUENCE, COPY_SEQUENCE, ONE_SHOT_SEQUENCE])
        self.assertEqual(groups, {LOOPED_SEQUENCE: LOOPED_SEQUENCE, COPY_SEQUENCE: LOOPED_SEQUENCE, ONE_SHOT_SEQUENCE: ONE_SHOT_SEQUENCE})


class MusicFilesTest(unittest.TestCase):
    def test_the_table_lists_files_by_sequence_and_section(self) -> None:
        b = board()
        add_sectioned(b)
        add_direct(b)
        b.alias(COPY_SEQUENCE, LOOPED_SEQUENCE)
        with tempfile.TemporaryDirectory() as folder:
            out = Output(Path(folder))
            sounds.convert_music(b.program(), b.wave_rom.tobytes(), out, None,
                                 (LOOPED_SEQUENCE, COPY_SEQUENCE, SECTIONS_SEQUENCE, DIRECT_SEQUENCE), workers=1)
            table = json.loads((Path(folder) / "music" / "arcade.json").read_text())["tracks"]
            self.assertEqual(table[str(COPY_SEQUENCE)], table[str(LOOPED_SEQUENCE)])
            sections = table[str(SECTIONS_SEQUENCE)]["sections"]
            self.assertEqual([row["section"] for row in sections], [0, 1])
            for row in sections:
                self.assertTrue((Path(folder) / "music" / row["file"]).exists())
                self.assertTrue(row["loop"] is not None and row["loop"] < row["length"])
            self.assertGreater(sections[1]["delay"], 0)
            self.assertEqual(sections[0]["delay"], 0)
            direct = table[str(DIRECT_SEQUENCE)]["sections"]
            self.assertEqual([(row["section"], row["delay"]) for row in direct], [(0, 0), (1, 0)])
            self.assertTrue(direct[0]["cues"], "the intro's bars that test the section variable")


class PlayerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.b = board()
        add_player(self.b)
        self.space = c352.WaveSpace(self.b.wave_rom)

    def test_a_players_note_is_the_requests_wave_on_its_voice(self) -> None:
        result = sounds.probe(self.b.program(), self.space, 0x14, PLAYER_SEQUENCE, {WAVE_VAR: LOOPED_WAVE}, LOOPED_WAVE)
        notes = result.row["notes"]
        self.assertEqual(len(notes), 1)
        self.assertEqual(notes[0]["voice"], PLAYER_VOICE)
        self.assertEqual(notes[0]["wave"], -1)
        self.assertEqual(result.row["end"], 2 * PLAYER_STEP)

    def test_a_note_of_another_wave_names_it(self) -> None:
        result = sounds.probe(self.b.program(), self.space, 0x14, PLAYER_SEQUENCE, {WAVE_VAR: LOOPED_WAVE}, FORWARD_WAVE)
        self.assertEqual(result.row["notes"][0]["wave"], LOOPED_WAVE)

    def test_gain_is_both_front_bytes_on_the_mix_scale(self) -> None:
        self.assertAlmostEqual(sounds._gain(0x8080), 0.5 * sounds.MASTER_GAIN / 8, places=4)
        self.assertAlmostEqual(sounds._gain(0x0000), 0.0)
        self.assertAlmostEqual(sounds._gain(0x8000), 0.25 * sounds.MASTER_GAIN / 8, places=4)


class VorbisTest(unittest.TestCase):
    @unittest.skipIf(shutil.which("ffmpeg") is None, "no FFmpeg on the PATH")
    def test_two_encodings_of_the_same_samples_are_equal(self) -> None:
        tone = (np.sin(np.arange(22050) * 0.05) * 8000).astype("<i2")
        pcm = np.stack((tone, tone), axis=1).tobytes()
        tool = media.find_ffmpeg()
        self.assertEqual(media._vorbis(tool, pcm, 22050, 2), media._vorbis(tool, pcm, 22050, 2))


if __name__ == "__main__":
    unittest.main()
