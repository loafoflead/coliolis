package main;

import "core:math/linalg";
import "core:math";

// when ODIN_DEBUG { can't do dis..
	import "core:fmt";
// }

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
	rot: f32,
	mat: Mat4x4,
	// TODO: this pointer is invalidated if the parent is updated... :(
	parent: ^Transform,
}

transform_new :: proc(pos: Vec2, rot: f32) -> Transform {
	unimplemented("creating transform from pos and rot");
}

rotate :: proc(transform: ^Transform, radians: f32) {
	transform.mat = transform.mat * linalg.matrix4_rotate_f32(radians, Z_AXIS);
	transform_update(transform);
}

move :: proc(transform: ^Transform, delta: Vec2) {
	transform.mat[3].xy += delta;
	transform_update(transform);
}

setpos :: proc(transform: ^Transform, pos: Vec2) {
	transform.mat[3].xy = pos;
	transform_update(transform);
}

@private
transform_update :: proc(transform: ^Transform) {
	transform.pos = pos(transform);
	transform.rot = rot(transform);
}

rot :: proc(transform: ^Transform) -> f32 {
	return math.atan2(transform.mat[1][0], transform.mat[1][0]);
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
	rot := linalg.matrix4_rotate_f32(linalg.PI, Y_AXIS);
	return transform_from_matrix(transform.mat * rot);
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
	fwd := transform_forward(transform);
	right_mat := linalg.matrix4_rotate_f32(linalg.π/2, Z_AXIS);
	return (Vec4 { fwd.x, fwd.y, 0, 1 } * right_mat).xy;
}

transform_point :: proc(transform: ^Transform, point: Vec2) -> Vec2 {
	res := transform.mat * Vec4 { point.x, point.y, 0, 1 };
	return res.xy;
}

transform_from_matrix :: proc(mat: Mat4x4) -> Transform {
	t := Transform {
		mat = mat
	};
	transform_update(&t);
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