package main;
import rl "thirdparty/raylib";
import "core:math/linalg/hlsl";
import "core:math/linalg";

Physics_Object :: struct {
	using transform: World_Transform,
	vel, acc: Vec2,
	mass: f32,
	flags: Physics_Object_Flagset,
	hitbox: Hitbox,
}

phys_obj_to_rect :: proc(obj: ^Physics_Object) -> Rect {
	return Rect {
		obj.pos.x, obj.pos.y, obj.hitbox.x, obj.hitbox.y,
	};
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic 			= 1 << 0,
	No_Velocity_Dampening 	= 1 << 1,
	No_Collisions 			= 1 << 2,
	No_Gravity				= 1 << 3,
}

Physics_Object_Flagset :: bit_set[Physics_Object_Flag];

Hitbox :: [2]f32;

draw_hitbox_at :: proc(pos: Vec2, box: ^Hitbox) {
	hue := hlsl.fmod_float(linalg.length(box^), 360.0); // holy shit this is cool
	colour := rl.ColorFromHSV(hue, 1.0, 1.0);
	draw_rectangle(pos, cast(Vec2) box^);
}

update_physics_object :: proc(obj_id: int, world: ^Physics_World, dt: f32) {
	obj := &phys_world.objects[obj_id];
	if Physics_Object_Flag.Non_Kinematic in obj.flags {
		return;
	}
	resistance: f32 = 1.0;
	if Physics_Object_Flag.No_Velocity_Dampening not_in obj.flags {
		resistance = 1.0 - ARBITRARY_DRAG_COEFFICIENT;
	}
	
	// if linalg.length(obj.vel) < MINIMUM_VELOCITY_MAGNITUDE do obj.vel = Vec2{};

	next_pos := obj.pos + obj.vel * dt;

	next_vel := (obj.vel + obj.acc * dt) * resistance;

	if Physics_Object_Flag.No_Gravity not_in obj.flags {
		obj.acc = {0, EARTH_GRAVITY} * obj.mass;
	}

	if Physics_Object_Flag.No_Collisions not_in obj.flags {
		for &other_obj, i in world.objects {
			if 
				i == obj_id || Physics_Object_Flag.No_Collisions in other_obj.flags
			{ continue; }

			r1 := transmute(rl.Rectangle) Rect { next_pos.x, next_pos.y, obj.hitbox.x, obj.hitbox.y };
			r2 := transmute(rl.Rectangle) phys_obj_to_rect(&other_obj);
			if rl.CheckCollisionRecs(r1, r2) {
				collision_rect := rl.GetCollisionRec(r1, r2);
				// use obj.pos instead of next_pos so we know where we came from
				move_back := linalg.normalize((obj.pos + obj.hitbox / 2.0) - (other_obj.pos + other_obj.hitbox / 2.0));
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
	}

	delta := next_pos - obj.pos;
	obj.pos = next_pos;
	for &child in obj.transform.children {
		child.pos += delta;
	}
	obj.vel = next_vel;
}

Physics_World :: struct #no_copy {
	objects: [dynamic]Physics_Object,
	// timestep: f32,
}

initialise_phys_world :: proc() {
	phys_world.objects = make([dynamic]Physics_Object, 0, 10);
}

free_phys_world :: proc() {
	delete(phys_world.objects);
}

add_phys_object_aabb :: proc(
	mass:  f32,
	scale: Vec2, 
	pos:   Vec2 = Vec2{},
	vel:   Vec2 = Vec2{},
	acc:   Vec2 = Vec2{},
	parent: ^World_Transform = nil,
	flags: Physics_Object_Flagset = {}
) -> ^Physics_Object 
{
	obj := Physics_Object {
		pos = pos, 
		vel = vel, 
		acc = acc, 
		parent = parent,
		mass = mass, 
		flags = flags, 
		hitbox = cast(Hitbox) scale,
	};
	append(&phys_world.objects, obj);
	return &phys_world.objects[len(phys_world.objects)-1];
}

update_phys_world :: proc(dt: f32) {
	for _, i in phys_world.objects {
		update_physics_object(i, &phys_world, dt);
	}
}