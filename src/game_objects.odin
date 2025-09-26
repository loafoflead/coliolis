package main

import b2d "thirdparty/box2d"
import "core:math/ease"
import "core:log"
import "core:fmt"

import "core:strings"

import "rendering"
import rl "thirdparty/raylib"

Puzzle_Element :: struct {
	inputs: []Puzzle_Input,

	active: bool,

	outputs: []Puzzle_Output,
}

Puzzle_Input_Kind :: enum {
	Toggle = 0,
	Set_Active,
	Set_Inactive,
	Match_Source, // match the source's activity
	Oppose_Source, // be the opposite of the source's activity
}

Element_Id :: Game_Object_Id

Puzzle_Input :: struct {
	source: string,
	event: string,
	kind: Puzzle_Input_Kind,
}

// implicitly can also be nil
Output_Payload :: union{bool}

Puzzle_Output :: struct {
	target: string,
	event: string,
	payload: Output_Payload,
}

Event_Recv_Result :: enum {
	Became,
	Stayed,
	Active,
	Inactive,
	Toggled,
	Valid,
}

inputs_update_to_sources :: proc(inputs: []Puzzle_Input) -> (active: bool) {
	// TODO: work out some form of priority for events vs sources
	for input in inputs {
		if input.source != "" {
			src_active, ok := game_state.sources[input.source]
			active |= src_active
			if !ok {
				log.errorf("Game object has uninitialised or nonexistent source: '%s'", input.source)
			}
		}
	}

	return
}

input_receive_event :: proc(pe: ^Puzzle_Element, event: ^Game_Event, modify_state := true) -> (res: bit_set[Event_Recv_Result; u8], payload: Output_Payload) {
	prev_active := pe.active
	new_active := pe.active
	for input in pe.inputs {
		// log.infof("%#v", input)
		if event_matches(event.name, input.event) {
			// log.info("passes")
			res += {.Valid}
			switch pl in event.payload {
			case Boolean_Event:
				payload = cast(bool)pl
			case Simple_Event, Cube_Die, Level_Event, Activation_Event:
				payload = nil
			}
			switch input.kind {
			case .Toggle:
				new_active = !pe.active
			case .Set_Active:
				new_active = true
			case .Set_Inactive:
				new_active = false
			case .Match_Source, .Oppose_Source:
				log.warnf("Puzzle element input that expected an event is configured to update from a source.")
			}
		}
	}

	if new_active != prev_active do res += {.Became}
	else do res += {.Stayed}

	if new_active {
		res += {.Active}
	}
	else {
		res += {.Inactive}
	}

	if new_active == !prev_active do res += {.Toggled} 

	if modify_state do pe.active = new_active

	return
}

trigger_output :: proc(output: Puzzle_Output, sender:= GAME_OBJECT_INVALID) {
	payload: Game_Event_Payload

	switch v in output.payload {
	case bool:
		payload = Boolean_Event(v)
	case nil: 
		payload = Simple_Event{}
	}

	log.info(output)

	send_game_event(Game_Event {
		sender = sender,
		name = output.event,
		payload = payload,
	})
}

element_outputs_update :: proc(pe: Puzzle_Element) {
	for output in pe.outputs {
		if output.target != "" && output.target in game_state.sources {
			game_state.sources[output.target] = pe.active
		}
	}
}

update_outputs :: proc(outputs: []Puzzle_Output, state: bool) {
	for output in outputs {
		if output.target != "" && output.target in game_state.sources {
			game_state.sources[output.target] = state
		}
	}
}

// FEATURES CONFIG

// button is a physically simulated joint
PHYSICS_BUTTON :: false

// END FEATURES CONFIG


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

CUBE_BTN_PRESSED :: 1.3

Cube_Button :: struct {
	using common: Level_Feature_Common,
	on_pressed, on_unpressed: []Puzzle_Output,
	active: bool,
	
	channel: Game_Event_Category,
	joint: b2d.JointId,
	occupants_count: int,
}

Laser_Emitter :: struct {
	using common: Level_Feature_Common,
	using io: Puzzle_Element,
}

