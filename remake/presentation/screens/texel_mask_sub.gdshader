shader_type canvas_item;
render_mode blend_sub;

// The PSX's B−F through a CLUT whose entries are all white but the transparent 0 (select.ovl's
// 0x7FD0): each opaque texel of the texture subtracts the vertex colour.

varying vec4 shade;

void vertex() {
	shade = COLOR;
}

void fragment() {
	COLOR = vec4(shade.rgb, texture(TEXTURE, UV).a);
}
