package main;

import "core:log"
import "core:c/libc"
import "core:fmt"
import "core:math"
import rl "thirdparty/raylib"

import b2d "thirdparty/box2d"

import "base:runtime"

Physics_Object_Id :: b2d.BodyId; 
PHYS_OBJ_INVALID :: Physics_Object_Id{}

PHYSICS_TIMESTEP :: f32(1.0/60.0)
PHYSICS_SUBSTEPS :: 2

Collision_Layer :: enum {
	Default,
	Portal_Surface,
	L0, L1,
}
COLLISION_LAYERS_ALL: bit_set[Collision_Layer] : {.Default, .Portal_Surface, .L0, .L1};

PHYS_OBJ_DEFAULT_COLLIDE_WITH :: bit_set[Collision_Layer] { .Default }
PHYS_OBJ_DEFAULT_COLLISION_LAYERS 	  :: bit_set[Collision_Layer] { .Default }

PHYS_OBJ_DEFAULT_FLAGS :: bit_set[Physics_Object_Flag] {}

AABB :: [2]f32;

ColliderType :: enum {
	AABB,
}

Collider :: union {
	AABB,
}

Cache_Collision :: struct {
	trigger: int,
	a, b: Physics_Object_Id,
}

Physics_Object :: struct {
	using local: Transform,
	vel, acc: Vec2,
	mass: f32,
	flags: bit_set[Physics_Object_Flag],
	collider: Collider,
	collision_layers: bit_set[Collision_Layer],
	collide_with_layers: bit_set[Collision_Layer],

	linked_game_object: Maybe(Game_Object_Id),
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic, 			// not updated by physics world
	No_Velocity_Dampening, 	// unaffected by damping
	No_Collisions, 			// doesn't collide
	No_Gravity,				// unaffected by gravity
	Drag_Exception, 		// use drag values for the player 
	Trigger,				// collide but don't physics
	Fixed,					// used outside of the physics world to mark objects as no-touch

	Weigh_Down_Buttons,		// yeah... need to put this somewhere else eventually (bet I will never fix it)
}

Physics :: struct #no_copy {
	world: b2d.WorldId,
	bodies: [dynamic]Physics_Object_Id,
	// objects: [dynamic]Physics_Object,
	initialised: bool,
	// collision_placeholder: Physics_Object_Id, // used for casting rect
	// collisions: [dynamic][2]Physics_Object_Id,
	// prevent collisions after a reinit by adding this to every Phys_Obj_Id
	// and subtracting it on selection
	// generation: int,
	// timestep: f32,
}


initialise_phys_world :: proc() {
	world_def := b2d.DefaultWorldDef() 
	physics.world = b2d.CreateWorld(world_def)

	ground_body_def := b2d.DefaultBodyDef()
	ground_body_def.position = Vec2{0, -10}

	ground_id := b2d.CreateBody(physics.world, ground_body_def)
	append(&physics.bodies, ground_id)

	ground_box := b2d.MakeBox(50, 10)

	ground_shape_def := b2d.DefaultShapeDef()
	_ = b2d.CreatePolygonShape(ground_id, ground_shape_def, ground_box)

	body_def := b2d.DefaultBodyDef()
	body_def.type = b2d.BodyType.dynamicBody
	body_def.position = Vec2{0, 4}
	body_id := b2d.CreateBody(physics.world, body_def)
	log.info(body_id)
	append(&physics.bodies, body_id)

	dynamic_box := b2d.MakeBox(1, 1)
	shape_def := b2d.DefaultShapeDef()
	shape_def.density = 1
	shape_def.material.friction = 0.3

	_ = b2d.CreatePolygonShape(body_id, shape_def, dynamic_box)
	
	// phys_world.objects = make([dynamic]Physics_Object, 0, 10);
	// phys_world.collisions = make([dynamic][2]Physics_Object_Id)
	// phys_world.collision_placeholder = add_phys_object_aabb(
	// 	scale={1, 1},
	// 	flags = {.Non_Kinematic, .Fixed, .Trigger},
	// 	collision_layers = {.Default},
	// )
	// phys_world.initialised = true;
}