Laser_Receiver :: struct {
	using common: Level_Feature_Common,
	using io: Puzzle_Element,

	last_powered_tick: u64,
}

Cube :: struct {
	respawn_event: string,
}

Cube_Spawner :: struct {
	using common: Level_Feature_Common,
	using io: Puzzle_Element,
	timer: ^Timer,
}

t :: struct {
	portal: i32,
}

Portal_Fixture :: struct {
	using common: Level_Feature_Common,
	using io: Puzzle_Element,
	portal: i32,
}

SLIDING_DOOR_SPEED_MS :: f32(5.0)

Sliding_Door :: struct {
	using common: Level_Feature_Common,
	using io: Puzzle_Element,
	open_percent: f32,
}

G_Trigger_Type :: enum {
	Kill,
	Vaporise,
	Level_Exit,
}

G_Trigger :: struct {
	using common: Level_Feature_Common,
	type: G_Trigger_Type,
	// TODO: callback?
	// TODO: on_trigger broadcast event
}

obj_cube_new :: proc(pos: Vec2, respawn_event: string = "") -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	obj := add_phys_object_aabb(
		pos = pos,
		mass = 50,
		scale = {32, 32},
		friction = 1,
		flags = {.Never_Sleep},
		name="cube",
	)

	cube: Cube
	cube.respawn_event = respawn_event

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = cube,
		on_render = game_obj_collider_render,
		on_killed = cube_on_kill,
		flags = {.Weak_To_Being_Vaporised, .Portal_Traveller, .Weigh_Down_Buttons},
	})
	pair_physics(id, obj)

	return // id
}

obj_sliding_door_new :: proc(door: Sliding_Door) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	obj := add_phys_object_aabb(
		pos = door.pos,
		scale = door.dims,
		facing = door.facing,
		flags = {.Non_Kinematic},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
		name="sliding_door",
		// collide_with = {}
	)

	door := door

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = door,
		on_update = sliding_door_update,
		on_event = sliding_door_event_recv,
		on_render = door_render,
	})
	events_subscribe(id)
	pair_physics(id, obj)

	return // id
}

obj_cube_btn_new :: proc(btn: Cube_Button) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	flags: bit_set[Physics_Object_Flag]

	when PHYSICS_BUTTON {
		flags = {.Fixed_Rotation}
	}
	else {
		flags = {.Fixed_Rotation, .Trigger, .Non_Kinematic}
	}

	obj := add_phys_object_aabb(
		pos = btn.pos - btn.dims * btn.facing - Vec2{0, 16},
		// TODO: rot
		scale = {32*2, 20},
		flags = flags,
		collide_with = PHYS_OBJ_DEFAULT_COLLIDE_WITH + {.Player},
		on_collision_enter = cube_btn_collide,
		on_collision_exit = cube_btn_exit,
		name="cube_button",
	)

	btn := btn

when PHYSICS_BUTTON {
	anchor_def := b2d.DefaultBodyDef()
	anchor_def.position = rl_to_b2d_pos(btn.pos - btn.dims * btn.facing - Vec2{0, 16})
	origin_anchor := b2d.CreateBody(physics.world, anchor_def)

	// target := btn.pos + btn.dims * -btn.facing

	prism_joint_def := b2d.DefaultPrismaticJointDef()

	// The first attached body
	prism_joint_def.bodyIdA = origin_anchor
	// The local anchor point relative to bodyA's origin
	prism_joint_def.localAnchorA = anchor_def.position

	// The second attached body
	prism_joint_def.bodyIdB = obj
	// The local anchor point relative to bodyB's origin
	prism_joint_def.localAnchorB = rl_to_b2d_pos(btn.pos)

	// The local translation unit axis in bodyA
	prism_joint_def.localAxisA = btn.facing

	// The constrained angle between the bodies: bodyB_angle - bodyA_angle
	prism_joint_def.referenceAngle = 0

	prism_joint_def.enableSpring = true
	prism_joint_def.hertz = 1
	prism_joint_def.dampingRatio = 1

	// prism_joint_def.enableMotor = true
	// prism_joint_def.maxMotorForce = 500
	// prism_joint_def.motorSpeed = 10

	prism_joint_def.enableLimit = true
	prism_joint_def.lowerTranslation = 0
	prism_joint_def.upperTranslation = 1.5

	btn.joint = b2d.CreatePrismaticJoint(physics.world, prism_joint_def)
}

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = btn,
		// TODO: on_event instead for the logic stuff
		on_render = cube_btn_render,
		on_update = update_cube_btn,
	})
	register_puzzle_outputs(btn.on_pressed, id)
	register_puzzle_outputs(btn.on_unpressed, id, default=true)
	pair_physics(id, obj)

	return // id
}

