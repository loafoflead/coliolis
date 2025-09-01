package main;

import rl "thirdparty/raylib"
import b2d "thirdparty/box2d"

import "core:os";
import "core:math/linalg";
import "core:math"
import "core:log"
import "core:fmt"

PORTAL_EXIT_SPEED_BOOST :: 10
PORTAL_OCCUPANTS_INITIAL_CAP :: 10

PORTAL_WIDTH, PORTAL_HEIGHT :: f32(9), f32(80)

@(rodata)
PORTAL_COLOURS := [2]Colour {
	Colour{0x00, 0x96, 0x50, 255},
	Colour{0xf0, 0x5f, 0x45, 255},
}

Portal_State :: enum {
	Connected,
	Alive,
}

Portal_Occupant :: struct {
	phys_id: Physics_Object_Id,
	layers: Collision_Set,
	last_side: f32, // dot(occupant_to_portal_surface, portal_surface)
	last_new_pos: Vec2,
	tp_timer: ^Timer,
}

Portal :: struct {
	obj: Physics_Object_Id,
	state: bit_set[Portal_State],
	occupants: [dynamic]Portal_Occupant,
	linked: int,
}

Portal_Handler :: struct {
	portals: [2]Portal,
	edge_colliders: [2]Physics_Object_Id,
	// teleported_timer: ^Timer,
	textures: [2]Texture_Id,
	surface_particle: Particle_Def,
}

portal_dims :: proc() -> Vec2 {
	return {PORTAL_WIDTH, PORTAL_HEIGHT}
}

