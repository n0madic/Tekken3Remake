shader_type spatial;
// The arcade's polygonal stage scene (docs/research/arcade/stages.md#scene-drawing):
// unlit texels times the corner's colour factor (CUSTOM1.rgb, linear: a textured packet's colour
// with 0x80 = 1, an untextured one's colour itself on a white texel), front faces only
// (FUN_801DB560 drops a polygon whose NCLIP is not positive).
// UV is in atlas texels. CUSTOM0 = (x, y, w, h) of a GPU texture window in the atlas: with w > 0
// UV holds page texels that repeat inside that rectangle (the packets with mode bit 0x80).
// Stages 6 and 12 animate one rectangle of the atlas (FUN_801E2114): with frame ≥ 0 its texels
// come from that frame of `frames` (the frames one below the other), also in the atlas gutter
// around it.
render_mode unshaded, cull_back, depth_draw_opaque;

#ifdef CRISP
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
#else
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
#endif

#ifdef CRISP
uniform sampler2D frames : source_color, filter_nearest, repeat_disable;
#else
uniform sampler2D frames : source_color, filter_linear, repeat_disable;
#endif
uniform vec4 frames_rect = vec4(0.0);   // x, y, w, h in atlas texels
uniform int frame = -1;
const float GUTTER = 2.0;               // atlas.py's gutter

varying flat vec4 window;
varying vec3 factor;

void vertex() {
	window = CUSTOM0;
	factor = CUSTOM1.rgb;
}

void fragment() {
	vec2 texel = UV;
	if (window.z > 0.0) {
		texel = window.xy + mod(UV, window.zw) + 0.5;
	}
	vec4 colour = texture(atlas, texel / vec2(textureSize(atlas, 0)));
	vec2 local = texel - frames_rect.xy;
	if (frame >= 0 && all(greaterThanEqual(local, vec2(-GUTTER))) && all(lessThan(local, frames_rect.zw + GUTTER))) {
		local = clamp(local, vec2(0.5), frames_rect.zw - 0.5) + vec2(0.0, float(frame) * frames_rect.w);
		colour = texture(frames, local / vec2(textureSize(frames, 0)));
	}
	if (colour.a < 0.5) {
		discard;
	}
	ALBEDO = colour.rgb * factor;
}