obj_laser_receiver_new :: proc(recv: Laser_Receiver) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	obj := add_phys_object_aabb(
		pos = recv.pos - recv.dims * recv.facing - Vec2{0, 16},
		facing = recv.facing,
		scale = {20, 32*1.5},
		flags = {.Fixed_Rotation, .Non_Kinematic},
		collide_with = PHYS_OBJ_DEFAULT_COLLIDE_WITH,
		name="laser_recv",
	)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = recv,
		on_update = laser_receiver_update,
	})
	register_puzzle_element(recv, id)
	pair_physics(id, obj)

	return // id
}

obj_laser_emitter_new :: proc(le: Laser_Emitter) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	le := le

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = le,
		on_update = laser_emitter_update,
	})
	events_subscribe(id)

	return // id
}

obj_cube_spawner_new :: proc(spwner: Cube_Spawner) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	spwner := spwner
	spwner.timer = get_temp_timer(1, flags = {.Update_Automatically})
	set_timer_done(spwner.timer)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = spwner,
		on_event = spawner_recv_event,
	})
	events_subscribe(id)

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
	events_subscribe(id)

	return // id
}

obj_trigger_new :: proc(trigger: G_Trigger) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	name: cstring
	switch trigger.type {
		case .Kill:
			name = "trigger_kill"
		case .Vaporise:
			name = "trigger_vaporise"
		case .Level_Exit:
			name = "trigger_level_exit"
		case:
			name = "trigger_idk"
	}

	obj := add_phys_object_aabb(
		pos = trigger.pos,
		scale = trigger.dims,
		flags = {.Non_Kinematic, .Trigger},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
		on_collision_enter = trigger_on_collide,
		collide_with = PHYS_OBJ_DEFAULT_COLLIDE_WITH + {.Player},
		name=name,
		// collide_with = {}
	)

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = trigger,
		on_render = trigger_render,
	})
	pair_physics(id, obj)

	return // id
}

obj_trigger_new_from_ty :: proc(type: G_Trigger_Type, obj: Physics_Object_Id = PHYS_OBJ_INVALID) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	trueobj := obj

	if trueobj == PHYS_OBJ_INVALID {
		#partial switch type {
		case .Kill: 
			log.error("Cannot generate collider for kill trigger without physics object")
			return GAME_OBJECT_INVALID
		case .Level_Exit:
			log.info("Generating default level exit")
			trueobj = add_phys_object_aabb(
				pos = state_level().level_exit,
				scale = {32*4, 32*2},
				flags = {.Non_Kinematic, .No_Gravity, .Fixed, .Trigger},
				collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
				collide_with = PHYS_OBJ_DEFAULT_COLLIDE_WITH + {.Player},
				on_collision_enter = trigger_on_collide,
				name="trigger_level_exit",
			)
		case:
			log.errorf("obj_trigger_new_from_ty does not support %v, only Level_Exit and Kill, please use obj_trigger_new", type)
			return GAME_OBJECT_INVALID
		}
	}

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = G_Trigger {
			type = type,
		},
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
		flags = {.Weigh_Down_Buttons, .Portal_Traveller},
	})
	game_state.player = id

	phys_obj_data(get_player().obj).game_object = id
	// phys_obj_data(get_player().dynamic_obj).game_object = id

	return id
}

cube_btn_collide :: proc(self, collided: Physics_Object_Id, _, _: b2d.ShapeId) {
	btn, _, _ := phys_obj_gobj(self, Cube_Button)
	self_id := phys_obj_gobj_id(self)
	other_gobj := phys_obj_gobj(collided)

	if .Weigh_Down_Buttons in other_gobj.flags {
		btn.occupants_count += 1

		if btn.occupants_count == 1 {
			btn.active = true

			for outpt in btn.on_pressed do trigger_output(outpt, sender = self_id)
		}
	}
}

