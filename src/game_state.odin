package main

import b2d "thirdparty/box2d"

import "core:log"
import "core:container/queue"
import "core:slice"
import "core:math/ease"

import vmem "core:mem/virtual"

import "tiled"

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
Game_Object_Render_Function     :: #type proc(self: Game_Object_Id, camera: Camera2D)
Game_Object_Event_Recv_Function :: #type proc(self: Game_Object_Id, event: ^Game_Event)

GAMESTATE_MESSAGES_PER_FRAME 	:: 16
GAMESTATE_EVENTS_PER_FRAME 		:: 16

Game_State :: struct {
	initialised: bool,
	objects: [dynamic]Game_Object,
	player: Game_Object_Id,
	current_level: Maybe(Level_Features),

	messages: queue.Queue(Game_Object_Message),
	events: [Game_Event_Type]queue.Queue(Game_Event),
	event_subscribers: map[Game_Object_Id]Game_Event_Set,
}

Game_Object_Type :: union{Cube_Spawner, G_Trigger, Player, Portal_Fixture, Cube_Button, Sliding_Door, Cube}

Game_Object :: struct {
	on_collide: Game_Object_On_Collide_Function,
	on_collide_enter: Game_Object_On_Collide_Function,
	on_collide_exit: Game_Object_On_Collide_Function,

	on_update: Game_Object_On_Update_Function,
	on_render: Game_Object_Render_Function,
	on_event: Game_Object_Event_Recv_Function,

	// Add here any new game object types
	data: Game_Object_Type,
	obj: Maybe(Physics_Object_Id),
}

initialise_game_state :: proc() {
	game_state.objects = make([dynamic]Game_Object)
	queue.init(&game_state.messages)
	for ty in Game_Event_Type {
		queue.init(&game_state.events[ty])
	}
	game_state.initialised = true
}

free_game_state :: proc() {
	delete(game_state.objects)
	queue.destroy(&game_state.messages)
}

game_load_level_from_tilemap :: proc(path: string) {
	tmap, tmap_ok := load_tilemap(path);
	if !tmap_ok {
		log.error("Failed to load game level from tilemap", path)
		return
	}

	reinit_phys_world()

	clear(&game_state.objects)
	initialise_portal_handler()

	// fmt.printfln("%#v", tilemap(test_map))
	generate_static_physics_for_tilemap(tmap)
	// generate_kill_triggers_for_tilemap(tmap)
	lvl, any_found := level_features_from_tilemap(tmap)

	// if !any_found {
	// 	log.error("Failed to load level features from tilemap", path)
	// 	return
	// }
	lvl.tilemap = tmap
	game_state.current_level = lvl

	player_gobj_id := obj_player_new(dir_tex)
	player := game_obj(player_gobj_id, Player)
	b2d.Body_SetTransform(player.obj, state_get_player_spawn(), {1, 0})
	game_state.player = player_gobj_id

	game_init_level()
}

game_init_level :: proc() {
	assert(game_state.initialised && game_state.current_level != nil)

	log.info(game_state.current_level)

	obj_trigger_new(.Level_Exit)
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

get_game_obj :: proc(id: Game_Object_Id) -> (^Game_Object, bool) #optional_ok {
	if id == GAME_OBJECT_INVALID || int(id) >= len(game_state.objects) do return nil, false

	return &game_state.objects[int(id)], true
}

get_game_obj_data :: proc(id: Game_Object_Id, $T: typeid) -> (^T, bool) #optional_ok {
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

update_game_state :: proc(dt: f32) {
	to_delete := make([dynamic]int)
	for obj, i in game_state.objects {
		should_delete := false
		if obj.on_update != nil do should_delete = (obj.on_update)(Game_Object_Id(i), dt)
		if should_delete do append(&to_delete, i)
	}

	for _ in 0..<GAMESTATE_MESSAGES_PER_FRAME {
		message := queue.pop_back_safe(&game_state.messages) or_break

		inform_game_object(message.gobj, message.payload)
	}

	for _ in 0..<GAMESTATE_EVENTS_PER_FRAME {
		l_event := queue.pop_back_safe(&game_state.events[.Logic]) or_break

		for id, channels in game_state.event_subscribers {
			gobj := game_obj(id)
			if .Logic in channels {
				if gobj.on_event != nil do (gobj.on_event)(id, &l_event)
			}
		}
	}

	#reverse for idx in to_delete {
		// moves the last elem to this pos,
		// so reverse means this should always be good
		unordered_remove(&game_state.objects, idx)
	}
}

