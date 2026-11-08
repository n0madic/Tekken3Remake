class_name ArcadeScreens
extends Control
## The arcade's 2D screens: shows the view of the flow's state. The fight's own 2D is ArcadeFightHud.

var title := ArcadeTitleView.new()
var select := ArcadeSelectView.new()
var vs := ArcadeVsView.new()
var ranking := ArcadeRankingView.new()
var ending := ArcadeEndingView.new()
var _views: Array[ArcadeCanvas] = []


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.setup(hud_data, screens)
	select.setup(hud_data, screens)
	vs.setup(hud_data, screens)
	ranking.setup(hud_data, screens)
	ending.setup(hud_data, screens)
	_views = [title, select, vs, ranking, ending]
	for view in _views:
		add_child(view)
		view.visible = false


func show_state(flow: ArcadeGameFlow) -> void:
	var view: ArcadeCanvas = null
	match flow.state:
		ArcadeGameFlow.State.SELECT:
			view = select
			select.show_state(flow)
		ArcadeGameFlow.State.MATCH:
			if not flow.showing_fight():
				view = vs
				vs.show_state(flow)
		ArcadeGameFlow.State.RANKING:
			view = ranking
			ranking.show_state(flow)
		ArcadeGameFlow.State.ENDING:
			view = ending
			ending.show_state(flow)
		_:
			view = title
			title.show_state(flow)
	for each in _views:
		each.visible = each == view
