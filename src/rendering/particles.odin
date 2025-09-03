package rendering

import "core:log"
import "core:math/rand"
import "core:math/linalg"
import "core:math/ease"
import "base:runtime"

import "../transform"

Rad :: transform.Rad

@private
particle_handler: Particle_Handler

// i like determinism...
PARTICLE_RANDOM_SEED :: u64(1337)
PARTICLE_COUNT :: 1024

Particle_Shape :: enum {
	Square,
	Circle,
}

alpha_lerp_const :: proc(t: f32) -> f32 {
	return 1
}

alpha_lerp_linear :: proc(t: f32) -> f32 {
	return t
}

Particle_Draw_Info :: struct {
	shape: Particle_Shape,
	texture: Maybe(Texture_Id),
	radius: f32,
	scale: Vec2,
	colour: Colour,
	alpha_easing: Maybe(ease.Ease),
}

Particle_Init_Fixed :: struct {
	vel: Vec2,
	ang_vel: f32,
}

Particle_Init_Random :: struct {
	vel_dir_min, vel_dir_max: f32,
	vel_mag_min, vel_mag_max: f32,
	ang_vel_min, ang_vel_max: f32,
	// half extents
	vert_spread, horiz_spread: f32,
}

Particle_Physics :: struct {
	perm_acc: Vec2,

	initial_conds: union{Particle_Init_Fixed, Particle_Init_Random},

	ang_vel: f32,
	vel, acc: Vec2,
}

Particle_Lerp :: struct {
	origin, target: Vec2,
	ease_proc: #type proc(t: f32) -> f32,
}

Particle_Def :: struct {
	draw_info: Particle_Draw_Info,
	movement: union{Particle_Lerp, Particle_Physics},
	lifetime_secs: f32,
}

Particle :: struct {
	def: Particle_Def,

	pos: Vec2, 
	rot: f32,
	
	life: f32,
}

Particle_Handler :: struct {
	particles: [PARTICLE_COUNT]Particle,
	particle_index: int,
	default_particle: Particle_Def,
	rng_state: rand.Default_Random_State,
	rngen: rand.Generator,
}

initialise_particle_handler :: proc() {
	particle_handler.rng_state = rand.create(PARTICLE_RANDOM_SEED)
	particle_handler.rngen = runtime.default_random_generator(&particle_handler.rng_state)
	particle_handler.default_particle = Particle_Def {
		draw_info = Particle_Draw_Info {
			shape = .Square,
			scale = Vec2 {10, 10},
			colour = Colour(255),
			alpha_easing = .Linear,
		},
		lifetime_secs = 1,
		movement = Particle_Physics {
			perm_acc = Vec2(0),
			initial_conds = Particle_Init_Random {
				vel_dir_max = 360,
				vel_mag_max = 50,
				ang_vel_min = -100,
				ang_vel_max = 100,
			}
		}
	}
}

free_particle_handler :: proc() {
}

particle_initialise :: proc(particle: ^Particle, def: Particle_Def) {
	particle.life = def.lifetime_secs

	particle.def = def
}

particle_render :: proc(particle: ^Particle) {
	draw_info := particle.def.draw_info
	frac := particle.life / particle.def.lifetime_secs
	switch draw_info.shape {
	case .Square:
		if ease_ty, ok := draw_info.alpha_easing.?; ok {
			draw_info.colour.a = u8(ease.ease(ease_ty, frac) * 256)
		}
		trans:= transform.new(particle.pos, Rad(linalg.to_radians(particle.rot)))
		tex := draw_info.texture.? or_else TEXTURE_INVALID

		draw_rectangle_transform(
			&trans,
			Rect{0, 0, draw_info.scale.x, draw_info.scale.y},
			colour=draw_info.colour,
			texture_id=tex,
		)
	case .Circle:
		unimplemented("circlular particles")
	}
}

particle_update :: proc(particle: ^Particle, dt: f32) {
	frac := particle.life / particle.def.lifetime_secs
	switch &movement in particle.def.movement {
	case Particle_Lerp:
		particle.pos = movement.origin + (movement.target - movement.origin) * (movement.ease_proc)(frac)
	case Particle_Physics:
		particle.pos += movement.vel * dt
		movement.vel += movement.acc * dt * dt
		particle.rot += movement.ang_vel * dt
	}
	particle.life -= dt
}

particle_spawn :: proc(pos: Vec2, rot: f32, def: Particle_Def) {
	particle_handler.particle_index %= len(particle_handler.particles)

	particle := &particle_handler.particles[particle_handler.particle_index]
	if particle.life > 0 {
		log.warn("appear to have overrun particle buffer, erasing old ones")
	}

	particle_initialise(particle, def)

	particle.pos = pos
	particle.rot = rot

	switch &mv in particle.def.movement {
	case Particle_Lerp:
		particle.pos = mv.origin
	case Particle_Physics:
		switch init in mv.initial_conds {
		case Particle_Init_Fixed:
			mv.vel = init.vel
			mv.ang_vel = init.ang_vel
		case Particle_Init_Random:
			vel_ang := rand.float32_range(init.vel_dir_min, init.vel_dir_max, gen = particle_handler.rngen)
			vel_mag := rand.float32_range(init.vel_mag_min, init.vel_mag_max, gen = particle_handler.rngen)

			mv.vel = transform.angle_to_dir(rot + vel_ang) * vel_mag
			mv.ang_vel = rand.float32_range(init.ang_vel_min, init.ang_vel_max, gen = particle_handler.rngen)

			right := transform.angle_to_dir(rot - 90)
			fwd := transform.angle_to_dir(rot)
			pos_along_vert := rand.float32_range(-init.vert_spread/2, init.vert_spread/2, gen = particle_handler.rngen)
			particle.pos += right * pos_along_vert
			pos_along_horiz := rand.float32_range(-init.horiz_spread/2, init.horiz_spread/2, gen = particle_handler.rngen)
			particle.pos += fwd * pos_along_horiz
		}
		mv.acc = mv.perm_acc
	}

	particle_handler.particle_index += 1
}

update_particles :: proc(dt: f32) {
	for &particle in particle_handler.particles {
		if particle.life <= 0 do continue
		particle_update(&particle, dt)
	}
}

render_particles :: proc() {
	for &particle in particle_handler.particles {
		if particle.life <= 0 do continue
		particle_render(&particle)
	} 
}