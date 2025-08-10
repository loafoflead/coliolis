package main

import "core:fmt"
import "core:container/queue"

Level_Features :: struct {
	player_spawn: Vec2,
	level_exit: Vec2,
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

state_get_player_spawn :: proc() -> (point: Vec2 = 0, loaded: bool = false) #optional_ok {
	assert(game_state.initialised)

	if lvl, ok := game_state.current_level.?; ok == true {
		point = lvl.player_spawn
		loaded = true
	}
	return
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
	data: union{G_Trigger, Player},
}

G_Trigger_Type :: enum {
	Kill,
}

G_Trigger :: struct {
	type: G_Trigger_Type,
	obj: Physics_Object_Id,
	// TODO: callback?
}

obj_trigger_new :: proc(type: G_Trigger_Type, obj: Physics_Object_Id) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = G_Trigger {
			type = type,
			obj = obj,
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

trigger_on_collide :: proc(self, other: Game_Object_Id, self_obj, other_obj: ^Physics_Object) {
	trigger, ok := game_state.objects[int(self)].data.(G_Trigger)
	assert(ok)

	switch trigger.type {
	case .Kill:
		other_obj.vel = 0
		setpos(other_obj, state_get_player_spawn())
		fmt.println("died")
	}
}