class_name GpxParser
extends RefCounted
## Reads a GPX file into a Route: track points (or route points when the file
## has no track), joined across segments, with elevation when present.

static var last_error := ""


static func parse_file(path: String) -> Route:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		last_error = "could not read the file"
		return null
	var r := parse_bytes(bytes)
	if r != null and r.name == "":
		r.name = path.get_file().get_basename().replace("_", " ").replace("-", " ")
	return r


static func parse_bytes(bytes: PackedByteArray) -> Route:
	last_error = ""
	var x := XMLParser.new()
	if x.open_buffer(bytes) != OK:
		last_error = "not an XML file"
		return null
	var trk := {"lat": PackedFloat64Array(), "lon": PackedFloat64Array(), "ele": PackedFloat64Array(), "has": false}
	var rte := {"lat": PackedFloat64Array(), "lon": PackedFloat64Array(), "ele": PackedFloat64Array(), "has": false}
	var name := ""
	var current: Dictionary = {}     # the list the open point belongs to
	var in_point := false
	var reading := ""                # "ele" or "name" while inside that element
	var depth_name_ok := true        # only the first <name> (the route's or the track's) counts
	while x.read() == OK:
		match x.get_node_type():
			XMLParser.NODE_ELEMENT:
				var tag := x.get_node_name().to_lower()
				if tag == "trkpt" or tag == "rtept":
					current = trk if tag == "trkpt" else rte
					current.lat.append(float(x.get_named_attribute_value_safe("lat")))
					current.lon.append(float(x.get_named_attribute_value_safe("lon")))
					current.ele.append(0.0)
					in_point = not x.is_empty()
				elif tag == "ele" and in_point:
					reading = "ele"
				elif tag == "name" and not in_point and depth_name_ok:
					reading = "name"
			XMLParser.NODE_TEXT:
				var text := x.get_node_data().strip_edges()
				if text == "":
					continue
				if reading == "ele":
					current.ele[current.ele.size() - 1] = float(text)
					current.has = true
				elif reading == "name":
					name = text
					depth_name_ok = false
			XMLParser.NODE_CDATA:
				if reading == "name" and name == "":
					name = x.get_node_data().strip_edges()
					depth_name_ok = false
			XMLParser.NODE_ELEMENT_END:
				var tag := x.get_node_name().to_lower()
				if tag == "trkpt" or tag == "rtept":
					in_point = false
				if tag == "ele" or tag == "name":
					reading = ""
	var src: Dictionary = trk if trk.lat.size() >= 2 else rte
	if src.lat.size() < 2:
		last_error = "no track or route points in the file"
		return null
	var r := Route.new()
	r.name = name
	r.lats = src.lat
	r.lons = src.lon
	r.eles = src.ele
	r.has_elevation = src.has
	r.finish()
	if r.length < 100.0:
		last_error = "the route is shorter than 100 m"
		return null
	return r
