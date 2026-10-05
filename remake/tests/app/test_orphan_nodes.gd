extends TestSuite
## OrphanNodes.free_all: the unparented member nodes of the owner and of its descendants are
## freed; a member pointing at a live node elsewhere in the tree leaves that node and its own
## unparented parts alone.


class Holder extends Node:
	var part: Node
	var parts: Array[Node] = []
	var elsewhere: Node


func test_frees_only_the_owners_unparented_members() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	var owner := Holder.new()
	owner.part = Node.new()
	owner.parts.append(Node.new())
	var child := Holder.new()
	owner.add_child(child)
	child.part = Node.new()
	var other := Holder.new()
	root.add_child(other)
	other.part = Node.new()
	owner.elsewhere = other
	var freed: Array[Node] = [owner.part, owner.parts[0], child.part]
	OrphanNodes.free_all(owner)
	for node: Node in freed:
		expect(not is_instance_valid(node), "an unparented member of the owner is freed")
	expect(is_instance_valid(other), "a live node elsewhere is not freed")
	expect(is_instance_valid(other.part), "nor the part it keeps unparented")
	owner.free()
	other.part.free()
	other.free()


## The stage viewer is a main scene that replaces the game scene: its own unparented parts go with it.
func test_stage_viewer_frees_its_parts() -> void:
	var viewer: Node = (load("res://app/stage_viewer.gd") as GDScript).new()
	var label: Node = viewer.get("label") as Node
	expect(is_instance_valid(label) and label.get_parent() == null, "the label is an unparented member")
	viewer.free()
	expect(not is_instance_valid(label), "freed with the viewer")
