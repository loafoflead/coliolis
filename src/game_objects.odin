package main

import b2d "thirdparty/box2d"
import "core:math/ease"
import "core:log"

Puzzle_Element :: struct {
	inputs: []Puzzle_Input,

	active: bool,

	outputs: []Puzzle_Output,
}

Puzzle_Input_Kind :: enum {
	Toggle = 0,
	Set_Active,
	Set_Inactive,
}

Element_Id :: Game_Object_Id

Puzzle_Input :: struct {
	source: Element_Id,
	event: string,
	kind: Puzzle_Input_Kind,
}

Puzzle_Output :: struct {
	target: Element_Id,
	event: string,
	payload: union{string},
}

Event_Recv_Result :: enum {
	Became,
	Stayed,
	Active,
	Inactive,
	Toggled,
}

input_receive_event :: proc(pe: ^Puzzle_Element, event: ^Game_Event) -> (res: bit_set[Event_Recv_Result; u8]) {
	prev_active := pe.active
	for input in pe.inputs {
		if event_matches(event.name, input.event) {
			switch input.kind {
			case .Toggle:
				pe.active = !pe.active
			case .Set_Active:
				pe.active = true
			case .Set_Inactive:
				pe.active = false
			}
		}
	}

	if pe.active != prev_active do res += {.Became}
	else do res += {.Stayed}

	if pe.active {
		res += {.Active}
	}
	else {
		res += {.Inactive}
	}

	if pe.active == !prev_active do res += {.Toggled} 

	return
}

trigger_output :: proc(output: Puzzle_Output) {
	payload: Game_Event_Payload

	switch v in output.payload {
	case string:
		unimplemented("trigger_output use different kinds of payloads")
	case nil: 
		payload = Simple_Event{}
	}

	log.info(output)

	send_game_event(Game_Event {
		name = output.event,
		payload = payload,
	})
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
	condition: Condition,
	open: bool,
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
	pair_physics(id, obj)

	return // id
}

obj_cube_spawner_new :: proc(spwner: Cube_Spawner) -> (id: Game_Object_Id) {
	assert(game_state.initialised)

	spwner := spwner
	spwner.timer = get_temp_timer(1, flags = {.Update_Automatically})

	id = Game_Object_Id(len(game_state.objects))
	append(&game_state.objects, Game_Object {
		data = spwner,
		// TODO: on_event instead for the logic stuff
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

	obj := add_phys_object_aabb(
		pos = trigger.pos,
		scale = trigger.dims,
		flags = {.Non_Kinematic, .Trigger},
		collision_layers = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
		on_collision_enter = trigger_on_collide,
		collide_with = PHYS_OBJ_DEFAULT_COLLIDE_WITH + {.Player},
		name="trigger_?",
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
	btn, _ := phys_obj_gobj(self, Cube_Button)
	other_gobj := phys_obj_gobj(collided)

	if .Weigh_Down_Buttons in other_gobj.flags {
		btn.occupants_count += 1

		if btn.occupants_count == 1 {
			btn.active = true

			for outpt in btn.on_pressed do trigger_output(outpt)
		}
	}
}

cube_btn_exit :: proc(self, collided: Physics_Object_Id, _, _: b2d.ShapeId) {
	btn, _ := phys_obj_gobj(self, Cube_Button)
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

			for outpt in btn.on_pressed do trigger_output(outpt)
			for outpt in btn.on_unpressed {
				if outpt.event != "" {
					trigger_output(outpt)
				}
			}
		}
	}
}

trigger_on_collide :: proc(self, collided: Physics_Object_Id, _, _: b2d.ShapeId) {
	trigger, _ := phys_obj_gobj(self, G_Trigger)

	switch trigger.type {
	case .Level_Exit:
		if collided == get_player().obj {
			log.info("Player hit level exit")
			send_game_event("lvl", Level_Event.End)
		}
	case .Kill:
		if collided == get_player().obj {
			b2d.Body_SetLinearVelocity(collided, Vec2(0))
			phys_obj_goto(collided, state_get_player_spawn())
			log.info("Player hit death trigger")
		}
	case .Vaporise:
		gobj := phys_obj_gobj(collided)
		if .Weak_To_Being_Vaporised in gobj.flags {
			queue_remove_game_obj(phys_obj_data(collided).game_object.?)
		}
	}
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
	// btn := game_obj(self, Cube_Button)

	if !is_timer_done("game.level_loaded") do return

when PHYSICS_BUTTON {
	j_transl := b2d.PrismaticJoint_GetTranslation(btn.joint)
	if j_transl > CUBE_BTN_PRESSED {
		if !btn.pressed {
			btn.pressed = true
			send_game_event(Game_Event {
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
				name = btn.on_pressed,
				payload = Activation_Event {
					activated = false,
				},
			})
			if btn.on_unpressed != "" {
				send_game_event(Game_Event {
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

	obj := game_obj(self).obj.?

	origin := door.pos
	target := door.pos + door.dims * door.facing 

	if door.open {
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
	#partial switch payload in event.payload {
	case Simple_Event:
		door := game_obj(self, Sliding_Door)
		if event_matches(event.name, door.condition.event) {
			door.open = true
		}
	}
}

prtl_frame_event_recv :: proc(self: Game_Object_Id, event: ^Game_Event) {
	frame := game_obj(self, Portal_Fixture)
	#partial switch payload in event.payload {
	case Activation_Event, Simple_Event:
		self := game_obj(self, Portal_Fixture)
		res := input_receive_event(self, event)
		log.info(res)
		log.info(res &~ {.Became, .Active})
		log.info(res & {.Became, .Active})
		log.info(res - {.Became, .Active})
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
	log.info("heyyy", event)
	#partial switch payload in event.payload {
	case Simple_Event:
		self := game_obj(self, Cube_Spawner)
		result := input_receive_event(self, event)
		if result & {.Active} != {} && is_timer_done(self.timer) {
			obj_cube_new(self.pos + self.facing * 32, self.inputs[0].event)
			// reset_timer(self.timer)
			self.timer.flags -= {.Update_Automatically}
			reset_timer(self.timer)
			self.active = false
		}
	case Cube_Die:
		log.error("huh")
		self := game_obj(self, Cube_Spawner)

		result := input_receive_event(self, event)

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

cube_on_kill :: proc(self: Game_Object_Id) {
	self := game_obj(self, Cube)

	if self.respawn_event == "" do return 

	send_game_event(Game_Event {
		name = self.respawn_event,
		payload = Cube_Die {
			event_name = self.respawn_event,
		},
	})
}