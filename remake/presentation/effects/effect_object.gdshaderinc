// An effect object's sprite per MultiMesh instance (effects.md#common-conventions): the quad of its
// model in view space at the instance origin, corners INSTANCE_CUSTOM = (x0, y0, x1, y1) in metres
// (the game's y runs down), textured from the object page's 4-bit indices through one palette row:
// COLOR = (u0, v0, frame size, palette row) in texels. Index colours 0x0000 are transparent.

uniform sampler2D page : filter_nearest, repeat_disable;
uniform sampler2D palettes : source_color, filter_nearest, repeat_disable;

// Tekken Ball's solid ball, (x, y, z, radius) in world metres, radius 0 for none: a sprite nearer to
// the camera than the ball's centre is drawn over all of the ball in the game, so it is moved along
// its view ray to just in front of the sphere, scaled to look the same (EffectsView.pull_over_ball,
// which does the same for the flipbooks; the objects have no sort bias).
uniform vec4 ball = vec4(0.0);
uniform float ball_margin = 0.008;
uniform float min_pull = 0.25;

varying vec4 sprite;

void vertex() {
	sprite = COLOR;
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 q = INSTANCE_CUSTOM;
	float pull = 1.0;
	if (ball.w > 0.0) {
		vec3 ball_centre = (VIEW_MATRIX * vec4(ball.xyz, 1.0)).xyz;
		float front = -ball_centre.z - ball.w - ball_margin;
		float reach = ball.w + 0.5 * length(vec2(q.z - q.x, q.w - q.y));
		if (-centre.z < -ball_centre.z && -centre.z > front && front > 0.0 && distance(centre, ball_centre) < reach) {
			pull = max(front / -centre.z, min_pull);
		}
	}
	VERTEX = (centre + vec3(mix(q.x, q.z, UV.x), -mix(q.y, q.w, UV.y), 0.0)) * pull;
}

vec4 texel_colour(vec2 uv) {
	vec2 texel = floor(sprite.xy + min(uv * sprite.z, vec2(sprite.z - 0.001)));
	float index = texelFetch(page, ivec2(texel), 0).r * 255.0;
	return texelFetch(palettes, ivec2(int(index + 0.5), int(sprite.w + 0.5)), 0);
}
