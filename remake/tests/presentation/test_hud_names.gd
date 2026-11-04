extends TestSuite
## What the 2D views read from the converted pictures: the fight HUD's name plates go by the
## costume key (a slot can serve two characters' costumes).

const HUD_JSON := "res://imported/hud/hud.json"
const ANNA_FIRST := 72
const ANNA_THIRD := 74
const NINA_THIRD := 22


func _entry(data: HudData, key: int) -> Dictionary:
	return data.names[str(key)]


func test_a_shared_slot_keeps_each_costumes_colours() -> void:
	if not require(HUD_JSON):
		return
	var data := HudData.load_from(HUD_JSON.get_base_dir())
	expect_equal(_entry(data, ANNA_FIRST)["plate"], "plate_0.png", "Anna's first costume: the first plate")
	expect_equal(_entry(data, NINA_THIRD)["plate"], "plate_2.png", "Nina's third, on the same slot: the third")
	expect_equal(_entry(data, ANNA_THIRD)["plate"], "plate_2.png", "Anna's third: the third")
	expect(str(_entry(data, ANNA_FIRST)["file"]) != str(_entry(data, NINA_THIRD)["file"]), "each with its own name sprite")
