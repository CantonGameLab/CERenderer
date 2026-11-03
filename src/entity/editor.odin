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


