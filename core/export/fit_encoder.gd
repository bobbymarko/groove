class_name FitEncoder
extends RefCounted
## Writes a FIT activity file from ride samples. Hand-rolled: the activity
## subset of the FIT profile is small and well documented. Output is validated
## by tests with an independent reader and, in practice, by intervals.icu and
## the COROS app accepting the files.

const FIT_EPOCH_OFFSET := 631065600          # seconds from Unix epoch to FIT epoch (1989-12-31)
const MANUFACTURER_DEVELOPMENT := 255
const PRODUCT_ID := 1
const SOFTWARE_VERSION := 100                # 1.00
const PROFILE_VERSION := 2132

# Base types
const T_ENUM := 0x00
const T_UINT8 := 0x02
const T_UINT16 := 0x84
const T_UINT32 := 0x86
const T_UINT32Z := 0x8C

# Global message numbers
const MSG_FILE_ID := 0
const MSG_FILE_CREATOR := 49
const MSG_DEVICE_INFO := 23
const MSG_EVENT := 21
const MSG_RECORD := 20
const MSG_LAP := 19
const MSG_SESSION := 18
const MSG_ACTIVITY := 34

const SPORT_CYCLING := 2
const SUB_SPORT_VIRTUAL_ACTIVITY := 58
const SUB_SPORT_INDOOR_CYCLING := 6

const CRC_TABLE := [0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
	0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400]

# Field layouts: [field number, size, base type]
const FIELDS := {
	MSG_FILE_ID: [[0, 1, T_ENUM], [1, 2, T_UINT16], [2, 2, T_UINT16], [3, 4, T_UINT32Z], [4, 4, T_UINT32]],
	MSG_FILE_CREATOR: [[0, 2, T_UINT16]],
	MSG_DEVICE_INFO: [[253, 4, T_UINT32], [0, 1, T_UINT8], [2, 2, T_UINT16], [4, 2, T_UINT16], [3, 4, T_UINT32Z], [5, 2, T_UINT16]],
	MSG_EVENT: [[253, 4, T_UINT32], [0, 1, T_ENUM], [1, 1, T_ENUM], [4, 1, T_UINT8]],
	MSG_RECORD: [[253, 4, T_UINT32], [7, 2, T_UINT16], [4, 1, T_UINT8], [3, 1, T_UINT8], [6, 2, T_UINT16], [5, 4, T_UINT32]],
	MSG_LAP: [[254, 2, T_UINT16], [253, 4, T_UINT32], [0, 1, T_ENUM], [1, 1, T_ENUM], [2, 4, T_UINT32],
		[7, 4, T_UINT32], [8, 4, T_UINT32], [9, 4, T_UINT32], [15, 1, T_UINT8], [16, 1, T_UINT8],
		[17, 1, T_UINT8], [19, 2, T_UINT16], [20, 2, T_UINT16], [24, 1, T_ENUM], [25, 1, T_ENUM]],
	MSG_SESSION: [[254, 2, T_UINT16], [253, 4, T_UINT32], [0, 1, T_ENUM], [1, 1, T_ENUM], [2, 4, T_UINT32],
		[5, 1, T_ENUM], [6, 1, T_ENUM], [7, 4, T_UINT32], [8, 4, T_UINT32], [9, 4, T_UINT32],
		[11, 2, T_UINT16], [16, 1, T_UINT8], [17, 1, T_UINT8], [18, 1, T_UINT8], [20, 2, T_UINT16],
		[21, 2, T_UINT16], [25, 2, T_UINT16], [26, 2, T_UINT16], [28, 1, T_ENUM], [34, 2, T_UINT16],
		[35, 2, T_UINT16], [36, 2, T_UINT16], [101, 2, T_UINT16]],
	MSG_ACTIVITY: [[253, 4, T_UINT32], [0, 4, T_UINT32], [1, 2, T_UINT16], [2, 1, T_ENUM], [3, 1, T_ENUM], [4, 1, T_ENUM], [5, 4, T_UINT32]],
}
const LOCAL := {MSG_FILE_ID: 0, MSG_FILE_CREATOR: 1, MSG_DEVICE_INFO: 2, MSG_EVENT: 3, MSG_RECORD: 4, MSG_LAP: 5, MSG_SESSION: 6, MSG_ACTIVITY: 7}


static func fit_time(unix: int) -> int:
	return unix - FIT_EPOCH_OFFSET


