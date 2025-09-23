package main;

// https://www.iforce2d.net/b2dtut/sensors


import "core:log"
import "core:c/libc"
import "core:math/linalg"
import "core:slice"
import vmem "core:mem/virtual"

import b2d "thirdparty/box2d"

import "base:runtime"

import "core:c"

import "rendering"
import "transform"

Rad :: transform.Rad

// BINDINGS 
// Get the touching contact data for a shape. The provided shapeId will be either shapeIdA or shapeIdB on the contact data.

// i'm going to leave this here, because it's possibly the dumbest thing in the universe
// a function which, when the shape provided is a sensor, will return every single collision 
// that sensor has, with *other senors*.
// there is also a function that returns the shape's collisions with normal colliders, which is
// disabled for sensors.
// pure, genius
@(require_results)
Shape_GetSensorOverlaps :: proc "c" (shapeId: b2d.ShapeId, shapes_buf: []b2d.ShapeId) -> []b2d.ShapeId {
	n := b2d.Shape_GetSensorOverlaps(shapeId, raw_data(shapes_buf), c.int(len(shapes_buf)))
	return shapes_buf[:n]
}
// 

Physics_Object_Id :: b2d.BodyId; 
PHYS_OBJ_INVALID :: Physics_Object_Id{}

PHYSICS_TIMESTEP :: f32(1.0/60.0)
PHYSICS_SUBSTEPS :: 4

DEFAULT_FRICTION :: f32(0.4)

PIXELS_PER_METRE :: 32
PIXELS_TO_METRES_RATIO :: f64(1.0/f64(PIXELS_PER_METRE))

GRAVITY :: Vec2{0, -10}

Collision_Layer :: enum u64 {
	Default,
	Portal_Surface,
	L0, L1,
	Player,
}
Collision_Set :: bit_set[Collision_Layer; u64]
COLLISION_LAYERS_ALL: bit_set[Collision_Layer; u64] : {.Default, .Player, .Portal_Surface, .L0, .L1};

PHYS_OBJ_DEFAULT_COLLIDE_WITH :: bit_set[Collision_Layer; u64] { .Default }
PHYS_OBJ_DEFAULT_COLLISION_LAYERS 	  :: bit_set[Collision_Layer; u64] { .Default }

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

Phys_Collide_Callback :: #type proc(self, collided: Physics_Object_Id, self_shape, other_shape: b2d.ShapeId)

Phys_Body_Data :: struct {
	game_object: Maybe(Game_Object_Id),
	transform: Transform,
	on_collision_enter: Phys_Collide_Callback,
	on_collision_exit: Phys_Collide_Callback,
	// TODO: on_collide_enter callback?
}

Ray_Collision :: struct {
	point: Vec2,
	normal: Vec2,
	obj_id: Physics_Object_Id,
}

Physics_Object_Flag :: enum u32 {
	Non_Kinematic, 			// not updated by physics world (b2d.staticBody)
	Non_Dynamic, 			// solved but no forces applied by physics world (b2d.kinematicBody)
	No_Velocity_Dampening, 	// unaffected by damping
	No_Collisions, 			// doesn't collide
	No_Gravity,				// unaffected by gravity
	Drag_Exception, 		// use drag values for the player 
	Trigger,				// collide but don't physics
	Fixed,					// used outside of the physics world to mark objects as no-touch
	Invisible_To_Triggers,  // self explanatory...(?)
	Fixed_Rotation,			// no rotation
	Never_Sleep,			// never sleep

	Weigh_Down_Buttons,		// yeah... need to put this somewhere else eventually (bet I will never fix it)
}

