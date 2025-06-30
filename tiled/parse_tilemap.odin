package tiled;

import xml "core:encoding/xml";
import "core:strconv";
import "core:os";
import "core:fmt";

Tilemap :: struct {
	// TODO: make possible to have multiple
	tileset: Tileset,
	version: string,
	width, height: uint,
	tilewidth, tileheight: uint,
}

Tilemap_Layer :: struct {
	name: string,
	id: uint,
	width, height: uint,
}

parse_tilemap :: proc(path: string, parse_tileset_automatically: bool = true, check_tileset_valid: bool = true) -> (_t: Tilemap, err: bool) {
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
		tileset_source := xml.find_attribute_val_by_key(doc, tileset_id, "source") or_return;
		if !os.exists(tileset_source) {
			fmt.printfln(
				"ERROR: Tileset `{}` required by tilemap `{}` could not be found in `{}`. The tilemap source field must point to a valid tileset, or you can set the tileset yourself.",
				tileset_source,
				path,
				os.get_current_directory(),
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
						os.get_current_directory(),
					)
				}
			}
		}
	}

	return tilemap, true;
}