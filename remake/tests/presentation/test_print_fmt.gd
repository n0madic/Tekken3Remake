extends TestSuite
## ScreenCanvas.print_fmt (FUN_8004D15C's format): the text runs it draws, each with its font,
## colour and pen position. %c / %f / %H / %V end a run, a line break returns to the line start
## (%H), %% prints a percent sign without taking an argument, and %d / %x keep their width.


## Records the runs instead of drawing glyphs.
class Recorder extends ScreenCanvas:
	var calls: Array = []

	func text(s: String, font_index: int, colour: int, x: float, y: float, _alpha := 1.0) -> void:
		calls.append([s, font_index, colour, x, y])


func test_runs_and_pen() -> void:
	var canvas := Recorder.new()
	canvas.hud = HudData.new()
	canvas.hud.fonts[0] = _font(8, 16)
	canvas.hud.fonts[1] = _font(12, 20)
	canvas.print_fmt("AB%3d\nC%cD%fE%HF\nG%s%%%02x%V%C", [7, 5, 1, 40, "xy", 0x1AB, 100, 65], 0, 2)
	expect_equal(canvas.calls, [
		["AB  7", 0, 2, 0.0, 0.0],        # %3d: two spaces and the digit
		["C", 0, 2, 0.0, 16.0],           # after the line break, at the line start
		["D", 0, 5, 8.0, 16.0],           # %c 5
		["E", 1, 5, 16.0, 16.0],          # %f 1
		["F", 1, 5, 40.0, 16.0],          # %H 40 moves the pen and the line start
		["Gxy%AB", 1, 5, 40.0, 36.0],     # line 2 of font 1 at x 40; %02x keeps two digits
		["A", 1, 5, 112.0, 100.0],        # %V 100, %C 65
	])
	canvas.free()


func test_negative_and_large_numbers() -> void:
	expect_equal(ScreenCanvas._number_text(-5, "d", 3, false), " -5", "a minus sign takes a place")
	expect_equal(ScreenCanvas._number_text(123, "d", 2, false), "23", "a width keeps the low digits")
	expect_equal(ScreenCanvas._number_text(200_000_000, "d", 0, false), "99999999", "past 10⁸")
	expect_equal(ScreenCanvas._number_text(100_000_000, "d", 0, false), "99999999", "exactly 10⁸ (game-bugs #66 not reproduced)")
	expect_equal(ScreenCanvas._number_text(-5, "D", 0, false), "99999999", "%D is unsigned: −5 is past 10⁸ (draw_sim.py)")
	expect_equal(ScreenCanvas._number_text(42, "D", 0, false), "42")


static func _font(advance: int, line: int) -> HudData.FontInfo:
	var info := HudData.FontInfo.new()
	info.advance = advance
	info.line = line
	return info
