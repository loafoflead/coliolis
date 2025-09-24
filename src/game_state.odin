package main

import b2d "thirdparty/box2d"

import "core:log"
import "core:container/queue"
import "core:math/ease"

// import vmem "core:mem/virtual"

import "rendering"

Camera2D :: rendering.Camera2D


Level_Features :: struct {
	player_spawn, player_spawn_facing: Vec2,
	level_exit: Vec2,
	next_level: string,

	tilemap: Tilemap_Id,

	// TODO: arena plz i love the buggers
	// arena: vmem.Arena,
}

Game_Object_On_Collide_Function :: #type proc(self, other: Game_Object_Id, self_phys, other_phys: ^Physics_Object)
Game_Object_On_Update_Function  :: #type proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool)
Game_Object_Render_Function     :: #type proc(self: Game_Object_Id, camera: rendering.Camera2D)
Game_Object_Event_Recv_Function :: #type proc(self: Game_Object_Id, event: ^Game_Event)
Game_Object_Killed_Callback     :: #type proc(self: Game_Object_Id)

GAMESTATE_MESSAGES_PER_FRAME 	:: 16
GAMESTATE_EVENTS_PER_FRAME 		:: 16
GAMEOBJS_DELETED_PER_FRAME 		:: 16

Game_State :: struct {
	initialised: bool,
	objects: [dynamic]Game_Object,
	to_delete: queue.Queue(Game_Object_Id),

	player: Game_Object_Id,
	current_level: Maybe(Level_Features),

	messages: queue.Queue(Game_Object_Message),
	events: queue.Queue(Game_Event),
	event_subscribers: [dynamic]Game_Object_Id,
}

Game_Object_Type :: union{Cube_Spawner, G_Trigger, Player, Portal_Fixture, Cube_Button, Sliding_Door, Cube}

Game_Object_Flags :: enum {
	Weigh_Down_Buttons,
	Portal_Traveller,
	Weak_To_Being_Vaporised,

	Dead,
}

Game_Object_Flagset :: bit_set[Game_Object_Flags; u32]

@interface
Game_Object :: struct {
	on_update: Game_Object_On_Update_Function,
	on_render: Game_Object_Render_Function,
	on_event: Game_Object_Event_Recv_Function,
	on_killed: Game_Object_Killed_Callback,

	flags: Game_Object_Flagset,

	// Add here any new game object types
	data: Game_Object_Type,
	obj: Maybe(Physics_Object_Id),
}

initialise_game_state :: proc() {
	game_state.objects = make([dynamic]Game_Object)
	queue.init(&game_state.messages)
	// for ty in Game_Event_Category {
	queue.init(&game_state.events)
	// }
	game_state.initialised = true
}

free_game_state :: proc() {
	delete(game_state.objects)
	queue.destroy(&game_state.messages)
	queue.destroy(&game_state.events)
}

game_load_level_from_tilemap :: proc(path: string) {
	tmap, tmap_ok := load_tilemap(path);
	if !tmap_ok {
		log.error("Failed to load game level from tilemap", path)
		return
	}

	reinit_phys_world()

	clear(&game_state.objects)
	queue.clear(&game_state.events)
	queue.clear(&game_state.messages)
	clear(&game_state.event_subscribers)
	game_state.player = 0
	initialise_portal_handler()

	create_named_timer("game.level_loaded", 0.25, flags = {.Update_Automatically})
	reset_timer("game.level_loaded")

	// fmt.printfln("%#v", tilemap(test_map))
	generate_static_physics_for_tilemap(tmap)
	generate_kill_triggers_for_tilemap(tmap)
	lvl, any_found := level_features_from_tilemap(tmap)

	if !any_found {
		log.error("Failed to load level features from tilemap", path)
	}

	lvl.tilemap = tmap
	game_state.current_level = lvl

	player_gobj_id := obj_player_new(dir_tex)
	player_goto(state_get_player_spawn())
	// phys_obj_goto(player.obj, state_get_player_spawn())
	game_state.player = player_gobj_id

	game_init_level()
}

game_init_level :: proc() {
	assert(game_state.initialised && game_state.current_level != nil)

	log.info(game_state.current_level)

	obj_trigger_new_from_ty(.Level_Exit)
}

state_get_player_spawn :: proc() -> (point: Vec2 = 0, loaded: bool = false) #optional_ok {
	assert(game_state.initialised)

	if lvl, ok := game_state.current_level.?; ok == true {
		point = lvl.player_spawn + lvl.player_spawn_facing * PLAYER_HEIGHT * 1.5
		loaded = true
	}
	return
}

state_level :: proc() -> ^Level_Features {
	assert(game_state.initialised)
	if lvl, ok := &game_state.current_level.?; ok == true {
		return lvl
	}

	return nil
}

