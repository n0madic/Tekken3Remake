// Seam-exact skinning of the game's character models.
//
// Every corner stores up to three part-local positions: VERTEX in joint `bone_a`, CUSTOM0.xyz
// in joint `bone_b`, blended with weight CUSTOM0.w (0 or 0.5 on the PlayStation's models, as
// DrawSkinnedPart averages seam vertices of neighbouring parts), and (UV2, CUSTOM3.w) in joint
// `bone_c` with weight wc (the arcade's seams weigh up to three joints, FUN_8019a858). The
// normal is local to joint `bone_n`. CUSTOM1 = (bone_a, bone_b, bone_n, bone_c + wc). With `smooth_normals` the normal is instead the
// converter's smooth one (character.py smooth_normals): CUSTOM2.xyz in joint bone_n plus, while
// they agree, CUSTOM3.xyz in joint CUSTOM2.w (smooth_normal()). Joint j is the 3 × 4 affine matrix in
// bone_rows[3j .. 3j + 2], already converted to Godot space (metres, y up).

const int JOINT_ROWS = 84;                    // 3 × CharacterModel.JOINT_COUNT
// A smooth normal's half shorter than this (squared, in part-local units: sums of unit normals)
// is empty or cancelled out.
const float EMPTY_HALF = 0.01;

uniform vec4 bone_rows[JOINT_ROWS];
// The stage's light rig as DrawSkinnedPart's NCCT applies it (stages.md#lighting): the vertex
// colour is base · (back + light · max(N·L, 0) + fill · max(N·down, 0)), clamped to 0xFF, and it
// modulates the texel in display space (0x80 = 1), clamped again. StageLighting.fighter_parameters
// sets them per stage (the defaults: stage 4's); the main light's direction is Godot's own.
uniform vec3 base_colour = vec3(0.984375, 0.984375, 1.0);
uniform vec3 back_colour = vec3(0.53515625);
uniform vec3 light_colour = vec3(0.9140625, 0.859375, 0.734375);
uniform vec3 fill_colour = vec3(0.45703125, 0.4296875, 0.3671875);
// The Shading setting: the converter's smooth normals instead of the game's own, and the curved
// surfaces (CurvedMesh: the mesh is a grid per triangle, CUSTOM0 = (triangle, barycentric
// weights), and the triangles' corners are in corner_data).
uniform bool smooth_normals = false;
uniform float smooth_crease_cos = 0.17364818;   // CharacterModel.smooth_crease_cos
uniform bool curved = false;
uniform sampler2D corner_data : filter_nearest, repeat_disable;
uniform int corner_texels = 6;                  // CurvedMesh.CORNER_TEXELS
// Bit per joint: faces skinned to it collapse to a point (parts the game does not draw).
uniform int hidden_joints = 0;
// The Textures setting: smooth (bilinear; the atlas keeps a 2-texel gutter around each region)
// or crisp (RenderQuality compiles the shader with CRISP defined). Sampled as stored (sRGB): the
// game's lighting works on display values.
#ifdef CRISP
uniform sampler2D albedo_texture : filter_nearest, repeat_disable;
#else
uniform sampler2D albedo_texture : filter_linear, repeat_disable;
#endif

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// The display-space product of a texel (sRGB) and the vertex colour of intensity `i`, in linear.
vec3 lit(vec3 texel_srgb, vec3 i) {
	vec3 vertex_colour = min(base_colour * i, vec3(255.0 / 128.0));
	return srgb_to_linear(min(texel_srgb * vertex_colour, vec3(1.0)));
}

vec3 joint_point(int j, vec3 p) {
	vec4 q = vec4(p, 1.0);
	return vec3(dot(bone_rows[3 * j], q), dot(bone_rows[3 * j + 1], q), dot(bone_rows[3 * j + 2], q));
}

vec3 joint_direction(int j, vec3 n) {
	return vec3(dot(bone_rows[3 * j].xyz, n), dot(bone_rows[3 * j + 1].xyz, n), dot(bone_rows[3 * j + 2].xyz, n));
}

