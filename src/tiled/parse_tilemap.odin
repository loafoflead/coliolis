package tiled;

// helpful stuff: https://forum.odin-lang.org/t/need-some-help-understanding-how-to-utilize-core-encoding-xml/1130/2
// https://discourse.mapeditor.org/t/tiled-csv-format-has-exceptionally-large-tile-values-solved/4765
// https://discourse.mapeditor.org/t/how-to-know-which-tileset-uses-a-tile-in-a-tilemap/4869

import "core:encoding/json"
import "core:strconv"
import "core:os"
import "core:fmt"
import "core:log"
import "core:strings"

import "base:runtime"

import vmem "core:mem/virtual"

TILEMAP_MAX_LAYERS :: 10
TILEMAP_MAX_OBJECT_GROUPS :: 10
TILEMAP_MAX_OBJECTS_PER_GROUP :: 10

TILEMAP_OBJ_TYPE_MARKER :: "marker"
TILEMAP_OBJTYPE_FUNC    :: "func"

Tilemap_Json :: struct {	
	tiledversion: string,
	version: string,
	compressionlevel: int,
	orientation: string,
	renderorder: string,

	width, height: uint,
	tileheight, tilewidth: uint,
	infinite: bool,
	type: string,
	
	layers: []Tilemap_Json_Layer,
	tilesets: []Tilemap_Json_Tileset,
}

Tilemap_Json_Tileset :: struct {
	firstgid: uint,
	source: string,
}

Tilemap_Json_Layer :: struct {
	x, y: f32,
	width, height: uint,
	visible: bool,
	id: int,
	name: string,

	data: []uint,
	objects: []Tilemap_Json_Object,

	draworder: string,
	opacity: f32,
	properties: []Tilemap_Json_Property,
	type: string,
}
Tilemap_Layer :: struct {
	name: string,
	opacity: f32,
	id: Tilemap_Object_Id,
	width, height: uint,
	pos: [2]f32,
	data: []Tile,
	visible: bool,
	properties: map[string]Tilemap_Object_Property,
}

Json_Vertex :: struct {x, y: f32}

Tilemap_Json_Object :: struct {
	x, y: f32,
	width, height: f32,
	visible: bool,
	id: int,
	name: string,
	polygon: []Json_Vertex,

	rotation: f32,
	type: string,
	properties: []Tilemap_Json_Property,
}

Tilemap_Json_Property :: struct {
	name: string,
	type: string,
	value: json.Value,
	propertytype: string,
}


Tilemap :: struct {
	// TODO: make possible to have multiple
	tilesets: []Tileset,
	version: string,
	width, height: uint,
	tilewidth, tileheight: uint,
	layers: []Tilemap_Layer,
	objects: []Tilemap_Object,
	ids: map[Tilemap_Object_Id]union{^Tilemap_Layer, ^Tilemap_Object},

	arena: vmem.Arena,
}

Tilemap_Object_Type :: enum {
	Other = 0,
	Marker,
	Func,
}

Tilemap_Class :: struct {
	classname: string,
	// TODO: make []u8
	json_data: string,
}

Tilemap_Enum :: struct {
	name: string,
	value: string,
}

Tilemap_Object_Property :: union {
	Tilemap_Class,
	Tilemap_Enum,
	Tilemap_Object_Id, // for links
	string,
}

Tilemap_Object_Id :: distinct int

Tilemap_Object :: struct {
	name: string,
	id: Tilemap_Object_Id,
	type_string: string,
	type: Tilemap_Object_Type,
	pos, dims: [2]f32,
	vertices: []([2]f32),
	rot: f32,
	visible: bool,
	properties: map[string]Tilemap_Object_Property,
}

Tile_Orientation :: enum {
	Flip_Horiz, 
	Flip_Vert,
	Flip_Diagonal,
}

Tile_Orientation_Set :: bit_set[Tile_Orientation; u32]

Tile :: struct {
	guid: uint,
	orientation: Tile_Orientation_Set,
}

free_tilemap :: proc(tilemap: ^Tilemap) {
	vmem.arena_destroy(&tilemap.arena)
}

// https://discourse.mapeditor.org/t/how-to-know-which-tileset-uses-a-tile-in-a-tilemap/4869
tilemap_tile_belongs_to_set :: proc() {
	unimplemented("todo: get tileset of tile using GID")
}

find_layers_with_property :: proc(tilemap: ^Tilemap, property, value: string) -> (layers: [dynamic]^Tilemap_Layer, found: bool) {
	layers = make([dynamic]^Tilemap_Layer)
	for &layer in tilemap.layers {
		if property in layer.properties {
			str, ok := layer.properties[property].(string)
			if !ok do continue
			if str == value {
				append(&layers, &layer)
				found = true
			}
		}
	}

	return
}

