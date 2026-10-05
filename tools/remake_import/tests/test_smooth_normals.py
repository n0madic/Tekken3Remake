"""The fighters' smooth normals and curved edges (character.smooth_normals, smooth_edges) on
synthetic faces: no game data."""

from __future__ import annotations

import math
import unittest

import character
from character import Term

UP = (0.0, 1.0, 0.0)
SIDE = (1.0, 0.0, 0.0)
TILTED = (0.0, math.cos(math.radians(30)), math.sin(math.radians(30)))


def _faces(*quads: tuple[Term, ...]) -> list:
    """Single-sided body faces whose corners are one part-local vertex each, lit by its own normal."""
    return [(False, -1, [(0, ((t, 1.0),), t, 0, 0) for t in quad]) for quad in quads]


def _run(faces: list, normals: dict, positions: dict) -> tuple[dict, dict, set]:
    smooth, keys = character.smooth_normals(faces, positions.__getitem__, normals.__getitem__)
    return smooth, keys, character.smooth_edges(faces, keys, smooth)


class SmoothNormalsTest(unittest.TestCase):
    def setUp(self) -> None:
        # Two quads of part 0 sharing the edge (x = 1): corners 0..5, each with its own term so
        # the shared points are found by position, as duplicated KMD vertices are.
        self.positions = {}
        coords = [(0, 0, 0), (1, 0, 0), (0, 0, 1), (1, 0, 1), (1, 0, 0), (2, 0, 0), (1, 0, 1), (2, 0, 1)]
        self.terms = [Term(0, 0, i) for i in range(len(coords))]
        for t, p in zip(self.terms, coords):
            self.positions[t] = p

    def test_shared_points_average_close_normals(self) -> None:
        t = self.terms
        normals = {**{x: UP for x in t[:4]}, **{x: TILTED for x in t[4:]}}
        faces = _faces(tuple(t[:4]), tuple(t[4:]))
        smooth, _, edges = _run(faces, normals, self.positions)
        s_own, part_own, s_other, part_other = smooth[(0, 1)]   # the left quad's corner at (1, 0, 0)
        for got, want in zip(s_own, (UP[i] + TILTED[i] for i in range(3))):
            self.assertAlmostEqual(got, want)
        self.assertEqual((part_own, s_other, part_other), (0, (0.0, 0.0, 0.0), 0))
        self.assertEqual(smooth[(0, 0)][0], UP)           # an unshared corner keeps its normal
        self.assertEqual(len(edges), 1)                   # the shared edge may bulge

    def test_crease_keeps_normals_apart(self) -> None:
        t = self.terms
        normals = {**{x: UP for x in t[:4]}, **{x: SIDE for x in t[4:]}}
        faces = _faces(tuple(t[:4]), tuple(t[4:]))
        smooth, _, edges = _run(faces, normals, self.positions)
        self.assertEqual(smooth[(0, 1)][0], UP)
        self.assertEqual(smooth[(1, 0)][0], SIDE)
        self.assertEqual(edges, set())                    # a crease stays straight

    def test_hand_edges_stay_straight(self) -> None:
        t = self.terms
        normals = {x: UP for x in t}
        faces = _faces(tuple(t[:4]), tuple(t[4:]))
        faces[1] = (False, 6, faces[1][2])                # the right quad belongs to a hand
        _, _, edges = _run(faces, normals, self.positions)
        self.assertEqual(edges, set())

    def test_seam_halves_live_in_both_joints(self) -> None:
        # A corner blended from parts 0 and 1, lit once in each part's joint.
        a, b = Term(0, 0, 0), Term(1, 1, 0)
        positions = {a: (0, 0, 0), b: (5, 0, 0)}
        normals = {a: UP, b: SIDE}
        faces = [(False, -1, [(0, ((a, 0.5), (b, 0.5)), a, 0, 0)]), (False, -1, [(0, ((a, 0.5), (b, 0.5)), b, 0, 0)])]
        smooth, _ = character.smooth_normals(faces, positions.__getitem__, normals.__getitem__)
        self.assertEqual(smooth[(0, 0)], (UP, 0, SIDE, 1))   # its own joint's half, then the other's
        self.assertEqual(smooth[(1, 0)], (SIDE, 1, UP, 0))

    def test_groups_are_transitive(self) -> None:
        # Three faces at one point: A and C are 100 degrees apart, B within 50 of each, so all
        # three corners get the same sum (no per-corner neighbourhoods that disagree).
        terms = [Term(0, 0, i) for i in range(9)]
        positions = {t: (0, 0, 0) if i % 3 == 0 else (i, 0, 0) for i, t in enumerate(terms)}

        def tilt(degrees: float) -> tuple[float, float, float]:
            return (math.sin(math.radians(degrees)), math.cos(math.radians(degrees)), 0.0)

        normals = {}
        for f, degrees in enumerate((-50.0, 0.0, 50.0)):
            for t in terms[3 * f:3 * f + 3]:
                normals[t] = tilt(degrees)
        faces = [(False, -1, [(0, ((t, 1.0),), t, 0, 0) for t in terms[3 * f:3 * f + 3]]) for f in range(3)]
        smooth, _ = character.smooth_normals(faces, positions.__getitem__, normals.__getitem__)
        sums = {smooth[(f, 0)][0] for f in range(3)}
        self.assertEqual(len(sums), 1)


if __name__ == "__main__":
    unittest.main()
