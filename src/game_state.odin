package main

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

Game_Object_Type :: union{G_Trigger, Player, Portal_Fixture, Cube_Button, Sliding_Door}

Game_Object :: struct {
	on_collide: Game_Object_On_Collide_Function,
	on_collide_enter: Game_Object_On_Collide_Function,
	on_collide_exit: Game_Object_On_Collide_Function,
	is_colliding: bool,

	on_update: Game_Object_On_Update_Function,
	on_render: Game_Object_Render_Function,
	on_event: Game_Object_Event_Recv_Function,

	// Add here any new game object types
	data: Game_Object_Type,
	// TODO: add optional phys_obj field for consistency and lightening load on message system
	// and decoupling physics system
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
	// TODO: free queues
}

game_init_level :: proc() {
	assert(game_state.initialised && game_state.current_level != nil)

	obj_trigger_new(.Level_Exit)
}

state_get_player_spawn :: proc() -> (point: Vec2 = 0, loaded: bool = false) #optional_ok {
	assert(game_state.initialised)

	if lvl, ok := game_state.current_level.?; ok == true {
		point = lvl.player_spawn + lvl.player_spawn_facing * PLAYER_HEIGHT / 2
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

update_game_state :: proc(dt: f32) {
	to_delete := make([dynamic]int)
	for obj, i in game_state.objects {
		should_delete := false
		if obj.on_update != nil do should_delete = (obj.on_update)(Game_Object_Id(i), dt)
		if should_delete do append(&to_delete, i)
	}

	// TODO: work out which order best here
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

render_game_objects :: proc(camera: Camera2D) {
	for obj, i in game_state.objects {
		if obj.on_render != nil do (obj.on_render)(Game_Object_Id(i), camera)
	}
}


Game_Object_Id :: distinct int
GAME_OBJECT_INVALID :: Game_Object_Id(-1)


Condition_Type :: enum {
	Always_Active,
	On_Event,
}

Condition :: struct {
	type: Condition_Type,
	event_name: string,
	override: bool,
}

condition_true :: proc(cond: Condition) -> bool {
	if cond.override do return true

	switch cond.type {
	case .Always_Active:
		return true
	case .On_Event:
		unimplemented()
	}
	return false
}

Level_Feature_Common :: struct {
	pos, facing, dims: Vec2,
}

Cube_Button :: struct {
	using common: Level_Feature_Common,
	event: string,
	channel: Game_Event_Type,
	obj: Physics_Object_Id,
}

Portal_Fixture :: struct {
	using common: Level_Feature_Common,
	condition: Condition,
	portal: i32,
}

Sliding_Door :: struct {
	using common: Level_Feature_Common,
	obj: Physics_Object_Id,
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
	obj: Physics_Object_Id,
	// TODO: callback?
}

obj_sliding_door_new :: proc(door: Sliding_Door) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	door := door

	obj := add_phys_object_aabb(
		pos = door.pos,
		scale = door.dims,
		flags = {.Non_Kinematic, .No_Gravity},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS
	)

	door.obj = obj

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = door,
		// TODO: on_event instead for the logic stuff
		on_update = sliding_door_update,
		on_event = sliding_door_event_recv,
	})
	events_subscribe(id, {.Logic})
	phys_obj(game_state.objects[int(id)].data.(Sliding_Door).obj).linked_game_object = id

	return // id
}

obj_cube_btn_new :: proc(btn: Cube_Button) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	btn := btn

	obj := add_phys_object_aabb(
		pos = btn.pos,
		// TODO: rot
		scale = {32*2, 20},
		flags = {.Non_Kinematic, .No_Gravity, .Trigger},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS
	)

	btn.obj = obj

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = btn,
		// TODO: on_event instead for the logic stuff
		on_collide_enter = cube_btn_collide,
		on_collide_exit = cube_btn_exit,
	})
	phys_obj(game_state.objects[int(id)].data.(Cube_Button).obj).linked_game_object = id

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
			obj = trueobj,
		},
		on_collide = trigger_on_collide,
	})
	phys_obj(game_state.objects[int(id)].data.(G_Trigger).obj).linked_game_object = id

	return // id
}

obj_player_new :: proc(tex: Texture_Id) -> Game_Object_Id {
	id := Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = player_new(tex),
		on_update = update_player,
		on_render = draw_player,
	})
	phys_obj(game_state.objects[int(id)].data.(Player).obj).linked_game_object = id
	game_state.player = id

	return id
}


cube_btn_collide :: proc(self, other: Game_Object_Id, self_obj, other_obj: ^Physics_Object) {
	log.info("hi")
	btn := game_obj(self, Cube_Button)
	if other_obj == phys_obj(game_obj(game_state.player, Player).obj) {
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
	log.info("bye")
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
		log.info("TODO: implement going to the next level")
		fallthrough
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

	obj := phys_obj(door.obj)

	target: Vec2

	if door.open && door.open_percent < 1 {
		target = door.pos + (door.dims * door.facing)
		door.open_percent += dt
	}
	else if !door.open && door.open_percent > 0 {
		target = door.pos
		door.open_percent -= dt
	}

	if door.open_percent < 0 do door.open_percent = 0
	if door.open_percent > 1 do door.open_percent = 1

	new_pos := obj.pos + (target - obj.pos) * ease.ease(ease.Ease.Circular_In, door.open_percent);
	setpos(obj, new_pos)

	return false
}

sliding_door_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	#partial switch payload in event.payload {
	case Logic_Event:
		door := game_obj(self, Sliding_Door)
		if event.name == door.condition.event_name {
			door.open = payload.activated
		}
	}
}

prtl_frame_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	#partial switch payload in event.payload {
	case Logic_Event:
		self := game_obj(self, Portal_Fixture)
		if event.name == self.condition.event_name do self.condition.override = payload.activated
	}
}



trigger_render :: proc(self: Game_Object_Id, _: Camera2D) {
	gobj := game_obj(self, G_Trigger)

	draw_phys_obj(gobj.obj)
}