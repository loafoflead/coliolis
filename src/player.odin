package main;

import vmem "core:mem/virtual"

import "core:c/libc"
import "core:log"

import "core:math"
import "core:math/ease";
import "core:math/linalg"

import rl "thirdparty/raylib"
import b2d "thirdparty/box2d"

PLAYER_HORIZ_ACCEL :: 5000.0; // newtons???
PLAYER_JUMP_STR :: 100.0; // idk

PLAYER_WIDTH :: 32;
PLAYER_HEIGHT :: 32;

PLAYER_WEIGHT :: 60;

PLAYER_STEP_UP_HEIGHT :: 20;

PORTAL_RANGE :: 500
PLAYER_REACH :: 80
SNAP_LIMIT   :: 40

Player :: struct {
	// logic_obj: Physics_Object_Id,
	// dynamic_obj: Physics_Object_Id,
	obj: Physics_Object_Id,

	transform: Transform,
	vel: Vec2,

	texture: Texture_Id,
	step_timer: Timer,

	lerp_origin, lerp_target: Vec2, 

	in_air: bool,
	jump_timer: Timer,
	jumping: bool,
	coyote_timer: Timer,
	teleporting: bool,

	portals_unlocked: int,
}

player_dims :: proc() -> Vec2 {
	return {PLAYER_WIDTH, PLAYER_HEIGHT}
}

player_new :: proc(texture: Texture_Id) -> Player {
	player: Player;
	// add_phys_object_aabb(
	// 	pos = get_screen_centre(), 
	// 	mass = PLAYER_WEIGHT, 
	// 	scale = Vec2 { PLAYER_WIDTH, PLAYER_HEIGHT },
	// 	flags = {.Fixed_Rotation, .Never_Sleep},
	// 	friction = 0.25,
	// );
	arena := vmem.arena_allocator(&physics.arena)

	player.transform = transform_new(0, 0)
	body_def := b2d.DefaultBodyDef()
	data := new(Phys_Body_Data, allocator = arena)
	data.transform = transform_new(0, 0)
	body_def.userData = data
	body_def.name = "player"
	body_def.type = b2d.BodyType.kinematicBody

	player.obj = b2d.CreateBody(physics.world, body_def)

	shape := b2d.DefaultShapeDef()
	// shape.maxPush = 0.025
	// shape.clipVelocity = false
	shape.filter = b2d.Filter {
		transmute(u64)Collision_Set{.Player},
		transmute(u64)Collision_Set{.Default},
		0
	}
	shape.enableSensorEvents = true

	_ = b2d.CreateCapsuleShape(player.obj, shape, player_capsule())

	// player.logic_obj = add_phys_object_aabb(
	// 	pos = get_screen_centre(), 
	// 	scale = Vec2 { PLAYER_WIDTH, PLAYER_HEIGHT },
	// 	flags = {.Fixed_Rotation, .Non_Dynamic},
	// 	collision_layers = {},
	// 	collide_with = COLLISION_LAYERS_ALL,
	// );
	player.texture = texture;

	player.step_timer = timer_new(0.2)
	set_timer_done(&player.step_timer)

	player.coyote_timer = timer_new(0.2)
	player.jump_timer = timer_new(0.35, flags={.Update_Automatically})

	return player;
}

player_goto :: proc(pos: Vec2) {
	setpos(&get_player().transform, pos)
	// b2d.Body_SetTransform(get_player().logic_obj, rl_to_b2d_pos(pos), {1, 0})
	// b2d.Body_SetTransform(get_player().dynamic_obj, rl_to_b2d_pos(pos), {1, 0})
	// unimplemented("player_goto")
}

player_pos :: proc() -> Vec2 {
	return get_player().transform.pos
	// return phys_obj_pos(game_obj(game_state.player, Player).logic_obj)
}

player_feet :: proc() -> Vec2 {
	capsule := player_capsule()
	return player_pos() + capsule.center2 + linalg.normalize(capsule.center2) * capsule.radius
}

