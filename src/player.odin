package main;

import "core:log"

import "core:math"
import "core:math/ease";

import rl "thirdparty/raylib"
import b2d "thirdparty/box2d"

PLAYER_HORIZ_ACCEL :: 5000.0; // newtons???
PLAYER_JUMP_STR :: 25_000.0; // idk

PLAYER_WIDTH :: 32;
PLAYER_HEIGHT :: 32;

PLAYER_WEIGHT :: 60;

PLAYER_STEP_UP_HEIGHT :: 20;

PORTAL_RANGE :: 500
PLAYER_REACH :: 80
SNAP_LIMIT   :: 40

Player :: struct {
	obj: Physics_Object_Id,
	texture: Texture_Id,
	step_timer: Timer,

	lerp_origin, lerp_target: Vec2, 

	in_air: bool,
	jump_timer: Timer,
	jumping: bool,
	coyote_timer: Timer,

	portals_unlocked: int,
}

player_dims :: proc() -> Vec2 {
	return {PLAYER_WIDTH, PLAYER_HEIGHT}
}

player_feet :: proc(player: ^Player) -> Vec2 {
	obj := phys_obj(player.obj);
	return obj.pos + Vec2 {0, PLAYER_HEIGHT / 2 - 2};
}

player_new :: proc(texture: Texture_Id) -> Player {
	player: Player;
	player.obj = add_phys_object_aabb(
		pos = get_screen_centre(), 
		mass = PLAYER_WEIGHT, 
		scale = Vec2 { PLAYER_WIDTH, PLAYER_HEIGHT },
		flags = {.Fixed_Rotation, .Never_Sleep},
		friction = 0.25,
	);
	player.texture = texture;

	player.step_timer = timer_new(0.2)
	set_timer_done(&player.step_timer)

	player.coyote_timer = timer_new(0.2)
	player.jump_timer = timer_new(0.35, flags={.Update_Automatically})

	return player;
}

update_player :: proc(player: Game_Object_Id, dt: f32) -> (should_delete: bool = false) {
	player := game_obj(player, Player)
	player_obj := player.obj

	move: f32 = 0.0;
	if rl.IsKeyDown(rl.KeyboardKey.D) {
		move +=  1;
	}
	if rl.IsKeyDown(rl.KeyboardKey.A) {
		move += -1;
	}

	update_timer(&player.jump_timer, dt)

	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) && is_timer_done(&player.jump_timer) {
		if !player.in_air || !is_timer_done(&player.coyote_timer) {
			player.jumping = true;
			impulse := Vec2 {
				0,
				-PLAYER_JUMP_STR
				// -PLAYER_JUMP_STR * (1 - ease.exponential_out(player.jump_timer.current))
			}
			b2d.Body_ApplyLinearImpulseToCenter(player_obj, rl_to_b2d_pos(impulse), wake=true)
			if !is_timer_done(&player.coyote_timer) do set_timer_done(&player.coyote_timer);
			reset_timer(&player.jump_timer)
		}
	}
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

	if phys_obj_grounded(player.obj) {
		player.in_air = false;
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

	if move != 0.0 && is_timer_done(&player.step_timer) {
		// b2d.Body_ApplyForceToCenter(player_obj, Vec2{move * PLAYER_HORIZ_ACCEL, 0}, wake = true)
		new_vel := b2d.Body_GetLinearVelocity(player_obj)
		new_vel.x = move * PLAYER_HORIZ_ACCEL
		b2d.Body_ApplyForceToCenter(player_obj, Vec2{move * PLAYER_HORIZ_ACCEL, 0}, false)
		// b2d.Body_SetLinearVelocity(player_obj, new_vel)
		// player_obj.acc.x = move * PLAYER_HORIZ_ACCEL;
	}
	else {
		cur_vel := b2d.Body_GetLinearVelocity(player_obj)
		if math.abs(cur_vel.x) > 1 {
			force := Vec2{
				cur_vel.x,
				0
			}
			b2d.Body_ApplyForceToCenter(player_obj, -rl_to_b2d_pos(force * 60 * PLAYER_WEIGHT), wake=false)
		}
	}

	if rl.IsKeyPressed(rl.KeyboardKey.L) {
		player.portals_unlocked += 1
		log.info(player.portals_unlocked)
	}
	// else {
	// 	if math.abs(player_obj.rot) > 0.1 {
	// 		// rotate(player_obj, player_obj.rot * 0.01);
	// 		rotate(player_obj, player_obj.rot * -0.05);
	// 	}
	// 	else {
	// 		player_obj.local = transform_new(player_obj.pos, 0);
	// 		// setrot(player_obj, 0);
	// 	}
	// 	// if player_obj.rot < 0 && player_obj.rot > -linalg.PI {
	// 	// 	rotate(player_obj, player_obj.rot * 0.01);
	// 	// }
	// 	// else if player_obj.rot > 0 && player_obj.rot < linalg.PI {
	// 	// 	rotate(player_obj, -player_obj.rot * 0.01);
	// 	// }
	// }

	return
}

draw_player :: proc(player: Game_Object_Id, _: Camera2D) {
	player := game_obj(player, Player)
	// obj:=phys_obj(player.obj);
	
	// r := phys_obj_to_rect(obj).zw;
	draw_phys_obj(player.obj);
	// draw_rectangle_transform(obj, phys_obj_to_rect(obj), texture_id=player.texture);
	// draw_texture(player.texture, obj.pos, pixel_scale=phys_obj_to_rect(obj).zw);	
	// draw_rectangle(obj.pos - r/2, r);	
}
