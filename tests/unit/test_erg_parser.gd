extends TestCase
## .mrc / .erg course files.

const MRC := """[COURSE HEADER]
VERSION = 2
UNITS = ENGLISH
DESCRIPTION = Two steps and a ramp
FILE NAME = sweetspot.mrc
MINUTES PERCENT
[END COURSE HEADER]
[COURSE DATA]
0.00	50
5.00	80
5.00	90
15.00	90
15.00	50
20.00	50
[END COURSE DATA]
[COURSE TEXT]
0	Spin easy	10
300	Sweet spot now	10
[END COURSE TEXT]
"""

const ERG := """[COURSE HEADER]
VERSION = 2
UNITS = ENGLISH
DESCRIPTION = watts file
FTP = 250
MINUTES WATTS
[END COURSE HEADER]
[COURSE DATA]
0.00	125
10.00	125
10.00	250
20.00	250
[END COURSE DATA]
"""


func test_mrc_segments() -> void:
	var w := ErgParser.parse(MRC, "mrc", 200)
	assert_true(w != null, ErgParser.last_error)
	assert_eq(w.segments.size(), 3)
	assert_eq(w.segments[0].kind, WorkoutSegment.Kind.WARMUP)
	assert_near(w.segments[0].power_low, 0.5)
	assert_near(w.segments[0].power_high, 0.8)
	assert_near(w.segments[1].duration, 600.0)
	assert_near(w.segments[1].power_low, 0.9)
	assert_eq(w.segments[1].kind, WorkoutSegment.Kind.STEADY)
	assert_near(w.total_duration(), 1200.0)
	assert_eq(w.name, "sweetspot")
	assert_eq(w.description, "Two steps and a ramp")
	assert_eq(w.text_events.size(), 2)
	assert_eq(w.text_events[1].message, "Sweet spot now")
	assert_near(float(w.text_events[1].time), 300.0)


func test_erg_uses_file_ftp() -> void:
	var w := ErgParser.parse(ERG, "erg", 999)
	assert_true(w != null, ErgParser.last_error)
	assert_eq(w.segments.size(), 2)
	assert_near(w.segments[0].power_low, 0.5)
	assert_near(w.segments[1].power_low, 1.0)


func test_erg_without_ftp_uses_rider_ftp() -> void:
	var w := ErgParser.parse(ERG.replace("FTP = 250\n", ""), "erg", 125)
	assert_true(w != null)
	assert_near(w.segments[1].power_low, 2.0)


func test_garbage() -> void:
	assert_true(ErgParser.parse("hello", "mrc", 200) == null)