Physics :: struct #no_copy {
	world: b2d.WorldId,
	bodies: [dynamic]Physics_Object_Id,

	arena: vmem.Arena,
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
	arena := vmem.arena_allocator(&physics.arena)

	world_def := b2d.DefaultWorldDef() 
	world_def.gravity = GRAVITY
	world_def.enableContinuous = true
	physics.world = b2d.CreateWorld(world_def)

	physics.bodies = make([dynamic]Physics_Object_Id, allocator = arena)

	// add_phys_object_aabb(pos = {0, -10}, scale={50, 10}, flags = {.Non_Kinematic})
	// add_phys_object_aabb(pos = {0, 4}, scale={1, 1}, flags = {})

	// ground_body_def := b2d.DefaultBodyDef()
	// ground_body_def.position = Vec2{0, -10}

	// ground_id := b2d.CreateBody(physics.world, ground_body_def)
	// append(&physics.bodies, ground_id)

	// ground_box := b2d.MakeBox(50, 10)

	// ground_shape_def := b2d.DefaultShapeDef()
	// _ = b2d.CreatePolygonShape(ground_id, ground_shape_def, ground_box)

	// body_def := b2d.DefaultBodyDef()
	// body_def.type = b2d.BodyType.dynamicBody
	// body_def.position = Vec2{0, 4}
	// body_id := b2d.CreateBody(physics.world, body_def)
	// log.info(body_id)
	// append(&physics.bodies, body_id)

	// dynamic_box := b2d.MakeBox(1, 1)
	// shape_def := b2d.DefaultShapeDef()
	// shape_def.density = 1
	// shape_def.material.friction = 0.3
	// shape_def.enableSensorEvents = true
	// log.info(shape_def)

	// _ = b2d.CreatePolygonShape(body_id, shape_def, dynamic_box)
	
	// phys_world.objects = make([dynamic]Physics_Object, 0, 10);
	// phys_world.collisions = make([dynamic][2]Physics_Object_Id)
	// phys_world.collision_placeholder = add_phys_object_aabb(
	// 	scale={1, 1},
	// 	flags = {.Non_Kinematic, .Fixed, .Trigger},
	// 	collision_layers = {.Default},
	// )
	physics.initialised = true;
}

reinit_phys_world :: proc() {
	old := physics.world
	vmem.arena_free_all(&physics.arena)
	
	arena := vmem.arena_allocator(&physics.arena)

	world_def := b2d.DefaultWorldDef()
	world_def.gravity = GRAVITY
	world_def.enableContinuous = true
	// TODO: delete the old one? check if it increments the generation
	physics.world = b2d.CreateWorld(world_def)
	b2d.DestroyWorld(old)

	physics.bodies = make([dynamic]Physics_Object_Id, allocator = arena)
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

b2d_to_rl_pos :: proc(pos: Vec2) -> Vec2 {
	return Vec2{f32(f64(pos.x) / PIXELS_TO_METRES_RATIO), -f32(f64(pos.y) / PIXELS_TO_METRES_RATIO)}
}

rl_to_b2d_pos :: proc(pos: Vec2) -> Vec2 {
	return Vec2{f32(f64(pos.x) * PIXELS_TO_METRES_RATIO), -f32(f64(pos.y) * PIXELS_TO_METRES_RATIO)}
}

rl_to_b2_facing :: proc(facing: Vec2) -> b2d.Rot {
	return {facing.x, -facing.y}
}

b2_to_rl_facing :: proc(facing: b2d.Rot) -> Vec2 {
	return {facing.c, -facing.s}
} 

draw_phys_world :: proc() {
	MAX_SHAPES :: 2

	shapes := make([]b2d.ShapeId, MAX_SHAPES)
	defer delete(shapes)

	for body_id in physics.bodies {
		draw_phys_obj(body_id)
		// shapes := b2d.Body_GetShapes(body_id, shapes)
		// polygon := b2d.Shape_GetPolygon(shapes[0])
		// transform := b2d.Body_GetTransform(body_id)
		// draw_polygon_convex(transform, vertices = polygon.vertices[:])
		// draw_line(rl_to_b2d_pos(transform.p), rl_to_b2d_pos(transform.p) + transmute(Vec2)transform.q / camera.zoom * 50, Colour{2..<4=255})
		// right := linalg.matrix2_rotate_f32(linalg.PI/2) * transmute(Vec2)transform.q
		// draw_line(rl_to_b2d_pos(transform.p), rl_to_b2d_pos(transform.p) + right / camera.zoom * 50, Colour{1=255, 3 = 255})
		// draw_rectangle(pos, scale={2, 2}, rot= math.atan2(rot.s, rot.c))
	}
}

phys_obj_gobj_typed :: proc(id: Physics_Object_Id, $T: typeid) -> (gobj: ^T, game_object: ^Game_Object) {
	data := phys_obj_data(id)
	ok: bool
	gobj_id, found := data.game_object.?
	assert(found, "mistyped game object request")

	gobj, ok = game_obj(gobj_id, T)
	game_object, ok = game_obj(gobj_id)

	return
}

phys_obj_gobj_untyped :: proc(id: Physics_Object_Id) -> (game_object: ^Game_Object, ok: bool) #optional_ok {
	data := phys_obj_data(id) or_return
	gobj_id, found := data.game_object.?
	assert(found, "nonexistent gobj")

	game_object, ok = game_obj(gobj_id)

	return
}

