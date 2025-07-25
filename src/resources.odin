package main;
import rl "thirdparty/raylib";
import "tiled";
import "core:strings";
import "core:fmt";

ASSETS_PATH :: "./assets";

Texture_Id :: distinct int;

Resources :: struct #no_copy {
	textures: [dynamic]rl.Texture2D,
	tilemaps: [dynamic]Tilemap,
}

initialise_resources :: proc() {
	resources.textures = make([dynamic]rl.Texture2D, 10);
	resources.tilemaps = make([dynamic]Tilemap, 10);
}

free_resources :: proc() {
	delete(resources.textures);
	// TODO: check if the xml library requires unloading
	delete(resources.tilemaps);
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

load_tilemap :: proc(path: string) -> (index: int, err: bool = true) {
	fullpath := fmt.tprintf("%s/%s", ASSETS_PATH, path);
	tilemap := tiled.parse_tilemap(fullpath, path_prefix = ASSETS_PATH) or_return;
	
	texture_id := load_texture(tilemap.tileset.source) or_return;

	index = len(resources.tilemaps);
	append(&resources.tilemaps, Tilemap { tilemap = tilemap, texture_id = texture_id });

	return;
}