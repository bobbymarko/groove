class_name Gatt
extends RefCounted
## Bluetooth GATT constants and pure codec functions for the profiles we use:
## Fitness Machine Service (FTMS) for trainer control and telemetry, and the
## Heart Rate Service. No I/O here, so everything is unit-testable.

const FTMS_SERVICE := "00001826-0000-1000-8000-00805f9b34fb"
const FTMS_INDOOR_BIKE_DATA := "00002ad2-0000-1000-8000-00805f9b34fb"
const FTMS_CONTROL_POINT := "00002ad9-0000-1000-8000-00805f9b34fb"
const FTMS_STATUS := "00002ada-0000-1000-8000-00805f9b34fb"
const FTMS_POWER_RANGE := "00002ad8-0000-1000-8000-00805f9b34fb"

const HEART_RATE_SERVICE := "0000180d-0000-1000-8000-00805f9b34fb"
const HEART_RATE_MEASUREMENT := "00002a37-0000-1000-8000-00805f9b34fb"

const CYCLING_POWER_SERVICE := "00001818-0000-1000-8000-00805f9b34fb"

enum FtmsOp {
	REQUEST_CONTROL = 0x00,
	RESET = 0x01,
	SET_TARGET_RESISTANCE = 0x04,
	SET_TARGET_POWER = 0x05,
	START_RESUME = 0x07,
	STOP_PAUSE = 0x08,
	SET_SIM_PARAMS = 0x11,
	RESPONSE = 0x80,
}

enum FtmsResult {
	SUCCESS = 0x01,
	NOT_SUPPORTED = 0x02,
	INVALID_PARAMETER = 0x03,
	OPERATION_FAILED = 0x04,
	CONTROL_NOT_PERMITTED = 0x05,
}


## Lower-case 128-bit form. Accepts 16-bit short UUIDs too.
static func norm(uuid: String) -> String:
	var u := uuid.to_lower().strip_edges()
	if u.length() == 4:
		return "0000%s-0000-1000-8000-00805f9b34fb" % u
	return u


# --- FTMS commands -------------------------------------------------------------

static func ftms_request_control() -> PackedByteArray:
	return PackedByteArray([FtmsOp.REQUEST_CONTROL])


static func ftms_start() -> PackedByteArray:
	return PackedByteArray([FtmsOp.START_RESUME])


static func ftms_set_target_power(watts: int) -> PackedByteArray:
	var b := PackedByteArray([FtmsOp.SET_TARGET_POWER, 0, 0])
	b.encode_s16(1, clampi(watts, -32768, 32767))
	return b


## Simulation mode with a fixed grade. Used for "ERG off": the trainer behaves
## like a hill, so power follows cadence and gear. Wind 0, Crr 0.004, Cw 0.51.
static func ftms_set_sim_grade(grade_percent: float) -> PackedByteArray:
	var b := PackedByteArray([FtmsOp.SET_SIM_PARAMS, 0, 0, 0, 0, 40, 51])
	b.encode_s16(1, 0)
	b.encode_s16(3, int(round(clampf(grade_percent, -40.0, 40.0) * 100.0)))
	return b


# --- FTMS parsing ---------------------------------------------------------------

## Indoor Bike Data (0x2AD2). Returns only the fields present in the packet:
## speed_kph, cadence_rpm, power_w, heart_rate, distance_m, elapsed_s.
static func parse_indoor_bike_data(d: PackedByteArray) -> Dictionary:
	var out := {}
	if d.size() < 2:
		return out
	var flags := d.decode_u16(0)
	var i := 2
	if not (flags & (1 << 0)):            # "More Data" clear => instantaneous speed present
		if i + 2 <= d.size():
			out["speed_kph"] = d.decode_u16(i) * 0.01
		i += 2
	if flags & (1 << 1):                   # average speed
		i += 2
	if flags & (1 << 2):                   # instantaneous cadence, 0.5 rpm
		if i + 2 <= d.size():
			out["cadence_rpm"] = d.decode_u16(i) * 0.5
		i += 2
	if flags & (1 << 3):                   # average cadence
		i += 2
	if flags & (1 << 4):                   # total distance, uint24 metres
		if i + 3 <= d.size():
			out["distance_m"] = d[i] | (d[i + 1] << 8) | (d[i + 2] << 16)
		i += 3
	if flags & (1 << 5):                   # resistance level
		i += 2
	if flags & (1 << 6):                   # instantaneous power, sint16 W
		if i + 2 <= d.size():
			out["power_w"] = d.decode_s16(i)
		i += 2
	if flags & (1 << 7):                   # average power
		i += 2
	if flags & (1 << 8):                   # expended energy: total u16, per hour u16, per minute u8
		i += 5
	if flags & (1 << 9):                   # heart rate u8
		if i + 1 <= d.size():
			out["heart_rate"] = d[i]
		i += 1
	if flags & (1 << 10):                  # metabolic equivalent
		i += 1
	if flags & (1 << 11):                  # elapsed time u16 s
		if i + 2 <= d.size():
			out["elapsed_s"] = d.decode_u16(i)
		i += 2
	return out


## Control Point indication. {} if not a response; else {op, result, ok}.
static func parse_control_response(d: PackedByteArray) -> Dictionary:
	if d.size() < 3 or d[0] != FtmsOp.RESPONSE:
		return {}
	return {"op": d[1], "result": d[2], "ok": d[2] == FtmsResult.SUCCESS}


## Supported Power Range (0x2AD8): {min, max, step} in watts.
static func parse_power_range(d: PackedByteArray) -> Dictionary:
	if d.size() < 6:
		return {}
	return {"min": d.decode_s16(0), "max": d.decode_s16(2), "step": d.decode_u16(4)}


static func result_name(code: int) -> String:
	for k in FtmsResult.keys():
		if FtmsResult[k] == code:
			return k.to_lower().replace("_", " ")
	return "0x%02X" % code


# --- Heart rate ----------------------------------------------------------------

## Heart Rate Measurement (0x2A37). Returns bpm, or -1 if malformed.
static func parse_heart_rate(d: PackedByteArray) -> int:
	if d.size() < 2:
		return -1
	if d[0] & 0x01:
		return d.decode_u16(1) if d.size() >= 3 else -1
	return d[1]
