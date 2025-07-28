package main;
import rl "thirdparty/raylib";
import rlgl "thirdparty/raylib/rlgl";
import "core:math/linalg/hlsl";
import "core:math/linalg";
import "core:math";

import "core:fmt";


EARTH_GRAVITY :: 5.0;
// terminal velocity = sqrt((gravity * mass) / (drag coeff))
ARBITRARY_DRAG_COEFFICIENT :: 0.01;

// terrible name, basically how much should two rectangles be overlapping 
// in order for the collision to trip over into slowing down the collider
// this exists to make moving along surfaces smoother
COLLISION_OVERLAP_FOR_BRAKING_THRESHOLD :: Vec2 { 0.01, 0.1 };

// TODO: distinct
Physics_Object_Id :: int; 
Collision_Layer :: enum {
	Default, Trigger, L0, L1,
}
COLLISION_LAYERS_ALL: bit_set[Collision_Layer] : {.Default, .Trigger, .L0, .L1};

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
	collision_layers: bit_set[Collision_Layer],
	collide_with_layers: bit_set[Collision_Layer],
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
	Fixed,					// used outside of the physics world to mark objects as no-touch
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
		val := hlsl.fmod_float(f32(obj_id) * 10, 360.0); // holy shit this is cool
		dcolour = transmute(Colour) rl.ColorFromHSV(1.0, 0.1, val);
	}
	else {
		dcolour = colour;
	}
	switch co in obj.collider {
	case AABB:
		w_rect := aabb_obj_to_world_rect(obj);
		draw_rectangle(w_rect.xy, w_rect.zw, col=dcolour);
		world := transform_to_world(obj);
		// draw_rectangle(obj.pos - co/2, co);
		// box := phys_obj_bounding_box(obj);
		// draw_rectangle(world.pos - box.zw / 2, box.zw, col=dcolour);
		// draw_rectangle_transform(&world, phys_obj_to_rect(obj));
		// draw_rectangle(world.pos, cast(Vec2) obj.hitbox, rot=linalg.to_degrees(world.rot), col=dcolour);
		// fwd arrow
		centre := phys_obj_centre(obj);
		end := centre + transform_forward(&world) * 50;
		draw_line(centre, end);
		// right arrow
		end = centre + transform_right(&world) * 50;
		draw_line(centre, end, colour=Colour{0, 255, 0, 255});
	}
}

phys_obj_local_centre :: proc(obj: ^Physics_Object) -> Vec2 {
	return obj.pos;
}

phys_obj_centre :: proc(obj: ^Physics_Object) -> Vec2 {
	pos := phys_obj_world_pos(obj);
	return pos;
}

