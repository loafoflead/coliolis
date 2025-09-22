
package transform

import b2d "../thirdparty/box2d"

import "core:math/linalg";
import "core:math";

// when ODIN_DEBUG { can't do dis..
// }

Rad :: distinct f32
Deg :: distinct f32 // TODO: not needed(?)

Mat3x3 :: linalg.Matrix3f32;
Mat4x4 :: linalg.Matrix4f32;
Mat2x2 :: linalg.Matrix2f32;
Vec2 :: linalg.Vector2f32
Vec3 :: linalg.Vector3f32;
Vec4 :: linalg.Vector4f32;

// https://math.libretexts.org/Bookshelves/Applied_Mathematics/Mathematics_for_Game_Developers_(Burzynski)/04%3A_Matrices/4.06%3A_Rotation_Matrices_in_3-Dimensions
// note: we are rotating in 2d around the Z axis 

X_AXIS :: Vec3 {1, 0, 0};
Y_AXIS :: Vec3 {0, 1, 0};
Z_AXIS :: Vec3 {0, 0, 1};

Transform :: struct {
	pos: Vec2,
	facing: Vec2,
	// TODO: this pointer is invalidated if the parent is updated... :(
	parent: ^Transform,
}

dir_to_angle :: proc(facing: Vec2) -> Rad {
	return Rad(math.atan2(facing.y, facing.x))
} 

angle_to_dir_deg :: proc(degrees: f32) -> Vec2 {
	return Vec2{math.cos(linalg.to_radians(degrees)), math.sin(linalg.to_radians(degrees))}
}

angle_to_dir_rad :: proc(rads: Rad) -> Vec2 {
	return Vec2{math.cos(f32(rads)), math.sin(f32(rads))}
}

angle_to_dir :: proc{angle_to_dir_deg, angle_to_dir_rad}

b2d_to_mat4 :: proc(transform: b2d.Transform) -> Mat4x4 {
	matr := Mat4x4 {
		transform.q.c, -transform.q.s, 0, transform.p.x,
		transform.q.s, transform.q.c,  0, -transform.p.y,
		0, 0, 						   1, 			  0,
		0, 0, 						   0,			  1,
	}
	return matr
}

new :: proc(pos: Vec2, rot: Rad, parent: ^Transform = nil) -> Transform {
	// new := from_matrix(linalg.MATRIX4F32_IDENTITY);
	// rotate(&new, rot);
	// setpos(&new, pos);
	new := Transform {
		pos = pos,
		facing = angle_to_dir(rot),
	}
	new.parent = parent;
	return new;
}

@(deprecated="no longer needed")
reset_rotation_plane :: proc(transform: ^Transform) {
	// new := new(transform.pos, transform.rot);
	// transform^ = new;
}

get_mat :: proc(transform: ^Transform) -> Mat3x3 {
	return Mat3x3 {
		transform.facing.x, -transform.facing.y, transform.pos.x,
		transform.facing.y,  transform.facing.x, transform.pos.y,
		0, 					 0, 			     1,
	}
}

rotate :: proc(transform: ^Transform, radians: Rad) {
	mat := get_mat(transform) * linalg.matrix3_rotate_f32(f32(radians), Z_AXIS);
	transform^ = from_matrix(mat)
}

move :: proc(transform: ^Transform, delta: Vec2) #no_bounds_check {
	transform.pos += delta;
}

setpos :: proc(transform: ^Transform, pos: Vec2) #no_bounds_check {
	transform.pos = pos;
}

setrot :: proc(transform: ^Transform, radians: Rad) #no_bounds_check {
	// z-axis rot:
	// cos(a) -sin(a) .. ..
	// sin(a) cos(a)  .. ..
	// ..  	  ..	  .. ..
	// 0 	  0 	  0  0
	transform.facing = angle_to_dir(radians)
}

// realigns 'accessible' fields pos and rot to reflect the matrix
// state of the structure
// this is to allow users to do transform.rot and transform.pos, 
// but it's stupid and outdated, only added bc i was too lazy to go 
// everywhere to change it, will remove it (or not...)
@(deprecated="no longer useful")
align :: proc(transform: ^Transform) {
	// transform.pos = pos(transform);
	// transform.rot = rot(transform);
}

rot :: proc(transform: ^Transform) -> Rad {
	return Rad(math.atan2(transform.facing.y, transform.facing.x))
}

pos :: proc(transform: ^Transform) -> Vec2 {
	return transform.pos;
}

facing :: proc(transform: ^Transform) -> Vec2 {
	return transform.facing
}

@(deprecated="No longer used")
euler_angles_xyz :: proc(transform: ^Transform) -> (Rad, Rad, Rad) {
	return Rad(0), Rad(0), Rad(0)
}

// // stole from: https://math.stackexchange.com/questions/525082/reflection-across-a-line
// matrix_reflect :: proc(mat: Mat2x2, line: Vec2) -> Mat2x2 {
// 	// y = mx
// 	m := line.y / line.x;
// 	factor := 1 / (1 + m*m);
// 	mat := Mat2x2 {
// 		1 - m*m, 2*m,
// 		2*m, m*m - 1,
// 	};
// 	return factor * mat;
// }

@(deprecated="flipping is graphical now")
flip :: proc(transform: ^Transform) -> Transform {
	return new(0, 0)
}

@(deprecated="flipping is graphical now")
flip_vert :: proc(transform: ^Transform) -> Transform {
	return new(0, 0)
}

forward :: proc(transform: ^Transform) -> Vec2 #no_bounds_check {
	// https://stackoverflow.com/questions/53608944/getting-a-forward-vector-from-rotation-and-position
	// const mat4 inverted = glm::inverse(transformationMatrix);
	// const vec3 forward = normalize(glm::vec3(inverted[2]));
	// inverted := linalg.matrix4_inverse(transform.mat);
	fwd := linalg.normalize(transform.facing);
	return fwd;
}

right :: proc(transform: ^Transform) -> Vec2 #no_bounds_check {
	fwd := forward(transform)
	return {fwd.y, -fwd.x}
}

transform_point :: proc(transform: ^Transform, point: Vec2) -> Vec2 #no_bounds_check {
	res := get_mat(transform) * Vec3 { point.x, point.y, 1 };
	return res.xy;
}

from_matrix :: proc(mat: Mat3x3) -> Transform {
	t := Transform {
		pos = mat[2].xy,
		facing = mat[0].xy,
		parent = nil,
	}
	return t
}

to_world :: proc(transform: ^Transform) -> Transform {
	if transform.parent == nil {
		return transform^;
	}
	else {
		parent := to_world(transform.parent);
		res := get_mat(&parent) * get_mat(transform);

		// rot_mat := matrix2_rotate_f32(transform.parent.rot);
		// mag := linalg.length(transform.pos);
		// smth := Vec2 { math.cos(transform.parent.rot - transform.rot), math.sin(transform.parent.rot - transform.rot) };
		// pos := transform.parent.pos + mag*smth;
		return from_matrix(res);
	}
}