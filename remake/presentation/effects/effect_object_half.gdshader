shader_type spatial;
// The 50 % page (tpage 0x1F: B / 2 + F / 2).
render_mode unshaded, skip_vertex_transform, depth_draw_never, cull_disabled, blend_mix;

#include "res://presentation/effects/effect_object.gdshaderinc"

void fragment() {
	vec4 c = texel_colour(UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
	ALPHA = 0.5;
}