get_player :: proc "contextless" () -> ^Player {
	g := game_obj(game_state.player, Player)
	return g
}

player_capsule :: proc() -> b2d.Capsule {
	mover : b2d.Capsule
	// if game_state.player != 0 && get_player().teleporting {
	// 	mover.center1 = Vec2(0)
	// 	mover.center2 = mover.center1
	// }
	// else {
		mover.center1 = Vec2{0, 1}
		mover.center2 = -Vec2{0, 1}
	// }
	// mover.center1 = b2d.TransformPoint( m_transform, m_capsule.center1 );
	// mover.center2 = b2d.TransformPoint( m_transform, m_capsule.center2 );
	mover.radius = 1
	return mover
}

player_grounded_check :: proc() -> bool {
	player := get_player()

	target := player_pos() + transform_right(&player.transform) * 21
	filter := b2d.Shape_GetFilter(phys_obj_shape(player.obj))
	layers := transmute(Collision_Set)filter.maskBits

	_, hit := cast_ray_in_world(player_pos(), target - player_pos(), exclude = {player.obj}, layers = layers, triggers = false)
	// draw_line(player_pos(), target)

	// if hit do log.info("COWABUNGA")

	return hit

	// points : []Vec2 = { Vec2{0, 0} }
	// proxy := b2d.MakeProxy(points, radius = f32(0.1))
	// filter := b2d.DefaultQueryFilter()
	// filter.maskBits = transmute(u64)Collision_Set{.Default}
	// filter.categoryBits = transmute(u64)Collision_Set{.Default}


	// Shapecast_Ctx :: struct {
	// 	collided: bool,
	// 	position, normal: Vec2,
	// 	obj: Physics_Object_Id,
	// }

	// ctx: Shapecast_Ctx

	// callback := proc "c" (shape_id: b2d.ShapeId, point: Vec2, normal: Vec2, fraction: f32, ctx: rawptr) -> f32 {
	// 	dat := cast(^Shapecast_Ctx)ctx
	// 	obj := b2d.Shape_GetBody(shape_id)

	// 	if b2d.Shape_IsSensor(shape_id) do return fraction
	// 	if b2d.Body_GetType(obj) == b2d.BodyType.kinematicBody do return fraction

	// 	libc.printf("%s\n", b2d.Body_GetName(obj))

	// 	dat.collided = true
	// 	dat.position = point
	// 	dat.normal = normal
	// 	dat.obj = obj
	// 	return 0 // stop here
	// 	// return fraction
	// }

	// pos := rl_to_b2d_pos(player_pos() /*+ transform_right(&player.transform) * 3*/)

	// _ = b2d.World_CastShape( physics.world, proxy, pos, filter, callback, &ctx );
	// draw_line(player_pos(), player_pos() + transform_right(&player.transform) * 3 / f32(PIXELS_TO_METRES_RATIO))
	// draw_line(player_pos(), b2d_to_rl_pos(ctx.position))
	// return ctx.collided && math.abs(player.vel.y) <= 0.1 
}

