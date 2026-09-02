class_name TestCase
extends RefCounted
## Minimal test base. Subclasses in tests/unit define test_* methods.

var failures: Array[String] = []
var _current := ""


func run() -> Dictionary:
	var passed := 0
	var failed := 0
	for m in get_method_list():
		var n: String = m.name
		if not n.begins_with("test_"):
			continue
		_current = n
		var before := failures.size()
		setup()
		call(n)
		teardown()
		if failures.size() == before:
			passed += 1
		else:
			failed += 1
	return {"passed": passed, "failed": failed}


func setup() -> void:
	pass


func teardown() -> void:
	pass


func fail(msg: String) -> void:
	failures.append("%s.%s: %s" % [get_script().resource_path.get_file(), _current, msg])


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		fail("expected true" + (" — " + msg if msg else ""))


func assert_eq(actual, expected, msg := "") -> void:
	if actual != expected:
		fail("expected %s, got %s%s" % [str(expected), str(actual), (" — " + msg if msg else "")])


func assert_near(actual: float, expected: float, tolerance := 0.001, msg := "") -> void:
	if absf(actual - expected) > tolerance:
		fail("expected %s ± %s, got %s%s" % [expected, tolerance, actual, (" — " + msg if msg else "")])
