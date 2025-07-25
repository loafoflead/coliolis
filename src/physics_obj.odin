package main;
import rl "thirdparty/raylib";
import rlgl "thirdparty/raylib/rlgl";
import "core:math/linalg/hlsl";
import "core:math/linalg";
import "core:math";


EARTH_GRAVITY :: 5.0;
// terminal velocity = sqrt((gravity * mass) / (drag coeff))
ARBITRARY_DRAG_COEFFICIENT :: 0.01;

// TODO: distinct
Physics_Object_Id :: int; 

AABB :: [2]f32;

ColliderType :: enum {
	AABB,
}

Collider :: union {
	AABB,
}

Physics_Object :: struct {
	using local: Transform,
	vel, acc: Vec2,
	mass: f32,
	flags: bit_set[Physics_Object_Flag],
	collider: Collider,
}


phys_obj :: proc(id: Physics_Object_Id) -> (^Physics_Object, bool) #optional_ok {
	if len(phys_world.objects) < cast(int) id || cast(int) id == -1 do return nil, false;
	obj := &phys_world.objects[cast(int)id];
	// obj.world = transform_to_world(obj.transform);
	return obj, true;
}

phys_obj_world_pos :: proc(obj: ^Physics_Object) -> Vec2 {
	return transform_to_world(obj).pos;
}

phys_obj_collider_ty :: proc(obj: ^Physics_Object) -> ColliderType {
	switch _t in obj.collider {
	case AABB:
		return ColliderType.AABB;
	}
	unreachable();
}

phys_obj_id_collider_ty :: proc(obj_id: Physics_Object_Id) -> ColliderType {
	obj := phys_obj(obj_id);
	return phys_obj_collider_ty(obj);
}

aabb_obj_to_world_rect :: proc(obj: ^Physics_Object) -> Rect {
	pos := transform_to_world(obj).pos;
	switch collider in obj.collider {
	case AABB:
		world := transform_to_world(obj);
		box := phys_obj_bounding_box(obj);
		box.xy += world.pos;
		return box;
	case:
		unreachable();
		// unimplemented("implement colliders other than AABB");
	}
}

phys_obj_to_rect :: proc(obj: ^Physics_Object) -> Rect {
	switch collider in obj.collider {
	case AABB:
		rect := Rect {0,0, collider.x, collider.y};
		return rect;
	case:
		unreachable();
		// unimplemented("implement colliders other than AABB");
	}
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic, 			// not updated by physics world
	No_Velocity_Dampening, 	// unaffected by damping
	No_Collisions, 			// doesn't collide
	No_Gravity,				// unaffected by gravity
	Drag_Exception, 		// use drag values for the player 
	Trigger, 				// just used for checking collision
}

draw_hitbox_at :: proc(pos: Vec2, box: ^AABB) {
	hue := hlsl.fmod_float(linalg.length(box^), 360.0); // holy shit this is cool
	colour := rl.ColorFromHSV(hue, 1.0, 1.0);
	draw_rectangle(pos, cast(Vec2) box^);
}

draw_phys_obj :: proc(obj_id: Physics_Object_Id, colour: Colour = Colour{}) {
	obj := phys_obj(obj_id);
	dcolour: Colour;
	if colour == {} {
		val := hlsl.fmod_float(cast(f32)obj_id * 1049209430 - cast(f32)obj_id * 109100 + 1023952094, 360.0); // holy shit this is cool
		dcolour = transmute(Colour) rl.ColorFromHSV(1.0, 0.1, val);
	}
	else {
		dcolour = colour;
	}
	switch _ in obj.collider {
	case AABB:
		world := transform_to_world(obj);
		box := phys_obj_bounding_box(obj);
		draw_rectangle(world.pos + box.xy, box.zw, col=dcolour);
		// draw_rectangle_transform(&world, phys_obj_to_rect(obj));
		// draw_rectangle(world.pos, cast(Vec2) obj.hitbox, rot=linalg.to_degrees(world.rot), col=dcolour);
	}
}

phys_obj_local_centre :: proc(obj: ^Physics_Object) -> Vec2 {
	// pos := phys_obj_world_pos(obj);
	switch collider in obj.collider {
	case AABB:
		bb := phys_obj_bounding_box(obj);
		return bb.xy + bb.zw / 2;
	}
	unreachable();
}

phys_obj_centre :: proc(obj: ^Physics_Object) -> Vec2 {
	// pos := phys_obj_world_pos(obj);
	switch collider in obj.collider {
	case AABB:
		bb := aabb_obj_to_world_rect(obj);
		return bb.xy + bb.zw / 2;
	}
	unreachable();
}

