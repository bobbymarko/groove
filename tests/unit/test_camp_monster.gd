extends TestCase
## Camp's monster kit: every part the editor offers exists, every combination
## fits the bike, and a saved rider comes back unchanged.


func test_every_editor_part_exists_in_the_kit() -> void:
	for body in MonsterEditor.PARTS.body:
		assert_true(PartKit.has_part("monster", "body_" + str(body[0])), "body " + str(body[0]))
		assert_true(PartKit.has_part("monster", "body_%s_fur" % body[0]), "fur body " + str(body[0]))
	for key in ["head", "eyes", "mouth"]:
		for opt in MonsterEditor.PARTS[key]:
			if str(opt[0]) != "":
				var prefix: String = {"head": "head_", "eyes": "eyes_", "mouth": "mouth_"}[key]
				assert_true(PartKit.has_part("monster", prefix + str(opt[0])), "%s %s" % [key, opt[0]])
	for opt in MonsterEditor.PARTS.hands:
		assert_true(PartKit.has_part("monster", "hand_" + str(opt[0])), "hand " + str(opt[0]))
	for opt in MonsterEditor.PARTS.feet:
		assert_true(PartKit.has_part("monster", str(opt[0])), "feet " + str(opt[0]))
	for opt in MonsterEditor.EXTRAS:
		var id := str(opt[0])
		if id == "horns":
			assert_true(PartKit.has_part("monster", "horn_l") and PartKit.has_part("monster", "horn_r"), "horns")
		else:
			assert_true(PartKit.has_part("monster", id), "extra " + id)


func test_extreme_proportions_still_fit_the_bike() -> void:
	for leg in [0.45, 1.0]:
		for arm in [0.4, 0.95]:
			for body in ["round", "square", "bean"]:
				var recipe: Dictionary = MonsterPresets.FUZZ.duplicate(true)
				recipe["body"] = body
				recipe["size"]["leg"] = leg
				recipe["size"]["arm"] = arm
				recipe["size"]["girth"] = 1.5
				var r := MonsterRider.new()
				r.recipe = recipe
				r.build()
				r.advance(0.3)
				var where := "%s leg %.2f arm %.2f" % [body, leg, arm]
				assert_true(r._saddle_s >= 0.12 and r._saddle_s <= 0.90, "saddle in range: " + where)
				assert_true(r._lean >= 0.0 and r._lean <= deg_to_rad(34.1), "lean in range: " + where)
				var o := r.rig.pivot.transform.origin
				assert_true(o.is_finite(), "pivot finite: " + where)
				r.free()


func test_every_preset_builds_standing_and_riding() -> void:
	for p in MonsterPresets.all() + [MonsterPresets.TRADER]:
		var r := MonsterRider.new()
		r.recipe = p
		r.build()
		r.advance(0.5)
		assert_true(r.rig.pivot.get_child_count() > 1, "%s has parts" % p.name)
		r.free()


func test_saved_rider_round_trips() -> void:
	var original: Dictionary = MonsterPresets.BOT.duplicate(true)
	var back: Dictionary = CampSave._decode(JSON.parse_string(JSON.stringify(CampSave._encode(original))))
	assert_eq(back.body, original.body)
	assert_eq(back.extras, original.extras)
	assert_true((back.colours.glow as Color).is_equal_approx(original.colours.glow), "colour survives")
	assert_near(float(back.size.leg), float(original.size.leg))
	assert_true((back.bike.frame as Color).is_equal_approx(original.bike.frame), "bike colour survives")
