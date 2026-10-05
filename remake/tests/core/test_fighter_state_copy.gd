extends TestSuite
## FighterState.copy_from (Tekken Ball's third record): a copy of the record, field for field.


func test_copy_keeps_the_root_move_apart_from_the_pose_move() -> void:
	var a := FighterState.new()
	a.pose_move = MoveRow.new()
	a.root_move = MoveRow.new()
	a.pos_x = 5
	a.pos_y = 6
	a.pos_z = 7
	a.player_index = 1
	var b := FighterState.new()
	b.copy_from(a)
	expect(b.root_move == a.root_move, "root_move")
	expect(b.pose_move == a.pose_move, "pose_move")
	expect(b.root_move != b.pose_move, "the two stay apart (the `move` view would set both)")
	expect_equal(b.anchor, PackedInt32Array([5, 6, 7]), "the anchor's fields")
	expect_equal(b.player_index, 1, "plain fields")
