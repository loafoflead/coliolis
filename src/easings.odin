package main;

import "core:math";

// Credit to Andrey Sitnik(https://sitnik.ru/) and Ivan Solovev(https://solovev.one/)
// taken from https://easings.net

ease_out_expo :: proc(x: f32) -> f32 {
	return x == 1 ? 1 : 1 - math.pow(2, -10 * x);
}