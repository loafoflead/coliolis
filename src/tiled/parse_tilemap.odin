package tiled;

// helpful stuff: https://forum.odin-lang.org/t/need-some-help-understanding-how-to-utilize-core-encoding-xml/1130/2
// https://discourse.mapeditor.org/t/tiled-csv-format-has-exceptionally-large-tile-values-solved/4765

import xml "core:encoding/xml";
import "core:strconv";
import "core:os";
import "core:fmt";

TILEMAP_MAX_LAYERS :: 10
TILEMAP_MAX_OBJECT_GROUPS :: 10
TILEMAP_MAX_OBJECTS_PER_GROUP :: 10

Tilemap :: struct {
	// TODO: make possible to have multiple
	tileset: Tileset,
	version: string,
	width, height: uint,
	tilewidth, tileheight: uint,
	layers: [dynamic]Tilemap_Layer,
	object_groups: [dynamic]Object_Group,
}

Object_Group :: struct {
	name: string,
	id: uint,
	objects: [dynamic]Tilemap_Object,
}

Object_Class :: enum {
	Other = 0,
	Point,
}

Tilemap_Object :: struct {
	name: string,
	id: uint,
	type: string,
	class: Object_Class,
	pos: [2]f32,
	properties: map[string]string,
}

Tilemap_Layer :: struct {
	name: string,
	id: uint,
	width, height: uint,
	data: []Tile,
	properties: map[string]string,
}

Tile 	   :: distinct uint

free_tilemap :: proc(tilemap: Tilemap) {
	for layer in tilemap.layers do delete(layer.data)
	delete(tilemap.layers)
	for group in tilemap.object_groups {
		for obj in group.objects do delete(obj.properties)
		delete(group.objects)
	}
	delete(tilemap.object_groups)
}

tile_from_id :: proc(id: uint) -> Tile {
	return Tile(id)
}

find_layers_with_property :: proc(tilemap: ^Tilemap, property, value: string) -> (layers: [dynamic]^Tilemap_Layer, found: bool) {
	layers = make([dynamic]^Tilemap_Layer)
	for &layer, i in tilemap.layers {
		if property in layer.properties {
			if layer.properties[property] == value {
				append(&layers, &layer)
				found = true
			}
		}
	}

	return
}