get_tile_tileset :: proc(tilemap: ^Tilemap, tile: Tile) -> (set: ^Tileset, idx: int) {
	NOT_EXACTLY_UINT_MAX :: uint(9999090909090909)
	next_gid := NOT_EXACTLY_UINT_MAX // there's no UINT_MAX in core:math :( (2025)
	for i in 0..<len(tilemap.tilesets) {
		if i+1 == len(tilemap.tilesets) do next_gid = NOT_EXACTLY_UINT_MAX
		else do next_gid = tilemap.tilesets[i+1].firstgid

		if tile.guid >= tilemap.tilesets[i].firstgid && tile.guid < next_gid {
			return &tilemap.tilesets[i], i
		}
	}
	// if len(tilemap.tilesets) == 1 do return &tilemap.tilesets[0], 0
	// lwr_bound, upper_bound := uint(1), tilemap.tilesets[1].firstgid
	// for i in 1..<len(tilemap.tilesets) {
	// 	tset := tilemap.tilesets[i]
	// 	if uint(tile) <= upper_bound && uint(tile) > lwr_bound {
	// 		return &tilemap.tilesets[idx], idx
	// 	}
	// 	else if uint(tile) > upper_bound {
	// 		lwr_bound = upper_bound
	// 		upper_bound = tset.firstgid if i != len(tilemap.tilesets)-1 else 9999999999999
	// 		idx += 1
	// 	}
	// }
	return &tilemap.tilesets[idx], idx
}

tilemap_parse_property :: proc(arena: runtime.Allocator, property: Tilemap_Json_Property) -> (prop: Tilemap_Object_Property, ok: bool) {
	ok = true
	switch property.type {
	case "class":
		builda, alloc_err := strings.builder_make(len=0, cap=0, allocator = arena)
		if alloc_err != nil {
			log.panicf("%v", alloc_err)
		}

		opt: json.Marshal_Options

		err := json.marshal_to_builder(&builda, property.value, &opt)		
		if err != nil {
			log.panicf("Failed to marshal json value (impossible): %v", property.value)
		}
		prop = Tilemap_Class{
			classname = property.propertytype,
			json_data = strings.to_string(builda),
		}
	case "string":
		if property.propertytype != "" {
			prop = Tilemap_Enum {
				name = property.propertytype,
				value = property.value.(string),
			}
		}
		else {
			prop = property.value.(string)
		}
	case "file":
		prop = property.value.(string)
	case "color", "float", "int", "bool":
		unimplemented("More data types for top level object properties")
	case "object":
		prop = cast(Tilemap_Object_Id)(property.value.(i64))
	case:
		log.warnf("Unsupported object property type '%s'", property.type)
		ok = false
	}

	return
}