update_player :: proc(player: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	player := game_obj(player, Player)
	// player_obj := player.obj

	movement := Vec2(0);
	if rl.IsKeyDown(rl.KeyboardKey.D) {
		movement.x +=  1;
	}
	if rl.IsKeyDown(rl.KeyboardKey.A) {
		movement.x += -1;
	}

	update_timer(&player.jump_timer, dt)

	PLAYER_SPEED :: 7
	PLAYER_MOVE_SUBSTEPS :: 5

	PLAYER_MAX_X_SPEED :: 100
	PLAYER_MAX_Y_SPEED :: 200

	if movement != 0.0 && is_timer_done(&player.step_timer) {
		player.vel += movement * PLAYER_SPEED
		// target = player.transform.pos + movement * PLAYER_SPEED * dt
		// b2d.Body_SetLinearVelocity(player.obj, move * PLAYER_SPEED)
	}

	if player.in_air {
		player.vel.x *= 0.95
	}
	else {
		player.vel.x *= 0.9
	}

	player.vel.x = math.clamp(player.vel.x, -PLAYER_MAX_X_SPEED, PLAYER_MAX_X_SPEED)//math.sign(player.vel.x) * math.max(math.abs(player.vel.x), PLAYER_MAX_X_SPEED)
	player.vel.y = math.clamp(player.vel.y, -PLAYER_MAX_Y_SPEED, PLAYER_MAX_Y_SPEED)//math.sign(player.vel.y) * math.max(math.abs(player.vel.y), PLAYER_MAX_Y_SPEED)

	if player.in_air {
		// gravity
		player.vel += Vec2{0, 4}
	}
	else {
		if !player.jumping do player.vel.y *= 0.8
	}

	// COPIED FROM:
	// https://github.com/erincatto/box2d/blob/main/samples/sample_character.cpp

	target := player.transform.pos + player.vel * dt
	// player.vel *= 0.9

	Mover_Context :: struct {
		planes: [10]b2d.CollisionPlane,
		idx: int,
	}
	mctx: Mover_Context

	result_proc := proc "c" (shapeId: b2d.ShapeId, plane: ^b2d.PlaneResult, ctx: rawptr) -> bool {
		if ctx == nil {
			libc.printf("bad bad mojo\n")
			libc.abort()
			// log.panicf("bad bad booboo")
		}
		// libc.printf("crazy? i was crazy once\n")

		body := b2d.Shape_GetBody(shapeId)

		if b2d.Shape_IsSensor(shapeId) do return true

		mctx := cast(^Mover_Context)ctx

		max_push := f32(9999999999) // TODO: f32.Max or whaddeva
		clip_velocity := true

		// if ctx.idx == len(ctx.planes)-1 do return true
		if plane.hit {
			mctx^.planes[mctx.idx] = b2d.CollisionPlane{plane.plane, max_push, 0, clip_velocity}
			mctx^.idx += 1
		}
		return true
	}
	body_filter := b2d.Shape_GetFilter(phys_obj_shape(player.obj))
	filter := b2d.DefaultQueryFilter()
	filter.maskBits = body_filter.maskBits
	filter.categoryBits = transmute(u64)Collision_Set{.Default}
	tolerance := f32(0.01) // ?

	for i:=0; i < PLAYER_MOVE_SUBSTEPS; i+=1 {
		mctx.idx = 0
		mover := player_capsule()
		mover.center1 = rl_to_b2d_pos(transform_point(&player.transform, b2d_to_rl_pos(mover.center1)))
		mover.center2 = rl_to_b2d_pos(transform_point(&player.transform, b2d_to_rl_pos(mover.center2)))

		b2d.World_CollideMover(physics.world, mover, filter, result_proc, &mctx)
		result := b2d.SolvePlanes( rl_to_b2d_pos(target) - rl_to_b2d_pos(player.transform.pos), mctx.planes[:mctx.idx]);

		// m_totalIterations += result.iterationCount;

		fraction := b2d.World_CastMover( physics.world, mover, result.position, filter );

		delta := fraction * result.position;

		target += b2d_to_rl_pos(delta)
		setpos(&player.transform, target);

		// idfk???
		if ( b2d.LengthSquared( delta ) < tolerance * tolerance )
		{
			break;
		}
	}

	b2d_vel := player.vel
	b2d_vel.y = -b2d_vel.y
	b2d_vel = b2d.ClipVector( b2d_vel, mctx.planes[:mctx.idx] );
	b2d_vel.y = -b2d_vel.y
	player.vel = b2d_vel

	b2d.Body_SetTransform(player.obj, rl_to_b2d_pos(player.transform.pos), {1, 0})

	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) && is_timer_done(&player.jump_timer) {
		if !player.in_air || !is_timer_done(&player.coyote_timer) {
			player.jumping = true
			player.vel += Vec2{0, -1} * PLAYER_JUMP_STR
			reset_timer(&player.jump_timer)
			if !is_timer_done(&player.coyote_timer) do set_timer_done(&player.coyote_timer);
		}
	}

	// if rl.IsKeyPressed(rl.KeyboardKey.SPACE) && is_timer_done(&player.jump_timer) {
	// 	if !player.in_air || !is_timer_done(&player.coyote_timer) {
	// 		player.jumping = true;
	// 		impulse := Vec2 {
	// 			0,
	// 			-PLAYER_JUMP_STR
	// 			// -PLAYER_JUMP_STR * (1 - ease.exponential_out(player.jump_timer.current))
	// 		}
	// 		b2d.Body_ApplyLinearImpulseToCenter(player_obj, rl_to_b2d_pos(impulse), wake=true)
	// 		if !is_timer_done(&player.coyote_timer) do set_timer_done(&player.coyote_timer);
	// 		reset_timer(&player.jump_timer)
	// 	}
	// }
	// if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
	// 	if player.jumping && !is_timer_done(&player.jump_timer) {
	// 		impulse := Vec2 {
	// 			0,
	// 			-PLAYER_JUMP_STR
	// 			// -PLAYER_JUMP_STR * (1 - ease.exponential_out(player.jump_timer.current))
	// 		}
	// 		b2d.Body_ApplyLinearImpulseToCenter(player_obj, rl_to_b2d_pos(impulse), wake=true)
	// 		// b2d.Body_SetLinearVelocity(
	// 		// 	player_obj, rl_to_b2d_pos(new_vel)
	// 		// )
	// 		// set_timer_done(&player.jump_timer)
	// 		// update_timer(&player.jump_timer, dt);
	// 	}
	// }
	// else {
	// 	player.jumping = false;
	// }

	if player_grounded_check() {
		// if math.abs(player.vel.y) < 0.1 {
			player.in_air = false;
		// }
		// reset_timer(&player.jump_timer);
		reset_timer(&player.coyote_timer);
	}
	else {
		update_timer(&player.coyote_timer, dt);
		player.in_air = true;
	}

