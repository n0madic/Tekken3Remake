extends TestSuite
## BallView's court (the centre band and the two side lines at ± the neutral zone): the zone is
## set when a fight starts, after the view's first step, and by the ball type of each match, so
## the court follows it instead of keeping the zone it first saw.


## A view with its nodes in place, as `setup` leaves them (no game memory needed for the court).
static func _view() -> BallView:
	var view := BallView.new()
	view.add_child(view._ball)
	view.add_child(view._court)
	return view


static func _half_width(view: BallView) -> float:
	return view._court.mesh.get_aabb().size.x / 2.0


static func _half_width_of(zone: int) -> float:
	var view := _view()
	view._set_zone(zone)
	var width := _half_width(view)
	view.free()
	return width


func test_court_follows_the_neutral_zone() -> void:
	var view := _view()
	view._set_zone(0)
	var unset := _half_width(view)
	view._set_zone(2304)
	var wide := _half_width(view)
	expect(wide > unset, "a zone set after the first step moves the side lines out of the centre")
	var mesh := view._court.mesh
	view._set_zone(2304)
	expect(view._court.mesh == mesh, "the same zone keeps the mesh")
	view._set_zone(1536)
	expect(_half_width(view) < wide, "a ball type with a narrower zone narrows the court")
	view.free()
	var middle := _half_width_of(1920)
	expect(middle > _half_width_of(1536) and middle < wide, "and the third type's zone lies between")


func test_occluder_is_the_sphere_in_the_scene() -> void:
	var view := _view()
	view._radius = 0.4
	view._stretch = 1.25
	view._solid = true
	view._ball.position = Vector3(1, 2, 3)
	expect_equal(view.occluder(), Vector4(1, 2, 3, 0.5), "the ball's place and its radius, as far as an impact squash stretches it")
	view._solid = false
	expect_equal(view.occluder().w, 0.0, "none for a ball drawn over the scene")
	view._solid = true
	view.visible = false
	expect_equal(view.occluder().w, 0.0, "none for a ball not shown")
	view.free()