portal_goto :: proc(portal: i32, pos, facing: Vec2) {
	assert(portal > 0 && portal < 3)

	og := Vec3{pos.x, pos.y, 0}
	pt := og + Vec3{math.round(facing.x), math.round(facing.y), 0}
	quat := linalg.quaternion_look_at(og, pt, Z_AXIS)

	x, y, z := linalg.euler_angles_xyz_from_quaternion(quat)
	ang := z + linalg.PI/2

	obj_id := portal_handler.portals[portal - 1].obj

	up := Vec3{0, 0, 1}

	// TODO: seriously figure out wtf the deal is with this
	// i mean this is seriously just trial and error, absolutely no science to it
	// I dont understand if the linalg package has some weird matrix format i'm not privy to
	// (I'm using :
	//	[
	//    cos, -sin, .., x,
	//	  sin,  cos, .., y,	
	//    .. ,   .., 1 , 0,
	//    .. ,   .., .., 1
	//	]
	// ) and i just have no idea why this is so shit
	// and this business of always having to rotate by a quarter turn is so weird and pops
	// up everywhere its so annoying
	// fix it pls
	mpos := Vec3{get_world_mouse_pos().x, get_world_mouse_pos().y, 0}

	mat3 := linalg.matrix3_look_at_f32(
		Vec3{pos.x, pos.y, 0},
		Vec3{pos.x, pos.y, 0} + Vec3{math.round(facing.x), math.round(facing.y), 0}, 
		up
	)
	mat3 = mat3 * linalg.matrix3_rotate_f32(-linalg.PI/2, up)
	// log.infof(
	// 	"[\n\t%f, %f, %f,\n\t%f, %f, %f,\n\t%f, %f, %f\n]", 
	// 	mat3[0, 0], mat3[1, 0], mat3[2, 0],
	// 	mat3[0, 1], mat3[1, 1], mat3[2, 1],
	// 	mat3[0, 2], mat3[1, 2], mat3[2, 2],
	// )

	right: Vec3
	fwd := Vec3{facing.x, facing.y, 0}
	// linalg.normalize(-Vec3{pos.x, pos.y, 0} + mpos)

	right = fwd * linalg.matrix3_rotate_f32(linalg.π/2, Z_AXIS)

	if facing.y <= 0 do fwd = fwd * linalg.matrix3_rotate_f32(linalg.PI, right)
	if facing.x <= 0 do fwd = fwd * linalg.matrix3_rotate_f32(-linalg.PI, right)
	// else do fwd = fwd * linalg.matrix3_rotate_f32(linalg.PI, right)

	mat4 := linalg.matrix4_look_at_from_fru_f32(
		eye = Vec3{pos.x, pos.y, 0},
		f = fwd,
		r = right,
		u = up,
	)
	mat4 = mat4 * linalg.matrix4_rotate_f32(-linalg.PI/2, up)
	// log.infof(
	// 	"[\n\t%f, %f, %f, %f,\n\t%f, %f, %f, %f,\n\t%f, %f, %f, %f,\n\t%f, %f, %f, %f\n]", 
	// 	mat4[0, 0], mat4[1, 0], mat4[2, 0], mat4[3, 0],
	// 	mat4[0, 1], mat4[1, 1], mat4[2, 1], mat4[3, 1],
	// 	mat4[0, 2], mat4[1, 2], mat4[2, 2], mat4[3, 2],
	// 	mat4[0, 3], mat4[1, 3], mat4[2, 3], mat4[3, 3],
	// )

	trans := transform_new(pos, 0)//transform_from_matrix(mat4)
	trans.mat[0, 0], trans.mat[0, 1] = mat4[0,0], mat4[2, 0]
	trans.mat[1, 0], trans.mat[1, 1] = mat4[0,1], mat4[2, 1]
	transform_align(&trans)
	// log.infof("\n%#v", mat4)
	// draw_rectangle_transform(&trans, Rect{0, 0, 200, 100})
	// draw_line(trans.pos, trans.pos + transform_forward(&trans) * 1000, Colour{0, 255, 0, 255})
	// draw_line(trans.pos, trans.pos + transform_right(&trans) * 1000)
	phys_obj_set_transform(obj_id, trans)
	phys_obj_goto(obj_id, pos, {trans.mat[0, 0], trans.mat[0, 1]})

	// phys_obj_transform_sync_from_body(obj_id, sync_rotation=false)
	// transform := phys_obj_transform(obj_id)
	// setrot(transform, Rad(ang))
	// // phys_obj_transform(obj_id, sync_rotation=true)
	// // phys_obj_transform(obj_id) ^= transform_flip(phys_obj_transform(obj_id))
	// if math.round(facing.y) != 0 {
	// 	// up (for raylib)
	// 	if facing.y < 0 {
	// 		// do nothing
	// 	}
	// 	else {
	// 		flup := transform_flip_vert(phys_obj_transform(obj_id))
	// 		phys_obj_set_transform(obj_id, flup)
	// 	}
	// }
	// if math.round(facing.x) != 0 {
	// 	if facing.x < 0 {
	// 		rotate(transform, Rad(linalg.PI))
	// 	}
	// 	else {
	// 		flup := transform_flip(phys_obj_transform(obj_id))
	// 		phys_obj_set_transform(obj_id, flup)
	// 	}
	// }

	// if math.round(facing.x) == 0 {
	// 	if facing.y > 0 {
	// 		phys_obj_rotate(obj_id, Rad(-linalg.PI))
	// 	} else {
	// 		flup := transform_flip(phys_obj_transform(obj_id))
	// 		phys_obj_set_transform(obj_id, flup)
	// 		// log.infof("%#v", phys_obj_transform(obj_id))
	// 		// phys_obj_transform(obj_id) ^= transform_flip(phys_obj_transform(obj_id))
	// 		// log.infof("%#v", phys_obj_transform(obj_id))
	// 	}
	// }
	// else if facing.x < 0 {
	// 	phys_obj_rotate(obj_id, Rad(linalg.PI))
	// }
	// else {
	// 	flup := transform_flip(phys_obj_transform(obj_id))
	// 	phys_obj_set_transform(obj_id, flup)
	// 	// phys_obj_transform(obj_id) ^= transform_flip(phys_obj_transform(obj_id))
	// }
	// phys_obj_transform(obj_id, sync_rotation=true)

	// phys_obj_transform_sync(obj_id)

	// phys_obj_transform(obj_id, sync_rotation=true)
	portal_handler.portals[portal - 1].state += {.Alive}
}

