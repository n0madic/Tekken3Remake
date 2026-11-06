shader_type spatial;
// The 50 % flipbooks (the landing dust: B / 2 + F / 2).
render_mode unshaded, skip_vertex_transform, depth_draw_never, cull_disabled, blend_mix;

#include "res://presentation/effects/flipbook.gdshaderinc"