game_obj_col_enter :: proc(gobj_id, other_gobj: Game_Object_Id, obj, other_obj: Physics_Object_Id) {
	gobj := game_obj(gobj_id)
	log.error("deprecated: game_obj_col_enter")
	// if gobj.on_collide_enter != nil do (gobj.on_collide_enter)(gobj_id, other_gobj, phys_obj(obj), phys_obj(other_obj))
}

game_obj_col_exit :: proc(gobj_id, other_gobj: Game_Object_Id, obj, other_obj: Physics_Object_Id) {
	gobj := game_obj(gobj_id)
	log.error("deprecated: game_obj_col_enter")
	// if gobj.on_collide_exit != nil do (gobj.on_collide_exit)(gobj_id, other_gobj, phys_obj(obj), phys_obj(other_obj))
}


render_game_objects :: proc(camera: Camera2D) {
	for obj, i in game_state.objects {
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

Level_Feature_Common :: struct {
	pos, dims, facing: Vec2,
}

Level_Exit :: struct {
	using common: Level_Feature_Common,
	next_level: string,
}

Level_Entrance :: struct {
	using common: Level_Feature_Common,
}

Cube_Button :: struct {
	using common: Level_Feature_Common,
	event: string,
	channel: Game_Event_Type,
}

Cube :: struct {
}

Cube_Spawner :: struct {
	using common: Level_Feature_Common,
	condition: Condition,
}

Portal_Fixture :: struct {
	using common: Level_Feature_Common,
	condition: Condition,
	portal: i32,
}

SLIDING_DOOR_SPEED_MS :: f32(5.0)

Sliding_Door :: struct {
	using common: Level_Feature_Common,
	condition: Condition,
	open_percent: f32,
	open: bool,
}

G_Trigger_Type :: enum {
	Kill,
	Level_Exit,
}

G_Trigger :: struct {
	type: G_Trigger_Type,
	// TODO: callback?
}

obj_cube_new :: proc(pos: Vec2) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	obj := add_phys_object_aabb(
		pos = pos,
		mass = kg(3),
		scale = {32, 32},
		flags = {.Weigh_Down_Buttons},
	)

	cube: Cube

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = cube,
		on_render = game_obj_collider_render,
	})
	pair_physics(id, obj)

	return // id
}

obj_sliding_door_new :: proc(door: Sliding_Door) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	obj := add_phys_object_aabb(
		pos = door.pos,
		scale = door.dims,
		flags = {.Non_Kinematic, .No_Gravity},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS
	)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = door,
		on_update = sliding_door_update,
		on_event = sliding_door_event_recv,
		on_render = door_render,
	})
	events_subscribe(id, {.Logic})
	pair_physics(id, obj)

	return // id
}

obj_cube_btn_new :: proc(btn: Cube_Button) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	obj := add_phys_object_aabb(
		pos = btn.pos,
		// TODO: rot
		scale = {32*2, 20},
		flags = {.Non_Kinematic, .No_Gravity, .Trigger},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS
	)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = btn,
		// TODO: on_event instead for the logic stuff
		on_collide_enter = cube_btn_collide,
		on_collide_exit = cube_btn_exit,
		on_render = cube_btn_render,
	})
	pair_physics(id, obj)

	return // id
}

obj_cube_spawner_new :: proc(spwner: Cube_Spawner) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = spwner,
		// TODO: on_event instead for the logic stuff
		on_event = spawner_recv_event,
	})
	events_subscribe(id, {.Logic})

	return // id
}


obj_prtl_frame_new :: proc(fixture: Portal_Fixture) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = fixture,
		// TODO: on_event instead for the logic stuff
		on_update = update_prtl_frame,
		on_event = prtl_frame_event_recv,
	})
	events_subscribe(id, {.Logic})

	return // id
}

obj_trigger_new :: proc(type: G_Trigger_Type, obj: Physics_Object_Id = PHYS_OBJ_INVALID) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	trueobj := obj

	if trueobj == PHYS_OBJ_INVALID {
		switch type {
		case .Kill: 
			log.error("Cannot generate collider for kill trigger without physics object")
			return GAME_OBJECT_INVALID
		case .Level_Exit:
			log.info("Generating default level exit")
			trueobj = add_phys_object_aabb(
				pos = state_level().level_exit,
				scale = {32*4, 32*2},
				flags = {.Non_Kinematic, .No_Gravity, .Fixed, .Trigger},
				collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS
			)
		}
	}

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = G_Trigger {
			type = type,
		},
		on_collide = trigger_on_collide,
		on_render = trigger_render,
	})
	pair_physics(id, trueobj)

	return // id
}

