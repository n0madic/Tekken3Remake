# Character sound banks: `pBAV` VH plus ARC VB

The 52 repeated character-resource groups each contain a VH candidate at BNS ID `72 + 4n` and a companion five-member ARC at ID `73 + 4n`, for `n = 0..51`. Forty-eight VH records and ARC member 2 bodies are nonempty; the other four pairs are both empty. The VH and VB bytes are identical across the local original Japan, Japan Rev.1, and USA releases. [`inspect_vab.py`](../../../tools/research/inspect_vab.py) checks the complete structure below against Japan Rev.1 and USA; the original Japan comparison is covered separately by [`compare_japan_revisions.py`](../../../tools/research/compare_japan_revisions.py).

The [Sony File Formats manual](https://psx.arthus.net/sdk/Psy-Q/DOCS/FileFormat47.pdf) defines a VAB as a 32-byte header, a fixed 128-entry program table, a variable tone table, a 256-entry VAG size table, and raw waveform data. Sony's [Run-Time Library Reference](https://psx.arthus.net/sdk/Psy-Q/DOCS/LibRef47.pdf) defines the `VabHdr`, `ProgAtr`, and `VagAtr` structures. Tekken 3 stores the header/tables in the BNS `.vh` record and the waveform bytes in ARC member 2; joining them yields the declared VAB file size exactly.

## Verified VH layout

All integer fields are little-endian. Byte offsets are relative to the beginning of the `.vh` BNS record.

| Offset | Type / bytes | Meaning and local check |
|---:|---|---|
| `0x00` | `pBAV` | On-disc little-endian representation of Sony's `VABp` signature. |
| `0x04` | `u32` | Version `7` in all 48 banks. |
| `0x08` | `u32` | VAB ID `0` in all 48 banks. |
| `0x0C` | `u32` | Total file size; equals `VH byte length + ARC member 2 byte length` in every bank. |
| `0x10` | `u16` | Reserved value `0xEEEE` in all 48 banks. |
| `0x12` | `u16 ps` | Number of nonempty programs; 1 or 2 here. |
| `0x14` | `u16 ts` | Total number of active tones. |
| `0x16` | `u16 vs` | Number of waveform samples; 9–22 here. |
| `0x18` | `u8` | Master volume. |
| `0x19` | `u8` | Master pan. |
| `0x1A..0x1B` | two `u8` | User-defined bank attributes. |
| `0x1C` | `u32` | Reserved value `0xFFFFFFFF` in all 48 banks. |
| `0x20..0x81F` | `128 × 16` bytes | Fixed program attribute table. |
| `0x820..` | `ps × 16 × 32` bytes | Sixteen tone slots for each nonempty program, in ascending program-number order. |
| `0x820 + ps × 0x200` | `256 × u16` | VAG size table; ends exactly at VH EOF. |

In the program table, entry `p` starts at `0x20 + 16p`. Its first byte is the number of active tones in that program (`0..16`); the remaining fields follow Sony's 16-byte `ProgAtr`, including master volume at `+1`, priority at `+2`, mode at `+3`, and pan at `+4`. Counting nonzero first bytes yields `ps`, and summing them yields `ts` in every bank. The local set has **72 nonempty programs** and **788 active tones** across 48 banks.

Each 32-byte `VagAtr` tone slot includes priority, mode, volume, pan, center note, tuning and note limits in its first bytes; ADSR1 and ADSR2 are little-endian `u16` at `+16` and `+18`, followed by signed `i16` program number at `+20` and VAG ID at `+22`. A tone block belongs to the corresponding nonempty program; all 16 slots, including unused slots, carry that program number. In every active slot, the program reference matches its owner and the VAG ID lies in `0..vs`. A VAG ID of zero occurs in **three** active tones: VH BNS IDs `127`, `131`, and `223`, program 1, tone 0. These must not be rejected as malformed or dereferenced as waveform 0. Unused slots have VAG ID zero.

## VAG size table and VB segmentation

The 256 `u16` table entries are *sizes*, not absolute offsets. Entry 0 and every entry after `vs` are zero in all banks. For VAG IDs `1..vs`:

```text
size_bytes(vag_id) = size_table[vag_id] << 3
vb_offset(1) = 0
vb_offset(vag_id + 1) = vb_offset(vag_id) + size_bytes(vag_id)
```

The cumulative end of VAG `vs` equals ARC member 2 length in every bank, without padding or an unexplained tail. Each size is a positive multiple of 16 bytes. Across the 48 banks, the table splits **3,077,088 VB bytes into 785 samples**, from 336 to 18,576 bytes each. The apparent disparity between 788 active tone slots and 785 samples consists of the three VAG-ID-zero tones above.

The VB bytes admit consecutive 16-byte SPU-ADPCM frames. In all **192,318** frames, the first byte's high nibble is `0..4`, its low nibble is `0..12`, and the second byte has no bits above `0x07`. Each of the 785 samples starts with one all-zero 16-byte frame. Sony's [Run-Time Library Overview](https://psx.arthus.net/sdk/Psy-Q/DOCS/Devrefs/Libovr.pdf) describes an extra `00 07 77 … 77` IRQ-clear block at the end of one-shot VAGs. Exactly **775** local samples have that full 16-byte block, preceded by a frame with flag `0x01`; their second frame has flag `0x04`. The remaining **10** samples have no IRQ-clear block, contain exactly one frame flagged `0x06`, and end with flag `0x03`. These ten are consistent with SPU loop start/end flag semantics; five reuse one 37-frame waveform and five reuse one 247-frame waveform across banks.

## SPU-ADPCM to PCM

[`decode_vab_sample.py`](../../../tools/research/decode_vab_sample.py) implements the [FFmpeg PSX ADPCM decoder](https://github.com/FFmpeg/FFmpeg/blob/master/libavcodec/adpcm.c) for the observed mono VAB samples. Each 16-byte frame holds a predictor/shift byte, a flag byte, and 14 bytes of 4-bit signed residuals. The *low* nibble comes before the high nibble, yielding 28 PCM samples per frame. Predictor history starts at zero for each VAG and continues across its frames.

```text
coefficients[0..4] = (0,0), (60,0), (115,-52), (98,-55), (122,-60)
filter = frame[0] >> 4
shift  = frame[0] & 15
flag   = frame[1]

for packed_byte in frame[2:16]:
    for nibble in (packed_byte & 15, packed_byte >> 4):
        residual = nibble if nibble < 8 else nibble - 16
        scaled = (residual << 12) >> shift       # arithmetic right shift
        correction = trunc_toward_zero((previous * c1 + older * c2) / 64)
        decoded = scaled + correction if flag < 7 else 0
        emit clip_to_signed_16_bit(decoded)
        older, previous = previous, decoded      # retain unclipped history
```

This integer rule decoded all 785 bounded samples into 5,363,204 PCM values without a frame error. It produced byte-for-byte identical little-endian PCM to FFmpeg for a one-shot sample (VH ID 72, VAG 1) after omitting its 28-sample silent guard frame, and for a looping sample (VH ID 192, VAG 12) including its end frame. The wrapper VAGs used for that comparison were temporary files with an explicitly chosen 44,100 Hz rate; the source VH/VB data has no standalone VAG header or sample-rate field. Decoder agreement establishes the PCM conversion; the game's playback rate, volume, pan and envelope are in [sound.md](../code/sound.md).

For an export that preserves a loop, set `loop_start_pcm = 28 × index_of_flag_0x06_frame` and `loop_end_pcm = 28 × frame_count`, with the end exclusive. The observed loop-start frame indexes are 33 or 189. `decode_vab_sample.py` writes these bounds as a standard WAV `smpl` loop (end inclusive). For one-shot samples, omit the terminal `00 07 77 … 77` guard frame from audible PCM; keep the initial all-zero lead-in frame. The raw VH/VB bytes carry no sample rate; the exporter uses the game's playback rate from the tone's key and tuning ([sound.md](../code/sound.md#playback-rate)) unless `--sample-rate` overrides it.

## Converter boundary

A converter can reconstruct exact VH/VB slices, program and tone references, raw samples, FFmpeg-equivalent PCM, and the observed loop bounds. Preserve VAG ID zero as a tone without a local waveform. The game always plays tone `t` at key `60 + t`, so each sample's playback rate follows from its tone's centre note and fine tuning ([sound.md](../code/sound.md#playback-rate), verified by running `SsPitchFromNote` in the harness): 22,050, 16,042, 11,025, 7,957 or 7,095 Hz for the tunings found here. Volume, pan and ADSR follow the libsnd rules in [sound.md](../code/sound.md#playback-rate) (VH values used verbatim, no positional panning); reverb is switched off (`SoundSelectBanks` sets depth 0 and releases the work area), so there is no effect routing. Embedding loop metadata in a target format is left to the converter. The emitted WAV's caller-supplied sample rate is an explicit preview choice, not a recovered game value. No sampled audio has yet been claimed as playback-equivalent.

Run `python3 tools/research/inspect_vab.py` to reproduce the Japan Rev.1/USA bank counts, table bounds, program/tone linkage and frame-header scan without exporting game samples. For one local preview, run `python3 tools/research/decode_vab_sample.py --vh-id 72 --vag-id 1 --sample-rate 44100 --out work/vag1.wav`; the chosen rate is only for inspection.
