package main;
import rl "thirdparty/raylib";

import "core:log"
import "core:strings"

import "core:encoding/json"
import vmem "core:mem/virtual"

import "tiled"
import "transform"
import "rendering"

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
	event_name: string,
}



facing_from_json :: proc(json_value: json.Value) -> Vec2 {
	log.info(json_value)
	obj, ok := json_value.(json.Object)
	if !ok do return Vec2(0)
	return Vec2 {
		cast(f32) (obj["x"].(i64) or_else 0),
		cast(f32) (obj["y"].(i64) or_else 0),
	}
}

// condition_from_json :: proc(json_obj: json.Object) -> (Condition, bool) {
// 	condition_json: Condition_Json
// 	json_err := json.unmarshal_string(json_obj["activated_when"].(string) or_else "{}", &condition_json, allocator = context.temp_allocator)
// 	if json_err != nil {
// 		log.errorf("Failed to parse json string for condition, error: %v", json_err)
// 		return {}, false
// 	}

// 	type: Condition_Type
// 	// TODO: whose memory is this...?
// 	event_name: string

// 	switch condition_json.type {
// 	case "always":
// 		type = .Always_Active
// 	case "event":
// 		type = .On_Event
// 		event_name = json_obj["event"].(string) or_else ""
// 	case:
// 		log.errorf("Unknown condition type '%s'", condition_json.type)
// 		return {}, false
// 	}

// 	return Condition {
// 		type = type,
// 		event_name = event_name,
// 	}, true
// }

level_features_from_tilemap :: proc(id: Tilemap_Id) -> (features: Level_Features, any_found: bool) {
	tm := tilemap(id)

	OBJECTS: for &object in tm.objects {
		pos := object.pos - Vec2(32/2)
		// object.pos = rl_to_b2d_pos(object.pos)
		if object.type == .Func {
			func_class: string
			func_data: string
			PROPS: for name, prop in object.properties {
				switch name {
					case "func":
						#partial switch value in prop {
							case string:
								func_class = value
							case tiled.Tilemap_Enum:
								func_class = value.value
							case tiled.Tilemap_Class:
								func_class = value.classname
						}
						continue PROPS
					case "func_data":
						#partial switch value in prop {
							case string:
								func_data = value
							case:
								log.warnf("func_data must be a Json string, not a %v", prop)
								continue OBJECTS
						}
					case:
						log.warnf("Property '%s' of Tiled object with value (%v) will be ignored.", name, prop)
						continue OBJECTS
				}
			}

			func_class = strings.to_lower(func_class, allocator=context.temp_allocator)

			arena := vmem.arena_allocator(&tm.arena)
			err : json.Unmarshal_Error

			switch func_class {
				case "entry_chute":
					features.player_spawn = pos
					features.player_spawn_facing = transform.angle_to_dir(object.rot)
				case "exit_chute", "level_exit", "exit":
					features.level_exit = pos
					features.next_level = func_data
				case "portal_frame", "portal_fixture":
					frame: Portal_Fixture
					err = json.unmarshal_string(func_data, &frame, allocator = arena)
					frame.pos, frame.dims, frame.facing = pos, object.dims, transform.angle_to_dir(object.rot)
					obj_prtl_frame_new(frame)
				case "cube_button":
					btn: Cube_Button
					err = json.unmarshal_string(func_data, &btn, allocator = arena)
					btn.pos, btn.dims, btn.facing = pos, object.dims, transform.angle_to_dir(object.rot)
					obj_cube_btn_new(btn)
				case "cube_spawner":
					spwnr: Cube_Spawner
					err = json.unmarshal_string(func_data, &spwnr, allocator = arena)
					spwnr.pos, spwnr.dims, spwnr.facing = pos, object.dims, transform.angle_to_dir(object.rot)
					obj_cube_spawner_new(spwnr)
				case "sliding_door":
					door : Sliding_Door
					err = json.unmarshal_string(func_data, &door, allocator = arena)
					door.pos = pos + object.dims/2
					door.dims, door.facing = object.dims, transform.angle_to_dir(object.rot)
					obj_sliding_door_new(door)
				case "trigger":
					trigger : G_Trigger
					err = json.unmarshal_string(func_data, &trigger, allocator = arena)
					trigger.pos = pos + object.dims/2
					trigger.dims = object.dims
					obj_trigger_new(trigger)
				case:
					log.warnf("Unknown object class '%s'", func_class)
					continue
			}
			if err != nil do log.panicf("Failed to unmarshal json data for object (impossible) from data '%s'", func_data)
		}
	}

	return
}

