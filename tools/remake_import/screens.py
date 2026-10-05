"""The attract loop's 2D screens: the title pictures, their texts and the text colours.

- `screens/title.png`, `screens/title_enbu.png`: the 368 × 480 title picture of `title.ovl`
  (archive `0x800EC570`) and the red-lightning variant `enbu.ovl` shows after the
  demonstration (archive `0x800B9E60`), assembled from their six strips as FUN_800DAAD8 draws
  them (menu_sim.title_backdrop);
- `screens/namco.png`, `screens/namco_enbu.png`: the Namco logo drawn above the copyright;
- `icon.png`: the application icon, the TEKKEN 3 logo cut square from the title picture, and
  Android's adaptive layers `icon_foreground.png` (the logo inside the 66 % safe zone the launcher
  never masks), `icon_background.png` (black) and `icon_monochrome.png` (the logo's bright parts);
- `screens/screens.json`: the texts (format escapes removed; the font's `@` is ©) with their
  colour, font and position on the 368 × 480 screen, and the text colours: per font and
  colour index the palette's top, bottom and outline entries (the glyphs shade from entry 1
  to entry 10 over an entry-11 outline).
"""

from __future__ import annotations

import struct

import numpy as np
from PIL import Image

from common import Disc, Output
from vram import Vram, png_bytes, rgba, unpack_indices
import overlay_images
import sources
import system_textures

SCREEN_W, SCREEN_H = 0x170, 0x1E0
TITLE_ARCHIVE = 0x800EC570
ENBU_ARCHIVE = 0x800B9E60
# FUN_800DAAD8: screen position of each strip member (the six strips, then the logo).
STRIPS = ((0, 0), (0x80, 0), (0x100, 0), (0, 0x100), (0x80, 0x100), (0x100, 0x100))
LOGO_MEMBER = 6
OPTIONS_STRIPS = 9                 # title.ovl's archive: the options backdrop's six strips (CLUT rows 500–505)
PAD_ARCHIVE = 0x800D5384           # title.ovl: the key configuration's pad pictures (digital, analog)
LOGO_AT = (0x97, 0x184)
ICON_CROP = (28, 44, 312)          # the title picture's logo: x, y and side of the square
ICON_SIZE = 256
ADAPTIVE_SIZE = 432                # Android's adaptive layers (108 dp at xxxhdpi)
ADAPTIVE_SAFE = 0.64               # the share of the layer a launcher's mask always shows
MONOCHROME_LEVEL = 110             # the luminance from which the logo counts in the monochrome layer
FONT_TABLE = 0x80021FD0            # 16 bytes per font; +0xE CLUT offset
FONTS = 3
COLOURS = 16
TEXT_CLUT_X, TEXT_CLUT_Y = 256, 504
GRADIENT_TOP, GRADIENT_BOTTOM, OUTLINE = 1, 10, 11
PRESENTS = 0x80022678
START_PROMPTS = 0x80022328         # 4 × (string, half width): no pad, P1, P2, both
COPYRIGHT = (0x800B9378, 0x800B93A0)   # title.ovl
COPYRIGHT_AT = ((0x2D, 0x19C), (0x2D, 0x1B0))
PROMPT_Y = 0x16C
PRESENTS_AT = (0x75, 0xF0)


def _blocks(tim: bytes) -> dict[str, tuple[int, int, int, int]]:
    """A TIM's blocks by kind: x, y, w, h in VRAM words."""
    return {kind: (x, y, w, h) for kind, x, y, w, h, _ in system_textures.tim_blocks(tim)}


def _tim_source(tim: bytes, palette_tim: bytes | None = None) -> tuple[Vram, int, int, int, int, int, np.ndarray]:
    """A TIM uploaded as the game does (its CLUT row belongs to it), or its pixels with another
    TIM's CLUT (a CLUT-only TIM uploaded for this picture): the VRAM, the picture's first texel
    (x in texels of its depth, y), its size, depth and CLUT."""
    vram = Vram()
    vram.upload_tim(tim)
    blocks = _blocks(tim)
    x, y, w, h = blocks["image"]
    if palette_tim is None:
        cx, cy, _, _ = blocks["clut"]
    else:
        vram.upload_tim(palette_tim)
        cx, cy, _, _ = _blocks(palette_tim)["clut"]
    depth = 8 if struct.unpack_from("<I", tim, 4)[0] & 7 == 1 else 4
    per_word = 16 // depth
    return vram, x * per_word, y, w * per_word, h, depth, vram.words[cy, cx:cx + (1 << depth)]