phys_obj_gobj :: proc{phys_obj_gobj_typed, phys_obj_gobj_untyped}

phys_obj_data :: proc(id: Physics_Object_Id) -> (^Phys_Body_Data, bool) #optional_ok {
	raw := b2d.Body_GetUserData(id)
	if raw == nil do log.panicf("Tried to access obj data where none existed") //return nil, false

	return cast(^Phys_Body_Data)raw, true
}

ang_to_b2d_rot :: proc(ang: Rad) -> Vec2 {
	return transmute(Vec2) b2d.MakeRot(f32(ang))
}

phys_obj_goto :: proc(id: Physics_Object_Id, pos: Vec2 = MARKER_VEC2, rot:= MARKER_VEC2) {
	pos := rl_to_b2d_pos(pos)
	dir: b2d.Rot
	if pos == MARKER_VEC2 do pos = b2d.Body_GetPosition(id)
	
	if rot == MARKER_VEC2 do dir = b2d.Body_GetRotation(id)
	else do dir = transmute(b2d.Rot)rot

	b2d.Body_SetTransform(id, pos, dir)
}

phys_obj_goto_transform :: proc(id: Physics_Object_Id, transform: Transform) {
	b2d.Body_SetTransform(id, rl_to_b2d_pos(transform.pos), rl_to_b2_facing(transform.facing))
}

phys_obj_goto_parent :: proc(id: Physics_Object_Id) {
	world := transform.to_world(phys_obj_transform(id))
	phys_obj_goto_transform(id, world)
}

// TODO: make less dookie
phys_obj_rotate :: proc(id: Physics_Object_Id, rot: Rad) {
	cur := b2d.Body_GetRotation(id)
	nrot := transmute(b2d.Rot)b2d.RotateVector(transmute(b2d.Rot)transform.angle_to_dir(rot), transmute(Vec2)cur)
	b2d.Body_SetTransform(id, b2d.Body_GetPosition(id), nrot)
}

/// Gets the transform while also populating it with current position and 
/// Z-axis rotations for this body
phys_obj_transform :: proc(id: Physics_Object_Id) -> (t: ^Transform, ok: bool) #optional_ok {
	data := phys_obj_data(id) or_return
	t = &data.transform
	ok = true
	return
}

phys_obj_set_transform :: proc(id: Physics_Object_Id, transform: Transform) {
	data := phys_obj_data(id)
	data.transform = transform
}

phys_obj_transform_sync_from_body :: proc(id: Physics_Object_Id, sync_rotation := false) {
	t := transform.new(0, 0)

	b2d_pos := b2d.Body_GetPosition(id)
	if sync_rotation {
		b2d_rot := b2d.Body_GetRotation(id)
		t.facing = b2_to_rl_facing(b2d_rot)
	}

	pos := b2d_to_rl_pos(b2d_pos)

	// rows, then columns (y, then x)
	t.pos = pos

	phys_obj_set_transform(id, t)
}

phys_obj_transform_new_from_body :: proc(id: Physics_Object_Id, sync_rotation := false) -> Transform {
	t := phys_obj_transform(id)^

	b2d_pos := b2d.Body_GetPosition(id)
	if sync_rotation {
		b2d_rot := b2d.Body_GetRotation(id)
		t.facing = b2_to_rl_facing(b2d_rot)
	}

	pos := b2d_to_rl_pos(b2d_pos)

	// rows, then columns (y, then x)
	t.pos = pos
	
	return t
}

phys_obj_transform_apply_to_body :: proc(id: Physics_Object_Id) {
	transform := phys_obj_transform(id)
	b2d.Body_SetTransform(id, rl_to_b2d_pos(transform.pos), rl_to_b2_facing(transform.facing))
}

phys_obj_pos :: proc(id: Physics_Object_Id) -> Vec2 {
	return b2d_to_rl_pos(b2d.Body_GetPosition(id))
}

