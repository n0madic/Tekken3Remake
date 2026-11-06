// A flipbook sprite (effects.md#flipbooks): one frame of the strip on a quad that faces the camera at
// the sprite's point (the node's position and uniform scale; EffectsView.place moves and scales it
// near Tekken Ball's ball), drawn at the depth of the ordering-table entry the game files it under.
//
// FUN_80077158 files the sprite at slot (otz − 0x6E) >> 3 with otz = Z >> 2, the slot 1 for the dust
// ring's calls (flag 2): 440 units nearer than its centre, or over everything. The faces of the
// fighters stand at their own entries (fighter_skin.gdshaderinc, face_key_depth()), so at the sprite's
// true depth a hit spark on a body is cut by the nearer parts of that body, while in the game it is
// drawn over them. Every corner of the quad is drawn at the entry's depth in the camera's projection,
// as the fighters' faces are, so the depth test reproduces the table's order. The sprite goes into the
// table after the fighters' faces, which makes it the first drawn of its entry: the farthest of them.
//
// Use with `render_mode unshaded, skip_vertex_transform, depth_draw_never, cull_disabled` and a
// blend mode; the quad's corners are the mesh's VERTEX.xy.

const int SORT_BIAS_OTZ = 0x6E;               // FUN_80077158's `otz − 0x6E`, a quarter of the depth in game units
const int DUST_SLOT = 1;                      // the slot of the calls with flag 2
const float ENTRY_UNITS = 32.0;               // an ordering-table entry's depth in game units
const float ENTRY_LAST = 0.999;               // inside its entry the sprite is behind every face

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float frame_scale = 1.0;              // u across the frame: 1 / frames, negative when mirrored
uniform float frame_offset = 0.0;             // u of the frame's left edge (right edge when mirrored)
uniform vec4 tint = vec4(1.0);
uniform bool over_all = false;                // the dust ring: slot 1, over the fighters too
uniform float units_per_metre = 1000.0;       // WorldSpace.UNITS_PER_METRE
uniform float depth_near = 0.06;              // FaceKeys.NEAR_CLAMP: nothing is drawn nearer, in metres

// The depth, in the camera's projection, of the entry the game files a sprite centred at the view
// depth `view_z` under.
float sprite_depth_of(float view_z, mat4 projection) {
	int units = int(max(-view_z * units_per_metre, 0.0));
	int slot = over_all ? DUST_SLOT : max(((units >> 2) - SORT_BIAS_OTZ) >> 3, 0);
	float z = max((float(slot) + ENTRY_LAST) * ENTRY_UNITS / units_per_metre, depth_near);
	vec4 c = projection * vec4(0.0, 0.0, -z, 1.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// OpenGL's clip space runs from −1 to 1; the window depth the fragment writes from 0 to 1.
	return 0.5 * c.z / c.w + 0.5;
#else
	return c.z / c.w;
#endif
}

// The sprite's depth for the fragment shader, −1 for the orthographic shadow pass.
varying flat float sprite_depth;

void vertex() {
	vec3 centre = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	VERTEX = centre + vec3(VERTEX.xy * length(MODEL_MATRIX[0].xyz), 0.0);
	sprite_depth = -1.0;
	if (PROJECTION_MATRIX[3][3] == 0.0) {
		sprite_depth = sprite_depth_of(centre.z, PROJECTION_MATRIX);
	}
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	// A shader that writes POSITION must write it on every path: the engine's own value first. The
	// clip-space depth is linear across a triangle, so its corners at one depth make the quad flat.
	POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	if (sprite_depth >= 0.0) {
		POSITION.z = sprite_depth * POSITION.w;
	}
#endif
}

void fragment() {
	vec4 texel = texture(albedo_texture, vec2(UV.x * frame_scale + frame_offset, UV.y));
	ALBEDO = texel.rgb * tint.rgb;
	ALPHA = texel.a * tint.a;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// The Compatibility renderer has no depth pre-pass to keep in step: the fragment writes the depth.
	DEPTH = sprite_depth >= 0.0 ? sprite_depth : FRAGCOORD.z;
#endif
}