def _tim_rgba(out: Output, rel: str | None, x: int, y: int, tim: bytes, palette_tim: bytes | None = None) -> np.ndarray:
    """A TIM through its own CLUT, or through `palette_tim`'s; recorded as the VRAM piece drawn at
    (x, y) of picture `rel` (unless None)."""
    vram, tx, ty, w, h, depth, clut = _tim_source(tim, palette_tim)
    if rel is not None:
        sources.piece(out, rel, x, y, vram.words, tx, ty, w, h, depth, clut)
    per_word = 16 // depth
    return rgba(clut[unpack_indices(vram.words[ty:ty + h, tx // per_word:(tx + w) // per_word], depth)])


def _title(out: Output, rel: str, logo_rel: str | None, members: list[bytes]) -> tuple[np.ndarray, np.ndarray]:
    """The title picture of six strips and the logo (their pieces recorded for `rel`, `logo_rel`)."""
    picture = np.zeros((SCREEN_H, SCREEN_W, 4), dtype=np.uint8)
    for member, (sx, sy) in zip(members, STRIPS):
        strip = _tim_rgba(out, rel, sx, sy, member)
        h, w = strip.shape[:2]
        picture[sy:sy + h, sx:sx + w] = strip
    return picture, _tim_rgba(out, logo_rel, 0, 0, members[LOGO_MEMBER])


def _text(raw: str) -> str:
    """A format string's literal text: escapes (`%c`, `%f`, `%H`, `%V`) removed, `@` as ©."""
    out, i = [], 0
    while i < len(raw):
        if raw[i] == "%":
            i += 2
            continue
        out.append("©" if raw[i] == "@" else raw[i])
        i += 1
    return "".join(out)


def _colours(disc: Disc) -> list[list[list[list[int]]]]:
    words = disc.system_vram().words

    def colour(x: int, y: int) -> list[int]:
        return [int(c) for c in rgba(words[y, x:x + 1])[0][:3]]

    fonts = []
    for font in range(FONTS):
        offset = disc.exe_u8(FONT_TABLE + 16 * font + 0xE, 1)[0]
        palette = []
        for c in range(COLOURS):
            v = c + offset
            x, y = TEXT_CLUT_X + 16 * (v & 15), TEXT_CLUT_Y + (v >> 4)
            palette.append([colour(x + GRADIENT_TOP, y), colour(x + GRADIENT_BOTTOM, y), colour(x + OUTLINE, y)])
        fonts.append(palette)
    return fonts


def _icon(picture: np.ndarray) -> np.ndarray:
    """The application icon: the logo square of the title picture, scaled to ICON_SIZE."""
    x, y, side = ICON_CROP
    square = Image.fromarray(np.ascontiguousarray(picture[y:y + side, x:x + side]), "RGBA")
    return np.asarray(square.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS))


def _adaptive(icon: np.ndarray) -> dict[str, np.ndarray]:
    """Android's adaptive icon layers from the square icon."""
    inner = int(ADAPTIVE_SIZE * ADAPTIVE_SAFE)
    at = (ADAPTIVE_SIZE - inner) // 2
    logo = np.asarray(Image.fromarray(icon, "RGBA").resize((inner, inner), Image.LANCZOS))
    foreground = np.zeros((ADAPTIVE_SIZE, ADAPTIVE_SIZE, 4), dtype=np.uint8)
    foreground[at:at + inner, at:at + inner] = logo
    background = np.zeros((ADAPTIVE_SIZE, ADAPTIVE_SIZE, 4), dtype=np.uint8)
    background[..., 3] = 255
    monochrome = np.zeros_like(foreground)
    luminance = foreground[..., :3].astype(np.uint16).max(axis=-1)
    monochrome[..., :3] = 255
    monochrome[..., 3] = np.where(luminance >= MONOCHROME_LEVEL, 255, 0)
    return {"foreground": foreground, "background": background, "monochrome": monochrome}


def convert(disc: Disc, out: Output) -> None:
    for name, block, archive in (("", "title", TITLE_ARCHIVE), ("_enbu", "enbu", ENBU_ARCHIVE)):
        members = overlay_images.archive_members(*disc.source(block, archive))
        picture, logo = _title(out, f"screens/title{name}.png", f"screens/namco{name}.png", members)
        out.write(f"screens/title{name}.png", png_bytes(picture))
        if not name:
            icon = _icon(picture)
            out.write("icon.png", png_bytes(icon))
            for layer, pixels in _adaptive(icon).items():
                out.write(f"icon_{layer}.png", png_bytes(pixels))
        out.write(f"screens/namco{name}.png", png_bytes(logo))
        if not name:
            backdrop = np.zeros((SCREEN_H, SCREEN_W, 4), dtype=np.uint8)
            for member, palette, (sx, sy) in zip(members, members[OPTIONS_STRIPS:OPTIONS_STRIPS + 6], STRIPS):
                strip = _tim_rgba(out, "screens/options.png", sx, sy, member, palette)
                h, w = strip.shape[:2]
                backdrop[sy:sy + h, sx:sx + w] = strip
            out.write("screens/options.png", png_bytes(backdrop))
    for i, member in enumerate(overlay_images.archive_members(*disc.source("title", PAD_ARCHIVE))):
        out.write(f"screens/pad_{i}.png", png_bytes(_tim_rgba(out, f"screens/pad_{i}.png", 0, 0, member)))
    prompts = []
    for i in range(4):
        pointer, half_width = struct.unpack_from("<II", disc.exe_bytes(START_PROMPTS + 8 * i, 8))
        prompts.append({"text": _text(disc.exe_text(pointer)), "half_width": half_width})
    presents = _text(disc.exe_text(PRESENTS))
    first = presents.index(" ") + 1
    out.write_json("screens/screens.json", {
        "screen": [SCREEN_W, SCREEN_H],
        "presents": {"font": 0, "at": list(PRESENTS_AT),
                     "parts": [{"text": presents[:first], "colour": 2}, {"text": presents[first:], "colour": 6}]},
        "start_prompts": {"font": 0, "colour": 5, "centre_x": SCREEN_W // 2, "y": PROMPT_Y, "texts": prompts},
        "copyright": [{"text": _text(disc.text("title", a)), "font": 0, "colour": 6, "at": list(at)}
                      for a, at in zip(COPYRIGHT, COPYRIGHT_AT)],
        "logo_at": list(LOGO_AT),
        "text_colours": _colours(disc),
        "fonts": [dict(zip(("advance", "line", "width", "height"), disc.exe_s16(FONT_TABLE + 16 * f + 4, 4)))
                  for f in range(FONTS)],
    })