parse_tilemap :: proc(path: string, path_prefix: string = "", parse_tileset_automatically: bool = true, check_tileset_valid: bool = true) -> (_t: Tilemap, err: bool) {
	json_data, ok := os.read_entire_file_from_filename(path)
	if !ok {
		log.errorf("Could not find tilemap file '%s'", path)
		return {}, false
	}
	defer delete(json_data)

	tilemap: Tilemap
	arena := vmem.arena_allocator(&tilemap.arena)

	tilemap_json: Tilemap_Json
	json_err := json.unmarshal(json_data, &tilemap_json, allocator = arena)
	if json_err != nil {
		log.errorf("Failed to parse json file for tilemap '%s', error: %v", path, json_err)
		return {}, false
	}

	if tilemap_json.version != EXPECTED_JSON_VERSION do log.warnf("Got version '%s' when expected '%s', some things may load incorrectly or not at all.", tilemap_json.version, EXPECTED_JSON_VERSION)

	loaded_tilesets := make([]Tileset, len(tilemap_json.tilesets), allocator = arena)

	for tileset, i in tilemap_json.tilesets {
		set, ok := parse_tileset(fmt.tprintf("%s/%s", path_prefix, tileset.source))
		if !ok {
			log.errorf("Failed to load tileset: '%s'", tileset.source)
			continue
		}
		set.firstgid = tileset.firstgid
		log.infof("Successfully loaded tileset '%s' for tilemap '%s'", set.name, path)
		loaded_tilesets[i] = set
	}

	tilemap.tilesets = loaded_tilesets

	tilemap.width, tilemap.height = tilemap_json.width, tilemap_json.height
	tilemap.tilewidth, tilemap.tileheight = tilemap_json.tilewidth, tilemap_json.tileheight
	tilemap.version = tilemap_json.version

	obj_count, layer_count: int
	for layer in tilemap_json.layers {
		if layer.type == "objectgroup" {
			obj_count += len(layer.objects)
		}
		else if layer.type == "tilelayer" {
			layer_count += 1
		}
	}

	ids := make(map[Tilemap_Object_Id]union{^Tilemap_Layer, ^Tilemap_Object}, allocator = arena)
	objects := make([]Tilemap_Object, obj_count, allocator = arena)
	layers := make([]Tilemap_Layer, layer_count, allocator = arena)

	obj_i, layer_i: int
	for layer in tilemap_json.layers {
		if layer.type == "objectgroup" {
			for object in layer.objects {
				obj: Tilemap_Object
				obj.name = object.name
				obj.pos = [2]f32{object.x, object.y}
				obj.dims = [2]f32{object.width, object.height}
				obj.visible = object.visible
				obj.id = Tilemap_Object_Id(object.id)
				obj.rot = object.rotation
				obj.type_string = object.type
				obj.type = tilemap_obj_type_from_string(object.type)
				obj.vertices = transmute([]([2]f32))object.polygon // TODO: is this... right?
				// TODO: add shape property to Tilemap_Object

				for property in object.properties {
					obj.properties[property.name] = tilemap_parse_property(arena, property) or_continue
				}

				objects[obj_i] = obj
				last := &objects[obj_i]
				ids[last.id] = last
				obj_i += 1
			}
		}
		else if layer.type == "tilelayer" {
			lyr: Tilemap_Layer

			lyr.name = layer.name
			lyr.pos = [2]f32{layer.x, layer.y}
			lyr.width, lyr.height = layer.width, layer.height
			for prop in layer.properties {
				lyr.properties[prop.name] = tilemap_parse_property(arena, prop) or_continue
			}
			lyr.opacity = layer.opacity
			lyr.visible = layer.visible
			lyr.id = Tilemap_Object_Id(layer.id)
			lyr.data = make([]Tile, len(layer.data), allocator = arena)
			for dat, i in layer.data {
				lyr.data[i] = tiled_data_to_tile(dat)
			}

			layers[layer_i] = lyr
			last := &layers[layer_i]
			ids[last.id] = last
			layer_i += 1
		}
		else {
			log.errorf("Unsupported layer type found in tilemap '%s': '%s'", path, layer.type)
		}
	}

	tilemap.objects = objects
	tilemap.layers = layers
	tilemap.ids = ids

	return tilemap, true
	// TODO: how to free?
	// doc, oopsie := xml.load_from_file(path);
	// if oopsie != nil {
	// 	fmt.printfln("ERROR: Tilemap `{}` not found in {}", path, os.get_current_directory());
	// 	return Tilemap{}, false;
	// }

	// infinite := xml.find_attribute_val_by_key(doc, 0, "infinite") or_return;
	// if infinite != "0" {
	// 	fmt.println("ERROR: `infinite` is expected to be \"0\", not `",infinite,"`");
	// 	return Tilemap{}, false;
	// }
	// orientation := xml.find_attribute_val_by_key(doc, 0, "orientation") or_return;
	// if orientation != "orthogonal" {
	// 	fmt.println("ERROR: `orientation` is expected to be \"orthogonal\", not `",orientation,"`");
	// 	return Tilemap{}, false;
	// }
	// renderorder := xml.find_attribute_val_by_key(doc, 0, "renderorder") or_return;
	// if renderorder != "right-down" {
	// 	fmt.println("WARNING: Render order is expected to be `right-down`, other values aren't taking into account.");
	// }

	// tilemap: Tilemap;
	// tilemap.version = xml.find_attribute_val_by_key(doc, 0, "version") or_return;
	// if tilemap.version != EXPECTED_VERSION {
	// 	fmt.printfln("WARNING: expected version `{}`, GOT `{}`, certain things might not work right.", EXPECTED_VERSION, tilemap.version);
	// }
	// tilemap.width = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "width") or_return) or_return;
	// tilemap.height = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "height") or_return) or_return;
	// tilemap.tilewidth = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tilewidth") or_return) or_return;
	// tilemap.tileheight = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tileheight") or_return) or_return;

	// tilemap.width_pixels = tilemap.width * tilemap.tilewidth
	// tilemap.height_pixels = tilemap.height * tilemap.tileheight

	// tileset_id := xml.find_child_by_ident(doc, 0, "tileset") or_return;
	// if parse_tileset_automatically {
	// 	tileset_source := fmt.tprintf("%s/%s", path_prefix, xml.find_attribute_val_by_key(doc, tileset_id, "source") or_return);
	// 	if !os.exists(tileset_source) {
	// 		fmt.printfln(
	// 			"ERROR: Tileset `{}` required by tilemap `{}` could not be found in `{}`. The tilemap source field must point to a valid tileset, or you can set the tileset yourself.",
	// 			tileset_source,
	// 			path,
	// 			fmt.tprintf("%s/%s", path_prefix, os.get_current_directory()),
	// 		);
	// 		return Tilemap{}, false;
	// 	}
	// 	else {
	// 		tilemap.tileset = parse_tileset(tileset_source) or_return;
	// 		if check_tileset_valid {
	// 			if !os.exists(tilemap.tileset.source) {
	// 				fmt.printfln(
	// 					"WARNING: tileset `{}` points to a path ({}) that can't be reached from `{}`, you may need to set it yourself, or be careful to properly place the source image relative to the executable.",
	// 					tilemap.tileset.name,
	// 					tilemap.tileset.source,
	// 					fmt.tprintf("%s/%s", path_prefix, os.get_current_directory()),
	// 				)
	// 			}
	// 		}
	// 	}
	// }

	// layers := make([dynamic]Tilemap_Layer);

	// for i in 0..=TILEMAP_MAX_LAYERS {
	// 	layer_xml_id := xml.find_child_by_ident(doc, 0, "layer", i) or_break;
	// 	layer: Tilemap_Layer;
	// 	layer.id 	 = strconv.parse_uint(xml.find_attribute_val_by_key(doc, layer_xml_id, "id") or_return) or_return;
	// 	layer.width  = strconv.parse_uint(xml.find_attribute_val_by_key(doc, layer_xml_id, "width") or_return) or_return;
	// 	layer.height = strconv.parse_uint(xml.find_attribute_val_by_key(doc, layer_xml_id, "height") or_return) or_return;
	// 	layer.name 	 = xml.find_attribute_val_by_key(doc, layer_xml_id, "name") or_return;

	// 	data_xml_id := xml.find_child_by_ident(doc, layer_xml_id, "data") or_return;
	// 	format := xml.find_attribute_val_by_key(doc, data_xml_id, "encoding") or_return;
	// 	if format != "csv" {
	// 		fmt.printfln("Cannot parse tile layer definitions in format '%v', only 'csv'.", format);
	// 		return Tilemap{}, false;
	// 	}
	// 	string_data := doc.elements[data_xml_id].value[0]; // TODO: brutal assertion here
	// 	layer.data = parse_layer_from_csv(string_data.(string), layer.width, layer.height) or_return;

	// 	props_id, found_props := xml.find_child_by_ident(doc, layer_xml_id, "properties")
	// 	if !found_props {
	// 		append(&layers, layer);
	// 		continue
	// 	}

	// 	layer.properties = make(map[string]string)

	// 	prop_idx: int
	// 	for {
	// 		prop_id := xml.find_child_by_ident(doc, props_id, "property", prop_idx) or_break

	// 		prop_name := xml.find_attribute_val_by_key(doc, prop_id, "name") or_break
	// 		prop_value := xml.find_attribute_val_by_key(doc, prop_id, "value") or_break
	// 		layer.properties[prop_name] = prop_value
	// 		prop_idx += 1
	// 	}

	// 	append(&layers, layer);
	// }

	// objects := make([dynamic]Tilemap_Object)
	// object_groups := make(map[string]Object_Group)

	// for i in 0..=TILEMAP_MAX_OBJECT_GROUPS {
	// 	group_xml_id := xml.find_child_by_ident(doc, 0, "objectgroup", i) or_break;
	// 	group: Object_Group;
	// 	group.id 	 = strconv.parse_uint(xml.find_attribute_val_by_key(doc, group_xml_id, "id") or_return) or_return;
	// 	group.name 	 = xml.find_attribute_val_by_key(doc, group_xml_id, "name") or_return;

	// 	group.objects = make([dynamic]Tilemap_Object_Id);

	// 	for j in 0..=TILEMAP_MAX_OBJECTS_PER_GROUP {
	// 		object: Tilemap_Object
	// 		obj_xml_id := xml.find_child_by_ident(doc, group_xml_id, "object", j) or_break

	// 		object.id = strconv.parse_uint(xml.find_attribute_val_by_key(doc, obj_xml_id, "id") or_return) or_return
	// 		object.pos.x = strconv.parse_f32(xml.find_attribute_val_by_key(doc, obj_xml_id, "x") or_return) or_return
	// 		object.pos.y = strconv.parse_f32(xml.find_attribute_val_by_key(doc, obj_xml_id, "y") or_return) or_return
	// 		object.name = xml.find_attribute_val_by_key(doc, obj_xml_id, "name") or_return
	// 		object.type_string = xml.find_attribute_val_by_key(doc, obj_xml_id, "type") or_return
	// 		object.type = tilemap_obj_type_from_string(object.type_string)

	// 		_, is_point := xml.find_child_by_ident(doc, obj_xml_id, "point")
	// 		if is_point do object.class = .Point
	// 		else do object.class = .Other

	// 		props_id, found_props := xml.find_child_by_ident(doc, obj_xml_id, "properties")
	// 		if !found_props {
	// 			id := Tilemap_Object_Id(len(objects))
	// 			append(&objects, object)
	// 			append(&group.objects, id)
	// 			continue
	// 		}

	// 		object.properties = make(map[string]string)

	// 		prop_idx: int
	// 		for {
	// 			prop_id := xml.find_child_by_ident(doc, props_id, "property", prop_idx) or_break

	// 			prop_name := xml.find_attribute_val_by_key(doc, prop_id, "name") or_break
	// 			prop_value := xml.find_attribute_val_by_key(doc, prop_id, "value") or_break
	// 			object.properties[prop_name] = prop_value
	// 			prop_idx += 1
	// 		}

	// 		id := Tilemap_Object_Id(len(objects))
	// 		append(&objects, object)
	// 		append(&group.objects, id)
	// 	}

	// 	object_groups[group.name] = group
	// }

	// // layer_def := xml.find_attribute_val_by_key(doc, 0, "renderorder") or_return;

	// tilemap.layers = layers
	// tilemap.object_groups = object_groups
	// tilemap.objects = objects

	// return tilemap, true;
}

