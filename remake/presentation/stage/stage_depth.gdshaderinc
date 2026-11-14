// The stage's depth band. The game's ordering table draws the floor, the panorama and the
// arcade scene in its farthest entries (FloorDrawGrid links the floor at the scene table's
// +0xFF4 − 4n, the panorama at +0xFC8 or +0xFF4), so they never hide a fighter or an effect:
// a body that lies partly under the floor is drawn over it. A depth buffer would cut it at the
// floor's plane, so the stage's fragments are drawn into a thin band at the far end of the depth
// range instead, behind everything else; they keep their order among themselves (the mapping is
// linear in the depth value). Depth is reversed (near = 1, far = 0), as in all three renderers.
// The band lies behind anything within STAGE_DEPTH_RANGE of the camera (tests/presentation/
// test_stage_depth.gd): the fighters (the table ends at 32.7 m), the effects, the ball, the items.
//
// The band is as wide as that allows, and it holds the depths from STAGE_DEPTH_NEAR ahead of the
// camera outwards, not from the camera's near plane: the reversed depth spends half its values on
// the first 5 cm, where no stage surface is. That matters on a 24-bit depth buffer (the Mobile
// renderer on Android GPUs, which Godot gives D24S8 where they have it; the web): from the near
// plane the band told apart stage surfaces at 10 m only 0.15 m apart, so the arcade scene's eaves,
// pillars and balustrade bases z-fought and flickered as the camera moved. From STAGE_DEPTH_NEAR it
// tells them apart 2 mm apart at 10 m, 2 cm at 30 m. A 32-bit float buffer (Forward+, and Mobile
// on Apple GPUs) is exact either way.
// A stage surface nearer than STAGE_DEPTH_NEAR rises above the band, but it still lies behind
// anything less than 12 times as far (test_stage_depth.gd). The floor comes that near, and what
// lies under it is right behind it; the arcade scene comes to 1.4 m in a few frames (stage 5's
// opening), which leaves the fighters (within 10 m) in front of it.
//
// Only the camera's own pass is shifted: the shadow passes (an orthographic projection for the
// sun) keep the true depth, so the floor and the props shadow as they are.
//
// Forward+ and Mobile shift the clip-space depth of the vertices (it is linear across a
// triangle, so the pixels are exact, and the depth pre-pass and the SSAO pass see the same
// values). Writing DEPTH from a fragment shader there does not work with the pre-pass (the floor
// fails the colour pass's depth test). The Compatibility renderer has no pre-pass, and its
// vertex path is not the same: it writes DEPTH from the fragment.
//
// Use: `STAGE_DEPTH_VERTEX` last in vertex(), `STAGE_DEPTH_FRAGMENT` in fragment().
// The band's numbers are checked against the camera and the backdrop quad in
// tests/presentation/test_stage_depth.gd.

const float STAGE_DEPTH_BASE = 2.0e-5;
const float STAGE_DEPTH_SPAN = 7.8e-4;
const float STAGE_DEPTH_RANGE = 50.0;     // metres
const float STAGE_DEPTH_NEAR = 4.0;       // metres: the band's top

// The band's scale: the depth of a point STAGE_DEPTH_NEAR ahead maps to the band's top.
float stage_depth_scale(mat4 projection) {
	vec4 c = projection * vec4(0.0, 0.0, -STAGE_DEPTH_NEAR, 1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// OpenGL's clip space runs from −1 to 1; the window depth the fragment writes from 0 to 1.
	return STAGE_DEPTH_SPAN / (0.5 * c.z / c.w + 0.5);
#else
	return STAGE_DEPTH_SPAN * c.w / c.z;
#endif
}

// A shader that writes POSITION or DEPTH writes it on every path: the engine's own value first.
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
#define STAGE_DEPTH_VERTEX
#define STAGE_DEPTH_FRAGMENT DEPTH = PROJECTION_MATRIX[3][3] == 0.0 ? STAGE_DEPTH_BASE + FRAGCOORD.z * stage_depth_scale(PROJECTION_MATRIX) : FRAGCOORD.z;
#else
#define STAGE_DEPTH_VERTEX POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)); if (PROJECTION_MATRIX[3][3] == 0.0) { POSITION.z = POSITION.z * stage_depth_scale(PROJECTION_MATRIX) + STAGE_DEPTH_BASE * POSITION.w; }
#define STAGE_DEPTH_FRAGMENT
#endif