phys_obj_shape :: proc(id: Physics_Object_Id) -> b2d.ShapeId {
	shape_buf := [4]b2d.ShapeId {}

	return b2d.Body_GetShapes(id, shape_buf[0:1])[0]
}

phys_shape_filter :: proc(belong_to_layers: bit_set[Collision_Layer; u64], collide_with := COLLISION_LAYERS_ALL) -> b2d.Filter {
	return b2d.Filter {
		maskBits = transmute(u64) collide_with,
		categoryBits = transmute(u64) belong_to_layers,
		groupIndex = 0,
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
	return transform.to_world(obj).pos;
}




free_phys_world :: proc() {
	b2d.DestroyWorld(physics.world);
	vmem.arena_destroy(&physics.arena)
	physics.initialised = false;
}

add_phys_object_polygon :: proc(
	mass:  f32 = 0,
	vertices: []Vec2,
	pos:   Vec2 = Vec2{},
	on_collision_enter: Phys_Collide_Callback = nil, 
	on_collision_exit : Phys_Collide_Callback = nil,
	friction: f32 = DEFAULT_FRICTION,
	can_rotate: bool = false,
	game_obj: Maybe(Game_Object_Id) = nil,
	parent: ^Transform = nil,
	flags: bit_set[Physics_Object_Flag] = PHYS_OBJ_DEFAULT_FLAGS,
	collision_layers: bit_set[Collision_Layer; u64] = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
	collide_with: bit_set[Collision_Layer; u64] = PHYS_OBJ_DEFAULT_COLLIDE_WITH,
	name: cstring = "",
) -> (id: Physics_Object_Id)
{
	vertices := vertices
	for &vert in vertices {
		vert = rl_to_b2d_pos(vert)
	}
	hull := b2d.ComputeHull(vertices)
	radius := f32(0.0) // no idea wtf this does :)
	polygon := b2d.MakePolygon(hull, radius)
	area := f32(10) // idfk

	id = add_phys_object(
		area,
		mass, 
		polygon, 
		pos, 
		on_collision_enter, 
		on_collision_exit, 
		friction, 
		can_rotate, 
		game_obj,
		parent,
		flags,
		collision_layers,
		collide_with,
		name,
	)
	return
}

add_phys_object_aabb :: proc(
	mass:  f32 = 0,
	scale: Vec2,
	pos:   Vec2 = Vec2{},
	on_collision_enter: Phys_Collide_Callback = nil, 
	on_collision_exit : Phys_Collide_Callback = nil,
	friction: f32 = DEFAULT_FRICTION,
	can_rotate: bool = false,
	game_obj: Maybe(Game_Object_Id) = nil,
	parent: ^Transform = nil,
	flags: bit_set[Physics_Object_Flag] = PHYS_OBJ_DEFAULT_FLAGS,
	collision_layers: bit_set[Collision_Layer; u64] = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
	collide_with: bit_set[Collision_Layer; u64] = PHYS_OBJ_DEFAULT_COLLIDE_WITH,
	name: cstring = "",
) -> (id: Physics_Object_Id)
{
	// to_f64 := proc(v: Vec2) -> [2]f64 {
	// 	return {f64(v.x), f64(v.y)}
	// }
	// to_f32 := proc(v: [2]f64) -> Vec2 {
	// 	return {f32(v.x), f32(v.y)}
	// }

	// double := to_f64(scale) / 2.0 * PIXELS_TO_METRES_RATIO
	// scale := to_f32(double)
	scale := scale / 2.0
	metre_scale := scale / f32(PIXELS_PER_METRE)
	box := b2d.MakeBox(metre_scale.x, metre_scale.y)

	id = add_phys_object(
		scale.x * scale.y,
		mass, 
		box, 
		pos, 
		on_collision_enter, 
		on_collision_exit, 
		friction, 
		can_rotate, 
		game_obj,
		parent,
		flags,
		collision_layers,
		collide_with,
		name,
	)
	return
}

add_phys_object :: proc(
	volume: f32,
	mass:  f32 = 0,
	polygon: b2d.Polygon,
	pos:   Vec2 = Vec2{},
	on_collision_enter: Phys_Collide_Callback = nil, 
	on_collision_exit : Phys_Collide_Callback = nil,
	friction: f32 = DEFAULT_FRICTION,
	can_rotate: bool = false,
	game_obj: Maybe(Game_Object_Id) = nil,
	parent: ^Transform = nil,
	flags: bit_set[Physics_Object_Flag] = PHYS_OBJ_DEFAULT_FLAGS,
	collision_layers: bit_set[Collision_Layer; u64] = PHYS_OBJ_DEFAULT_COLLISION_LAYERS,
	collide_with: bit_set[Collision_Layer; u64] = PHYS_OBJ_DEFAULT_COLLIDE_WITH,
	name: cstring = "",
) -> (id: Physics_Object_Id)
{
	if len(name) > 30 do log.panicf("phys obj can't have a name longer than 30 chars")
	// local := transform.new(pos, rot=0, parent=parent);
	// obj := Physics_Object {
	// 	vel = vel, 
	// 	acc = acc, 
	// 	local = local,
	// 	mass = mass, 
	// 	flags = flags,
	// 	linked_game_object = game_obj,
	// 	collider = cast(AABB) scale,
	// 	collision_layers = collision_layers,
	// 	collide_with_layers = collide_with,
	// };
	arena := vmem.arena_allocator(&physics.arena)

	body_def := b2d.DefaultBodyDef()
	body_def.position = rl_to_b2d_pos(pos)
	body_def.name = name

	if .Never_Sleep in flags {
		body_def.enableSleep = false
	}

	data := new(Phys_Body_Data, allocator = arena)
	// TODO: rot
	data.transform = transform.new(pos, 0)

	if gobj, valid := game_obj.?; valid {
		data.game_object = gobj
	}

	body_def.userData = data
	// body_def.gravity_scale = mass

	if .No_Gravity in flags {
		body_def.gravityScale = 0
	}

	if .Non_Kinematic in flags || .Fixed in flags {
		body_def.type = b2d.BodyType.staticBody
	}
	else if .Non_Dynamic in flags {
		body_def.type = b2d.BodyType.kinematicBody
	}
	else {
		body_def.type = b2d.BodyType.dynamicBody
	}

	if .Fixed_Rotation in flags {
		body_def.fixedRotation = true
	}

	body_id := b2d.CreateBody(physics.world, body_def)
	append(&physics.bodies, body_id)

	// NOTE: MakeBox uses half extents (the number u give is half of the full size)
	// but my api evolved with full scale, so this is just for me
	body_shape := b2d.DefaultShapeDef()

	if .Invisible_To_Triggers not_in flags {
		body_shape.enableSensorEvents = true
	}
	if .Trigger in flags {
		body_shape.isSensor = true

		phys_obj_data(body_id).on_collision_enter = on_collision_enter
		phys_obj_data(body_id).on_collision_exit = on_collision_exit
	}
	else if on_collision_enter != nil || on_collision_exit != nil {
		log.error("Object that was not a Trigger (b2d.Sensor) was passed with on_collision_enter/exit procs, not yet supported")
	}

	body_shape.density = (mass / volume) if mass != 0 else 1 
	body_shape.material.friction = DEFAULT_FRICTION
	// how fucking hard is it to just name things clearly :|
	body_shape.filter = b2d.Filter {
		// https://forum.odin-lang.org/t/how-to-abstract-a-c-bit-fields-with-odins-bit-set/523/2
		categoryBits = transmute(u64)collision_layers,
		maskBits = transmute(u64)collide_with,
		groupIndex = 0,
	}

	if 
		.No_Velocity_Dampening in flags || 
		.No_Collisions in flags || 
		.Drag_Exception in flags || 
		.Weigh_Down_Buttons in flags
	{
		log.warnf(
			"TODO: remove/replace old flags: %v",
			flags & {.No_Velocity_Dampening, .No_Collisions, .Drag_Exception, .Weigh_Down_Buttons},
		)
	}
	// log.info(collision_layers, transmute(u64)collision_layers)

	_ = b2d.CreatePolygonShape(body_id, body_shape, polygon)

	id = body_id
	
	return;
}

update_phys_world :: proc() {
	update_portals()
	b2d.World_Step(physics.world, PHYSICS_TIMESTEP, PHYSICS_SUBSTEPS)

	sensor_events := b2d.World_GetSensorEvents(physics.world)

	begin_events := slice.from_ptr(sensor_events.beginEvents, int(sensor_events.beginCount))
	for event in begin_events {
		body := b2d.Shape_GetBody(event.sensorShapeId)
		data := phys_obj_data(body)
		if data.on_collision_enter != nil {
			other_body := b2d.Shape_GetBody(event.visitorShapeId)
			(data.on_collision_enter)(body, other_body, event.sensorShapeId, event.visitorShapeId)
		}
	}
	end_events := slice.from_ptr(sensor_events.endEvents, int(sensor_events.endCount))
	for event in end_events {
		body := b2d.Shape_GetBody(event.sensorShapeId)
		data := phys_obj_data(body)
		if data.on_collision_exit != nil {
			other_body := b2d.Shape_GetBody(event.visitorShapeId)
			(data.on_collision_exit)(body, other_body, event.sensorShapeId, event.visitorShapeId)
		}
	}
}

phys_obj_aabb :: proc(id: Physics_Object_Id) -> b2d.AABB {
	return b2d.Shape_GetAABB(phys_obj_shape(id))
}

phys_obj_grounded :: proc(obj_id: Physics_Object_Id) -> bool {
	pos := phys_obj_pos(obj_id)
	aabb := phys_obj_aabb(obj_id)
	height := (aabb.upperBound.y - aabb.lowerBound.y) / f32(PIXELS_TO_METRES_RATIO)
	trans := phys_obj_transform_new_from_body(obj_id)
	_, hit := cast_ray_in_world(pos, transform.right(&trans) * (height), exclude = {obj_id})
	return hit
	// return cast_box_in_world(pos + Vec2{0, player_dims().y/2}, player_dims()/2, rot=Rad(0), exclude = {obj_id})
}

point_collides_in_world :: proc(point: Vec2, layers: bit_set[Collision_Layer; u64] = COLLISION_LAYERS_ALL, exclude: []Physics_Object_Id = {}, ignore_triggers := true) -> (
	collided_with: Physics_Object_Id = {},
	success: bool = false,
)
{
	point := rl_to_b2d_pos(point)
	body: Physics_Object_Id
	// OK, this is weird and complicated, because it seems to be designed by a c++ wizard,
	// this function returns false when it wants to stop the qry,
	// which is what we want bc we just want whatever object it gives us first,
	// and its our job to accumulate the results into an array or a map
	// using the ctx variable. cripes.
	get_res := proc "c" (shape: b2d.ShapeId, data: rawptr) -> bool {
		body := b2d.Shape_GetBody(shape)
		data := cast(^Physics_Object_Id) data
		b2d.Body_SetAwake(body, true)
		data ^= body
		return false
	}
	aabb := b2d.AABB {
		lowerBound = point - Vec2(0.001),
		upperBound = point + Vec2(0.001),
	}
	filtre := b2d.DefaultQueryFilter()
	filtre.maskBits = transmute(u64)COLLISION_LAYERS_ALL
	filtre.categoryBits = transmute(u64)COLLISION_LAYERS_ALL
	_ = b2d.World_OverlapAABB(physics.world, aabb, filtre, fcn = get_res, ctx = &body)
	// result := b2d.World_CastRayClosest(physics.world, point, point, filter = {}) 
	if body != PHYS_OBJ_INVALID {
		return body, true
	}
	return {}, false
}

cast_ray_in_world :: proc(og, to_end: Vec2, exclude: []Physics_Object_Id = {}, layers: bit_set[Collision_Layer; u64] = COLLISION_LAYERS_ALL, triggers := true, specific_triggers : []Physics_Object_Id = nil) -> (Ray_Collision, bool) { 
	filter := b2d.DefaultQueryFilter()

	if layers != COLLISION_LAYERS_ALL {
		// filter.categoryBits = transmute(u64)layers
		filter.maskBits = transmute(u64)layers
	}

	Raycast_Ctx :: struct {
		collided: bool,
		fraction: f32,
		exclude: []Physics_Object_Id,
		triggers: bool,
		specific_triggers: []Physics_Object_Id,
		position, normal: Vec2,
		obj: Physics_Object_Id,
	}

	ctx: Raycast_Ctx
	ctx.exclude = exclude
	ctx.triggers = triggers
	ctx.fraction = 999999 // TODO: f32.max

	callback := proc "c" (shape_id: b2d.ShapeId, point: Vec2, normal: Vec2, fraction: f32, ctx: rawptr) -> f32 {
		dat := cast(^Raycast_Ctx)ctx
		obj := b2d.Shape_GetBody(shape_id)
		context = runtime.default_context()

		is_object_acceptable := bool(!slice.contains(dat.exclude, obj) && fraction < dat.fraction)

		if b2d.Shape_IsSensor(shape_id) && !dat.triggers {
			return fraction
		}
		else if dat.triggers && len(dat.specific_triggers) != 0 {
			if slice.contains(dat.specific_triggers[:], obj) && is_object_acceptable {
				dat.collided = true
				dat.position = point
				dat.normal = normal
				dat.obj = obj
				dat.fraction = fraction
				// https://box2d.org/doc_version_2_4/classb2_ray_cast_callback.html
				return fraction
			}
		}

		if is_object_acceptable {
			dat.collided = true
			dat.position = point
			dat.normal = normal
			dat.obj = obj
			dat.fraction = fraction
			// https://box2d.org/doc_version_2_4/classb2_ray_cast_callback.html
			return fraction
		}
		return fraction
	}
	_ = b2d.World_CastRay(physics.world, rl_to_b2d_pos(og), rl_to_b2d_pos(to_end), filter, callback, ctx = &ctx)
	ctx.normal.y = -ctx.normal.y
	if ctx.collided do return Ray_Collision {
		point = b2d_to_rl_pos(ctx.position),
		normal = ctx.normal,
		obj_id = ctx.obj,
	}, true

	return {}, false
}

phys_obj_to_rect :: proc(obj: ^Physics_Object) -> Rect { return {} }

draw_phys_obj :: proc(obj_id: Physics_Object_Id, colour: Colour = Colour(255), texture := TEXTURE_INVALID, lines := true) {
	if !b2d.Body_IsEnabled(obj_id) do return
	shape_buf := [4]b2d.ShapeId{}

	shapes := b2d.Body_GetShapes(obj_id, shape_buf[:])
	ty := b2d.Shape_GetType(shapes[0])
	#partial switch ty {
	case .capsuleShape:
		capsule := b2d.Shape_GetCapsule(shapes[0])
		rendering.draw_circle(phys_obj_pos(obj_id) + capsule.center1 / f32(PIXELS_TO_METRES_RATIO), capsule.radius / f32(PIXELS_TO_METRES_RATIO),colour)
		rendering.draw_circle(phys_obj_pos(obj_id) + capsule.center2 / f32(PIXELS_TO_METRES_RATIO), capsule.radius / f32(PIXELS_TO_METRES_RATIO),colour)
	case .polygonShape:
		polygon := b2d.Shape_GetPolygon(shapes[0])
		// log.info(polygon.vertices[:polygon.count])
		b2d_transform := b2d.Body_GetTransform(obj_id)
		rendering.draw_polygon_convex(b2d_transform, vertices = polygon.vertices[:polygon.count], colour=colour, b2d_to_rl_pos=b2d_to_rl_pos)
		DEBUG_TRANSFORM :: false
		when DEBUG_TRANSFORM {
			rendering.draw_rectangle_transform(phys_obj_transform(obj_id), Rect{0,0, 50, 50})
		}
	case:
		log.panicf("idk how to draw a ", ty)
	}

	if !lines do return
	trans := phys_obj_transform_new_from_body(obj_id, sync_rotation=true)

	end := trans.pos + transform.forward(&trans) * 50 / rendering.camera.zoom;
	rendering.draw_line(trans.pos, end);
	// right arrow
	end = trans.pos + transform.right(&trans) * 50 / rendering.camera.zoom;
	rendering.draw_line(trans.pos, end, colour=Colour{0, 0, 255, 255});

	// draw_line(rl_to_b2d_pos(transform.p), rl_to_b2d_pos(transform.p) + transmute(Vec2)transform.q / camera.zoom * 50, Colour{2..<4=255})
	// right := linalg.matrix2_rotate_f32(linalg.PI/2) * transmute(Vec2)transform.q
	// draw_line(rl_to_b2d_pos(transform.p), rl_to_b2d_pos(transform.p) + right / camera.zoom * 50, Colour{0=255, 3 = 255})

	// shape_buf := [4]b2d.ShapeId {}
	// shapes := b2d.Body_GetShapes(obj_id, shape_buf[:])
	// polygon := b2d.Shape_GetPolygon(shapes[0])
	// transform := b2d.Body_GetTransform(obj_id)
	// draw_polygon_convex(transform, vertices = polygon.vertices[:], colour = colour)
}

