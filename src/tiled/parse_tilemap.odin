package tiled;

import xml "core:encoding/xml";
import "core:strconv";
import "core:os";
import "core:fmt";

TILEMAP_MAX_LAYERS :: 10;

Tilemap :: struct {
	// TODO: make possible to have multiple
	tileset: Tileset,
	version: string,
	width, height: uint,
	tilewidth, tileheight: uint,
	layers: [dynamic]Tilemap_Layer,
}

Tilemap_Layer :: struct {
	name: string,
	id: uint,
	width, height: uint,
	data: Layer_Data,
}

Layer_Data :: distinct []uint;

parse_tilemap :: proc(path: string, path_prefix: string = "", parse_tileset_automatically: bool = true, check_tileset_valid: bool = true) -> (_t: Tilemap, err: bool) {
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

		append(&layers, layer);
	}

	// layer_def := xml.find_attribute_val_by_key(doc, 0, "renderorder") or_return;

	tilemap.layers = layers;

	return tilemap, true;
}

parse_layer_from_csv :: proc(csv_str: string, width, height: uint) -> (data: Layer_Data, err: bool = false) {
	data = make(Layer_Data, width * height);
	index: int = 0;
	prev: int = 0;
	sv: string;
	x, y: uint;
	for r, i in csv_str {
		sv = csv_str[prev:i];
		if r == ',' {
			ok: bool;
			data[index], ok = strconv.parse_uint(sv);
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
	data[index], ok = strconv.parse_uint(sv);
	if !ok {
		fmt.printfln("Could not parse uint from %q (%i to end)", sv, prev);
		return;
	}
	if y != height-1 {
		fmt.printfln("ERROR: While loading tilemap, got height %d when parsing, expected %d from tilemap definition.", y, height-1);
		return nil, false;
	}
	return data, true;
}