state_player :: proc() -> ^Player {
	assert(game_state.initialised)

	return game_obj(game_state.player, Player)
}

get_game_obj :: proc "contextless" (id: Game_Object_Id) -> (^Game_Object, bool) #optional_ok {
	if id == GAME_OBJECT_INVALID || int(id) >= len(game_state.objects) do return nil, false

	return &game_state.objects[int(id)], true
}

get_game_obj_data :: proc "contextless" (id: Game_Object_Id, $T: typeid) -> (^T, bool) #optional_ok {
	if id == GAME_OBJECT_INVALID || int(id) >= len(game_state.objects) do return nil, false

	ret, valid := &game_state.objects[int(id)].data.(T)
	if !valid do return nil, false
	else do return ret, true
}

game_obj :: proc{get_game_obj, get_game_obj_data}

@(private)
pair_physics :: proc(gobj: Game_Object_Id, phobj: Physics_Object_Id) {
	game_obj(gobj).obj = phobj
	phys_obj_data(phobj).game_object = gobj
}

queue_remove_game_obj :: proc(id: Game_Object_Id) {
	queue.push_front(&game_state.to_delete, id)
}

update_game_state :: proc(dt: f32) {
	to_delete := make([dynamic]int)
	for obj, i in game_state.objects {
		should_delete := false
		if .Dead in obj.flags do continue
		if obj.on_update != nil do should_delete = (obj.on_update)(Game_Object_Id(i), dt)
		if should_delete do append(&to_delete, i)
	}

	for _ in 0..<GAMESTATE_MESSAGES_PER_FRAME {
		message := queue.pop_back_safe(&game_state.messages) or_break

		inform_game_object(message.gobj, message.payload)
	}

	for _ in 0..<GAMESTATE_EVENTS_PER_FRAME {
		event := queue.pop_back_safe(&game_state.events) or_break

		for id in game_state.event_subscribers {
			gobj := game_obj(id)
			if .Dead in gobj.flags do continue
			if gobj.on_event != nil do (gobj.on_event)(id, &event)
		}

		#partial switch value in event.payload {
		case Level_Event:
			#partial switch value {
			case .End:
				if state_level().next_level != "" {
					game_load_level_from_tilemap(state_level().next_level)
					return
				}
			}
		}
	}

	for _ in 0..<GAMEOBJS_DELETED_PER_FRAME {
		id := queue.pop_back_safe(&game_state.to_delete) or_break

		if .Dead in game_obj(id).flags do log.warn("tried to doubly kill a gobj")
		append(&to_delete, int(id))
	}

	if is_timer_just_done("game.level_loaded") {
		send_game_event(Game_Event {
			name = "level_load",
			payload = Level_Event.Load,
		})
	}

	#reverse for idx in to_delete {
		obj := game_state.objects[idx]
		if obj.on_killed != nil do (obj.on_killed)(Game_Object_Id(idx))
		// moves the last elem to this pos,
		// so reverse means this should always be good
		obj.flags += {.Dead}
		if phobj, ok := obj.obj.?; ok {
			b2d.Body_Disable(phobj)
		}
		// unordered_remove(&game_state.objects, idx)
	}
}

game_obj_col_enter :: proc(gobj_id, other_gobj: Game_Object_Id, obj, other_obj: Physics_Object_Id) {
	log.error("deprecated: game_obj_col_enter")
	// if gobj.on_collide_enter != nil do (gobj.on_collide_enter)(gobj_id, other_gobj, phys_obj(obj), phys_obj(other_obj))
}

game_obj_col_exit :: proc(gobj_id, other_gobj: Game_Object_Id, obj, other_obj: Physics_Object_Id) {
	log.error("deprecated: game_obj_col_enter")
	// if gobj.on_collide_exit != nil do (gobj.on_collide_exit)(gobj_id, other_gobj, phys_obj(obj), phys_obj(other_obj))
}


render_game_objects :: proc(camera: rendering.Camera2D) {
	for obj, i in game_state.objects {
		if .Dead in obj.flags do continue
		if obj.on_render != nil do (obj.on_render)(Game_Object_Id(i), camera)
	}
}


Game_Object_Id :: distinct int
GAME_OBJECT_INVALID :: Game_Object_Id(-1)


// Condition_Type :: enum {
// 	Always_Active,
// 	On_Event,
// }

Condition :: struct {
	type: string,
	channel: string,
	event: string,
	override: bool,
	run_once: bool,
}

condition_true :: proc(cond: Condition) -> (ret: bool) {
	if cond.override do ret = true

	switch cond.type {
	case "always":
		ret = true
	case "event":
		unimplemented()
	}
	return
}
