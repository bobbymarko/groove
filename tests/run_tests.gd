extends SceneTree
## Headless test runner:  godot --headless --path . -s tests/run_tests.gd
## Loads every tests/unit/test_*.gd, runs its test_* methods, exits 1 on failure.

func _initialize() -> void:
	var total_passed := 0
	var total_failed := 0
	var all_failures: Array[String] = []
	var dir := DirAccess.open("res://tests/unit")
	if dir == null:
		push_error("tests/unit not found")
		quit(2)
		return
	var files := Array(dir.get_files())
	files.sort()
	for f in files:
		if not (f.begins_with("test_") and f.ends_with(".gd")):
			continue
		var script: GDScript = load("res://tests/unit/" + f)
		var tc: TestCase = script.new()
		var r := tc.run()
		total_passed += r.passed
		total_failed += r.failed
		all_failures.append_array(tc.failures)
		print("%-40s %d passed, %d failed" % [f, r.passed, r.failed])
	for msg in all_failures:
		print("  FAIL ", msg)
	print("\n%d passed, %d failed" % [total_passed, total_failed])
	quit(0 if total_failed == 0 else 1)
