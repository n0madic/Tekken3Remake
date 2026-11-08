class_name ArcadeTitleView
extends ArcadeCanvas
## The transition's NAMCO PRESENTS (FUN_801B5EEC) and the attract's pictures (FUN_801BD318): black,
## the movie (black in a build without it), the title picture with its logo, copyright and prompt,
## the demonstration's credits.

var flow: ArcadeGameFlow
var movie := ArcadeMovieView.new()


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_arcade(hud_data, screens)
	add_child(movie)


func show_state(game: ArcadeGameFlow) -> void:
	flow = game
	frame_count = game.frame()
	if game.state == ArcadeGameFlow.State.ATTRACT and game.picture == ArcadeGameFlow.Picture.MOVIE:
		movie.show_frame(game.timer)
	else:
		movie.stop()
	redraw()


func _draw() -> void:
	begin()
	if flow == null:
		return
	match flow.state:
		ArcadeGameFlow.State.ATTRACT, ArcadeGameFlow.State.TITLE:
			_picture(flow.picture)
		_:
			black()
			if flow.presents_shown:
				show_text("presents")


func _picture(kind: int) -> void:
	match kind:
		ArcadeGameFlow.Picture.TITLE_PROMPT:
			_title_picture()
			_logo()
			_copyright()
			main_prompt()
			credits_line()
		ArcadeGameFlow.Picture.TITLE:
			_title_picture()
		ArcadeGameFlow.Picture.ENBU:
			credits_line()
		_:
			black()


func _title_picture() -> void:
	picture_at(str(data.title["picture"]), 0, 0)


func _logo() -> void:
	var logo: Dictionary = data.title["logo"]
	var x: int = logo["x"]
	var y: int = logo["y"]
	picture_at(str(logo["file"]), x, y)


func _copyright() -> void:
	var keys: Array = data.title["copyright"]
	for key: String in keys:
		show_text(key)