// The blend of `pa` in joint `bone_a` with `pb` in `bone_b` by `wb` and with `pc` in joint
// floor(`c`) by fract(`c`).
vec3 skinned(int bone_a, vec3 pa, int bone_b, vec3 pb, float wb, float c, vec3 pc) {
	vec3 a = joint_point(bone_a, pa);
	vec3 p = mix(a, joint_point(bone_b, pb), wb);
	float bone_c = floor(c);
	float wc = c - bone_c;
	return wc > 0.0 ? p + wc * (joint_point(int(bone_c), pc) - a) : p;
}

bool joint_hidden(int j) {
	return ((hidden_joints >> j) & 1) != 0;
}

// The smooth normal (unnormalized, skinned) from its halves: `own` in joint `own_joint` (the
// joint of the game's normal `game`, used when the half is empty) and `other` in `other_joint`,
// added only while the two lie within the crease angle in this pose. `shared` asks for the
// normal every corner with the same two halves agrees on (the curved patches' edges must meet):
// the test is symmetric, and when it fails the half of the lower joint is kept instead of the
// corner's own.
vec3 smooth_normal(int own_joint, vec3 own, int other_joint, vec3 other, vec3 game, bool shared) {
	if (dot(own, own) < EMPTY_HALF) {
		return joint_direction(own_joint, game);
	}
	vec3 a = joint_direction(own_joint, own);
	if (dot(other, other) < EMPTY_HALF) {
		return a;
	}
	vec3 b = joint_direction(other_joint, other);
	if (dot(normalize(a), normalize(b)) >= smooth_crease_cos) {
		return a + b;
	}
	return shared && other_joint < own_joint ? b : a;
}

vec4 corner_texel(int corner, int t) {
	int i = corner * corner_texels + t;
	int width = textureSize(corner_data, 0).x;
	return texelFetch(corner_data, ivec2(i % width, i / width), 0);
}

// Corner k of triangle t, skinned: its position, smooth normal for the light and for the patch
// (smooth_normal()'s shared one), whether the edge to the next corner may bulge, and whether its
// joint is hidden.
void corner(int t, int k, out vec3 p, out vec3 n, out vec3 patch_n, out bool bulges, out bool hidden) {
	int c = 3 * t + k;
	vec4 a = corner_texel(c, 0);
	vec4 b = corner_texel(c, 1);
	vec4 own = corner_texel(c, 2);
	vec4 other = corner_texel(c, 3);
	vec4 game = corner_texel(c, 4);
	vec4 third = corner_texel(c, 5);
	bulges = own.w >= 1.0;
	float wb = own.w - (bulges ? 2.0 : 0.0);
	int bone_a = int(a.w + 0.5);
	p = skinned(bone_a, a.xyz, int(b.w + 0.5), b.xyz, wb, third.w, third.xyz);
	int own_joint = int(game.w + 0.5);
	int other_joint = int(other.w + 0.5);
	n = normalize(smooth_normal(own_joint, own.xyz, other_joint, other.xyz, game.xyz, false));
	patch_n = normalize(smooth_normal(own_joint, own.xyz, other_joint, other.xyz, game.xyz, true));
	hidden = joint_hidden(bone_a);
}

// The PN triangle's control point next to corner i on the edge to corner j: a third of the way
// along the edge, pulled onto corner i's tangent plane when the edge may bulge.
vec3 edge_point(vec3 pi, vec3 ni, vec3 pj, bool bulges) {
	vec3 q = (2.0 * pi + pj) / 3.0;
	return bulges ? q - dot(pj - pi, ni) * ni / 3.0 : q;
}

