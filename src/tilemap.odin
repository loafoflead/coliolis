package main;
import rl "thirdparty/raylib";
import "tiled";

Tilemap :: struct {
	using tilemap: tiled.Tilemap,
	texture_id: int,
}


generate_static_physics_for_tilemap :: proc(tilemap: int, layer: int) {
	tileset := resources.tilemaps[tilemap].tileset;
	layer := resources.tilemaps[tilemap].layers[layer];
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
				flags = {.Non_Kinematic, .No_Gravity},
			);
		}
	}
}

draw_tilemap :: proc(index: int, pos: Vec2) {
	// TODO: blit the entire tilemap into a texture and draw that instead of doing this every frame
	src_idx := resources.tilemaps[index].texture_id;
	tileset := resources.tilemaps[index].tileset;
	DRAWN_LAYER :: 0;
	layer := resources.tilemaps[index].layers[DRAWN_LAYER];
	for y in 0..<layer.height {
		for x in 0..<layer.width {
			tile := layer.data[y * layer.width + x];
			// NOTE: zero seems to mean nothing, so all offsets have one added to them
			if tile == 0 do continue;
			tile -= 1;
			// TODO: figure out what these magic values mean
			if tile >= 1610612788 do continue; //tile == 1610612806 || tile == 1610612807 || tile == 1610612797 || tile == 1610612788 do continue;

			// the index of the tile in the source image
			tile_x := tile % tileset.columns;
			tile_y := (tile - tile_x) / (tileset.columns);

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