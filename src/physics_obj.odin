package main;
import rl "thirdparty/raylib";
import "core:math/linalg/hlsl";
import "core:math/linalg";


EARTH_GRAVITY :: 5.0;
// terminal velocity = sqrt((gravity * mass) / (drag coeff))
ARBITRARY_DRAG_COEFFICIENT :: 0.01;

// TODO: distinct
Physics_Object_Id :: int; 

Physics_Object :: struct {
	using local: Transform,
	vel, acc: Vec2,
	mass: f32,
	flags: bit_set[Physics_Object_Flag],
	hitbox: Hitbox,
}

phys_obj :: proc(id: Physics_Object_Id) -> (^Physics_Object, bool) #optional_ok {
	if len(phys_world.objects) < cast(int) id || cast(int) id == -1 do return nil, false;
	obj := &phys_world.objects[cast(int)id];
	// obj.world = transform_to_world(obj.transform);
	return obj, true;
}

phys_obj_to_world_rect :: proc(obj: ^Physics_Object) -> Rect {
	pos := transform_to_world(obj).pos;
	return Rect {
		pos.x, pos.y, obj.hitbox.x, obj.hitbox.y,
	};
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic, 			// not updated by physics world
	No_Velocity_Dampening, 	// unaffected by damping
	No_Collisions, 			// doesn't collide
	No_Gravity,				// unaffected by gravity
	Drag_Exception, 		// use drag values for the player 
	Trigger, 				// just used for checking collision
}

Hitbox :: [2]f32;

draw_hitbox_at :: proc(pos: Vec2, box: ^Hitbox) {
	hue := hlsl.fmod_float(linalg.length(box^), 360.0); // holy shit this is cool
	colour := rl.ColorFromHSV(hue, 1.0, 1.0);
	draw_rectangle(pos, cast(Vec2) box^);
}

draw_phys_obj :: proc(obj_id: Physics_Object_Id, colour: Colour = Colour{}) {
	obj := phys_obj(obj_id);
	dcolour: Colour;
	if colour == {} {
		val := hlsl.fmod_float(cast(f32)obj_id * 1000 - cast(f32)obj_id * 109100 + 1023952094, 360.0); // holy shit this is cool
		dcolour = transmute(Colour) rl.ColorFromHSV(1.0, 0.1, val);
	}
	else {
		dcolour = colour;
	}
	world := transform_to_world(obj);
	rl.DrawPoly()
	draw_rectangle(world.pos, cast(Vec2) obj.hitbox, rot=linalg.to_degrees(world.rot), col=dcolour);
}

point_collides_in_world :: proc(point: Vec2, count_triggers: bool = false) -> (
	collided_with: ^Physics_Object = nil, 
	collided_with_id: Physics_Object_Id = -1,
	success: bool = false
) 
{
	for &other_obj, i in phys_world.objects {
		if Physics_Object_Flag.No_Collisions in other_obj.flags do continue;
		if !count_triggers && .Trigger in other_obj.flags do continue;

		if rl.CheckCollisionPointRec(transmute(rl.Vector2) point, transmute(rl.Rectangle) phys_obj_to_world_rect(&other_obj)) {
			collided_with = &other_obj;
			collided_with_id = i;
			success = true;
			return;
		}
	}
	return;
}

get_first_collision_in_world :: proc(obj_id: Physics_Object_Id, set_pos: Vec2 = MARKER_VEC2, count_triggers: bool = false) -> (rl.Rectangle, ^Physics_Object, bool) {
	obj := phys_obj(obj_id);
	if .No_Collisions in obj.flags do return rl.Rectangle{}, nil, false;
	for &other_obj, i in phys_world.objects {
		if 
			i == obj_id || Physics_Object_Flag.No_Collisions in other_obj.flags
		{ continue; }
		if !count_triggers && .Trigger in other_obj.flags do continue;

		pos: Vec2;
		if set_pos == MARKER_VEC2 do pos = transform_to_world(obj).pos;
		else do pos = set_pos;
		r1 := transmute(rl.Rectangle) Rect { pos.x, pos.y, obj.hitbox.x, obj.hitbox.y };
		r2 := transmute(rl.Rectangle) phys_obj_to_world_rect(&other_obj);
		if rl.CheckCollisionRecs(r1, r2) {
			collision_rect := rl.GetCollisionRec(r1, r2);
			return collision_rect, &other_obj, true;
		}
	}
	return rl.Rectangle{}, nil, false;
}