void curved_vertex(inout vec3 vertex, inout vec3 normal, vec4 custom0) {
	int t = int(custom0.x + 0.5);
	vec3 w = custom0.yzw;
	vec3 p0, p1, p2, n0, n1, n2, q0, q1, q2;
	bool e01, e12, e20, h0, h1, h2;
	corner(t, 0, p0, n0, q0, e01, h0);
	corner(t, 1, p1, n1, q1, e12, h1);
	corner(t, 2, p2, n2, q2, e20, h2);
	vec3 b210 = edge_point(p0, q0, p1, e01);
	vec3 b120 = edge_point(p1, q1, p0, e01);
	vec3 b021 = edge_point(p1, q1, p2, e12);
	vec3 b012 = edge_point(p2, q2, p1, e12);
	vec3 b102 = edge_point(p2, q2, p0, e20);
	vec3 b201 = edge_point(p0, q0, p2, e20);
	vec3 e = (b210 + b120 + b021 + b012 + b102 + b201) / 6.0;
	vec3 b111 = e + (e - (p0 + p1 + p2) / 3.0) / 2.0;
	float u = w.x;
	float v = w.y;
	float s = w.z;
	vertex = p0 * u * u * u + p1 * v * v * v + p2 * s * s * s
		+ 3.0 * (b210 * u * u * v + b120 * u * v * v + b201 * u * u * s
			+ b021 * v * v * s + b102 * u * s * s + b012 * v * s * s)
		+ 6.0 * b111 * u * v * s;
	normal = normalize(n0 * u + n1 * v + n2 * s);
	if (h0 || h1 || h2) {
		vertex = vec3(0.0);
	}
}

void vertex() {
	if (curved) {
		curved_vertex(VERTEX, NORMAL, CUSTOM0);
	} else {
		int bone_a = int(CUSTOM1.x + 0.5);
		int bone_b = int(CUSTOM1.y + 0.5);
		int bone_n = int(CUSTOM1.z + 0.5);
		VERTEX = skinned(bone_a, VERTEX, bone_b, CUSTOM0.xyz, CUSTOM0.w, CUSTOM1.w, vec3(UV2, CUSTOM3.w));
		if (joint_hidden(bone_a)) {
			VERTEX = vec3(0.0);
		}
		NORMAL = normalize(smooth_normals
			? smooth_normal(bone_n, CUSTOM2.xyz, int(CUSTOM2.w + 0.5), CUSTOM3.xyz, NORMAL, false)
			: joint_direction(bone_n, NORMAL));
	}
}

varying vec3 texel_srgb;
varying vec3 unlit_intensity;          // back + fill: everything but the main light
varying vec3 unlit;                    // lit(texel, unlit_intensity)

void fragment() {
	vec4 texel = texture(albedo_texture, UV);
	// The colour is made here and in light(): ALBEDO 1 passes DIFFUSE_LIGHT through unchanged,
	// and the shaders disable Godot's ambient light (the back colour replaces it).
	ALBEDO = vec3(1.0);
	texel_srgb = texel.rgb;
	float down = max(-(INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0);
	unlit_intensity = back_colour + fill_colour * down;
	unlit = lit(texel_srgb, unlit_intensity);
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	EMISSION = unlit;
#endif
	// Transparent texels (CLUT 0x0000) cut the faces at alpha 0.5; with MSAA the cut edges are
	// antialiased by alpha to coverage instead of staircased.
	ALPHA = texel.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
	// The game lights its models with diffuse Gouraud shading only. Any specular reflection, however
	// faint at head-on angles, rises with Godot's Fresnel term towards grazing ones, so it gives dark
	// polygons (hair) a plastic sheen the original never shows.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// The stage's main light (Godot's shadows in ATTENUATION) adds what it adds to the game's
		// vertex colour. It is the only directional light that reaches the fighters: the up-shining
		// fill light is already in `unlit`, and StageLighting keeps it off the fighters' render layer.
		float d = max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		// The Compatibility renderer adds EMISSION after encoding the light to sRGB, so the
		// whole colour comes with the main light there.
		DIFFUSE_LIGHT += lit(texel_srgb, unlit_intensity + light_colour * d);
#else
		DIFFUSE_LIGHT += lit(texel_srgb, unlit_intensity + light_colour * d) - unlit;
#endif
	} else {
		// The effects' point lights (fire, glows): diffuse on the texel.
		DIFFUSE_LIGHT += srgb_to_linear(texel_srgb) * LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) / PI;
	}
}
