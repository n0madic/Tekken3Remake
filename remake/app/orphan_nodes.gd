class_name OrphanNodes
extends RefCounted
## Frees the nodes a scene made but never parented. The views keep their parts as member nodes
## made at construction and parent them only when used (in setup or _ready), so a part that was
## never used belongs to no tree and is not freed with its owner: the game scene's screens when
## `--fight` or `--m0` replaces it at once, a view never set up. The main scenes call free_all on
## their way out (NOTIFICATION_PREDELETE), which walks their members and children.


## Frees every unparented node among the script members of `owner` and of its descendants,
## and of the nodes freed (their members and children first). Arrays and dictionaries of nodes
## count as members. Members pointing elsewhere (another branch of the tree, an autoload) are
## left alone: those nodes and what they hold belong to their own owners.
static func free_all(owner: Node) -> void:
	_sweep(owner, owner, {})


static func _sweep(owner: Node, node: Node, seen: Dictionary) -> void:
	if seen.has(node):
		return
	seen[node] = true
	for child in node.get_children(true):
		_sweep(owner, child, seen)
	for property in node.get_property_list():
		if (property["usage"] as int) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			for value in _nodes_in(node.get(property["name"] as String)):
				if is_instance_valid(value) and not seen.has(value) and _owned(owner, value):
					_sweep(owner, value, seen)
					if value.get_parent() == null:
						value.free()


## `node` is `owner`'s to free: in its subtree, or in no tree with no parent (an unparented part,
## or the subtree of one).
static func _owned(owner: Node, node: Node) -> bool:
	if owner.is_ancestor_of(node):
		return true
	var top := node
	while top.get_parent() != null:
		top = top.get_parent()
	return not top.is_inside_tree()


static func _nodes_in(value: Variant) -> Array[Node]:
	var nodes: Array[Node] = []
	if value is Array:
		for item: Variant in value:
			nodes.append_array(_nodes_in(item))
	elif value is Dictionary:
		for item: Variant in (value as Dictionary).values():
			nodes.append_array(_nodes_in(item))
	elif is_instance_valid(value) and value is Node:
		nodes.append(value as Node)
	return nodes
