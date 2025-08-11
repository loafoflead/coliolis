package tiled;

import xml "core:encoding/xml";
import "core:strconv";

import "core:log";
import "core:os";

Tileset :: struct {
	name: string,
	version: string,
	tilewidth, tileheight: uint,
	tilecount, columns: uint,
	width, height: uint,
	source: string,
	firstgid: uint,
}

parse_tileset :: proc(path: string) -> (t: Tileset, err: bool) {
	doc, ok := xml.load_from_file(path);
	if ok != nil {
		log.errorf("Tileset `%s` not found in %s", path, os.get_current_directory());
		return Tileset{}, false;
	}

	tileset: Tileset;
	tileset.name = xml.find_attribute_val_by_key(doc, 0, "name") or_return;
	tileset.version = xml.find_attribute_val_by_key(doc, 0, "version") or_return;
	if tileset.version != EXPECTED_XML_VERSION {
		log.warnf("expected version `%s`, got `%s`, certain things might not work right.", EXPECTED_XML_VERSION, tileset.version);
	}
	tileset.tileheight = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tileheight") or_return) or_return;
	tileset.tilewidth = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tilewidth") or_return) or_return;
	tileset.tilecount = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "tilecount") or_return) or_return;
	tileset.columns = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 0, "columns") or_return) or_return;

	tileset.source = xml.find_attribute_val_by_key(doc, 1, "source") or_return;
	tileset.width = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 1, "width") or_return) or_return;
	tileset.height = strconv.parse_uint(xml.find_attribute_val_by_key(doc, 1, "height") or_return) or_return;
	
	return tileset, true;
}