package main;
import rl "thirdparty/raylib";
import "tiled";

import "core:strings"
import "core:fmt"
import "core:log"

import "core:encoding/json"

GENERATE_STATIC_COLLISION 	:: "static_collision"
GENERATE_KILL_TRIGGER 		:: "hurt_box"

PROP_CLASS :: "class"

MARKER_PLAYER_SPAWN :: "player_spawn"
MARKER_LEVEL_EXIT :: "level_exit"

Tilemap :: struct {
	using tilemap: tiled.Tilemap,
	textures: []Texture_Id,
	render_texture: rl.RenderTexture2D,
}

Condition_Json :: struct {
	type: string,
}

condition_from_json :: proc(json_string: string) -> (Condition, bool) {
	condition_json: Condition_Json
	json_err := json.unmarshal_string(json_string, &condition_json, allocator = context.temp_allocator)
	if json_err != nil {
		log.errorf("Failed to parse json string for condition, error: %v", json_err)
		return {}, false
	}

	type: Condition_Type

	switch condition_json.type {
	case "always":
		type = .Always_Active
	case "event":
		type = .On_Event
	case:
		log.errorf("Uknown condition type '%s'", condition_json.type)
		return {}, false
	}

	return Condition {
		type = type,
	}, true
}

level_features_from_tilemap :: proc(id: Tilemap_Id) -> (features: Level_Features, any_found: bool) {
	tm := tilemap(id)

	for object in tm.objects {
		if object.type == .Func {
			for name, prop in object.properties {
				#partial switch value in prop {
				case string:
					log.warnf("property '%s' with value '%s' will be ignored", name, value)
				case tiled.Tilemap_Class:
					switch value.classname {
					case "Entry_Chute"		: features.player_spawn = object.pos/* - Vec2{cast(f32)tm.tilewidth, cast(f32)tm.tileheight}*/
					case "Exit_Chute"		: features.level_exit = object.pos/* - Vec2{cast(f32)tm.tilewidth, cast(f32)tm.tileheight}*/
					case "Portal_Fixture"	: 
						append(&features.portal_fixtures, Portal_Fixture{ 
							pos = object.pos,
							facing = Vec2 {
								cast(f32) (value.json_value["facing_x"].(i64) or_else 0),
								cast(f32) (value.json_value["facing_y"].(i64) or_else 0),
							},
							portal = cast(i32) (value.json_value["portal"].(i64) or_else 0),
							active_condition = condition_from_json(value.json_value["activation_condition"].(string) or_else "{}") or_continue
						})
					case:
						log.warnf("Unknown object class '%s'", value.classname)
						continue
					}
				}
				any_found = true
			}
		}
	}

	return
}

generate_static_physics_for_tilemap :: proc(id: Tilemap_Id) {
	layers, found := tiled.find_layers_with_property(tilemap(id), "generate", GENERATE_STATIC_COLLISION)
	if !found {
		log.warn("No layer was found with the generate:\"static_collision\" property, no collision was generated")
		return
	}
	for layer in layers {
		for y in 0..<layer.height {
			for x in 0..<layer.width {
				tile := layer.data[y * layer.width + x]
				// NOTE: zero seems to mean nothing, so all offsets have one added to them
				if tile == 0 do continue;

				tileset, _ := tiled.get_tile_tileset(tilemap(id), tile);

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
	layers, found := tiled.find_layers_with_property(tilemap(id), "generate", GENERATE_KILL_TRIGGER)
	if !found {
		log.warn("No layer was found with the generate:\"hurt\" property, no kill triggers were generated")
		return
	}
	for layer in layers {
		for y in 0..<layer.height {
			for x in 0..<layer.width {
				tile := layer.data[y * layer.width + x];
				// NOTE: zero seems to mean nothing, so all offsets have one added to them
				if tile == 0 do continue;

				tileset, _ := tiled.get_tile_tileset(tilemap(id), tile)

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
	for layer in tm.layers {
		if !layer.visible do continue
		if "no_render" in layer.properties do continue

		for y in 0..<layer.height {
			for x in 0..<layer.width {
				tile := layer.data[y * layer.width + x]
				// NOTE: zero seems to mean nothing, so all offsets have one added to them
				if tile == 0 do continue;

				tileset, idx := tiled.get_tile_tileset(tilemap(id), tile)
				src_idx := tm.textures[idx]
				tile_id := uint(tile)

				tile_id -= 1;
				tile_id -= idx;
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
