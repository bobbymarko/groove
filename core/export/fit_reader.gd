class_name FitReader
extends RefCounted
## FIT decoder: header, definition and data messages, developer fields,
## little- and big-endian, strings, CRC. Returns
## {header, messages: [{global, fields: {num: value}}], crc_ok}. Numbers come
## back as ints (strings as String); invalid values are left as read.

const T_STRING := 0x07


static func read(bytes: PackedByteArray) -> Dictionary:
	var out := {"messages": [], "crc_ok": false, "header": {}}
	if bytes.size() < 14:
		return out
	var hsize := bytes[0]
	out.header = {
		"size": hsize, "protocol": bytes[1], "profile": bytes.decode_u16(2),
		"data_size": bytes.decode_u32(4), "magic": bytes.slice(8, 12).get_string_from_ascii(),
	}
	if out.header.magic != ".FIT":
		return out
	var data_end := hsize + int(out.header.data_size)
	if bytes.size() < data_end + 2:
		return out
	out.crc_ok = FitEncoder.crc16(bytes.slice(0, data_end)) == bytes.decode_u16(data_end)
	var defs := {}
	var i := hsize
	while i < data_end:
		var rh := bytes[i]
		i += 1
		if rh & 0x80:   # compressed timestamp header: local type in bits 5-6, no definitions
			var local_c := (rh >> 5) & 0x03
			if not defs.has(local_c):
				break
			i = _read_data(bytes, i, defs[local_c], out.messages)
			continue
		var local := rh & 0x0F
		if rh & 0x40:
			var arch := bytes[i + 1]
			var big := arch == 1
			var global := ((bytes[i + 2] << 8) | bytes[i + 3]) if big else bytes.decode_u16(i + 2)
			var nfields := bytes[i + 4]
			i += 5
			var fields := []
			for _f in nfields:
				fields.append([bytes[i], bytes[i + 1], bytes[i + 2]])
				i += 3
			var dev_size := 0
			if rh & 0x20:   # developer fields: skipped on read, but their bytes must be consumed
				var ndev := bytes[i]
				i += 1
				for _d in ndev:
					dev_size += bytes[i + 1]
					i += 3
			defs[local] = {"global": global, "fields": fields, "big": big, "dev_size": dev_size}
		else:
			if not defs.has(local):
				break
			i = _read_data(bytes, i, defs[local], out.messages)
	return out


static func _read_data(bytes: PackedByteArray, i: int, d: Dictionary, messages: Array) -> int:
	var values := {}
	for f in d.fields:
		var size: int = f[1]
		var base: int = f[2] & 0x1F
		if i + size > bytes.size():
			return bytes.size()
		if base == T_STRING:
			var raw := bytes.slice(i, i + size)
			var nul := raw.find(0)
			values[int(f[0])] = (raw.slice(0, nul) if nul >= 0 else raw).get_string_from_utf8()
		else:
			values[int(f[0])] = _int(bytes, i, size, bool(d.big), _signed(base))
		i += size
	i += int(d.dev_size)
	messages.append({"global": d.global, "fields": values})
	return i


static func _signed(base: int) -> bool:
	return base in [0x01, 0x03, 0x05, 0x0E]   # sint8, sint16, sint32, sint64


static func _int(bytes: PackedByteArray, i: int, size: int, big: bool, signed: bool) -> int:
	var v := 0
	if big:
		for k in size:
			v = (v << 8) | bytes[i + k]
	else:
		for k in range(size - 1, -1, -1):
			v = (v << 8) | bytes[i + k]
	if signed and size < 8 and v >= (1 << (size * 8 - 1)):
		v -= 1 << (size * 8)
	return v


static func of_type(decoded: Dictionary, global: int) -> Array:
	var out := []
	for m in decoded.messages:
		if m.global == global:
			out.append(m.fields)
	return out
