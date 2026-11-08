class_name ArcadeFightContent
extends FightContent
## FightContent for the arcade's conversion: one bank of moves for all bank types.

const EFFECT_TABLES := "tables/effects.json"

var effect_tables: ArcadeEffectTables


static func load_arcade(folder: String) -> ArcadeFightContent:
	var c := ArcadeFightContent.new()
	c.root = folder
	c.tables = FightTables.load_from(folder.path_join("tables"))
	c.effect_tables = ArcadeEffectTables.load_from(folder.path_join(EFFECT_TABLES))
	c.common = ArcadeBank.load_arcade(folder.path_join(MOTION))
	c.common_rows = c.common.link(c.common, c.tables.builtin_attack_ids)
	return c


func attachment_tables(solver: PoseSolver) -> ArcadeAttachmentTables:
	return ArcadeAttachmentTables.load_from(root.path_join(ArcadeAttachmentTables.FILE), solver, tables.fighter)


func bank(_bank_type: int) -> MotionBank:
	return common


func rows(_bank_type: int) -> Array[MoveRow]:
	return common_rows


## The rows of a bank type's slots (FUN_8018EC9C).
func slot_rows(bank_type: int) -> Array:
	var table: PackedInt32Array = (common as ArcadeBank).slots[bank_type]
	var out := []
	out.resize(table.size())
	for s in table.size():
		out[s] = common_rows[table[s]]
	return out