## meta: {started_at, ftp, ...}; samples: 1 Hz {t, p, c, h, v}; metrics: RideMetrics.compute().
static func encode(meta: Dictionary, samples: Array, metrics: Dictionary, virtual_ride := true) -> PackedByteArray:
	var start_unix := int(meta.get("started_at", samples[0].t if samples.size() > 0 else Time.get_unix_time_from_system()))
	var end_unix := int(samples[-1].t) if samples.size() > 0 else start_unix
	var elapsed_ms := maxi(end_unix - start_unix, samples.size()) * 1000
	var timer_ms := samples.size() * 1000
	var ftp := int(meta.get("ftp", 0))
	var serial := 0x52494445  # "RIDE"

	var b := StreamPeerBuffer.new()
	var defined := {}

	_msg(b, defined, MSG_FILE_ID, [4, MANUFACTURER_DEVELOPMENT, PRODUCT_ID, serial, fit_time(start_unix)])
	_msg(b, defined, MSG_FILE_CREATOR, [SOFTWARE_VERSION])
	_msg(b, defined, MSG_DEVICE_INFO, [fit_time(start_unix), 0, MANUFACTURER_DEVELOPMENT, PRODUCT_ID, serial, SOFTWARE_VERSION])
	_msg(b, defined, MSG_EVENT, [fit_time(start_unix), 0, 0, 0])   # timer start

	var dist_m := 0.0
	for s in samples:
		dist_m += float(s.get("v", 0.0)) / 3.6
		var hr := int(s.get("h", 0))
		_msg(b, defined, MSG_RECORD, [
			fit_time(int(s.t)),
			int(s.get("p", 0)),
			int(s.get("c", 0)),
			hr if hr > 0 else 0xFF,
			int(round(float(s.get("v", 0.0)) / 3.6 * 1000.0)),
			int(round(dist_m * 100.0)),
		])

	_msg(b, defined, MSG_EVENT, [fit_time(end_unix), 0, 4, 0])   # timer stop_all

	var avg_hr := int(metrics.get("avg_heart_rate", 0))
	var max_hr := int(metrics.get("max_heart_rate", 0))
	_msg(b, defined, MSG_LAP, [
		0, fit_time(end_unix), 9, 1, fit_time(start_unix),
		elapsed_ms, timer_ms, int(round(dist_m * 100.0)),
		avg_hr if avg_hr > 0 else 0xFF, max_hr if max_hr > 0 else 0xFF,
		int(metrics.get("avg_cadence", 0)), int(metrics.get("avg_power", 0)), int(metrics.get("max_power", 0)),
		7, SPORT_CYCLING,
	])
	_msg(b, defined, MSG_SESSION, [
		0, fit_time(end_unix), 8, 1, fit_time(start_unix),
		SPORT_CYCLING, SUB_SPORT_VIRTUAL_ACTIVITY if virtual_ride else SUB_SPORT_INDOOR_CYCLING,
		elapsed_ms, timer_ms, int(round(dist_m * 100.0)),
		int(round(float(metrics.get("kj", 0.0)))),
		avg_hr if avg_hr > 0 else 0xFF, max_hr if max_hr > 0 else 0xFF,
		int(metrics.get("avg_cadence", 0)), int(metrics.get("avg_power", 0)), int(metrics.get("max_power", 0)),
		0, 1, 0,
		int(metrics.get("normalized_power", 0)),
		int(round(float(metrics.get("tss", 0.0)) * 10.0)),
		int(round(float(metrics.get("intensity_factor", 0.0)) * 1000.0)),
		ftp,
	])
	_msg(b, defined, MSG_ACTIVITY, [fit_time(end_unix), timer_ms, 1, 0, 26, 1, fit_time(end_unix)])

	var data := b.data_array
	var header := StreamPeerBuffer.new()
	header.put_u8(14)
	header.put_u8(0x20)
	header.put_u16(PROFILE_VERSION)
	header.put_u32(data.size())
	header.put_data(".FIT".to_ascii_buffer())
	header.put_u16(crc16(header.data_array))
	var out := header.data_array
	out.append_array(data)
	var crc := crc16(out)
	out.append(crc & 0xFF)
	out.append((crc >> 8) & 0xFF)
	return out


static func _msg(b: StreamPeerBuffer, defined: Dictionary, global_num: int, values: Array) -> void:
	var fields: Array = FIELDS[global_num]
	var local: int = LOCAL[global_num]
	assert(values.size() == fields.size(), "field/value count mismatch for message %d" % global_num)
	if not defined.has(global_num):
		defined[global_num] = true
		b.put_u8(0x40 | local)
		b.put_u8(0)            # reserved
		b.put_u8(0)            # little endian
		b.put_u16(global_num)
		b.put_u8(fields.size())
		for f in fields:
			b.put_u8(f[0])
			b.put_u8(f[1])
			b.put_u8(f[2])
	b.put_u8(local)
	for i in fields.size():
		var v := int(values[i])
		match int(fields[i][1]):
			1: b.put_u8(clampi(v, 0, 0xFF))
			2: b.put_u16(clampi(v, 0, 0xFFFF))
			4: b.put_u32(v & 0xFFFFFFFF)


static func crc16(data: PackedByteArray) -> int:
	var crc := 0
	for byte in data:
		var tmp: int = CRC_TABLE[crc & 0xF]
		crc = (crc >> 4) & 0x0FFF
		crc = crc ^ tmp ^ int(CRC_TABLE[byte & 0xF])
		tmp = CRC_TABLE[crc & 0xF]
		crc = (crc >> 4) & 0x0FFF
		crc = crc ^ tmp ^ int(CRC_TABLE[(byte >> 4) & 0xF])
	return crc