PLAYER_STEPPING_UP :: false

when PLAYER_STEPPING_UP {
	if move != 0.0 && is_timer_done(&player.step_timer) {
		dir := Vec2 { move, 0 };
		ahead_of_feet := player_feet(player) + dir * 20;
		ahead_of_knees := player_feet(player) + -Y_AXIS.xy * PLAYER_STEP_UP_HEIGHT + dir * 20;
		draw_line(player_feet(player), ahead_of_feet, Colour{255, 0, 0, 255});
		draw_line(player_feet(player), ahead_of_knees, Colour{0, 0, 255, 255});
		_, hit_inside_body := point_collides_in_world(player_feet(player), layers = {.Default, .L0}, exclude = {player.obj});
		_, hit_feet := point_collides_in_world(ahead_of_feet, layers = {.Default, .L0});
		_, too_high := point_collides_in_world(ahead_of_knees, layers = {.Default, .L0});
		if !hit_inside_body && hit_feet && !too_high {
			// og := player_obj.pos + dir * 20;
			draw_line(player_obj.pos, ahead_of_knees, Colour{0, 255, 0, 255});

			col, hit := cast_ray_in_world(ahead_of_knees, Y_AXIS.xy);
			if hit && col.distance > 1 {
				reset_timer(&player.step_timer);
				player_obj.flags += {.Non_Kinematic, .No_Collisions}
				player.lerp_origin = player_obj.pos;
				player.lerp_target = (transmute(Vec3) col.point).xy - Vec2{0, phys_obj_to_rect(player_obj).w/2};
			}
		}
	}

	if !is_timer_done(&player.step_timer) {
		player_obj.pos = player.lerp_origin + (player.lerp_target - player.lerp_origin) * ease.ease(ease.Ease.Circular_In, timer_fraction(&player.step_timer)); 
		update_timer(&player.step_timer, dt);
	}

	if is_timer_just_done(&player.step_timer) {
		player_obj.flags -= {.Non_Kinematic, .No_Collisions}
		update_timer(&player.step_timer, dt);
	}
}

	// if move != 0.0 && is_timer_done(&player.step_timer) {
	// 	// b2d.Body_ApplyForceToCenter(player_obj, Vec2{move * PLAYER_HORIZ_ACCEL, 0}, wake = true)
	// 	new_vel := b2d.Body_GetLinearVelocity(player_obj)
	// 	new_vel.x = move * PLAYER_HORIZ_ACCEL
	// 	b2d.Body_ApplyForceToCenter(player_obj, Vec2{move * PLAYER_HORIZ_ACCEL, 0}, false)
	// 	// b2d.Body_SetLinearVelocity(player_obj, new_vel)
	// 	// player_obj.acc.x = move * PLAYER_HORIZ_ACCEL;
	// }
	// else {
	// 	cur_vel := b2d.Body_GetLinearVelocity(player_obj)
	// 	if math.abs(cur_vel.x) > 1 {
	// 		force := Vec2{
	// 			cur_vel.x,
	// 			0
	// 		}
	// 		b2d.Body_ApplyForceToCenter(player_obj, -rl_to_b2d_pos(force * 60 * PLAYER_WEIGHT), wake=false)
	// 	}
	// }

	if rl.IsKeyPressed(rl.KeyboardKey.L) {
		player.portals_unlocked += 1
		log.info(player.portals_unlocked)
	}

	// else {
		// if math.abs(player.transform.rot) > 0.1 {
		// 	// rotate(player_obj, player_obj.rot * 0.01);
		// 	rotate(&player.transform, player.transform.rot * -0.05);
		// }
		// else {
		// 	player.transform = transform_new(player.transform.pos, 0);
		// 	// setrot(player_obj, 0);
		// }
		// log.info(player.transform.rot)
		if player.transform.rot < 0 && player.transform.rot > -linalg.PI {
			rotate(&player.transform, 0.1);
		}
		else if player.transform.rot > 0 && player.transform.rot < linalg.PI {
			rotate(&player.transform, -0.1);
		}
		if math.abs(player.transform.rot) < 0.1 {
			// log.info("ABSOLUTE ZERO")
			setrot(&player.transform, 0)
		}
		else if math.abs(player.transform.rot - linalg.PI) < 0.1 {
			setrot(&player.transform, 0)
		}
	// }

	return
}