// https://discourse.mapeditor.org/t/tiled-csv-format-has-exceptionally-large-tile-values-solved/4765
tiled_data_to_tile :: proc(data: uint) -> (tile: Tile) {
	horizontal_flip := data & 0x80000000
	vertical_flip := data & 0x40000000
	diagonal_flip := data & 0x20000000
	guid := data & ~(uint(0x80000000) | uint(0x40000000) | uint(0x20000000)) //clear the flags

	orientation: Tile_Orientation_Set

	if bool(horizontal_flip) do orientation += {.Flip_Horiz}
	if bool(vertical_flip) do orientation += {.Flip_Vert}
	if bool(diagonal_flip) do orientation += {.Flip_Diagonal}

	tile = Tile {
		guid = guid,
		orientation = orientation,
	}

	return
}

tilemap_obj_type_from_string :: proc(s: string) -> Tilemap_Object_Type {
	switch s {
	case TILEMAP_OBJ_TYPE_MARKER: return Tilemap_Object_Type.Marker
	case TILEMAP_OBJTYPE_FUNC   : return .Func
	case: 
		log.warnf("Tilemap object type '%s' unknown", s)
		return Tilemap_Object_Type.Other
	}
}

parse_layer_from_csv :: proc(csv_str: string, width, height: uint) -> (data: []Tile, err: bool = false) {
	data = make([]Tile, width * height);
	index: int = 0;
	prev: int = 0;
	sv: string;
	x, y: uint;
	for r, i in csv_str {
		sv = csv_str[prev:i];
		if r == ',' {
			ok: bool;
			tiled_data: uint
			tiled_data, ok = strconv.parse_uint(sv)
			data[index] = tiled_data_to_tile(tiled_data)
			if !ok {
				fmt.printfln("Could not parse uint from %q (%i to %i)", sv, prev, i);
				return;
			}
			prev = i + 1
			index += 1;
			x += 1;
		}
		if r == '\n' {
			if x != width {
				fmt.printfln("ERROR: While loading tilemap, got width %d when parsing, expected %d from tilemap definition.", x, width);
				return nil, false;
			}
			x = 0;
			y += 1;
			prev = i + 1;
			continue;
		}
	}
	ok: bool;
	sv = csv_str[prev:];
	tiled_data: uint
	tiled_data, ok = strconv.parse_uint(sv);
	if !ok {
		fmt.printfln("Could not parse uint from %q (%i to end)", sv, prev);
		return;
	}
	data[index] = tiled_data_to_tile(tiled_data)
	if y != height-1 {
		fmt.printfln("ERROR: While loading tilemap, got height %d when parsing, expected %d from tilemap definition.", y, height-1);
		return nil, false;
	}
	return data, true;
}