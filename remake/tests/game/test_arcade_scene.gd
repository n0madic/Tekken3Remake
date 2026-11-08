extends TestSuite
## What a scripted scene tells the views. The traces of tests/game/test_arcade_flow_traces.gd prove the
## scene's state; this names what only the views read, and state no trace reaches.


## A flow from the arcade conversion, null (the test skipped) without one.
func _flow() -> ArcadeGameFlow:
	if not require(AssetCatalog.ROOT.path_join(ArcadeFlowData.FILE)):
		return null
	if not Assets.arcade_only():
		skip("not a conversion from the arcade set")
		return null
	var content := ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
	var data := ArcadeFlowData.load_from(AssetCatalog.ROOT.path_join(ArcadeFlowData.FILE))
	return ArcadeGameFlow.new(content, data, RuleSet.original(), ArcadeSettings.new(), 1)


func test_a_flipbook_event_names_the_side_and_the_characters_slot() -> void:
	var flow := _flow()
	if flow == null:
		return
	var character := 4
	var slot: int = flow.sim.t.fighter.costume_keys[character << 2]
	flow.enbu._flipbook_event(1, character)
	flow.sim.events.clear()
	flow.enbu._step_moves()
	var event := flow.sim.events.first(SimEvents.Kind.EFFECT_BOOK)
	if not expect(event != null, "the event is sent"):
		return
	expect_equal(event.a, 1, "the side's flipbook set")
	expect_equal(event.b, slot, "the character's slot")


## A reel's start ends the replay camera (FUN_801D4100 calls FUN_801D70D4); no flow trace runs a scene
## right after a replay.
func test_a_reel_ends_the_replay_camera() -> void:
	var flow := _flow()
	if flow == null:
		return
	var camera := flow.sim.camera as ArcadeCamera
	camera.replay_on = 1
	camera.reel_start(ArcadeEnbu.REEL_LIST)
	expect_equal(camera.replay_on, 0, "FUN_801D70D4")


## The demonstration asks for its music only when the operator's attract sound is on (the sound
## board's gate `0x8021FC20 != 0 || 0x8021FC64 == 0`); the remake's setting is that switch.
func test_the_attract_sound_lets_the_demonstration_play_its_music() -> void:
	var flow := _flow()
	if flow == null:
		return
	expect_equal(flow.attract_silent, 1, "the attract is silent from the boot")
	for on: int in [0, 1]:
		flow.settings.attract_sound = on
		flow.enbu.start()
		flow.sim.events.clear()
		for n in ArcadeEnbu.START_DELAY + 2:
			flow.enbu.step()
		var music := flow.sim.events.first(SimEvents.Kind.MUSIC)
		if on == 0:
			expect(music == null, "a silent attract: no music")
		elif expect(music != null, "the attract sound on: the music"):
			expect_equal(music.a, ArcadeEnbu.MUSIC, "the demonstration's music")