phys_obj_to_vertices :: proc(obj: ^Physics_Object) -> []Vec2 {
	switch collider in obj.collider {
	case AABB:
		slice := make([]Vec2, 4);
		local_transform := transform_to_world(obj);
		local_transform.pos = Vec2{};
		rect := Rect {0, 0, collider.x, collider.y};
		rect = transform_rect(&local_transform, rect);
		array := rect_to_points(rect);
		for item,i in array do slice[i] = item;
		return slice;
	}
	unreachable();
}

// TODO: make this a field of physics_object that updates automatically
// when collider gets changed
phys_obj_bounding_box :: proc(obj: ^Physics_Object) -> Rect {
	verts := phys_obj_to_vertices(obj);
	defer delete(verts);
	min_x, min_y, max_x, max_y: f32;
	for vert in verts {
		min_x = math.min(vert.x, min_x);
		min_y = math.min(vert.y, min_y);
		max_x = math.max(vert.x, max_x);
		max_y = math.max(vert.y, max_y);
	}
	return Rect {
		min_x, min_y, 
		max_x - min_x, max_y - min_y,
	}
}

rects_collision_check :: proc(a, b: Rect) -> bool {
	return rl.CheckCollisionRecs(transmute(rl.Rectangle) a, transmute(rl.Rectangle) b);
}

check_phys_objects_collide :: proc(obj1id, obj2id: Physics_Object_Id) -> bool {
	obj1 := phys_obj(obj1id);
	obj2 := phys_obj(obj2id);
	ty1 := phys_obj_collider_ty(obj1);
	ty2 := phys_obj_collider_ty(obj2);
	if ty1 == ty2 {
		switch ty1 {
		case .AABB:
			return rects_collision_check(aabb_obj_to_world_rect(obj1), aabb_obj_to_world_rect(obj2));
		}
	}
	else {
		unimplemented("diff colliding objects");
	}
	unreachable();
}

check_phys_object_point_collide :: proc(obj_id: Physics_Object_Id, point: Vec2) -> bool {
	obj := phys_obj(obj_id);
	if .No_Collisions in obj.flags do return false;
	ty := phys_obj_collider_ty(obj);
	switch ty {
	case .AABB:
		return rl.CheckCollisionPointRec(transmute(rl.Vector2) point, transmute(rl.Rectangle) aabb_obj_to_world_rect(obj))
	}

	unreachable();
}

point_collides_in_world :: proc(point: Vec2, count_triggers: bool = false) -> (
	collided_with: ^Physics_Object = nil, 
	collided_with_id: Physics_Object_Id = -1,
	success: bool = false
)
{
	for i in 0..<len(phys_world.objects) {
		obj := phys_obj(i);
		if Physics_Object_Flag.No_Collisions in obj.flags do continue;
		if !count_triggers && .Trigger in obj.flags do continue;

		if check_phys_object_point_collide(i, point) {
			collided_with = obj;
			collided_with_id = i;
			success = true;
			return;
		}
	}
	return;
}

get_first_collision_in_world :: proc(obj_id: Physics_Object_Id, set_pos: Vec2 = MARKER_VEC2, count_triggers: bool = false) -> (rl.Rectangle, ^Physics_Object, Physics_Object_Id, bool) {
	obj := phys_obj(obj_id);
	if .No_Collisions in obj.flags do return rl.Rectangle{}, nil, -1, false;
	for &other_obj, i in phys_world.objects {
		if 
			i == obj_id || Physics_Object_Flag.No_Collisions in other_obj.flags
		{ continue; }
		if !count_triggers && .Trigger in other_obj.flags do continue;

		pos: Vec2;
		if set_pos == MARKER_VEC2 do pos = transform_to_world(obj).pos;
		else do pos = set_pos;
		obj_rect := phys_obj_to_rect(obj);
		obj_rect.xy = pos.xy;
		r1 := transmute(rl.Rectangle) obj_rect;
		r2 := transmute(rl.Rectangle) aabb_obj_to_world_rect(&other_obj);
		if check_phys_objects_collide(obj_id, i) {
			collision_rect := rl.GetCollisionRec(r1, r2);
			return collision_rect, &other_obj, i, true;
		}
	}
	return rl.Rectangle{}, nil, -1, false;
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
		collision_rect, other_obj, other_id, ok := get_first_collision_in_world(obj_id, set_pos = next_pos);
		if ok {
			other_pos := transform_to_world(other_obj).pos;
			// use obj.pos instead of next_pos so we know where we came from
			obj_centre := phys_obj_centre(obj);
			other_obj_centre := phys_obj_centre(other_obj);
			move_back := linalg.normalize(obj_centre - other_obj_centre);
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

phys_obj_grounded :: proc(obj_id: int) -> bool {
	ok: bool;
	obj := phys_obj(obj_id);
	centre := phys_obj_centre(obj);
	centre.y += phys_obj_bounding_box(obj).w;
	// draw_rectangle(centre, Vec2(10), col=Colour{0, 255, 255, 255});
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
		collider = cast(AABB) scale, 
		// hitbox = cast(Hitbox) scale,
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