phys_obj_to_vertices :: proc(obj: ^Physics_Object) -> []Vec2 {
	switch collider in obj.collider {
	case AABB:
		slice := make([]Vec2, 4);
		local_transform := transform_to_world(obj);
		setpos(&local_transform, Vec2{});
		rect := Rect {0, 0, collider.x, collider.y};
		vertices := rect_to_points(rect);
		for &vert in vertices {
			vert -= rect.zw / 2;
			vert = transform_point(&local_transform, vert);
		}
		for item,i in vertices do slice[i] = item;
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
	if obj1.collide_with_layers & obj2.collision_layers == {} do return false;
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

check_phys_object_point_collide :: proc(obj_id: Physics_Object_Id, point: Vec2, layers: bit_set[Collision_Layer] = COLLISION_LAYERS_ALL) -> bool {
	obj := phys_obj(obj_id);
	if .No_Collisions in obj.flags do return false;
	if layers & obj.collision_layers == {} do return false;
	ty := phys_obj_collider_ty(obj);
	switch ty {
	case .AABB:
		return rl.CheckCollisionPointRec(
			transmute(rl.Vector2) point, 
			transmute(rl.Rectangle) aabb_obj_to_world_rect(obj)
		);
	}

	unreachable();
}

cast_ray_in_world :: proc(og, dir: Vec2, layers: bit_set[Collision_Layer] = COLLISION_LAYERS_ALL) -> (rl.RayCollision, bool) {
	closest: rl.RayCollision;
	closest.distance = math.F32_MAX;
	for i in 0..<len(phys_world.objects) {
		obj := phys_obj(i);
		if layers & obj.collision_layers == {} do continue;
		switch _ in obj.collider {
		case AABB:
			box := phys_obj_bounding_box(obj);
			box.xy += phys_obj_world_pos(obj);
			min := Vec3{ box.x, box.y, 0};
			max := min + Vec3 { box.z, box.w, 10};
			bb := rl.BoundingBox {
				min = min,
				max = max,
			}
			ray := rl.Ray { 
				position = rl.Vector3 { og.x, og.y, 5 }, 
				direction = rl.Vector3 { dir.x, dir.y, 0 }, 
			};
			col := rl.GetRayCollisionBox(ray, bb);
			if col.hit && col.distance < closest.distance do closest = col;
		}
	}
	return closest, closest.hit;
}

point_collides_in_world :: proc(point: Vec2, layers: bit_set[Collision_Layer] = COLLISION_LAYERS_ALL) -> (
	collided_with: ^Physics_Object = nil, 
	collided_with_id: Physics_Object_Id = -1,
	success: bool = false
)
{
	for i in 0..<len(phys_world.objects) {
		if check_phys_object_point_collide(i, point, layers) {
			collided_with = phys_obj(i);
			collided_with_id = i;
			success = true;
			return;
		}
	}
	return;
}

get_first_collision_in_world :: proc(obj_id: Physics_Object_Id, set_pos: Vec2 = MARKER_VEC2) -> (rl.Rectangle, ^Physics_Object, bool) {
	obj := phys_obj(obj_id);
	if .No_Collisions in obj.flags do return rl.Rectangle{}, nil, false;
	for &other_obj, i in phys_world.objects {
		if 
			i == obj_id || Physics_Object_Flag.No_Collisions in other_obj.flags
		{ continue; }
		if obj.collide_with_layers & other_obj.collision_layers == {} do continue;

		pos: Vec2;
		if set_pos == MARKER_VEC2 do pos = transform_to_world(obj).pos;
		else {
			pos = set_pos;
		}
		obj_rect := aabb_obj_to_world_rect(obj);
		obj_rect.xy = pos - obj_rect.zw / 2;

		r1 := transmute(rl.Rectangle) obj_rect;
		r2 := transmute(rl.Rectangle) aabb_obj_to_world_rect(&other_obj);
		if check_phys_objects_collide(obj_id, i) {
			collision_rect := rl.GetCollisionRec(r1, r2);
			return collision_rect, &other_obj, true;
		}
	}
	return rl.Rectangle{}, nil, false;
}

update_physics_object :: proc(obj_id: int, world: ^Physics_World, dt: f32) {
	obj := phys_obj(obj_id);
	pos := transform_to_world(obj).pos;
	if Physics_Object_Flag.Non_Kinematic in obj.flags || .Trigger in obj.collision_layers {
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
		if ok && .Trigger not_in other_obj.collision_layers {
			other_pos := transform_to_world(other_obj).pos;
			// use obj.pos instead of next_pos so we know where we came from
			obj_centre := phys_obj_centre(obj);
			other_obj_centre := phys_obj_centre(other_obj);
			move_back := linalg.normalize(obj_centre - other_obj_centre);
			// choose the smallest of the two coordinates to move back by
			if collision_rect.width > collision_rect.height {
				sign := -1.0 if move_back.y < 0.0 else f32(1.0);
				move_back.y = collision_rect.height * sign;
				if collision_rect.height > COLLISION_OVERLAP_FOR_BRAKING_THRESHOLD.y {
					other_obj.vel.y = ( next_vel.y * obj.mass ) / other_obj.mass;
					next_vel.y = 0; //-next_vel.y;
				}

				move_back.x = 0.0;
			}
			else {
				sign := -1.0 if move_back.x < 0.0 else f32(1.0);
				move_back.x = collision_rect.width * sign;
				if collision_rect.width > COLLISION_OVERLAP_FOR_BRAKING_THRESHOLD.x {
					other_obj.vel.x = ( next_vel.x * obj.mass ) / other_obj.mass;
					next_vel.x = 0; //-next_vel.x;
				}

				move_back.y = 0.0;
			}
			next_pos += move_back;
		}
	}

	setpos(obj, next_pos); // TODO: doesn't work if parented
	obj.vel = next_vel;
}

phys_obj_grounded :: proc(obj_id: int) -> bool {
	ok: bool;
	obj := phys_obj(obj_id);
	centre := phys_obj_centre(obj);
	centre.y += phys_obj_bounding_box(obj).w;
	// draw_rectangle(centre, Vec2(10), col=Colour{0, 255, 255, 255});
	_, _, ok = point_collides_in_world(centre, layers = {.Default} );
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
	flags: bit_set[Physics_Object_Flag] = {},
	collision_layers: bit_set[Collision_Layer] = {.Default},
	collide_with: bit_set[Collision_Layer] = {.Default, .Trigger},
) -> (id: Physics_Object_Id)
{
	local := transform_new(pos, rot=0, parent=parent);
	obj := Physics_Object {
		vel = vel, 
		acc = acc, 
		local = local,
		mass = mass, 
		flags = flags,
		collider = cast(AABB) scale,
		collision_layers = collision_layers,
		collide_with_layers = collide_with,
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