get_collision_between_objs_in_world :: proc(obj_id: Physics_Object_Id, other_obj_id: Physics_Object_Id) -> (rl.Rectangle, bool) {
	obj := phys_obj(obj_id);
	other_obj := phys_obj(other_obj_id);

	if .No_Collisions in obj.flags 			do return rl.Rectangle{}, false;
	if .No_Collisions in other_obj.flags 	do return rl.Rectangle{}, false;
	r1 := transmute(rl.Rectangle) phys_obj_to_world_rect(obj);
	r2 := transmute(rl.Rectangle) phys_obj_to_world_rect(other_obj);
	if rl.CheckCollisionRecs(r1, r2) {
		collision_rect := rl.GetCollisionRec(r1, r2);
		return collision_rect, true;
	}
	else do return rl.Rectangle{}, false;
}

update_physics_object :: proc(obj_id: int, world: ^Physics_World, dt: f32) {
	obj := phys_obj(obj_id);
	pos := transform_to_world(obj).pos;
	if Physics_Object_Flag.Non_Kinematic in obj.flags || .Trigger in obj.flags {
		return;
	}
	resistance: Vec2 = Vec2 {1.0, 1.0};
	if Physics_Object_Flag.No_Velocity_Dampening not_in obj.flags {
		resistance.x = 1.0 - ARBITRARY_DRAG_COEFFICIENT;
		resistance.y = 1.0 - ARBITRARY_DRAG_COEFFICIENT;
	}
	if .Drag_Exception in obj.flags {
		resistance.x = 0.98;
		resistance.y = 0.99;
	}
	
	// if linalg.length(obj.vel) < MINIMUM_VELOCITY_MAGNITUDE do obj.vel = Vec2{};

	next_pos := pos + obj.vel * dt;

	next_vel := (obj.vel + obj.acc * dt) * resistance;

	if Physics_Object_Flag.No_Gravity not_in obj.flags {
		obj.acc = {0, EARTH_GRAVITY} * obj.mass;
	}

	if Physics_Object_Flag.No_Collisions not_in obj.flags {
		collision_rect, other_obj, ok := get_first_collision_in_world(obj_id, set_pos = next_pos);
		if ok {
			other_pos := transform_to_world(other_obj).pos;
			// use obj.pos instead of next_pos so we know where we came from
			move_back := linalg.normalize((pos + obj.hitbox / 2.0) - (other_pos + other_obj.hitbox / 2.0));
			// choose the smallest of the two coordinates to move back by
			if collision_rect.width > collision_rect.height {
				sign := -1.0 if move_back.y < 0.0 else f32(1.0);
				move_back.y = collision_rect.height * sign;
				next_vel.y = -next_vel.y;

				move_back.x = 0.0;
			}
			else {
				sign := -1.0 if move_back.x < 0.0 else f32(1.0);
				move_back.x = collision_rect.width * sign;
				next_vel.x = -next_vel.x;

				move_back.y = 0.0;
			}
			next_pos += move_back;
		}
	}

	delta := next_pos - pos;
	obj.pos = world_pos_to_local(obj, next_pos);
	// for &child in obj.transform.children {
	// 	child.pos += delta;
	// }
	obj.vel = next_vel;
}

// TODO: naïve assumption that an object is grounded if it touches something...
phys_obj_grounded :: proc(obj_id: int) -> bool {
	ok: bool;
	obj := phys_obj(obj_id);
	pos := transform_to_world(obj).pos;
	// man this is amazing, i didn't even mean for this to be possible
	centre := pos + obj.hitbox / 2;
	centre.y += obj.hitbox.y;
	_, _, ok = point_collides_in_world(centre);
	return ok;
}

Physics_World :: struct #no_copy {
	objects: [dynamic]Physics_Object,
	initialised: bool,
	// timestep: f32,
}

initialise_phys_world :: proc() {
	phys_world.objects = make([dynamic]Physics_Object, 0, 10);
	phys_world.initialised = true;
}

free_phys_world :: proc() {
	delete(phys_world.objects);
	phys_world.initialised = false;
}

add_phys_object_aabb :: proc(
	mass:  f32 = 0,
	scale: Vec2,
	pos:   Vec2 = Vec2{},
	vel:   Vec2 = Vec2{},
	acc:   Vec2 = Vec2{},
	parent: ^Transform = nil,
	flags: bit_set[Physics_Object_Flag] = {}
) -> (id: Physics_Object_Id)
{
	obj := Physics_Object {
		vel = vel, 
		acc = acc, 
		local = {
			pos = pos,
			parent = parent,			
		},
		mass = mass, 
		flags = flags, 
		hitbox = cast(Hitbox) scale,
	};

	id = len(phys_world.objects);
	
	append(&phys_world.objects, obj);
	
	return;
}

update_phys_world :: proc(dt: f32) {
	for _, i in phys_world.objects {
		update_physics_object(i, &phys_world, dt);
	}
}