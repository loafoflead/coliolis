package main;

import rl "thirdparty/raylib"
import b2d "thirdparty/box2d"

import "core:os";
import "core:math/linalg";
import "core:math"
import "core:log"
import "core:fmt"

PORTAL_EXIT_SPEED_BOOST :: 1;

PORTAL_WIDTH, PORTAL_HEIGHT :: f32(16), f32(80)
@(rodata)
PORTAL_COLOURS := [2]Colour {
	Colour{0x00, 0x96, 0x50, 255},
	Colour{0xf0, 0x5f, 0x45, 255},
}

Portal_State :: enum {
	Connected,
	Alive,
}

Portal :: struct {
	obj: Physics_Object_Id,
	state: bit_set[Portal_State],
	occupant: Maybe(Physics_Object_Id),
	occupant_layers: bit_set[Collision_Layer; u64],
	occupant_last_side: f32, // dot(occupant_to_portal_surface, portal_surface)
	occupant_last_new_pos: Vec2,
}

Portal_Handler :: struct {
	portals: [2]Portal,
	edge_colliders: [4]Physics_Object_Id,
	teleported_timer: ^Timer,
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

	phys_obj_goto(obj_id, pos, facing)
	phys_obj_transform_sync_from_body(obj_id, sync_rotation=false)
	transform := phys_obj_transform(obj_id)
	setrot(transform, Rad(ang))
	// phys_obj_transform(obj_id, sync_rotation=true)
	// phys_obj_transform(obj_id) ^= transform_flip(phys_obj_transform(obj_id))
	if math.round(facing.y) != 0 {
		// up (for raylib)
		if facing.y < 0 {
			// do nothing
		}
		else {
			flup := transform_flip_vert(phys_obj_transform(obj_id))
			phys_obj_set_transform(obj_id, flup)
		}
	}
	if math.round(facing.x) != 0 {
		if facing.x < 0 {
			rotate(transform, Rad(linalg.PI))
		}
		else {
			flup := transform_flip(phys_obj_transform(obj_id))
			phys_obj_set_transform(obj_id, flup)
		}
	}

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

	for &ptl in portal_handler.portals {
		ptl.state = {}
		ptl.occupant = nil
		ptl.obj = PHYS_OBJ_INVALID
	}

	prtl_col_layers := Collision_Set{.Default, .L0}

	portal_handler.portals.x.obj = add_phys_object_aabb(
		pos = Vec2 {5, 0},
		scale = Vec2 { PORTAL_WIDTH, PORTAL_HEIGHT },
		flags = {.Non_Kinematic, .Trigger},
		on_collision_enter = prtl_collide_begin,
		on_collision_exit = prtl_collide_end,
		collision_layers = prtl_col_layers,
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.portals.y.obj = add_phys_object_aabb(
		pos = Vec2 {5, 0},
		scale = Vec2 { PORTAL_WIDTH, PORTAL_HEIGHT },
		flags = {.Non_Kinematic, .Trigger},
		on_collision_enter = prtl_collide_begin,
		on_collision_exit = prtl_collide_end,
		collision_layers = prtl_col_layers,
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.edge_colliders = {
		add_phys_object_aabb(
			pos = {-10, -50},
			scale = Vec2 { 20.0, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = COLLISION_LAYERS_ALL,
		),
		add_phys_object_aabb(
			pos = {-10, 50},
			scale = Vec2 { 20.0, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = COLLISION_LAYERS_ALL,
		),
		add_phys_object_aabb(
			pos = {10, -60},
			scale = Vec2 { 1.0, 1.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = {},
		),
		add_phys_object_aabb(
			pos = {10, 60},
			scale = Vec2 { 1.0, 1.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = {},
		),
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

	portal_handler.teleported_timer = 
		create_named_timer("portal_tp", 1.0, flags={.Update_Automatically});
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
		_, occupied := portal.occupant.?;
		if occupied {
			// positive = behind
			if portal.occupant_last_side > 0 do value = 0;
			else do value = 115;
		}
		if !is_timer_done("portal_tp") || .Connected not_in portal.state do sat = 0;
		// TODO: messed up HSV pls fix it l8r
		colour := transmute(Colour) rl.ColorFromHSV(value, sat, hue);
		ntrans := phys_obj_transform_new_from_body(portal.obj)
		portal_handler.surface_particle.draw_info.colour = PORTAL_COLOURS[i]
		particle_spawn(ntrans.pos, linalg.to_degrees(f32(ntrans.rot)), portal_handler.surface_particle)

		rotate(&ntrans, Rad(linalg.PI/2))
		move(&ntrans, -transform_right(&ntrans) * 16)
		draw_rectangle_transform(
			&ntrans,
			Rect {0, 0, 100, 32},
			texture_id = portal_handler.textures[0],
			colour = PORTAL_COLOURS[i],
		)
		// portal_handler.surface_particle.
		// draw_phys_obj(portal.obj, colour);
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

prtl_collide_begin :: proc(self, collided: Physics_Object_Id, self_shape, other_shape: b2d.ShapeId) {
	portal := portal_from_phys_id(self)
	occupant_id, occupied := portal.occupant.?;
	gobj, has_gobj := phys_obj_gobj(collided)
	if !has_gobj do return
	if .Portal_Traveller not_in gobj.flags do return

	if !occupied && is_timer_done("portal_tp") {
		ty := b2d.Body_GetType(collided)
		if ty != b2d.BodyType.staticBody {
			portal.occupant = collided;

			shape := phys_obj_shape(collided)
			cur_filter := b2d.Shape_GetFilter(shape)
			collides := transmute(bit_set[Collision_Layer; u64])cur_filter.maskBits
			belongs := transmute(bit_set[Collision_Layer; u64])cur_filter.categoryBits
			portal.occupant_layers = collides
			b2d.Shape_SetFilter(shape, b2d.Filter {
				categoryBits = cur_filter.categoryBits, //transmute(u64)bit_set[Collision_Layer;u64]{.L0},
				maskBits = transmute(u64)Collision_Set{.L0},
			})

			// 	shape, phys_shape_filter(
			// 	{},
			// 	collides,
			// ))
		}
	}
	else {
		log.info("TODO: implement more than one portalgoer")
	}
}

prtl_collide_end :: proc(self, collided: Physics_Object_Id, self_shape, other_shape: b2d.ShapeId) {
	portal := portal_from_phys_id(self)
	occupant_id, occupied := portal.occupant.?;

	if occupied && collided == occupant_id {
		shape := phys_obj_shape(occupant_id)
		cur_filter := b2d.Shape_GetFilter(shape)
		b2d.Shape_SetFilter(shape, b2d.Filter {
			categoryBits = cur_filter.categoryBits,//transmute(u64)portal.occupant_layers,
			maskBits = transmute(u64)portal.occupant_layers,
		})

		// 	phys_shape_filter(
		// 	transmute(bit_set[Collision_Layer; u64])cur_filter.maskBits,
		// 	portal.occupant_layers, 
		// ))

		portal.occupant = nil;
		set_timer_done("portal_tp");
	}
}

// TODO: make player a global?
update_portals :: proc(collider: Physics_Object_Id) {
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
		if .Connected not_in portal.state do continue

		occupant_id, occupied := portal.occupant.?;

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

		if !occupied do continue;


		for edge in portal_handler.edge_colliders {
			phys_obj_transform(edge).parent = phys_obj_transform(portal.obj)
			// phys_obj_transform_sync_from_body(edge, sync_rotation=false)
			phys_obj_goto_parent(edge)
		}

		if !is_timer_done("portal_tp") do continue;
		phys_obj_transform_sync_from_body(occupant_id, sync_rotation=false)
		occupant_trans := phys_obj_transform(occupant_id)
		portal_trans := phys_obj_transform(portal.obj)

		// log.infof("%#v", occupant_trans)
		// debug_log("%v", obj.collide_with_layers, timed=false);

		// debug_log("%v", obj.collide_with_layers)

		to_occupant_centre := occupant_trans.pos - portal_trans.pos;
		side := linalg.dot(to_occupant_centre, -transform_forward(portal_trans));

		other_portal := &portal_handler.portals[1 if i == 0 else 0];
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

		if side >= 0 && portal.occupant_last_side < 0 {
			fmt.println("teleportin")
			reset_timer("portal_tp");
			other_portal.occupant = occupant_id;
			other_portal.occupant_layers = portal.occupant_layers;

			new_vel := normalize(ntr.pos - portal.occupant_last_new_pos) * (linalg.length(b2d.Body_GetLinearVelocity(occupant_id)) + PORTAL_EXIT_SPEED_BOOST);
			new_vel.y = -new_vel.y
			new_pos := rl_to_b2d_pos(ntr.pos);

			b2d.Body_SetTransform(occupant_id, new_pos, transmute(b2d.Rot)angle_to_dir(ntr.rot))
			// b2d.Body_SetLinearVelocity(occupant_id, Vec2(0))
			b2d.Body_SetLinearVelocity(occupant_id, new_vel)
			// obj.acc = normalize(ntr.pos - portal.occupant_last_new_pos) * (length(obj.acc) + PORTAL_EXIT_SPEED_BOOST);
			// transform_reset_rotation_plane(&ntr);
			// obj.local = ntr;
			// setpos(obj, ntr.pos);

			// obj.collide_with_layers = portal.occupant_layers;
			portal.occupant = nil;
		}
		portal.occupant_last_new_pos = ntr.pos;
		portal.occupant_last_side = side;
	}
}