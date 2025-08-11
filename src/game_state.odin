package main

import "core:log"
import "core:container/queue"

import vmem "core:mem/virtual"

import "tiled"

Level_Features :: struct {
	player_spawn: Vec2,
	level_exit: Vec2,

	portal_fixtures: [dynamic]Portal_Fixture,

	// TODO: arena plz i love the buggers
	// arena: vmem.Arena,
}

Game_Object_On_Collide_Function :: #type proc(self, other: Game_Object_Id, self_phys, other_phys: ^Physics_Object)
Game_Object_On_Update_Function  :: #type proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool)
Game_Object_Render_Function     :: #type proc(self: Game_Object_Id, camera: Camera2D)

GAMESTATE_MESSAGES_PER_FRAME :: 16

Game_State :: struct {
	initialised: bool,
	objects: [dynamic]Game_Object,
	player: Game_Object_Id,
	current_level: Maybe(Level_Features),

	messages: queue.Queue(Game_Object_Message),
}

initialise_game_state :: proc() {
	game_state.objects = make([dynamic]Game_Object)
	queue.init(&game_state.messages)
	game_state.initialised = true
}

free_game_state :: proc() {
	delete(game_state.objects)
}

game_init_level :: proc() {
	assert(game_state.initialised && game_state.current_level != nil)

	obj_trigger_new(.Level_Exit)

	// log.error(state_level().portal_fixtures)
	for fixture in state_level().portal_fixtures {
		obj_prtl_frame_new(fixture)
	}
}

state_get_player_spawn :: proc() -> (point: Vec2 = 0, loaded: bool = false) #optional_ok {
	assert(game_state.initialised)

	if lvl, ok := game_state.current_level.?; ok == true {
		point = lvl.player_spawn
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
		if obj.update_fn != nil do should_delete = (obj.update_fn)(Game_Object_Id(i), dt)
		if should_delete do append(&to_delete, i)
	}

	// TODO: work out which order best here
	for _ in 0..<GAMESTATE_MESSAGES_PER_FRAME {
		message := queue.pop_back_safe(&game_state.messages) or_break

		inform_game_object(message.gobj, message.payload)
	}

	#reverse for idx in to_delete {
		// moves the last elem to this pos,
		// so reverse means this should always be good
		unordered_remove(&game_state.objects, idx)
	}
}

render_game_objects :: proc(camera: Camera2D) {
	for obj, i in game_state.objects {
		if obj.render_fn != nil do (obj.render_fn)(Game_Object_Id(i), camera)
	}
}

queue_inform_game_object :: proc(obj: Game_Object_Id, payload: Game_Object_Message_Payload) {
	assert(obj != GAME_OBJECT_INVALID && int(obj) < len(game_state.objects) )

	queue.push_front(&game_state.messages, Game_Object_Message { gobj = obj, payload = payload })
}

inform_game_object :: proc(obj: Game_Object_Id, payload: Game_Object_Message_Payload) {
	assert(obj != GAME_OBJECT_INVALID && int(obj) < len(game_state.objects) )

	// gobj is so funny to me idk why
	gobj := game_obj(obj)

	switch data in payload {
	case Collision:
		if gobj.on_collide != nil do (gobj.on_collide)(obj, data.other, data.self_obj, data.other_obj)
	}
}

Collision :: struct {
	other: Game_Object_Id,
	self_obj, other_obj: ^Physics_Object,
}

Game_Object_Message_Payload :: union {
	Collision,
}

Game_Object_Message :: struct {
	gobj: Game_Object_Id,
	payload: Game_Object_Message_Payload,
}

Game_Object_Id :: distinct int
GAME_OBJECT_INVALID :: Game_Object_Id(-1)

Game_Object :: struct {
	update_fn: Game_Object_On_Update_Function,
	on_collide: Game_Object_On_Collide_Function,
	render_fn: Game_Object_Render_Function,

	// Add here any new game object types
	data: union{G_Trigger, Player, Portal_Fixture},
}

Condition_Type :: enum {
	Always_Active,
	On_Event,
}

Condition :: struct {
	type: Condition_Type,
}

condition_true :: proc(cond: Condition) -> bool {
	switch cond.type {
	case .Always_Active:
		return true
	case .On_Event:
		unimplemented()
	}
	return false
}

Portal_Fixture :: struct {
	active_condition: Condition,
	portal: i32,
	pos, facing: Vec2,
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

obj_prtl_frame_new :: proc(fixture: Portal_Fixture) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = fixture,
		// TODO: on_event instead for the logic stuff
		update_fn = update_prtl_frame,
	})

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
				flags = {.Non_Kinematic, .No_Gravity, .Fixed},
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
		update_fn = update_player,
		render_fn = draw_player,
	})
	phys_obj(game_state.objects[int(id)].data.(Player).obj).linked_game_object = id

	return id
}

update_prtl_frame :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	frame := game_obj(self, Portal_Fixture)

	if condition_true(frame.active_condition) {
		portal_goto(frame.portal, frame.pos, frame.facing)
	}

	return false
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

trigger_render :: proc(self: Game_Object_Id, _: Camera2D) {
	gobj := game_obj(self, G_Trigger)

	draw_phys_obj(gobj.obj)
}