package main;

import "core:math/linalg";
import "core:math";

// when ODIN_DEBUG { can't do dis..
	import "core:fmt";
// }

Rad :: distinct f32
Deg :: distinct f32 // TODO: not needed(?)

Mat3x3 :: linalg.Matrix3f32;
Mat4x4 :: linalg.Matrix4f32;
Mat2x2 :: linalg.Matrix2f32;
Vec3 :: linalg.Vector3f32;
Vec4 :: linalg.Vector4f32;

// https://math.libretexts.org/Bookshelves/Applied_Mathematics/Mathematics_for_Game_Developers_(Burzynski)/04%3A_Matrices/4.06%3A_Rotation_Matrices_in_3-Dimensions
// note: we are rotating in 2d around the Z axis 

X_AXIS :: Vec3 {1, 0, 0};
Y_AXIS :: Vec3 {0, 1, 0};
Z_AXIS :: Vec3 {0, 0, 1};

Transform :: struct {
	pos: Vec2,
	rot: Rad,
	mat: Mat4x4,
	// TODO: this pointer is invalidated if the parent is updated... :(
	parent: ^Transform,
}

transform_new :: proc(pos: Vec2, rot: Rad, parent: ^Transform = nil) -> Transform {
	new := transform_from_matrix(linalg.MATRIX4F32_IDENTITY);
	rotate(&new, rot);
	setpos(&new, pos);
	new.parent = parent;
	return new;
}

transform_reset_rotation_plane :: proc(transform: ^Transform) {
	new := transform_new(transform.pos, transform.rot);
	transform^ = new;
}

rotate :: proc(transform: ^Transform, radians: Rad) {
	transform.mat = transform.mat * linalg.matrix4_rotate_f32(f32(radians), Z_AXIS);
	transform_align(transform);
}

move :: proc(transform: ^Transform, delta: Vec2) {
	transform.mat[3].xy += delta;
	transform_align(transform);
}

setpos :: proc(transform: ^Transform, pos: Vec2) {
	transform.mat[3].xy = pos;
	transform_align(transform);
}

setrot :: proc(transform: ^Transform, radians: Rad) {
	// z-axis rot:
	// cos(a) -sin(a) .. ..
	// sin(a) cos(a)  .. ..
	// ..  	  ..	  .. ..
	// 0 	  0 	  0  0
	rads := f32(radians)
	transform.mat[0,0] = math.cos(rads)
	transform.mat[1,0] = -math.sin(rads)

	transform.mat[1,1] = math.cos(rads)
	transform.mat[0,1] = math.sin(rads)
	transform_align(transform)
}

// realigns 'accessible' fields pos and rot to reflect the matrix
// state of the structure
// this is to allow users to do transform.rot and transform.pos, 
// but it's stupid and outdated, only added bc i was too lazy to go 
// everywhere to change it, will remove it (or not...)
transform_align :: proc(transform: ^Transform) {
	transform.pos = pos(transform);
	transform.rot = rot(transform);
}

rot :: proc(transform: ^Transform) -> Rad {
	return Rad(math.atan2(transform.mat[0][1], transform.mat[0][0]));
}

pos :: proc(transform: ^Transform) -> Vec2 {
	return transform.mat[3].xy;
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

transform_flip :: proc(transform: ^Transform) -> Transform {
	mirror := linalg.matrix4_rotate_f32(linalg.PI, Y_AXIS);
	for i in 0..<3 do mirror[i, 3] = 0
	for i in 0..<3 do mirror[3, i] = 0

	mirrored := transform.mat * mirror;

	ntr := transform_from_matrix(mirrored);
	return ntr;
}

transform_flip_vert :: proc(transform: ^Transform) -> Transform {
	mirror := linalg.matrix4_rotate_f32(-linalg.PI, X_AXIS);
	for i in 0..<3 do mirror[i, 3] = 0
	for i in 0..<3 do mirror[3, i] = 0

	mirrored := transform.mat * mirror;

	ntr := transform_from_matrix(mirrored);
	return ntr;
}

transform_forward :: proc(transform: ^Transform) -> Vec2 {
	// https://stackoverflow.com/questions/53608944/getting-a-forward-vector-from-rotation-and-position
	// const mat4 inverted = glm::inverse(transformationMatrix);
	// const vec3 forward = normalize(glm::vec3(inverted[2]));
	// inverted := linalg.matrix4_inverse(transform.mat);
	fwd := linalg.normalize(transform.mat[0].xy);
	return fwd;
}

transform_right :: proc(transform: ^Transform) -> Vec2 {
	// fwd := linalg.normalize(transform.mat[0]);
	right_mat := linalg.matrix4_rotate_f32(linalg.π/2, Z_AXIS);
	return (transform.mat * right_mat)[0].xy;
}

transform_point :: proc(transform: ^Transform, point: Vec2) -> Vec2 {
	res := transform.mat * Vec4 { point.x, point.y, 0, 1 };
	return res.xy;
}

transform_from_matrix :: proc(mat: Mat4x4) -> Transform {
	t := Transform {
		mat = mat
	};
	transform_align(&t);
	return t;
}

transform_to_world :: proc(transform: ^Transform) -> Transform {
	if transform.parent == nil {
		return transform^;
	}
	else {
		parent := transform_to_world(transform.parent);
		res := parent.mat * transform.mat;

		// rot_mat := matrix2_rotate_f32(transform.parent.rot);
		// mag := linalg.length(transform.pos);
		// smth := Vec2 { math.cos(transform.parent.rot - transform.rot), math.sin(transform.parent.rot - transform.rot) };
		// pos := transform.parent.pos + mag*smth;
		return transform_from_matrix(res);
	}
}