b2d_to_rl_pos :: proc(pos: Vec2) -> Vec2 {
	return Vec2{pos.x, -pos.y}
}

rl_pos_to_b2d :: proc(pos: Vec2) -> Vec2 {
	return Vec2{pos.x, -pos.y}
}

draw_phys_world :: proc() {
	MAX_SHAPES :: 2

	shapes := make([]b2d.ShapeId, MAX_SHAPES)

	for body_id in physics.bodies {
		shapes := b2d.Body_GetShapes(body_id, shapes)
		polygon := b2d.Shape_GetPolygon(shapes[0])
		transform := b2d.Body_GetTransform(body_id)
		draw_polygon_convex(transform, vertices = polygon.vertices[:])
		// draw_rectangle(pos, scale={2, 2}, rot= math.atan2(rot.s, rot.c))
	}
}

phys_obj_from_id :: proc(id: Physics_Object_Id) -> (^Physics_Object, bool) #optional_ok {
	log.panicf("update phys system")
	// if len(phys_world.objects) <= cast(int) id - phys_world.generation || cast(int) id - phys_world.generation < 0 || cast(int) id - phys_world.generation == -1 {
	// 	if int(id) <= phys_world.generation {
	// 		return nil, false
	// 		// log.panicf("Physics object that was deleted was used: %i", id)
	// 	}
	// 	else {
	// 		return nil, false
			// log.panicf("invalid phys obj id used: %i", id);
	// 	}
	// }
	// obj := &phys_world.objects[cast(int)id - phys_world.generation];
	// return obj, true;
}

phys_obj_from_index :: proc(index: int) -> (^Physics_Object, bool) #optional_ok {
	log.panicf("update phys system")
	// if len(phys_world.objects) < index || index == -1 do return nil, false;
	// obj := &phys_world.objects[index];
	// return obj, true;
}

phys_obj :: proc{phys_obj_from_id, phys_obj_from_index}

index_to_id :: proc(index: int) -> Physics_Object_Id {
	return PHYS_OBJ_INVALID
	// return Physics_Object_Id(index + phys_world.generation)
}

phys_obj_world_pos :: proc(obj: ^Physics_Object) -> Vec2 {
	return transform_to_world(obj).pos;
}


reinit_phys_world :: proc() {
	// phys_world.generation += len(phys_world.objects)

	// log.infof("Physics world generation: %i", phys_world.generation)

	// clear(&phys_world.objects)
	// clear(&phys_world.collisions)
	// phys_world.collision_placeholder = add_phys_object_aabb(
	// 	scale={1, 1},
	// 	flags = {.Non_Kinematic, .Fixed, .Trigger},
	// 	collision_layers = {.Default},
	// )
	// phys_world.initialised = true;
}

free_phys_world :: proc() {
	b2d.DestroyWorld(physics.world);
	physics.initialised = false;
}

add_phys_object_aabb :: proc(
	mass:  f32 = 0,
	scale: Vec2,
	pos:   Vec2 = Vec2{},
	vel:   Vec2 = Vec2{},
	acc:   Vec2 = Vec2{},
	game_obj: Maybe(Game_Object_Id) = nil,
	parent: ^Transform = nil,
	flags: bit_set[Physics_Object_Flag] = PHYS_OBJ_DEFAULT_FLAGS,
	collision_layers: bit_set[Collision_Layer] = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
	collide_with: bit_set[Collision_Layer] = PHYS_OBJ_DEFAULT_COLLIDE_WITH,
) -> (id: Physics_Object_Id)
{
	local := transform_new(pos, rot=0, parent=parent);
	obj := Physics_Object {
		vel = vel, 
		acc = acc, 
		local = local,
		mass = mass, 
		flags = flags,
		linked_game_object = game_obj,
		collider = cast(AABB) scale,
		collision_layers = collision_layers,
		collide_with_layers = collide_with,
	};

	// id = index_to_id(len(phys_world.objects));
	
	// append(&phys_world.objects, obj);
	id = PHYS_OBJ_INVALID
	
	return;
}

