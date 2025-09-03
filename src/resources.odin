package main;
import rl "thirdparty/raylib";
import "tiled";
import "core:strings";
import "core:log";
import "core:fmt";
import vmem "core:mem/virtual"

import rdr "rendering"

ASSETS_PATH :: "./assets";

Texture_Id 		:: rdr.Texture_Id
TEXTURE_INVALID :: rdr.TEXTURE_INVALID

Tilemap_Id :: distinct int
TILEMAP_INVALID :: Tilemap_Id(-1)

Resources :: struct #no_copy {
	textures: [dynamic]rl.Texture2D,
	tilemaps: [dynamic]Tilemap,
}

initialise_resources :: proc() {
	resources.textures = make([dynamic]rl.Texture2D, len=0, cap=10);
	resources.tilemaps = make([dynamic]Tilemap, len=0, cap=10);
}

free_resources :: proc() {
	delete(resources.textures);
	// TODO: check if the xml library requires unloading
	for &tilemap in resources.tilemaps do tiled.free_tilemap(&tilemap)
	delete(resources.tilemaps);
}

tilemap :: proc(id: Tilemap_Id) -> (^Tilemap, bool) #optional_ok {
	if id == TILEMAP_INVALID do return nil, false

	return &resources.tilemaps[int(id)], true
}

texture :: proc(id: Texture_Id) -> (^rl.Texture2D, bool) #optional_ok {
	if id == TEXTURE_INVALID do return nil, false

	return &resources.textures[int(id)], true
}

load_texture :: proc(path: string) -> (Texture_Id, bool) {
	fullpath := fmt.tprintf("%s/%s", ASSETS_PATH, path);
	cpath := strings.clone_to_cstring(fullpath);
	tex := rl.LoadTexture(cpath);
	success := rl.IsTextureValid(tex);
	index := len(resources.textures);
	if success {
		append(&resources.textures, tex);
	}
	return Texture_Id(index), success;
}

load_tilemap :: proc(path: string) -> (id: Tilemap_Id = TILEMAP_INVALID, err: bool = true) {
	fullpath := fmt.tprintf("%s/%s", ASSETS_PATH, path);
	tilemap := tiled.parse_tilemap(fullpath, path_prefix = ASSETS_PATH) or_return;
	
	alloc := vmem.arena_allocator(&tilemap.arena)
	textures := make_slice([]Texture_Id, len(tilemap.tilesets), allocator = alloc)

	for tileset, i in tilemap.tilesets {
		texture_id, ok := load_texture(tileset.source);
		if !ok {
			log.errorf("Failed to load tileset source image texture for tilemap '%s', tileset source: '%s'", path, tileset.source)
			continue
		}
		textures[i] = texture_id
	}
	tmap := Tilemap { tilemap = tilemap, textures = textures };

	// TODO: generate raylib RenderTexture to avoid redrawing tile by tile for 
	// static layers

	id = Tilemap_Id(len(resources.tilemaps));
	append(&resources.tilemaps, tmap);

	return;
}