phys_obj_colliding :: proc(obj: Physics_Object_Id) -> bool {
	contact_buf := [4]b2d.ContactData {}
	contacts := b2d.Body_GetContactData(obj, contact_buf[:])
	if len(contacts) != 0 do return true
	// for contact in contacts {
	// 	if contact.shapeIdB == first_shape_b || contact.shapeIdA == first_shape_b do return true
	// }
	return false
}

check_phys_objects_collide :: proc(obj1id, obj2id: Physics_Object_Id, first_set_pos := MARKER_VEC2) -> bool {
	shape_buf := [4]b2d.ShapeId {}

	first_shape_a := b2d.Body_GetShapes(obj1id, shape_buf[0:1])[0]
	first_shape_b := b2d.Body_GetShapes(obj2id, shape_buf[2:3])[0]

	if b2d.Shape_IsSensor(first_shape_a) {
		log.panicf("don't bother")
		// sensor_events := b2d.World_GetSensorEvents(physics.world)

		// slice := slice.from_ptr(sensor_events.beginEvents, int(sensor_events.beginCount))
		// for event in slice {
		// 	TODO: use collision layers instead of sensors because they seem to be 
		// 	the most poorly designed thing ever seen on earth
		// 	log.info(event)
		// 	if event.sensorShapeId == first_shape_a && event.visitorShapeId == first_shape_b {
		// 		log.warn("This sucks")
		// 		return true
		// 	}
		// }
		// overlaps_buf := [4]b2d.ShapeId{}
		// overlaps := Shape_GetSensorOverlaps(first_shape_a, overlaps_buf[:])
		// // contact_buf := [4]b2d.ContactData {}
		// // contacts := b2d.Shape_GetContactData(first_shape_a, contact_buf[:])
		// log.infof("overlaps: %v, searching for %v", len(overlaps), first_shape_b)
		// for cntct in overlaps {
		// 	if cntct == first_shape_b do return true
		// 	// if cntct.shapeIdB == first_shape_b || cntct.shapeIdA == first_shape_b do return true
		// }
	}
	else {
		contact_buf := [4]b2d.ContactData {}
		contacts := b2d.Body_GetContactData(obj1id, contact_buf[:])
		for contact in contacts {
			if contact.shapeIdB == first_shape_b || contact.shapeIdA == first_shape_b do return true
		}
	}

	return false
}

