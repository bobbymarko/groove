extends TestCase
## Camp's training session rules: the trail follows the workout, finds grow
## where they should, and foraging pays for riding on target.

var w: Workout
var trail: PowerTrail


func setup() -> void:
	w = ZwoParser.parse_file("res://camp/ride/workouts/camp_sampler.zwo")
	trail = PowerTrail.new(w)


func test_trail_is_as_long_as_the_workout() -> void:
	assert_near(trail.length(), w.total_duration() * PowerTrail.SCROLL)


func test_hard_blocks_are_higher_ground() -> void:
	var warm := trail.height_at(10.0 * PowerTrail.SCROLL)       # warmup, ~60 %
	var hard := trail.height_at(35.0 * PowerTrail.SCROLL)       # 110 % plateau
	var easy := trail.height_at(60.0 * PowerTrail.SCROLL)       # 55 % breather
	assert_true(hard > warm + 1.0, "plateau above the warmup")
	assert_true(easy < hard - 1.5, "drop after the interval")
	assert_near(trail.height_at(80.0 * PowerTrail.SCROLL), PowerTrail.MEADOW, 0.01, "max effort is a meadow")


func test_finds_grow_where_they_should() -> void:
	var kinds := {}
	for f in trail.finds():
		kinds[f.kind] = kinds.get(f.kind, 0) + 1
		if f.kind == PowerTrail.FLOWER:
			assert_eq(int(f.segment), 1, "flowers only on the hard steady block")
		if f.kind == PowerTrail.CRITTER:
			assert_eq(int(f.segment), 1, "the critter belongs to the hard block")
		if f.kind == PowerTrail.HONEY:
			assert_eq(int(f.segment), 3, "honey belongs to the max effort")
	assert_eq(kinds.get(PowerTrail.CRITTER, 0), 1)
	assert_eq(kinds.get(PowerTrail.HONEY, 0), 1)
	assert_true(kinds.get(PowerTrail.BERRY, 0) > 30, "berries all along")


func test_the_band() -> void:
	var f := Forage.new()
	f.ftp = 250
	for i in 3:
		f.add_second(240, 250)
	assert_eq(f.band(250), "in")
	for i in 3:
		f.add_second(200, 250)
	assert_eq(f.band(250), "low")
	assert_false(f.in_band(250))
	for i in 3:
		f.add_second(300, 250)
	assert_eq(f.band(250), "high")
	assert_true(f.in_band(250), "over target still forages")
	assert_eq(f.band(0), "in", "free ride counts any steady pedalling")


func test_critter_needs_the_whole_interval() -> void:
	var f := Forage.new()
	f.ftp = 250
	f.start_segment()
	for i in 30:
		f.add_second(270, 275)
	assert_true(f.critter_caught())
	f.start_segment()
	for i in 30:
		f.add_second(200 if i > 15 else 275, 275)
	assert_false(f.critter_caught(), "fading in the second half lets it go")


func test_harder_ground_and_bias_pay_more() -> void:
	var easy := Forage.new()
	easy.add("berry", 1, 100, 0.6)
	var hard := Forage.new()
	hard.add("berry", 1, 100, 1.1)
	var biased := Forage.new()
	biased.add("berry", 10, 110, 0.6)
	assert_eq(easy.value(), 1)
	assert_eq(hard.value(), 4)
	assert_eq(biased.value(), 11)
	assert_true(Forage.coins(10, 60.0) > Forage.coins(10, 20.0), "load bonus grows with TSS")


func test_honey_comes_from_watts_over_ftp() -> void:
	var f := Forage.new()
	f.ftp = 250
	f.start_segment()
	for i in 15:
		f.add_second(500, 0, true)
	assert_true(f.honey_earned() >= 20, "a big sprint fills the comb")
	f.start_segment()
	for i in 15:
		f.add_second(200, 0, true)
	assert_eq(f.honey_earned(), 0)
