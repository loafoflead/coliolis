package main;
import rl "thirdparty/raylib";
import "tiled";

Tilemap :: struct {
	using tilemap: tiled.Tilemap,
	texture_id: Texture_Id,
	render_texture: rl.RenderTexture2D,
}


generate_static_physics_for_tilemap :: proc(id: Tilemap_Id, layer: int) {
	tileset := tilemap(id).tileset;
	layer := tilemap(id).layers[layer];
	for y in 0..<layer.height {
		for x in 0..<layer.width {
			tile := layer.data[y * layer.width + x];
			// NOTE: zero seems to mean nothing, so all offsets have one added to them
			if tile == 0 do continue;

			pos := Vec2 { cast(f32) (x * tileset.tilewidth), cast(f32) (y * tileset.tileheight) };

			add_phys_object_aabb(
				pos = pos, 
				mass = 0, 
				scale = Vec2 { 
					cast(f32) tileset.tilewidth, 
					cast(f32) tileset.tileheight 
				},
				flags = {.Non_Kinematic, .No_Gravity, .Fixed},
				collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS + {.Portal_Surface}
			);
		}
	}
}

generate_texture_for_tilemap :: proc(tilemap: ^Tilemap) -> bool {
	unimplemented();
}

draw_tilemap :: proc(id: Tilemap_Id, pos: Vec2) {
	// TODO: blit the entire tilemap into a texture and draw that instead of doing this every frame
	src_idx := tilemap(id).texture_id;
	tileset := tilemap(id).tileset;
	DRAWN_LAYER :: 0;
	layer := tilemap(id).layers[DRAWN_LAYER];
	for y in 0..<layer.height {
		for x in 0..<layer.width {
			tile := layer.data[y * layer.width + x]
			tile_id := uint(tile)

			// NOTE: zero seems to mean nothing, so all offsets have one added to them
			if tile_id == 0 do continue;
			tile_id -= 1;
			// TODO: figure out what these magic values mean
			if tile_id >= 1610612788 do continue; //tile == 1610612806 || tile == 1610612807 || tile == 1610612797 || tile == 1610612788 do continue;

			// the index of the tile in the source image
			tile_x := tile_id % tileset.columns;
			tile_y := (tile_id - tile_x) / (tileset.columns);

			tile_pos := pos + Vec2 {cast(f32)x, cast(f32)y} * Vec2 {cast(f32)tileset.tilewidth, cast(f32)tileset.tileheight};
			drawn_portion := Rect { 
				cast(f32)(tile_x * tileset.tilewidth),
				cast(f32)(tile_y * tileset.tileheight),
				cast(f32) tileset.tilewidth,
				cast(f32) tileset.tileheight,
			};
			draw_texture(src_idx, tile_pos, drawn_portion = drawn_portion, pixel_scale = Vec2{cast(f32)tileset.tilewidth, cast(f32)tileset.tileheight});
		}
	}
}
