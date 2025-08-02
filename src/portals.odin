package main;

import rl "thirdparty/raylib";

import "core:os";
import "core:math/linalg";


PORTAL_EXIT_SPEED_BOOST :: 10;

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
	edge_colliders: [2]Physics_Object_Id,
	teleported_timer: ^Timer,
}

initialise_portal_handler :: proc() {
	if !phys_world.initialised do panic("Must initialise physics world before initialising portals");
	if !timers.initialised do panic("Must initialise timers before initialising portals");

	portal_handler.portals.x.obj = add_phys_object_aabb(
		scale = Vec2 { 20.0, 100.0 },
		flags = {.Non_Kinematic},
		collision_layers = {.Trigger},
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.portals.y.obj = add_phys_object_aabb(
		scale = Vec2 { 20.0, 100.0 },
		flags = {.Non_Kinematic},
		collision_layers = {.Trigger},
		collide_with = COLLISION_LAYERS_ALL,
	);
	portal_handler.edge_colliders = {
		add_phys_object_aabb(
			pos = {0, -60},
			scale = Vec2 { 20.0, 20.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
		),
		add_phys_object_aabb(
			pos = {0, 60},
			scale = Vec2 { 20.0, 20.0 },
			flags = {.Non_Kinematic}, 
			collision_layers = {.L0},
		),
	};

	portal_handler.teleported_timer = 
		create_named_timer("portal_tp", 1.0, flags={.Update_Automatically});
}
free_portal_handler :: proc() {}

draw_portals :: proc(selected_portal: int) {
	for &portal, i in portal_handler.portals {
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
		if !is_timer_done("portal_tp") do sat = 0;
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
	for &portal, i in portal_handler.portals {
		occupant_id, occupied := portal.occupant.?;

		collided := check_phys_objects_collide(portal.obj, collider);
		if collided && !occupied && is_timer_done("portal_tp") {
			portal.occupant = collider;
			obj := phys_obj(collider);
			portal.occupant_layers = obj.collide_with_layers;
			obj.collide_with_layers = {.L0};
		}
		else {
			if occupied && !collided {
				obj := phys_obj(occupant_id);
				obj.collide_with_layers = portal.occupant_layers;
				portal.occupant = nil;
				set_timer_done("portal_tp");
			}
		}

		if !occupied do continue;

		portal_obj := phys_obj(portal.obj);

		phys_obj(portal_handler.edge_colliders[0]).parent = portal_obj;
		phys_obj(portal_handler.edge_colliders[1]).parent = portal_obj;

		if !is_timer_done("portal_tp") do continue;

		obj := phys_obj(occupant_id);

		to_occupant_centre := obj.pos - phys_obj_centre(portal_obj);
		side := linalg.dot(to_occupant_centre, -transform_forward(portal_obj));

		other_portal := &portal_handler.portals[1 if i == 0 else 0];
		other_portal_obj := phys_obj(other_portal.obj);

		using linalg;
		oportal_mat := other_portal_obj.mat;
		portal_mat := portal_obj.mat;
		obj_mat := obj.mat;

		mirror := Mat4x4 {
			-1, 0,  0, 0,
			0, 1, 	0, 0,
			0, 0, 	1, 0,
			0, 0, 0, 1,
		}

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
			transform_reset_rotation_plane(&ntr);
			obj.local = ntr;
			// setpos(obj, ntr.pos);

			// obj.collide_with_layers = portal.occupant_layers;
			portal.occupant = nil;
		}
		portal.occupant_last_new_pos = ntr.pos;
		portal.occupant_last_side = side;
	}
}