obj_player_new :: proc(tex: Texture_Id) -> Game_Object_Id {
	id := Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = player_new(tex),
		on_update = update_player,
		on_render = draw_player,
	})
	phys_obj_data(game_state.objects[int(id)].data.(Player).obj).game_object = id
	game_state.player = id

	return id
}


cube_btn_collide :: proc(self, other: Game_Object_Id, self_obj, other_obj: ^Physics_Object) {
	btn := game_obj(self, Cube_Button)
	if .Weigh_Down_Buttons in other_obj.flags {
		send_game_event(Game_Event {
			sender = self,
			name = btn.event,
			payload = Logic_Event {
				activated = true
			}
		})
	}	
}

cube_btn_exit :: proc(self, other: Game_Object_Id, self_obj, other_obj: ^Physics_Object) {
	btn := game_obj(self, Cube_Button)
	
	send_game_event(Game_Event {
		sender = self,
		name = btn.event,
		payload = Logic_Event {
			activated = false
		}
	})	
}

trigger_on_collide :: proc(self, other: Game_Object_Id, self_obj, other_obj: ^Physics_Object) {
	trigger, ok := game_state.objects[int(self)].data.(G_Trigger)
	assert(ok)

	switch trigger.type {
	case .Level_Exit:
		if state_level().next_level != "" {
			game_load_level_from_tilemap(state_level().next_level)
		}
	case .Kill:
		other_obj.vel = 0
		setpos(other_obj, state_get_player_spawn())
		log.info("Player hit death trigger")
	}
}

update_prtl_frame :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	frame := game_obj(self, Portal_Fixture)

	if condition_true(frame.condition) {
		portal_goto(frame.portal, frame.pos, frame.facing)
	}

	return false
}

sliding_door_update :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	door := game_obj(self, Sliding_Door)

	obj := phys_obj(game_obj(self).obj.?)

	origin := door.pos
	target := door.pos + door.dims * transmute(Vec2)door.facing 

	if door.open {
		door.open_percent += SLIDING_DOOR_SPEED_MS * dt
	}
	else {
		door.open_percent -= SLIDING_DOOR_SPEED_MS * dt
	}

	if door.open_percent < 0 do door.open_percent = 0
	if door.open_percent > 1 do door.open_percent = 1

	new_pos := origin + (target - origin) * ease.ease(ease.Ease.Quintic_Out, door.open_percent);
	setpos(obj, new_pos)

	return false
}

sliding_door_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	#partial switch payload in event.payload {
	case Logic_Event:
		door := game_obj(self, Sliding_Door)
		if event.name == door.condition.event {
			door.open = payload.activated
		}
	}
}

prtl_frame_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	#partial switch payload in event.payload {
	case Logic_Event:
		self := game_obj(self, Portal_Fixture)
		// portal_goto(self.portal, self.pos, transmute(Vec2)self.facing)
		if event.name == self.condition.event do self.condition.override = payload.activated
	}
}

spawner_recv_event :: proc(self: Game_Object_Id, event: ^Game_Event) {
	#partial switch payload in event.payload {
	case Logic_Event:
		self := game_obj(self, Cube_Spawner)
		// TODO: hack, fix how condition works generally because it has
		// nothing to do with events...
		if event.name == self.condition.event && self.condition.override != true {
			obj_cube_new(self.pos + self.facing * 32)
			self.condition.override = true
		}
	}
}


game_obj_collider_render :: proc(self: Game_Object_Id, _: Camera2D) {
	gobj := game_obj(self)

	draw_phys_obj(gobj.obj.?)
}

trigger_render :: proc(self: Game_Object_Id, _: Camera2D) {
	gobj := game_obj(self)

	draw_phys_obj(gobj.obj.?)
}

cube_btn_render :: proc(self: Game_Object_Id, _: Camera2D) {
	gobj := game_obj(self)

	draw_phys_obj(gobj.obj.?)
}

door_render :: proc(self: Game_Object_Id, _: Camera2D) {
	gobj := game_obj(self)

	draw_phys_obj(gobj.obj.?)
}