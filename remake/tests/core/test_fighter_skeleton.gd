extends TestSuite
## FighterSkeleton builds every joint the mesh can reference, and FighterView keeps its
## culling bounds on the joints wherever the fighter stands.

const TABLES := AssetCatalog.ROOT + "tables/pose.json"
const MODEL := AssetCatalog.ROOT + "characters/costume_00"
const BANK := "divmot00"
const COMMON := "divmot99"
const STANCE_SLOT := 3


func _skeleton() -> FighterSkeleton:
	return FighterSkeleton.new(PoseTables.load_from(TABLES), CharacterModel.load_from(MODEL))


func _stance_pose() -> PackedInt32Array:
	var own := MotionBank.load_named(AssetCatalog.ROOT + "motion", BANK)
	var common := MotionBank.load_named(AssetCatalog.ROOT + "motion", COMMON)
	var anim := MotionSet.new(own, common).anim_for_slot(STANCE_SLOT)
	return anim.bank.pose(anim.value, 0)


func _present() -> bool:
	return require(TABLES) and require(MODEL + "/model.json")


func test_attachment_joints_follow_their_parent() -> void:
	if not _present():
		return
	var skeleton := _skeleton()
	skeleton.update(_stance_pose(), PackedInt32Array([0, 0, 0]), 0, 0)
	expect_equal(skeleton.joints.size(), CharacterModel.PART_COUNT, "every joint slot the mesh may use")
	for m in range(FighterSkeleton.JOINTS, FighterSkeleton.ALL_JOINTS):
		var parent := skeleton.joints[skeleton.parents[m]] if skeleton.parents[m] >= 0 else skeleton.root
		var expected := JointFrame.compose_offset(parent, Fx.identity(), skeleton.offsets[m])
		expect_equal(skeleton.joints[m].t, expected.t, "joint %d position" % m)
		expect_equal(skeleton.joints[m].rot, parent.rot, "joint %d rotation" % m)


func test_view_bounds_follow_the_fighter() -> void:
	if not _present():
		return
	var skeleton := _skeleton()
	var far := PackedInt32Array([15000, 0, -12000])        # 15 m right, 12 m ahead
	skeleton.update(_stance_pose(), far, 0, 0)
	var view := FighterView.new()
	view.set_joints(skeleton.joints)
	var bounds := view.mesh_instance.custom_aabb
	for j in FighterSkeleton.JOINTS:
		var p := WorldSpace.point_i(skeleton.joints[j].t)
		expect(bounds.has_point(p), "joint %d at %s outside %s" % [j, p, bounds])
	view.mesh_instance.free()
	view.free()
