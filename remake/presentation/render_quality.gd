class_name RenderQuality
extends RefCounted
## The graphics settings (remake-plan.md#quality-presets): the preset of the renderer in use
## applied to the environments, the stage lights and the window's viewport; the Textures setting
## (the crisp variant of a shader is compiled with CRISP defined); and the replacement texture
## packs (TexturePacks). Presets change only the look, never the game.
##
## | Preset       | Renderer      | Features                                                        |
## | web          | Compatibility | shadow maps, basic bloom, MSAA 2×                              |
## | mobile       | Mobile        | shadows, bloom, MSAA 2×, the 3D view at 85 % (bilinear)       |
## | mobile_high  | Mobile        | soft 4k shadows, bloom, MSAA 4×, the 3D view at full size      |
## | desktop_low  | Forward+      | shadows, bloom, MSAA 2×                                        |
## | desktop_high | Forward+      | soft 4k shadows, bloom, MSAA 4×, SSAO, SSIL                    |

const PRESETS := {
	"web": {"msaa": Viewport.MSAA_2X, "shadow_size": 2048, "soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		"glow": 0.5, "scale": 1.0},
	"mobile": {"msaa": Viewport.MSAA_2X, "shadow_size": 2048, "soft": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
		"glow": 0.5, "scale": 0.85},
	# The Mobile renderer has no SSAO, SSIL or SSR: its best is sharper shadows and edges at full size.
	"mobile_high": {"msaa": Viewport.MSAA_4X, "shadow_size": 4096, "soft": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		"glow": 0.6, "scale": 1.0},
	"desktop_low": {"msaa": Viewport.MSAA_2X, "shadow_size": 2048, "soft": RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		"glow": 0.6, "scale": 1.0},
	"desktop_high": {"msaa": Viewport.MSAA_4X, "shadow_size": 4096, "soft": RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
		"glow": 0.6, "scale": 1.0, "ssao": true, "ssil": true},
}
const CRISP_DEFINE := "#define CRISP\n"
## The settings that change the textures' look: the views built with them refresh their materials.
const TEXTURE_SETTINGS := ["texture_filter", "texture_pack"]

static var _crisp: Dictionary = {}           ## shader path → its crisp variant


## The settings of the preset in effect.
static func current() -> Dictionary:
	return PRESETS.get(Settings.preset(), PRESETS["desktop_low"])


static func apply_environment(env: Environment) -> void:
	var p := current()
	env.glow_enabled = true
	env.glow_intensity = p["glow"]
	env.ssao_enabled = p.get("ssao", false)
	env.ssao_intensity = 1.2
	env.ssao_radius = 0.6
	env.ssil_enabled = p.get("ssil", false)


static func apply_light(light: DirectionalLight3D) -> void:
	var soft: int = current()["soft"]
	light.shadow_blur = 1.5 if soft >= RenderingServer.SHADOW_QUALITY_SOFT_HIGH else 1.0


## The window's viewport and the shadow atlas.
static func apply_viewport(viewport: Viewport) -> void:
	var p := current()
	viewport.msaa_3d = p["msaa"] as Viewport.MSAA
	var scale: float = p["scale"]
	viewport.scaling_3d_scale = scale
	# FSR is Forward+ only: the Mobile renderer scales bilinearly.
	var fsr := scale < 1.0 and Settings.renderer() == "forward_plus"
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR
	RenderingServer.directional_shadow_atlas_set_size(p["shadow_size"] as int, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(p["soft"] as RenderingServer.ShadowQuality)


## `base` for the Textures setting: itself (smooth), or compiled with CRISP defined.
static func shader(base: Shader) -> Shader:
	if Settings.text("texture_filter") != "crisp":
		return base
	if not _crisp.has(base.resource_path):
		var variant := Shader.new()
		var code := base.code
		var at := code.find("\n", code.find("shader_type")) + 1
		variant.code = code.substr(0, at) + CRISP_DEFINE + code.substr(at)
		_crisp[base.resource_path] = variant
	return _crisp[base.resource_path]
