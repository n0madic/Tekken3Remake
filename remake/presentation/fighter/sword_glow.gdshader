shader_type spatial;
// The sword glow's ribbon (SwordGlowView): additive (B + F), the game's quads over the picture and
// behind the nearer parts. The vertices are in view space, each quad at the depth of its
// ordering-table entry (the same depth as the fighters' faces). COLOR is the game's vertex colour
// (0x80 = 1.0) interpolated in display values; it multiplies the texel of `levels` (grey, five bits
// a channel; a column of white serves the quads without a picture) and the product, a display
// value, is turned into the linear colour that is added.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D levels : filter_linear, repeat_disable;

vec3 to_linear(vec3 display) {
	vec3 curve = pow((display + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(display / 12.92, curve, step(vec3(0.04045), display));
}

void fragment() {
	ALBEDO = to_linear(COLOR.rgb * texture(levels, UV).r);
	ALPHA = 1.0;
}