phys_obj_centre :: proc(obj: ^Physics_Object) -> Vec2 {
	pos := phys_obj_world_pos(obj);
	return pos;
}

cast_box_in_world :: proc(centre, dimensions: Vec2, rot: Rad, exclude: []Physics_Object_Id = {}, layers := COLLISION_LAYERS_ALL) -> bool {
	rect := b2d.MakeBox(dimensions.x/2, dimensions.y/2)
	// verts := slice.from_ptr(rect.vertices[:], int(rect.count))
	aabb := b2d.ComputePolygonAABB(rect, b2d.Transform {p = centre, q = {1, 0}})
	diagonal := linalg.length(aabb.upperBound - aabb.lowerBound)
	shape_prxy := b2d.MakeProxy(
		rect.vertices[:],
		radius = diagonal,
	)
	filter := b2d.DefaultQueryFilter()

	if layers != COLLISION_LAYERS_ALL do log.warn("TODO: support collision layer filtering in box cast")
	if rot != Rad(0) do log.warn("TODO: support rotated box casts")

	Box_Cast_Ctx :: struct {
		collided: bool,
		exclude: []Physics_Object_Id,
	}

	ctx: Box_Cast_Ctx
	ctx.exclude = exclude

	callback := proc "c" (shape_id: b2d.ShapeId, _: Vec2, _: Vec2, fraction: f32, ctx: rawptr) -> f32 {
		dat := cast(^Box_Cast_Ctx)ctx
		obj := b2d.Shape_GetBody(shape_id)
		context = runtime.default_context()
		if !slice.contains(dat.exclude, obj) {
			libc.printf("hi")
			dat.collided = true
			return -1
		}
		return fraction
	}
	_ = b2d.World_CastShape(physics.world, shape_prxy, centre, filter, callback, ctx = &ctx)
	// TODO: could prob use the tree to check how many cols but will keep this for when i add layer checks etc..
	if ctx.collided do return true

	return false
}