initialise_portal_handler :: proc() {
	if !physics.initialised do panic("Must initialise physics world before initialising portals");
	if !timers.initialised do panic("Must initialise timers before initialising portals");

	ok: bool
	portal_handler.textures[0], ok = load_texture("portal_a.png")
	if !ok do log.panicf("missing portal texture")

	for &ptl, i in portal_handler.portals {
		if ptl.occupants != nil do delete(ptl.occupants)
		ptl.state = {}
		ptl.occupants = make([dynamic]Portal_Occupant, len=0, cap=PORTAL_OCCUPANTS_INITIAL_CAP)
		ptl.obj = PHYS_OBJ_INVALID
		ptl.linked = 1 if i == 0 else 0
	}

	prtl_col_layers := Collision_Set{.Default, .L0}

	portal_handler.portals.x.obj = add_phys_object_polygon(
		vertices = {
			{PORTAL_WIDTH/2, PORTAL_HEIGHT / 2},
			{-2 * PORTAL_WIDTH, PORTAL_HEIGHT /2},
			{-2 * PORTAL_WIDTH, -PORTAL_HEIGHT /2},
			{PORTAL_WIDTH/2, -PORTAL_HEIGHT / 2},
		},
		pos = Vec2 {5, 0},
		// scale = Vec2 { PORTAL_WIDTH, PORTAL_HEIGHT },
		flags = {.Non_Kinematic, .Trigger},
		on_collision_enter = prtl_collide_begin,
		on_collision_exit = prtl_collide_end,
		collision_layers = prtl_col_layers,
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.portals.y.obj = add_phys_object_polygon(
		vertices = {
			{PORTAL_WIDTH/2, PORTAL_HEIGHT / 2},
			{-2 * PORTAL_WIDTH, PORTAL_HEIGHT /2},
			{-2 * PORTAL_WIDTH, -PORTAL_HEIGHT /2},
			{PORTAL_WIDTH/2, -PORTAL_HEIGHT / 2},
		},
		pos = Vec2 {5, 0},
		// scale = Vec2 { PORTAL_WIDTH, PORTAL_HEIGHT },
		flags = {.Non_Kinematic, .Trigger},
		on_collision_enter = prtl_collide_begin,
		on_collision_exit = prtl_collide_end,
		collision_layers = prtl_col_layers,
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.edge_colliders = {
		add_phys_object_aabb(
			// vertices = {
			// 	({0  , 0} + Vec2{-10, 10}),
			// 	({20,  0} + Vec2{-10, 10}),
			// 	({20 ,  -20} + Vec2{-10, 10}),
			// },
			pos = {0, -40},
			scale = Vec2 { 12, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0, .Default},
			friction = 1,
			collide_with = COLLISION_LAYERS_ALL,
		),
		add_phys_object_aabb(
			// vertices = {
			// 	({0  , 0} - Vec2(10)),
			// 	({20,  0} - Vec2(10)),
			// 	({20 ,  20} - Vec2(10)),
			// 	// {10 , 10},
			// },
			pos = {0, 40},
			scale = Vec2 { 12, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0, .Default},
			friction = 1,
			collide_with = COLLISION_LAYERS_ALL,
		),
		// add_phys_object_aabb(
		// 	pos = {10, -60},
		// 	scale = Vec2 { 1.0, 1.0 },
		// 	flags = {.Non_Kinematic}, 
		// 	collision_layers = {.L0},
		// 	collide_with = {},
		// ),
		// add_phys_object_aabb(
		// 	pos = {10, 60},
		// 	scale = Vec2 { 1.0, 1.0 },
		// 	flags = {.Non_Kinematic}, 
		// 	collision_layers = {.L0},
		// 	collide_with = {},
		// ),
	};

	portal_handler.surface_particle = Particle_Def {
		draw_info = Particle_Draw_Info {
			shape = .Square,
			// texture = portal_handler.textures[0],
			scale = Vec2 {5, 5},
			colour = Colour{255, 0, 0, 255},
			alpha_easing = .Bounce_Out,
		},
		lifetime_secs = 1,
		movement = Particle_Physics {
			perm_acc = Vec2{0, 1000},
			initial_conds = Particle_Init_Random {
				vert_spread = PORTAL_HEIGHT,
				vel_dir_min = -36,
				vel_dir_max = 36,
				vel_mag_max = 19,
				vel_mag_min = 10,
				ang_vel_min = -10,
				ang_vel_max = 10,
			}
		}
	}

	for edge in portal_handler.edge_colliders do phys_obj_transform_sync_from_body(edge)

	// portal_handler.teleported_timer = 
		// create_named_timer("portal_tp", 1.0, flags={.Update_Automatically});
}
free_portal_handler :: proc() {}

draw_portals :: proc(selected_portal: int) {
	for &portal, i in portal_handler.portals {
		if .Alive not_in portal.state do continue
		value: f32;
		hue := f32(1);
		sat := f32(1);
		switch i {
			case 0: value = 60;  // poiple
			case 1: value = 115; // Grüne
			case: 	value = 0;	 // röt
		}
		if len(portal.occupants) > 0 {
			// positive = behind
			// if portal.occupant_last_side > 0 do value = 0;
			value = 115;
		}
		if .Connected not_in portal.state do sat = 0;
		// TODO: messed up HSV pls fix it l8r
		colour := transmute(Colour) rl.ColorFromHSV(value, sat, hue);
		ntrans := phys_obj_transform_new_from_body(portal.obj)
		portal_handler.surface_particle.draw_info.colour = PORTAL_COLOURS[i]
		// particle_spawn(ntrans.pos, linalg.to_degrees(f32(ntrans.rot)), portal_handler.surface_particle)

		rotate(&ntrans, Rad(linalg.PI/2))
		move(&ntrans, -transform_right(&ntrans) * 16)
		// draw_rectangle_transform(
		// 	&ntrans,
		// 	Rect {0, 0, 100, 32},
		// 	texture_id = portal_handler.textures[0],
		// 	colour = PORTAL_COLOURS[i],
		// )
		// portal_handler.surface_particle.
		draw_phys_obj(portal.obj, colour)
		// draw_rectangle(pos=obj.pos, scale=obj.hitbox, rot=obj.rot, col=colour);
	}
	for edge in portal_handler.edge_colliders {
		colour := transmute(Colour) rl.ColorFromHSV(1.0, 1.0, 134);

		draw_phys_obj(edge, colour);
	}
}

portal_from_phys_id :: proc(id: Physics_Object_Id) -> (^Portal, bool) #optional_ok {
	for &ptl in portal_handler.portals {
		if ptl.obj == id do return &ptl, true
	}
	return nil, false
}

teleport_occupant :: proc(occupant: Portal_Occupant, portal: ^Portal, other_portal: ^Portal) {
	occupant_id := occupant.phys_id
	player := false

	phys_obj_transform_sync_from_body(occupant_id, sync_rotation=false)
	occupant_trans := phys_obj_transform(occupant_id)
	if game_state.player == phys_obj_data(occupant_id).game_object.? {
		occupant_trans = &get_player().transform
		player = true
	}
	portal_trans := phys_obj_transform(portal.obj)

	// log.infof("%#v", occupant_trans)
	// debug_log("%v", obj.collide_with_layers, timed=false);

	// debug_log("%v", obj.collide_with_layers)

	to_occupant_centre := occupant_trans.pos - portal_trans.pos;
	side := linalg.dot(to_occupant_centre, -transform_forward(portal_trans));

	other_portal_trans := phys_obj_transform(other_portal.obj)

	using linalg;
	oportal_mat := other_portal_trans.mat;
	portal_mat := portal_trans.mat;
	obj_mat := occupant_trans.mat;

	// mirror := Mat4x4 {
	// 	-1, 0,  0, 0,
	// 	0, 1, 	0, 0,
	// 	0, 0, 	1, 0,
	// 	0, 0, 0, 1,
	// }
	mirror := matrix4_rotate_f32(PI, Y_AXIS);
	for i in 0..<3 do mirror[i, 3] = 0
	for i in 0..<3 do mirror[3, i] = 0

	obj_local := matrix4_inverse(portal_mat) * obj_mat;
	relative_to_other_portal := mirror * obj_local;

	fmat := oportal_mat * relative_to_other_portal;

	ntr := transform_from_matrix(fmat);
	// ntr.pos += other_portal_obj.pos;

	fmt.println("teleportin")
	noccupant := Portal_Occupant {
		phys_id = occupant.phys_id,
		last_side = 0,
		layers = occupant.layers,
		tp_timer = occupant.tp_timer,
	}
	reset_timer(occupant.tp_timer)
	append(&other_portal.occupants, noccupant)

	if player {
		new_vel := normalize(ntr.pos - occupant.last_new_pos) * (linalg.length(get_player().vel) + PORTAL_EXIT_SPEED_BOOST)
		get_player().transform = ntr
		// get_player().vel = new_vel
		get_player().vel = 0
		// TODO: rotate velocity instead o doing this silly shit
		get_player().teleporting = true
	}
	else {
		new_vel := normalize(ntr.pos - occupant.last_new_pos) * (linalg.length(b2d.Body_GetLinearVelocity(occupant_id)) + PORTAL_EXIT_SPEED_BOOST)
		new_pos := rl_to_b2d_pos(ntr.pos)
		new_vel.y = -new_vel.y

		b2d.Body_SetTransform(occupant_id, new_pos, transmute(b2d.Rot)angle_to_dir(ntr.rot))
		// b2d.Body_SetLinearVelocity(occupant_id, Vec2(0))
		b2d.Body_SetLinearVelocity(occupant_id, new_vel)
	}
	// obj.acc = normalize(ntr.pos - portal.occupant_last_new_pos) * (length(obj.acc) + PORTAL_EXIT_SPEED_BOOST);
	// transform_reset_rotation_plane(&ntr);
	// obj.local = ntr;
	// setpos(obj, ntr.pos);

	// obj.collide_with_layers = portal.occupant_layers;
}

prtl_collide_begin :: proc(self, collided: Physics_Object_Id, self_shape, other_shape: b2d.ShapeId) {
	portal := portal_from_phys_id(self)
	if .Connected not_in portal.state do return

	gobj, has_gobj := phys_obj_gobj(collided)
	log.infof("hit: '%s', %t, %v", b2d.Body_GetName(collided), has_gobj, gobj.flags)
	if !has_gobj do return
	if .Portal_Traveller not_in gobj.flags do return

	// if is_timer_done("portal_tp") {
	ty := b2d.Body_GetType(collided)

	for occupant in portal.occupants {
		if occupant.phys_id == collided do return
	}

	if ty != b2d.BodyType.staticBody {

		shape := phys_obj_shape(collided)
		cur_filter := b2d.Shape_GetFilter(shape)
		collides := transmute(bit_set[Collision_Layer; u64])cur_filter.maskBits

		to_occupant_centre := phys_obj_pos(collided) - phys_obj_pos(self);
		side := linalg.dot(to_occupant_centre, -transform_forward(phys_obj_transform(self)));

		occupant := Portal_Occupant {
			phys_id = collided,
			layers = collides,
			// TODO: this will eventually overflow the timers so maybe
			// just make it updated in the update func
			tp_timer = get_temp_timer(0.25, flags={.Update_Automatically}),
			last_side = side,
		}
	
		b2d.Shape_SetFilter(shape, b2d.Filter {
			categoryBits = cur_filter.categoryBits, //transmute(u64)bit_set[Collision_Layer;u64]{.L0},
			maskBits = transmute(u64)Collision_Set{.L0},
		})

		log.info("gainer")
		append(&portal.occupants, occupant)
		// portal.occupant = collided;

		// TODO: the only real way to fix buggines when walking up to a portal
		// from a direction is to instead disable all colliders intersecting this portal

		// 	shape, phys_shape_filter(
		// 	{},
		// 	collides,
		// ))
	}
	// }
}

prtl_collide_end :: proc(self, collided: Physics_Object_Id, self_shape, other_shape: b2d.ShapeId) {
	portal := portal_from_phys_id(self)
	if .Connected not_in portal.state do return

	retain := make([dynamic]Portal_Occupant, len=0, cap=len(portal.occupants))

	for occupant, i in portal.occupants {
		if collided == occupant.phys_id {

			to_occupant_centre := phys_obj_pos(collided) - phys_obj_pos(self);
			side := linalg.dot(to_occupant_centre, -transform_forward(phys_obj_transform(self)));

			log.infof("goner: %v", portal)
			if side >= 0 && occupant.last_side < 0 {
				teleport_occupant(occupant, portal, &portal_handler.portals[portal.linked])
				// continue
			}

			shape := phys_obj_shape(occupant.phys_id)
			cur_filter := b2d.Shape_GetFilter(shape)
			b2d.Shape_SetFilter(shape, b2d.Filter {
				categoryBits = cur_filter.categoryBits,//transmute(u64)portal.occupant_layers,
				maskBits = transmute(u64)occupant.layers,
			})
			if game_state.player == phys_obj_data(occupant.phys_id).game_object.? {
				get_player().teleporting = false
			}
		}
		else {
			append(&retain, occupant)
		}
	}

	delete(portal.occupants)
	portal.occupants = retain
}

// TODO: make player a global?
update_portals :: proc(collider: Physics_Object_Id) {
	if !is_timer_done("game.level_loaded") do return

	if .Alive in portal_handler.portals[0].state && .Alive in portal_handler.portals[1].state {
		for &ptl in portal_handler.portals {
			ptl.state += {.Connected}
		}
	}
	else {
		for &ptl in portal_handler.portals {
			ptl.state -= {.Connected}
		}
	}

	for &portal, i in portal_handler.portals {
		if .Connected not_in portal.state {
			continue
		}

		if len(portal.occupants) == 0 {
			// for edge in portal_handler.edge_colliders {
			// 	// TODO: why isn't this working?
			// 	phys_obj_transform(edge).parent = nil
			// 	phys_obj_goto(edge, Vec2(-100000))
			// }
		}
		else {
			for edge in portal_handler.edge_colliders {
				phys_obj_transform(edge).parent = phys_obj_transform(portal.obj)
				// phys_obj_transform_sync_from_body(edge, sync_rotation=false)
				// phys_obj_goto(edge, phys_obj_pos(portal.obj))
				phys_obj_goto_parent(edge)
			}
		}

		CONTACT_DATA_BUF_SIZE :: 4

		if len(portal.occupants) > 4 {
			log.warn("Portal is occupied by more objects than it can keep track of:", len(portal.occupants))
		}

		// remove any objects that we are no longer colliding with from the occupant list

		shape := phys_obj_shape(portal.obj)
		// buffer: [CONTACT_DATA_BUF_SIZE]b2d.ContactData
		buffer: [CONTACT_DATA_BUF_SIZE]b2d.ShapeId

		// keep := make([dynamic]Portal_Occupant, len=0, cap=len(portal.occupants))
		// copy(keep[:], portal.occupants[:])
		contacts_count := b2d.Shape_GetSensorOverlaps(shape, raw_data(buffer[:]), CONTACT_DATA_BUF_SIZE)
		contacts := buffer[:contacts_count]
		// contact_data := b2d.Shape_GetContactData(shape, buffer[:])

		for occupant in portal.occupants {
			found: Maybe(Physics_Object_Id)

			for contact in contacts {
				body := b2d.Shape_GetBody(contact)

				if body == occupant.phys_id {
					found = body
				}
			}

			if _, ok := found.?; !ok {
				prtl_collide_end(portal.obj, occupant.phys_id, b2d.nullShapeId, b2d.nullShapeId)
				log.info("lost boy!")
			}
		}

		// for contact in contact_data {
		// 	shape_a, shape_b := contact.shapeIdA, contact.shapeIdB

		// 	body_a, body_b := b2d.Shape_GetBody(shape_a), b2d.Shape_GetBody(shape_b)

		// 	body: Physics_Object_Id

		// 	if body_a == portal.obj do body = body_b
		// 	else do body = body_a

		// 	log.info(portal.occupants[0].phys_id, body)
		// 	for occupant in portal.occupants {
		// 		if occupant.phys_id == body {
		// 			prtl_collide_end(portal.obj, body, 0, 0)
		// 		}
		// 	}
		// }

		// if len(portal.occupants) != len(keep) {
		// 	log.info("removing non colliding guys")
		// }
		// delete(portal.occupants)
		// portal.occupants = keep

		// collided := check_phys_objects_collide(portal.obj, collider);
		// if collided && !occupied && is_timer_done("portal_tp") {
		// 	ty := b2d.Body_GetType(collider)
		// 	if ty != b2d.BodyType.staticBody {
		// 		portal.occupant = collider;

		// 		shape := phys_obj_shape(collider)
		// 		cur_filter := b2d.Shape_GetFilter(shape)
		// 		portal.occupant_layers = transmute(bit_set[Collision_Layer; u64])cur_filter.maskBits;
		// 		b2d.Shape_SetFilter(shape, phys_shape_filter(transmute(bit_set[Collision_Layer; u64])cur_filter.categoryBits, {.L0}))
		// 	}
		// }
		// else {
		// 	if occupied && !collided {
		// 		shape := phys_obj_shape(collider)
		// 		cur_filter := b2d.Shape_GetFilter(shape)
		// 		b2d.Shape_SetFilter(shape, phys_shape_filter(transmute(bit_set[Collision_Layer; u64])cur_filter.categoryBits, portal.occupant_layers))

		// 		portal.occupant = nil;
		// 		set_timer_done("portal_tp");
		// 	}
		// }

		// for edge in portal_handler.edge_colliders {
		// 	phys_obj_transform(edge).parent = phys_obj_transform(portal.obj)
		// 	// phys_obj_transform_sync_from_body(edge, sync_rotation=false)
		// 	// phys_obj_goto(edge, phys_obj_pos(portal.obj))
		// 	phys_obj_goto_parent(edge)
		// }

		remove := make([dynamic]int, len=0, cap=len(portal.occupants))

		for &occupant, occ_idx in portal.occupants {

			if !is_timer_done(occupant.tp_timer) do continue;

			other_portal := &portal_handler.portals[1 if i == 0 else 0]
			other_portal_trans := phys_obj_transform(other_portal.obj)
			portal_trans := phys_obj_transform(portal.obj)

			phys_obj_transform_sync_from_body(occupant.phys_id, sync_rotation=false)
			occupant_trans := phys_obj_transform(occupant.phys_id)
			if game_state.player == phys_obj_data(occupant.phys_id).game_object.? {
				occupant_trans = &get_player().transform
			}

			
			// }
			// else {
			// 	b2d.Shape_SetFilter(shape, b2d.Filter {
			// 		categoryBits = cur_filter.categoryBits, //transmute(u64)bit_set[Collision_Layer;u64]{.L0},
			// 		maskBits = transmute(u64)occupant.layers,
			// 	})
			// }

			to_occupant_centre := phys_obj_pos(occupant.phys_id) - phys_obj_pos(portal.obj);
			side := linalg.dot(to_occupant_centre, -transform_forward(phys_obj_transform(portal.obj)));

			using linalg;
			oportal_mat := other_portal_trans.mat;
			portal_mat := portal_trans.mat;
			obj_mat := occupant_trans.mat;

			// mirror := Mat4x4 {
			// 	-1, 0,  0, 0,
			// 	0, 1, 	0, 0,
			// 	0, 0, 	1, 0,
			// 	0, 0, 0, 1,
			// }
			mirror := matrix4_rotate_f32(PI, Y_AXIS);
			for i in 0..<3 do mirror[i, 3] = 0
			for i in 0..<3 do mirror[3, i] = 0

			obj_local := matrix4_inverse(portal_mat) * obj_mat;
			relative_to_other_portal := mirror * obj_local;

			fmat := oportal_mat * relative_to_other_portal;

			ntr := transform_from_matrix(fmat);

			if side >= 0 && occupant.last_side < 0 {
				teleport_occupant(occupant, &portal, other_portal)

				append(&remove, occ_idx)
			}

			occupant.last_new_pos = ntr.pos;
			occupant.last_side = side;
		}
		for idx in remove {
			log.infof("removing occupant %d from %v", idx, portal)
			unordered_remove(&portal.occupants, idx)
		}
	}
}