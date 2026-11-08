extends TestSuite
## Tekken Ball's burning ball: a charge of 100 or more starts effect type 15 with `d` 1, a flame on
## the ball (FUN_80073F78, FUN_800741E0). The game's flame primitives take the fire CLUT and the
## additive page from its globals (DAT_800ae250 = 0x7DC8, DAT_800ae338 = 0x3F); an object without
## them was skipped by the view, so a ball that should burn showed nothing.

const DISC_DATA := [
	"test_a_flame_on_the_ball_is_drawn",
]


func test_the_flame_has_the_fire_clut_and_the_additive_page() -> void:
	if not require(AssetCatalog.ROOT + "tables/fighter.json"):
		return
	var fight := FightState.new(FightTables.load_from(AssetCatalog.ROOT + "tables"), RuleSet.new())
	var flame := EffectObjects.alloc(fight, 15)
	flame.d = 1
	EffectObjects._ball_glow_start(fight, flame)
	expect_equal(flame.model, EffectObjects.Model.BALL, "the ball's quad")
	expect_equal(flame.flags & EffectObjects.VISIBLE, EffectObjects.VISIBLE, "drawn")
	expect_equal(flame.clut, EffectObjects.CLUT_FIRE, "the fire CLUT, 0x7DC8")
	expect_equal(flame.tpage, EffectObjects.TPAGE_ADD, "on the additive page, 0x3F")


func test_a_flame_on_the_ball_is_drawn() -> void:
	var dir := AssetCatalog.ROOT.path_join("effects")
	if not require(dir.path_join("effects.json")) or not require(AssetCatalog.ROOT + "tables/fighter.json"):
		return
	var view := EffectObjectsView.new()
	view.setup(EffectData.load_from(dir))
	var fight := FightState.new(FightTables.load_from(AssetCatalog.ROOT + "tables"), RuleSet.new())
	var flame := EffectObjects.alloc(fight, 15)
	flame.d = 1
	EffectObjects._ball_glow_start(fight, flame)
	for step: int in [1, 4, 7]:   # the growth's frames (FUN_80074594)
		flame.uv_table = EffectObjects.UvTable.FIREBALL_GROW
		flame.uv = step
		view.show_pool(fight.effects)
		expect_equal(view.additive.multimesh.visible_instance_count, 1, "the flame's frame %d is drawn" % step)
	flame.uv_table = EffectObjects.UvTable.FIREBALL_LOOP
	flame.uv = 3
	view.show_pool(fight.effects)
	expect_equal(view.additive.multimesh.visible_instance_count, 1, "and its flicker")
	view.free()