cube_btn_exit :: proc(self, collided: Physics_Object_Id, _, _: b2d.ShapeId) {
	btn, _, _ := phys_obj_gobj(self, Cube_Button)
	self_id := phys_obj_gobj_id(self)
	other_gobj := phys_obj_gobj(collided)

	// TODO: this may be a logic error bc it doesnt check if the thing leaving is 
	// an occupant
	if btn.active && .Weigh_Down_Buttons in other_gobj.flags {
		if btn.occupants_count == 0 {
			log.panic("TODO: fix when a button loses someone it doesn't have")
		}

		btn.occupants_count -= 1
		if btn.occupants_count == 0 {
			btn.active = false

			for outpt in btn.on_pressed do trigger_output(outpt, sender = self_id)
			for outpt in btn.on_unpressed {
				if outpt.event != "" {
					trigger_output(outpt, sender = self_id)
				}
			}
		}
	}
}

trigger_on_collide :: proc(self, collided: Physics_Object_Id, _, _: b2d.ShapeId) {
	trigger, _, _ := phys_obj_gobj(self, G_Trigger)
	self_id := phys_obj_gobj_id(self)

	switch trigger.type {
	case .Level_Exit:
		if collided == get_player().obj {
			log.info("Player hit level exit")
			send_game_event("lvl", Level_Event.End, sender = self_id)
		}
	case .Kill:
		if collided == get_player().obj {
			b2d.Body_SetLinearVelocity(collided, Vec2(0))
			phys_obj_goto(collided, state_get_player_spawn())
			log.info("Player hit death trigger")
		}
	case .Vaporise:
		gobj, ok := phys_obj_gobj(collided)

		if ok && .Weak_To_Being_Vaporised in gobj.flags {
			queue_remove_game_obj(phys_obj_data(collided).game_object.?)
		}
	}
}

laser_emitter_update :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool) {
	le := game_obj(self, Laser_Emitter)

	LASER_RANGE :: 32*10

	cols, hit := portal_aware_raycast(le.pos, le.facing * LASER_RANGE/*, exclude = {get_player().obj}*/)
	if hit {
		draw_line(cols[0].origin, cols[0].collision.point, colour=Colour{0, 255, 0, 255})
		for i in 0..<len(cols) {
			col := cols[i]
			draw_line(col.origin, col.collision.point, colour=Colour{0, 255, 0, 255})
		}
	} else {
		draw_line(le.pos, le.facing * LASER_RANGE, colour=Colour{255, 0, 0, 255})
	}

	for col in cols {
		recv, _, ok := phys_obj_gobj(col.obj_id, Laser_Receiver)
		if !ok do continue

		recv.last_powered_tick = game_state.ticks
	}

	return
}

laser_receiver_update :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool) {
	recv := game_obj(self, Laser_Receiver)
	self := game_obj(self)

	if recv.last_powered_tick == game_state.ticks do recv.io.active = true
	else do recv.io.active = false

	element_outputs_update(recv)

	text := strings.builder_make(allocator = context.temp_allocator)
	strings.write_string(&text, fmt.tprintf("%v\n%v", recv.io.active, recv.last_powered_tick))
	w_pos := rendering.world_pos_to_screen_pos(rendering.camera, phys_obj_pos(self.obj.?))
	rl.DrawText(strings.to_cstring(&text), i32(w_pos.x), i32(w_pos.y), fontSize = 20, color = rl.WHITE)

	return
}

update_prtl_frame :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	// frame := game_obj(self, Portal_Fixture)

	// draw_line(frame.pos, frame.pos + frame.facing * 100)

	// if condition_true(frame.condition) {
	// 	portal_goto(frame.portal, frame.pos, frame.facing)
	// }

	return false
}

update_cube_btn :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	btn := game_obj(self, Cube_Button)

	if !is_timer_done("game.level_loaded") do return

	update_outputs(btn.on_pressed, btn.active)
	update_outputs(btn.on_unpressed, !btn.active)