generate_static_physics_for_tilemap :: proc(id: Tilemap_Id) {
	tm := tilemap(id)
	layers, found := tiled.find_layers_with_property(tilemap(id), "generate", GENERATE_STATIC_COLLISION)
	if !found {
		log.warn("No layer was found with the generate:\"static_collision\" property, no collision was generated")
	}
	else {
		for layer in layers {
			for y in 0..<layer.height {
				for x in 0..<layer.width {
					tile := layer.data[y * layer.width + x]
					// NOTE: zero seems to mean nothing, so all offsets have one added to them
					if tile.guid == 0 do continue;

					tileset, _ := tiled.get_tile_tileset(tilemap(id), tile);

					pos := Vec2 { cast(f32) (x * tileset.tilewidth), cast(f32) (y * tileset.tileheight) };

					add_phys_object_aabb(
						pos = pos, 
						mass = 0,
						scale = Vec2 {
							cast(f32) tileset.tilewidth, 
							cast(f32) tileset.tileheight, 
						},
						flags = {.Non_Kinematic, .Fixed},
						collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS + {.Portal_Surface},
					);
				}
			}
		}
	}
	for &object in tm.objects {
		pos := object.pos - Vec2(32/2)
		// object.pos = rl_to_b2d_pos(object.pos)
		for _, prop in object.properties {
			#partial switch data in prop {
			case tiled.Tilemap_Enum:
				if data.value == "Static_Collision" {
					if object.dims == 0 && len(object.vertices) != 0 {
						add_phys_object_polygon(
							pos = pos + object.dims / 2, 
							vertices = object.vertices,
							flags = {.Non_Kinematic, .Fixed},
							collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS + {.Portal_Surface},
							name = "tilemap_static_poly",
						);
					}
					else {
						add_phys_object_aabb(
							pos = pos + object.dims / 2, 
							scale = object.dims,
							flags = {.Non_Kinematic, .Fixed},
							collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS + {.Portal_Surface},
							name = "tilemap_static_rect",
						);
					}
				}
			}
		}
		// if "gen" in object.properties {
		// 	log.info(object.properties["gen"])
		// 	prop, ok := object.properties["gen"].(tiled.Tilemap_Enum)
		// 	if !ok do continue
		// 	if prop.value == "Static_Collision" {
				
		// 	}
		// }
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
				if tile.guid == 0 do continue;

				tileset, _ := tiled.get_tile_tileset(tilemap(id), tile)

				pos := Vec2 { cast(f32) (x * tileset.tilewidth), cast(f32) (y * tileset.tileheight) };

				pid := add_phys_object_aabb(
					pos = pos, 
					scale = Vec2 { 
						cast(f32) tileset.tilewidth, 
						cast(f32) tileset.tileheight ,
					},
					flags = {.Non_Kinematic, .No_Gravity, .Fixed, .Trigger},
				);
				obj_trigger_new_from_ty(.Kill, pid)
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
				if tile.guid == 0 do continue;

				tileset, idx := tiled.get_tile_tileset(tilemap(id), tile)
				src_idx := tm.textures[idx]
				tile_id := tile.guid

				// tile_id -= 1
				tile_id -= tileset.firstgid
				// tile_id -= uint(idx);

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
				rendering.draw_texture(src_idx, tile_pos, drawn_portion = drawn_portion, pixel_scale = Vec2{cast(f32)tileset.tilewidth, cast(f32)tileset.tileheight});
			}
		}
	}
}
