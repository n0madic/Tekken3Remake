shader_type spatial;
// The additive flipbooks: HDR glow (B + F).
render_mode unshaded, skip_vertex_transform, depth_draw_never, cull_disabled, blend_add;

#include "res://presentation/effects/flipbook.gdshaderinc"
