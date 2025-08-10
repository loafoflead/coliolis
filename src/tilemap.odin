package main;
import rl "thirdparty/raylib";
import "tiled";

import "core:strings"
import "core:fmt"
import "core:log"

GENERATE_STATIC_COLLISION 	:: "static_collision"
GENERATE_KILL_TRIGGER 		:: "hurt_box"

PROP_MARKER_TYPE :: "type"

MARKER_PLAYER_SPAWN :: "player_spawn"
MARKER_LEVEL_EXIT :: "level_exit"

Tilemap :: struct {
	using tilemap: tiled.Tilemap,
	texture_id: Texture_Id,
	render_texture: rl.RenderTexture2D,
}


level_features_from_tilemap :: proc(id: Tilemap_Id) -> (features: Level_Features, any_found: bool) {
	tm := tilemap(id)

	for object in tm.objects {
		if object.type == .Marker {
			type, ok := object.properties[PROP_MARKER_TYPE]
			if !ok {
				log.errorf("Marker object has no type field, it cannot be used. Object: %v", object)
				continue
			} 
			switch type {
			case "player_spawn"	: features.player_spawn = object.pos - Vec2{cast(f32)tm.tilewidth, cast(f32)tm.tileheight}
			case "level_exit"	: features.level_exit = object.pos - Vec2{cast(f32)tm.tilewidth, cast(f32)tm.tileheight}
			case "cam_focus_point"	: log.warn("TODO: marker camera_focus")
			case:
				log.warnf("Unknown marker type '%s'", type)
				continue
			}
			any_found = true
		}
	}

	return
}

generate_static_physics_for_tilemap :: proc(id: Tilemap_Id) {
	tileset := tilemap(id).tileset;
	layers, found := tiled.find_layers_with_property(tilemap(id), "generate", GENERATE_STATIC_COLLISION)
	if !found {
		fmt.eprintln("No layer was found with the generate:\"static_collision\" property, no collision was generated")
		return
	}
	for layer in layers {
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
}

generate_kill_triggers_for_tilemap :: proc(id: Tilemap_Id) {
	tileset := tilemap(id).tileset;
	layers, found := tiled.find_layers_with_property(tilemap(id), "generate", GENERATE_KILL_TRIGGER)
	if !found {
		fmt.eprintln("No layer was found with the generate:\"hurt\" property, no kill triggers were generated")
		return
	}
	for layer in layers {
		for y in 0..<layer.height {
			for x in 0..<layer.width {
				tile := layer.data[y * layer.width + x];
				// NOTE: zero seems to mean nothing, so all offsets have one added to them
				if tile == 0 do continue;

				pos := Vec2 { cast(f32) (x * tileset.tilewidth), cast(f32) (y * tileset.tileheight) };

				pid := add_phys_object_aabb(
					pos = pos, 
					scale = Vec2 { 
						cast(f32) tileset.tilewidth, 
						cast(f32) tileset.tileheight 
					},
					flags = {.Non_Kinematic, .No_Gravity, .Fixed, .Trigger},
				);
				obj_trigger_new(.Kill, pid)
			}
		}
	}
}

generate_texture_for_tilemap :: proc(tilemap: ^Tilemap) -> bool {
	unimplemented();
}

draw_tilemap :: proc(id: Tilemap_Id, pos: Vec2) {
	// TODO: blit the entire tilemap into a texture and draw that instead of doing this every frame
	tm := tilemap(id)
	src_idx := tm.texture_id;
	tileset := tm.tileset;
	for layer in tm.layers {
		if "no_render" in layer.properties do continue

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
}
