shader_type sky;
// The arcade's sky (docs/research/arcade/stages.md#sky) as the environment's
// background. FUN_801A7688 scrolls a tiled picture by the camera's yaw and pitch: the screen's
// left edge shows strip pixel ((−yaw) & 0xFFF)·512 / step, and the sky's top lies
// −pitch·k / 256 + offset pixels (480-line display) down from the screen's top. Both are linear
// in the angles, so the picture behaves as a cylinder around the camera: a direction at yaw Y
// (4096 units) shows strip column (−Y mod 4096)·512 / step + 256 (the screen centre), and at
// elevation e shows row (top − e)·k / 256, where `top` is the elevation of the sky's top edge
// (set per step by StageView.set_view_pitch, after the stage's clamps).
// A direction (x, y, z) in Godot space has yaw atan2(−x, −z) (CameraRig.view_basis).
// In fights the arcade draws the sky with the camera's yaw minus the backdrop's turn
// (FUN_801D8FD0), so the sky turns with the scene (StageView.set_backdrop_turn).

#ifdef CRISP
uniform sampler2D strip : source_color, filter_nearest, repeat_disable;
#else
uniform sampler2D strip : source_color, filter_linear, repeat_disable;
#endif
uniform int kind = 0;                 // 0 tiles, 1 gradient, 2 one colour
uniform float yaw_step = 546.0;       // FUN_801A7688: span · 4096 / 360
uniform float pitch_scale = 288.0;    // k: pixels per 256 pitch units
uniform float turn = 0.0;             // the backdrop's turn (4096 units)
uniform float top = 0.0;              // elevation of the sky's top edge (4096 units)
uniform float rows = 4.0;
uniform vec4 upper_fill : source_color = vec4(0.0);  // a = 1: drawn above the sky
uniform vec4 lower_fill : source_color = vec4(0.0);  // a = 1: drawn below the sky
uniform vec3 gradient_top : source_color = vec3(0.0);
uniform vec3 gradient_bottom : source_color = vec3(0.0);

const float UNITS = 4096.0;
const float TILE = 64.0;
const float SCREEN_CENTRE = 256.0;
const float GRADIENT_ROWS = 192.0;   // the stage 3 gradient spans 0xC0 lines

void sky() {
	float elevation = asin(clamp(EYEDIR.y, -1.0, 1.0)) * UNITS / TAU;
	float row = (top - elevation) * pitch_scale / 256.0;
	vec3 colour = vec3(0.0);
	if (kind == 1) {
		colour = row < 0.0 ? gradient_top : mix(gradient_top, gradient_bottom, clamp(row / GRADIENT_ROWS, 0.0, 1.0));
	} else if (kind == 2) {
		colour = upper_fill.rgb * upper_fill.a;
	} else if (row < 0.0) {
		colour = upper_fill.rgb * upper_fill.a;
	} else if (row >= rows * TILE) {
		colour = lower_fill.rgb * lower_fill.a;
	} else {
		float yaw = atan(-EYEDIR.x, -EYEDIR.z) * UNITS / TAU - turn;
		float column = mod(-yaw, UNITS) * 512.0 / yaw_step + SCREEN_CENTRE;
		vec2 size = vec2(textureSize(strip, 0));
		vec4 texel = texture(strip, vec2(column, row) / size);
		colour = texel.rgb * step(0.5, texel.a);
	}
	COLOR = colour;
}
