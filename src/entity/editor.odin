package entity

import "vendor:cgltf"
import gl "vendor:OpenGL"
import s3 "vendor:sdl3"
import "core:fmt"
import me "../memory/"
import sam "../scene/"
import "../event/"
import "../paths/"
import "core:strings"
import "core:math/linalg"
import "core:math"

Node :: sam.Node
PointLight :: sam.PointLight
SpotLight :: sam.SpotLight

Focused :: struct {
	kind : FocusedKind,
	node : ^Node,
	point_light : ^PointLight,
	spot_light : ^SpotLight,
}

FocusedKind :: enum {
	Node,
	PointLight,
	SpotLight,
}

Line :: struct {
	a : [3]f32,
	b : [3]f32,
	color : [3]f32,
	thickness : f32,
}

Ellipse :: struct {
	normal : [3]f32,
	centor : [3]f32,
	major_half : f32,
	minor_half : f32,
	color : [3]f32,
	thickness : f32,
}

ArrowHandle :: struct {
	transform : Transform,
	length : f32,
	arrow_length : f32,
	thickness : f32,
	using focused : Focused,
}

lines : [dynamic]Line
ellipses : [dynamic]Ellipse
arrow_handles : [dynamic]ArrowHandle

drawLine :: proc(a, b : [3]f32, color : [3]f32, thickness : f32) {
	append(&lines, Line{a = a, b = b, color = color, thickness = thickness})
}

drawEllipse :: proc(normal, centor : [3]f32, major_half : f32, minor_half : f32, color : [3]f32, thickness : f32) {
	append(&ellipses, Ellipse{normal = normal, centor = centor, major_half = major_half, minor_half = minor_half, color = color, thickness = thickness})
}

drawArrowHandle :: proc(transform : Transform, length : f32, arrow_length : f32, thickness : f32, focus : Focused) {
	append(&arrow_handles, ArrowHandle{transform = transform, length = length, arrow_length = arrow_length, thickness = thickness, focused = focus})
}

clearOutline :: proc() {
	clear(&lines)
	clear(&ellipses)
	clear(&arrow_handles)
}