when PHYSICS_BUTTON {
	j_transl := b2d.PrismaticJoint_GetTranslation(btn.joint)
	if j_transl > CUBE_BTN_PRESSED {
		if !btn.pressed {
			btn.pressed = true
			send_game_event(Game_Event {
				sender = self,
				name = btn.on_pressed,
				payload = Activation_Event {
					activated = true,
				},
			})
		}
	}
	else {
		if btn.pressed {
			btn.pressed = false
			send_game_event(Game_Event {
				sender = self,
				name = btn.on_pressed,
				payload = Activation_Event {
					activated = false,
				},
			})
			if btn.on_unpressed != "" {
				send_game_event(Game_Event {
					sender = self,
					name = btn.on_unpressed,
					payload = Activation_Event {
						activated = true,
					},
				})
			}
		}
	}
}
else {
	// TODO: make a second phys object below the button trigger that goes down when 
	// the button is pressed
}

	return
}

sliding_door_update :: proc(self: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	door := game_obj(self, Sliding_Door)

	active := inputs_update_to_sources(door.io.inputs)
	door.io.active = active

	obj := game_obj(self).obj.?

	origin := door.pos
	target := door.pos + door.dims * door.facing 

	if door.active {
		door.open_percent += SLIDING_DOOR_SPEED_MS * dt
	}
	else {
		door.open_percent -= SLIDING_DOOR_SPEED_MS * dt
	}

	if door.open_percent < 0 do door.open_percent = 0
	if door.open_percent > 1 do door.open_percent = 1

	new_pos := origin + (target - origin) * ease.ease(ease.Ease.Quintic_Out, door.open_percent);
	phys_obj_goto(obj, new_pos)
	// setpos(obj, new_pos)

	return false
}

sliding_door_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	// TODO: is this outer switch necessary with all that input_receive_event is doing?
	#partial switch _ in event.payload {
	case Boolean_Event:
		self := game_obj(self, Sliding_Door)
		res, payload := input_receive_event(self, event, modify_state=false)
		if res & {.Valid} != {} {
			self.active = payload.(bool) or_else panic("Big whoopsie in event handling")
		}
	}
}

prtl_frame_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	frame := game_obj(self, Portal_Fixture)
	#partial switch payload in event.payload {
	case Activation_Event, Simple_Event, Level_Event:
		self := game_obj(self, Portal_Fixture)
		res, _ := input_receive_event(self, event)
		if res & {.Became, .Active} != {} do portal_goto(frame.portal, frame.pos, frame.facing)
		// for input in self.inputs {
		// 	if event_matches(event.name, input.event) {
		// 		self.active = true
		// 	}
		// }
		// portal_goto(self.portal, self.pos, transmute(Vec2)self.facing)
	}
}

spawner_recv_event :: proc(self: Game_Object_Id, event: ^Game_Event) {
	#partial switch payload in event.payload {
	case Simple_Event, Boolean_Event, Level_Event:
		self := game_obj(self, Cube_Spawner)
		result, _ := input_receive_event(self, event, modify_state=false)
		// NOTE: this wasn't working bc the timer wasn't done 
		// while it was recving a spawn event
		if result & {.Active} != {} && is_timer_done(self.timer) {
			obj_cube_new(self.pos + self.facing * 32, self.inputs[0].event)
			// reset_timer(self.timer)
			self.timer.flags -= {.Update_Automatically}
			reset_timer(self.timer)
		}
	case Cube_Die:
		log.error("huh")
		self := game_obj(self, Cube_Spawner)

		result, _ := input_receive_event(self, event)

		if result & {.Active} != {} {
			obj_cube_new(self.pos + self.facing * 32, self.inputs[0].event)
			self.active = false
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

cube_on_kill :: proc(self_id: Game_Object_Id) {
	self := game_obj(self_id, Cube)

	if self.respawn_event == "" do return 

	send_game_event(Game_Event {
		sender = self_id,
		name = self.respawn_event,
		payload = Cube_Die {
			event_name = self.respawn_event,
		},
	})
}