parse_tilemap :: proc(path: string, path_prefix: string = "", parse_tileset_automatically: bool = true, check_tileset_valid: bool = true) -> (_t: Tilemap, err: bool) {
	// TODO: how to free?
	doc, oopsie := xml.load_from_file(path);
	if oopsie != nil {
		fmt.printfln("ERROR: Tilemap `{}` not found in {}", path, os.get_current_directory());
		return Tilemap{}, false;
	}

	infinite := xml.find_attribute_val_by_key(doc, 0, "infinite") or_return;
	if infinite != "0" {
		fmt.println("ERROR: `infinite` is expected to be \"0\", not `",infinite,"`");
		return Tilemap{}, false;
	}
	orientation := xml.find_attribute_val_by_key(doc, 0, "orientation") or_return;
	if orientation != "orthogonal" {
		fmt.println("ERROR: `orientation` is expected to be \"orthogonal\", not `",orientation,"`");
		return Tilemap{}, false;
	}
	renderorder := xml.find_attribute_val_by_key(doc, 0, "renderorder") or_return;
	if renderorder != "right-down" {
		fmt.println("WARNING: Render order is expected to be `right-down`, other values aren't taking into account.");
	}

	tilemap: Tilemap;
	tilemap.version = xml.find_attribute_val_by_key(doc, 0, "version") or_return;
	if tilemap.version != EXPECTED_VERSION {
		fmt.printfln("WARNING: expected version `{}`, GOT `{}`, certain things might not work right.", EXPECTED_VERSION, tilemap.version);
	}
	tilemap.width = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "width") or_return) or_return;
	tilemap.height = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "height") or_return) or_return;
	tilemap.tilewidth = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tilewidth") or_return) or_return;
	tilemap.tileheight = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tileheight") or_return) or_return;

	tileset_id := xml.find_child_by_ident(doc, 0, "tileset") or_return;
	if parse_tileset_automatically {
		tileset_source := fmt.tprintf("%s/%s", path_prefix, xml.find_attribute_val_by_key(doc, tileset_id, "source") or_return);
		if !os.exists(tileset_source) {
			fmt.printfln(
				"ERROR: Tileset `{}` required by tilemap `{}` could not be found in `{}`. The tilemap source field must point to a valid tileset, or you can set the tileset yourself.",
				tileset_source,
				path,
				fmt.tprintf("%s/%s", path_prefix, os.get_current_directory()),
			);
			return Tilemap{}, false;
		}
		else {
			tilemap.tileset = parse_tileset(tileset_source) or_return;
			if check_tileset_valid {
				if !os.exists(tilemap.tileset.source) {
					fmt.printfln(
						"WARNING: tileset `{}` points to a path ({}) that can't be reached from `{}`, you may need to set it yourself, or be careful to properly place the source image relative to the executable.",
						tilemap.tileset.name,
						tilemap.tileset.source,
						fmt.tprintf("%s/%s", path_prefix, os.get_current_directory()),
					)
				}
			}
		}
	}

	layers := make([dynamic]Tilemap_Layer);

	for i in 0..=TILEMAP_MAX_LAYERS {
		layer_xml_id := xml.find_child_by_ident(doc, 0, "layer", i) or_break;
		layer: Tilemap_Layer;
		layer.id 	 = strconv.parse_uint(xml.find_attribute_val_by_key(doc, layer_xml_id, "id") or_return) or_return;
		layer.width  = strconv.parse_uint(xml.find_attribute_val_by_key(doc, layer_xml_id, "width") or_return) or_return;
		layer.height = strconv.parse_uint(xml.find_attribute_val_by_key(doc, layer_xml_id, "height") or_return) or_return;
		layer.name 	 = xml.find_attribute_val_by_key(doc, layer_xml_id, "name") or_return;

		data_xml_id := xml.find_child_by_ident(doc, layer_xml_id, "data") or_return;
		format := xml.find_attribute_val_by_key(doc, data_xml_id, "encoding") or_return;
		if format != "csv" {
			fmt.printfln("Cannot parse tile layer definitions in format '%v', only 'csv'.", format);
			return Tilemap{}, false;
		}
		string_data := doc.elements[data_xml_id].value[0]; // TODO: brutal assertion here
		layer.data = parse_layer_from_csv(string_data.(string), layer.width, layer.height) or_return;

		props_id, found_props := xml.find_child_by_ident(doc, layer_xml_id, "properties")
		if !found_props {
			append(&layers, layer);
			continue
		}

		layer.properties = make(map[string]string)

		prop_idx: int
		for {
			prop_id := xml.find_child_by_ident(doc, props_id, "property", prop_idx) or_break

			prop_name := xml.find_attribute_val_by_key(doc, prop_id, "name") or_break
			prop_value := xml.find_attribute_val_by_key(doc, prop_id, "value") or_break
			layer.properties[prop_name] = prop_value
			prop_idx += 1
		}

		append(&layers, layer);
	}

	object_groups := make([dynamic]Object_Group);

	for i in 0..=TILEMAP_MAX_OBJECT_GROUPS {
		group_xml_id := xml.find_child_by_ident(doc, 0, "objectgroup", i) or_break;
		group: Object_Group;
		group.id 	 = strconv.parse_uint(xml.find_attribute_val_by_key(doc, group_xml_id, "id") or_return) or_return;
		group.name 	 = xml.find_attribute_val_by_key(doc, group_xml_id, "name") or_return;

		group.objects = make([dynamic]Tilemap_Object);

		for j in 0..=TILEMAP_MAX_OBJECTS_PER_GROUP {
			object: Tilemap_Object
			obj_xml_id := xml.find_child_by_ident(doc, group_xml_id, "object", j) or_break

			object.id = strconv.parse_uint(xml.find_attribute_val_by_key(doc, obj_xml_id, "id") or_return) or_return
			object.pos.x = strconv.parse_f32(xml.find_attribute_val_by_key(doc, obj_xml_id, "x") or_return) or_return
			object.pos.y = strconv.parse_f32(xml.find_attribute_val_by_key(doc, obj_xml_id, "y") or_return) or_return
			object.name = xml.find_attribute_val_by_key(doc, obj_xml_id, "name") or_return
			object.type = xml.find_attribute_val_by_key(doc, obj_xml_id, "type") or_return

			_, is_point := xml.find_child_by_ident(doc, obj_xml_id, "point")
			if is_point do object.class = .Point
			else do object.class = .Other

			props_id, found_props := xml.find_child_by_ident(doc, obj_xml_id, "properties")
			if !found_props {
				append(&group.objects, object)
				continue
			}

			object.properties = make(map[string]string)

			prop_idx: int
			for {
				prop_id := xml.find_child_by_ident(doc, props_id, "property", prop_idx) or_break

				prop_name := xml.find_attribute_val_by_key(doc, prop_id, "name") or_break
				prop_value := xml.find_attribute_val_by_key(doc, prop_id, "value") or_break
				object.properties[prop_name] = prop_value
				prop_idx += 1
			}

			append(&group.objects, object)
		}

		append(&object_groups, group)
	}

	// layer_def := xml.find_attribute_val_by_key(doc, 0, "renderorder") or_return;

	tilemap.layers = layers
	tilemap.object_groups = object_groups

	return tilemap, true;
}

// https://discourse.mapeditor.org/t/tiled-csv-format-has-exceptionally-large-tile-values-solved/4765
tiled_data_to_tile :: proc(data: uint) -> (tile: Tile) {
	horizontal_flip := data & 0x80000000
	vertical_flip := data & 0x40000000
	diagonal_flip := data & 0x20000000
	tile = tile_from_id(data & ~(uint(0x80000000) | uint(0x40000000) | uint(0x20000000))) //clear the flags

	return
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