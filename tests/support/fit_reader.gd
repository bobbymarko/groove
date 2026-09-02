class_name FitReader
extends RefCounted
## Minimal independent FIT decoder for tests: header, definitions, data
## messages, CRC. Returns {header, messages: [{global, fields: {num: value}}], crc_ok}.

static func read(bytes: PackedByteArray) -> Dictionary:
	var out := {"messages": [], "crc_ok": false, "header": {}}
	if bytes.size() < 14:
		return out
	var hsize := bytes[0]
	out.header = {
		"size": hsize, "protocol": bytes[1], "profile": bytes.decode_u16(2),
		"data_size": bytes.decode_u32(4), "magic": bytes.slice(8, 12).get_string_from_ascii(),
	}
	var data_end := hsize + int(out.header.data_size)
	if bytes.size() < data_end + 2:
		return out
	var file_crc := bytes.decode_u16(data_end)
	out.crc_ok = FitEncoder.crc16(bytes.slice(0, data_end)) == file_crc
	var defs := {}
	var i := hsize
	while i < data_end:
		var rh := bytes[i]
		i += 1
		var local := rh & 0x0F
		if rh & 0x40:
			var arch := bytes[i + 1]
			var global := bytes.decode_u16(i + 2) if arch == 0 else ((bytes[i + 2] << 8) | bytes[i + 3])
			var nfields := bytes[i + 4]
			i += 5
			var fields := []
			for _f in nfields:
				fields.append([bytes[i], bytes[i + 1], bytes[i + 2]])
				i += 3
			defs[local] = {"global": global, "fields": fields}
		else:
			var d: Dictionary = defs[local]
			var values := {}
			for f in d.fields:
				var size: int = f[1]
				var v := 0
				match size:
					1: v = bytes[i]
					2: v = bytes.decode_u16(i)
					4: v = bytes.decode_u32(i)
				values[int(f[0])] = v
				i += size
			out.messages.append({"global": d.global, "fields": values})
	return out


static func of_type(decoded: Dictionary, global: int) -> Array:
	var out := []
	for m in decoded.messages:
		if m.global == global:
			out.append(m.fields)
	return out
