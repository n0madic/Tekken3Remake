shader_type spatial;
// The stage floor: the converted 10 × 10 tile pattern repeating over the ground up to and
// under the panorama walls. Texture coordinates come from the world position:
// u = x / size + 0.5, v = z / size + 0.5 in Godot space (the pattern's rows run towards
// the game's −z), so the tiles show no seams.

#ifdef CRISP
uniform sampler2D pattern : source_color, filter_nearest_mipmap, repeat_enable;
#else
uniform sampler2D pattern : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
#endif
uniform float pattern_size = 18.0;
// The tile-map stages draw their backdrop over the floor beyond the map's bottom edge: the
// floor ends where dot(xz, far_edge.xy) > far_edge.z (Godot space; off by default).
uniform vec3 far_edge = vec3(0.0, 0.0, 1.0e9);
// The spotlight floors (stages.md#floor, kinds 1–4; FUN_80049AE0): the brightness is
// min(K / r², limit) / 128 with r the floor distance to a light point, or the sum of two for
// kind 1 (spot_lights = (a.x, a.z, b.x, b.z) in Godot units, spot_k = K in square metres).
uniform int spot_kind = 0;
uniform vec4 spot_lights = vec4(0.0);
uniform float spot_k = 0.0;
uniform float spot_limit = 254.0;
// Kind 0's distance shading (FloorDrawGrid): the brightness is 128 + table[i] · shade >> 7
// (clamped to 0–254, 128 unchanged), i = min(max(depth − camera_distance, 0) · fade_scale >> 16,
// 1023), with the depth along the view in game units.
uniform sampler2D fade_table : filter_nearest;
uniform int shade = 0;
uniform int fade_scale = 0;
uniform float camera_distance = 0.0;
uniform float units_per_metre = 1.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(world_position.xz, far_edge.xy) > far_edge.z) {
		discard;
	}
	vec2 uv = world_position.xz / pattern_size + 0.5;
	ALBEDO = texture(pattern, uv).rgb;
	if (spot_kind != 0) {
		vec2 a = world_position.xz - spot_lights.xy;
		float level = spot_k / max(dot(a, a), 1.0e-6);
		if (spot_kind == 1) {
			vec2 b = world_position.xz - spot_lights.zw;
			level += spot_k / max(dot(b, b), 1.0e-6);
		}
		ALBEDO *= min(level, spot_limit) / 128.0;
	} else if (shade != 0) {
		float beyond = max(-VERTEX.z * units_per_metre - camera_distance, 0.0);
		int i = min(int(floor(beyond * float(fade_scale) / 65536.0)), 1023);
		int step = int(round(texelFetch(fade_table, ivec2(i, 0), 0).r * 255.0));
		float level = clamp(128.0 + floor(float(step * shade) / 128.0), 0.0, 254.0);
		ALBEDO *= level / 128.0;
	}
	ROUGHNESS = 0.9;
}
