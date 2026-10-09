shader_type sky;
// The arcade's sky (docs/research/arcade/stages.md#sky) as the environment's background.
// FUN_801A7688 lays a tiled picture out on the 512 × 480 screen: the screen's left edge shows
// strip pixel ((−yaw) & 0xFFF)·512 / step, the sky's top row lies −pitch·k / 256 + offset lines
// down from the screen's top (after the stage's clamps), and the strip's pixels are the screen's.
// The camera's yaw and pitch only scroll it: the picture is fixed to the screen, not to the world.
// Here a direction's screen position comes from the camera's view (`view`, world → camera) in
// the original 4:3 frame, which spans ±frame_tan in view-plane units (CameraRig.frame_tan): 512
// pixels across and 480 lines down, extended beyond it in wider or taller windows. StageView.place_sky
// sets `scroll` (the strip pixel at the frame's left edge) and `sky_top` (the top row's line)
// every rendered frame.
// In fights the arcade draws the sky with the camera's yaw minus the backdrop's turn
// (FUN_801D8FD0), so the sky turns with the scene (StageView.set_backdrop_turn).

#ifdef CRISP
uniform sampler2D strip : source_color, filter_nearest, repeat_disable;
#else
uniform sampler2D strip : source_color, filter_linear, repeat_disable;
#endif
uniform int kind = 0;                 // 0 tiles, 1 gradient, 2 one colour
uniform mat3 view = mat3(1.0);        // world → camera (Godot axes: −z forward, +y up)
uniform vec2 frame_tan = vec2(0.368, 0.276);  // the 4:3 frame's half extent in view-plane units
uniform float scroll = 0.0;           // strip pixel at the frame's left edge
uniform float sky_top = 0.0;          // line of the sky's top row (480-line frame)
uniform float turn_pixels = 4608.0;   // strip pixels in a full turn of the yaw
uniform float rows = 4.0;
uniform vec4 upper_fill : source_color = vec4(0.0);  // a = 1: drawn above the sky
uniform vec4 lower_fill : source_color = vec4(0.0);  // a = 1: drawn below the sky
uniform vec3 gradient_top : source_color = vec3(0.0);
uniform vec3 gradient_bottom : source_color = vec3(0.0);

const float TILE = 64.0;
const float HALF_WIDTH = 256.0;       // the 512-pixel screen
const float HALF_HEIGHT = 240.0;      // the 480-line screen
const float GRADIENT_ROWS = 192.0;   // the stage 3 gradient spans 0xC0 lines

void sky() {
	vec3 d = view * EYEDIR;
	// Directions behind the camera (never on screen) take the fills by their side of the horizon.
	float depth = max(-d.z, 1.0e-4);
	float row = HALF_HEIGHT - HALF_HEIGHT * d.y / depth / frame_tan.y - sky_top;
	if (d.z >= 0.0) {
		row = d.y > 0.0 ? -1.0 : 1.0e9;
	}
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
		vec2 size = vec2(textureSize(strip, 0));
		float column = scroll + HALF_WIDTH + HALF_WIDTH * d.x / depth / frame_tan.x;
		// Beyond the arcade's 512 pixels (wider windows) the picture continues round the turn.
		if (column < 0.0) {
			column += turn_pixels;
		} else if (column >= size.x) {
			column -= turn_pixels;
		}
		vec4 texel = texture(strip, vec2(column, row) / size);
		colour = texel.rgb * step(0.5, texel.a);
	}
	COLOR = colour;
}
