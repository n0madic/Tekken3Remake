shader_type spatial;
// The panorama is unlit in the game: texels modulated by the packet colour (0x80 = 1).
// Only the faces turned to the arena are drawn: from outside the panorama's box (the round intro
// camera starts beyond the walls, the overhead KO camera looks down from above the sky) the game
// shows the arena, not the outside of the wall or sky in front of the camera.
// The camera rig's coverage (tools/remake_import/stage.py) counts only these faces too.
render_mode unshaded, cull_back, depth_draw_opaque;

#ifdef CRISP
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
#else
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
#endif

void fragment() {
	vec4 texel = texture(atlas, UV);
	if (texel.a < 0.5) {
		discard;
	}
	ALBEDO = texel.rgb * COLOR.rgb * 2.0;
}
