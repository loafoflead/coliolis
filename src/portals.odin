package main;

import rl "thirdparty/raylib";

import "core:os";
import "core:math/linalg";
import "core:math"
import "core:log"

PORTAL_EXIT_SPEED_BOOST :: 10;

PORTAL_WIDTH, PORTAL_HEIGHT :: f32(30), f32(100)

Portal_State :: enum {
	Connected,
	Alive,
}

Portal :: struct {
	obj: Physics_Object_Id,
	state: bit_set[Portal_State],
	occupant: Maybe(Physics_Object_Id),
	occupant_layers: bit_set[Collision_Layer],
	occupant_last_side: f32, // dot(occupant_to_portal_surface, portal_surface)
	occupant_last_new_pos: Vec2,
}

Portal_Handler :: struct {
	portals: [2]Portal,
	edge_colliders: [4]Physics_Object_Id,
	teleported_timer: ^Timer,
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

	obj := phys_obj(portal_handler.portals[portal - 1].obj)

	setrot(obj, Rad(ang))
	if math.round(facing.x) == 0 {
		if facing.y < 0 {
			rotate(obj, Rad(linalg.PI))
		} else {
			obj.local = transform_flip(obj)
		}
	}
	else if facing.x < 0 {
		rotate(obj, Rad(linalg.PI))
	}
	else {
		obj.local = transform_flip(obj)
	}

	setpos(obj, pos)
	portal_handler.portals[portal - 1].state += {.Alive}
}

initialise_portal_handler :: proc() {
	if !physics.initialised do panic("Must initialise physics world before initialising portals");
	if !timers.initialised do panic("Must initialise timers before initialising portals");

	for &ptl in portal_handler.portals {
		ptl.state = {}
		ptl.occupant = nil
		ptl.obj = PHYS_OBJ_INVALID
	}

	portal_handler.portals.x.obj = add_phys_object_aabb(
		scale = Vec2 { PORTAL_WIDTH, PORTAL_HEIGHT },
		flags = {.Non_Kinematic, .Trigger},
		collision_layers = {},
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.portals.y.obj = add_phys_object_aabb(
		scale = Vec2 { PORTAL_WIDTH, PORTAL_HEIGHT },
		flags = {.Non_Kinematic, .Trigger},
		collision_layers = {},
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.edge_colliders = {
		add_phys_object_aabb(
			pos = {0, -50},
			scale = Vec2 { 20.0, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = {},
		),
		add_phys_object_aabb(
			pos = {0, 50},
			scale = Vec2 { 20.0, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = {},
		),
		add_phys_object_aabb(
			pos = {10, -60},
			scale = Vec2 { 10.0, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = {},
		),
		add_phys_object_aabb(
			pos = {10, 60},
			scale = Vec2 { 10.0, 10.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
			collide_with = {},
		),
	};

	portal_handler.teleported_timer = 
		create_named_timer("portal_tp", 0.1, flags={.Update_Automatically});
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
		draw_phys_obj(portal.obj, colour);
		// draw_rectangle(pos=obj.pos, scale=obj.hitbox, rot=obj.rot, col=colour);
	}
	for edge in portal_handler.edge_colliders {
		colour := transmute(Colour) rl.ColorFromHSV(1.0, 1.0, 134);

		draw_phys_obj(edge, colour);
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

		collided := check_phys_objects_collide(portal.obj, collider);
		if collided && !occupied && is_timer_done("portal_tp") {
			obj := phys_obj(collider);
			if .Fixed not_in obj.flags {
				portal.occupant = collider;
				portal.occupant_layers = obj.collide_with_layers;
				obj.collide_with_layers = {.L0};
			}
		}
		else {
			if occupied && !collided {
				obj := phys_obj(occupant_id);
				obj.collide_with_layers = portal.occupant_layers;
				obj.collide_with_layers -= {.L0}
				portal.occupant = nil;
				set_timer_done("portal_tp");
			}
		}

		if !occupied do continue;


		portal_obj := phys_obj(portal.obj);

		for edge in portal_handler.edge_colliders {
			phys_obj(edge).parent = portal_obj	
		}

		if !is_timer_done("portal_tp") do continue;

		obj := phys_obj(occupant_id);
		// debug_log("%v", obj.collide_with_layers, timed=false);

		// debug_log("%v", obj.collide_with_layers)

		to_occupant_centre := obj.pos - phys_obj_centre(portal_obj);
		side := linalg.dot(to_occupant_centre, -transform_forward(portal_obj));

		other_portal := &portal_handler.portals[1 if i == 0 else 0];
		other_portal_obj := phys_obj(other_portal.obj);

		using linalg;
		oportal_mat := other_portal_obj.mat;
		portal_mat := portal_obj.mat;
		obj_mat := obj.mat;

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
			reset_timer("portal_tp");
			other_portal.occupant = occupant_id;
			other_portal.occupant_layers = portal.occupant_layers;

			obj.vel = normalize(ntr.pos - portal.occupant_last_new_pos) * (length(obj.vel) + PORTAL_EXIT_SPEED_BOOST);
			// obj.acc = normalize(ntr.pos - portal.occupant_last_new_pos) * (length(obj.acc) + PORTAL_EXIT_SPEED_BOOST);
			// transform_reset_rotation_plane(&ntr);
			obj.local = ntr;
			// setpos(obj, ntr.pos);

			// obj.collide_with_layers = portal.occupant_layers;
			portal.occupant = nil;
		}
		portal.occupant_last_new_pos = ntr.pos;
		portal.occupant_last_side = side;
	}
}