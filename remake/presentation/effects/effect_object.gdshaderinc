// An effect object's sprite per MultiMesh instance (effects.md#common-conventions): the quad of its
// model in view space at the instance origin, corners INSTANCE_CUSTOM = (x0, y0, x1, y1) in metres
// (the game's y runs down), textured from the object page's 4-bit indices through one palette row:
// COLOR = (u0, v0, frame size, palette row) in texels. Index colours 0x0000 are transparent.

uniform sampler2D page : filter_nearest, repeat_disable;
uniform sampler2D palettes : source_color, filter_nearest, repeat_disable;

varying vec4 sprite;

void vertex() {
	sprite = COLOR;
	vec3 centre = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec4 q = INSTANCE_CUSTOM;
	VERTEX = centre + vec3(mix(q.x, q.z, UV.x), -mix(q.y, q.w, UV.y), 0.0);
}

vec4 texel_colour(vec2 uv) {
	vec2 texel = floor(sprite.xy + min(uv * sprite.z, vec2(sprite.z - 0.001)));
	float index = texelFetch(page, ivec2(texel), 0).r * 255.0;
	return texelFetch(palettes, ivec2(int(index + 0.5), int(sprite.w + 0.5)), 0);
}