draw_player :: proc(player: Game_Object_Id, _: Camera2D) {
	colour: Colour
	if get_player().in_air do colour=Colour{0, 255, 0, 155}
	else do colour={255, 0, 0, 255}

	capsule := player_capsule()
	player := game_obj(player, Player)

	draw_circle(transform_point(&player.transform, b2d_to_rl_pos(capsule.center1)), capsule.radius / f32(PIXELS_TO_METRES_RATIO), colour)
	draw_circle(transform_point(&player.transform, b2d_to_rl_pos(capsule.center2)), capsule.radius / f32(PIXELS_TO_METRES_RATIO), colour)
	// draw_circle(player_pos() + capsule.center1 / f32(PIXELS_TO_METRES_RATIO), capsule.radius / f32(PIXELS_TO_METRES_RATIO))
	// draw_circle(player_pos() + capsule.center2 / f32(PIXELS_TO_METRES_RATIO), capsule.radius / f32(PIXELS_TO_METRES_RATIO))
	// player := game_obj(player, Player)
	// obj:=phys_obj(player.obj);
	
	// r := phys_obj_to_rect(obj).zw;
	// draw_phys_obj(get_player().obj, colour=Colour{255, 0, 0, 255});
	
	// draw_phys_obj(get_player().obj, colour, lines = false);
	// draw_rectangle_transform(obj, phys_obj_to_rect(obj), texture_id=player.texture);
	// draw_texture(player.texture, obj.pos, pixel_scale=phys_obj_to_rect(obj).zw);	
	// draw_rectangle(obj.pos - r/2, r);	
}