update_phys_world :: proc() {
	b2d.World_Step(physics.world, PHYSICS_TIMESTEP, PHYSICS_SUBSTEPS)

	// previous := make([][2]Physics_Object_Id, len(phys_world.collisions))
	// copy(previous[:], phys_world.collisions[:])
	
	// clear(&phys_world.collisions)

	// cache_next_step_collisions(dt)

	// if len(phys_world.collisions) != len(previous) {
		// for i in 0..<len(phys_world.collisions) {
		// 	// gained an element
		// 	col := phys_world.collisions[i]
		// 	if !slice.contains(previous, col) {
		// 		obj_link, link1 := phys_obj(col[0]).linked_game_object.?
		// 		other_obj_link, link2 := phys_obj(col[1]).linked_game_object.?
		// 		if link1 && link2 {
		// 			game_obj_col_enter(obj_link, other_obj_link, col[0], col[1])
		// 		}
		// 	}
		// }
		// for i in 0..<len(previous) {
		// 	// lost an element
		// 	col := previous[i]
		// 	if !slice.contains(phys_world.collisions[:], col) {
		// 		obj_link, link1 := phys_obj(col[0]).linked_game_object.?
		// 		other_obj_link, link2 := phys_obj(col[1]).linked_game_object.?
		// 		if link1 && link2 {
		// 			game_obj_col_exit(obj_link, other_obj_link, col[0], col[1])
		// 		}
		// 	}
		// }
	// }

	// for _, i in phys_world.objects {
	// 	update_physics_object(i, &phys_world, dt);
	// }
}


phys_obj_grounded :: proc(obj_id: Physics_Object_Id) -> bool { return false}

point_collides_in_world :: proc(point: Vec2, layers: bit_set[Collision_Layer] = COLLISION_LAYERS_ALL, exclude: []Physics_Object_Id = {}, ignore_triggers := true) -> (
	collided_with: Physics_Object_Id = {},
	success: bool = false
)
{
	point := rl_pos_to_b2d(point)
	body: Physics_Object_Id
	// OK, this is weird and complicated, because it seems to be designed by a c++ wizard,
	// this function returns false when it wants to stop the qry,
	// which is what we want bc we just want whatever object it gives us first,
	// and its our job to accumulate the results into an array or a map
	// using the ctx variable. cripes.
	get_res := proc "c" (shape: b2d.ShapeId, data: rawptr) -> bool {
		body := b2d.Shape_GetBody(shape)
		data := cast(^Physics_Object_Id) data
		data ^= body
		return false
	}
	aabb := b2d.AABB {
		lowerBound = point - Vec2(0.1),
		upperBound = point + Vec2(0.1),
	}
	filtre := b2d.DefaultQueryFilter()
	result := b2d.World_OverlapAABB(physics.world, aabb, filtre, fcn = get_res, ctx = &body)
	// result := b2d.World_CastRayClosest(physics.world, point, point, filter = {}) 
	if body != PHYS_OBJ_INVALID {
		return body, true
	}
	return {}, false
}

cast_ray_in_world :: proc(og, dir: Vec2, layers: bit_set[Collision_Layer] = COLLISION_LAYERS_ALL) -> (rl.RayCollision, bool) { return {}, false }

phys_obj_to_rect :: proc(obj: ^Physics_Object) -> Rect { return {} }

draw_phys_obj :: proc(obj_id: Physics_Object_Id, colour: Colour = Colour{}, texture := TEXTURE_INVALID) {}

check_phys_objects_collide :: proc(obj1id, obj2id: Physics_Object_Id, first_set_pos := MARKER_VEC2) -> bool { return false }

phys_obj_centre :: proc(obj: ^Physics_Object) -> Vec2 {
	pos := phys_obj_world_pos(obj);
	return pos;
}

cast_box_in_world :: proc(centre, dimensions: Vec2, rot: Rad, exclude: []Physics_Object_Id = {}, layers := COLLISION_LAYERS_ALL) -> bool { return false }
