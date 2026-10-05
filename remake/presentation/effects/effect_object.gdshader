shader_type spatial;
// The additive page (tpage 0x3F: B + F).
render_mode unshaded, skip_vertex_transform, depth_draw_never, cull_disabled, blend_add;

#include "res://presentation/effects/effect_object.gdshaderinc"

// Brighter than white, as the additive flipbooks (EffectsView.HDR_BOOST), so the glow catches it.
uniform float hdr_boost = 1.0;

void fragment() {
	vec4 c = texel_colour(UV);
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb * hdr_boost;
}
