"""The fight HUD's name sprites by costume key (hud.py): no game data."""

from __future__ import annotations

import unittest

import hud


class NameSprites(unittest.TestCase):
    def test_a_slot_shared_by_two_keys_has_each_keys_colours(self) -> None:
        # Slot 36 is Nina's third costume (key 22, yellow) and Anna's first (key 72, red).
        slots = [-1] * hud.COSTUME_KEY_COUNT
        slots[22] = slots[72] = 36
        sprites = hud.name_sprites(slots)
        self.assertEqual(sprites[22], (36, 2, hud.NAME_UV[1]))
        self.assertEqual(sprites[72], (36, 0, hud.NAME_UV[1]))

    def test_force_enemies_stack_their_names_on_the_first_colours(self) -> None:
        slots = [-1] * hud.COSTUME_KEY_COUNT
        for i, key in enumerate(hud.FORCE_ENEMY_KEYS):
            slots[key] = 47 + i
        sprites = hud.name_sprites(slots)
        self.assertEqual(sprites[0x54], (47, 0, 0))
        self.assertEqual(sprites[0x57], (50, 0, 3 * hud.NAME_HEIGHT))

    def test_unused_and_placeholder_keys_have_no_name(self) -> None:
        slots = [-1] * hud.NAMED_KEYS + [0] * (hud.COSTUME_KEY_COUNT - hud.NAMED_KEYS)
        self.assertEqual(hud.name_sprites(slots), {})


if __name__ == "__main__":
    unittest.main()
