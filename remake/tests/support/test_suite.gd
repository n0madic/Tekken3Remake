class_name TestSuite
extends RefCounted
## Base class of the remake's test suites, run by `tests/run_tests.gd`.
##
## Every method named `test_*` without arguments is a test. A test fails when any
## expectation fails; it may call `skip()` when its inputs (converted assets, golden
## traces) are missing.

var failures: PackedStringArray = []
var skipped := ""
var _flow_content: FightContent        # loaded once per suite by `imported_flow`
var _flow_data: FlowData


func skip(reason: String) -> void:
	skipped = reason


## Whether `path` exists; skips the test with `reason` when it does not.
func require(path: String, reason := "run tools/remake_import/convert.py first") -> bool:
	if FileAccess.file_exists(path):
		return true
	skip(reason)
	return false


## A GameFlow over the converted game (original rules); null, and the test skipped, without it.
## The suite's flows share one load of the content and flow tables.
func imported_flow(seed := 1) -> GameFlow:
	if not require(AssetCatalog.ROOT.path_join("tables/flow.json")):
		return null
	if _flow_content == null:
		_flow_content = FightContent.load_from(AssetCatalog.ROOT)
		_flow_data = FlowData.load_from(AssetCatalog.ROOT.path_join("tables/flow.json"))
	return GameFlow.new(_flow_content, _flow_data, RuleSet.original(), seed)


func expect(condition: bool, message: String = "expectation failed") -> bool:
	if not condition:
		failures.append(message)
	return condition


func expect_equal(actual: Variant, expected: Variant, message: String = "") -> bool:
	if actual == expected:
		return true
	failures.append("%sexpected %s, got %s" % [message + ": " if message else "", str(expected), str(actual)])
	return false


## Called by the runner before each test.
func reset() -> void:
	failures.clear()
	skipped = ""
