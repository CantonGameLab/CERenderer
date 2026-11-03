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

Scancode :: s3.Scancode
Transform :: matrix[4,4]f32

MAX_ENTITY_COUNT	:: 2000
ZERO3				:: [3]f32{0., 0., 0.}

NodeHandle :: struct {
	using node : ^Node,
	node_index : u32,
}

Entity :: struct {
	using node_handle : NodeHandle
}

CameraEntity :: struct {
	//parameters
	move_speed : f32,
	rotate_speed : f32,
	//states
	yaw : f32,
	pitch : f32,
	position : [3]f32,
}

entities : me.GenArray(MAX_ENTITY_COUNT, Entity)
sponza_entity : Entity
main_camera_entity : CameraEntity
global_time : f64

createNode :: proc(node_handle : ^NodeHandle) {
	node_index, ok := me.ArrayAlloc(&sam.nodes)
	if !ok {
		fmt.eprintln("[x] the node pool is full, so the node cannot be created")
		return
	}
	node_handle.node_index = node_index
	node_handle.node = me.ArrayGet(&sam.nodes, node_handle.node_index)
}

InitScene :: proc() {
	
	sponza_model_path := "resource/assets/sponza_lit/sponza_lit.gltf"
	sponza_nodes : []sam.Node
	sponza_direction_lights : []sam.DirectionLight
	sponza_point_lights : []sam.PointLight
	sponza_spot_lights : []sam.SpotLight
	sponza_ret := sam.LoadglTFScene(
		sponza_model_path,
		&sponza_nodes,
		&sponza_direction_lights,
		&sponza_point_lights,
		&sponza_spot_lights,
	)
	if sponza_ret != .Success {
		fmt.eprintln("[x] the sponza scene did not load:", sponza_ret)
		return
	}

	createNode(&sponza_entity.node_handle)

	sponza_entity.mesh_id = sponza_nodes[0].mesh_id
	sponza_entity.transform = sponza_nodes[0].transform
	me.RefRetain(&sam.meshes, sponza_entity.mesh_id)
	delete(sponza_nodes)

	for light in sponza_direction_lights {
		id, ok := me.ArrayAlloc(&sam.direction_lights)
		if !ok {
			fmt.eprintln("[x] the direction light pool is full, a light was dropped")
			continue
		}
		sam.direction_lights.data[id] = light
	}
	delete(sponza_direction_lights)

	for light in sponza_point_lights {
		id, ok := me.ArrayAlloc(&sam.point_lights)
		if !ok {
			fmt.eprintln("[x] the point light pool is full, a light was dropped")
			continue
		}
		sam.point_lights.data[id] = light
	}
	delete(sponza_point_lights)

	for light in sponza_spot_lights {
		id, ok := me.ArrayAlloc(&sam.spot_lights)
		if !ok {
			fmt.eprintln("[x] the spot light pool is full, a light was dropped")
			continue
		}
		sam.spot_lights.data[id] = light
	}
	delete(sponza_spot_lights)

	// Sponza measured 29.8 m along the nave, 18.3 m across and 12.4 m tall, and the
	// nave runs along +X with the lamp row at z = -0.25, so the camera stands in the
	// nave at eye height and looks down it from the west end.
	target := linalg.Vector3f32{6.0, 1.6, -0.25}
	up := linalg.Vector3f32{0.0, 1.0, 0.0}
	eye := linalg.Vector3f32{-6.4, 1.65, -0.25}

	// 20 mm on a 36 mm sensor is 84 degrees across, which on a 16:9 frame is 54 up.
	sam.Main_Camera.fov_y = math.to_radians_f32(54)
	sam.Main_Camera.near = 0.1
	sam.Main_Camera.far = 1000

	main_camera_entity.move_speed = 3.0
	main_camera_entity.rotate_speed = 45.
	main_camera_entity.position = eye

	forward_initial := linalg.vector_normalize(target - eye)
	main_camera_entity.yaw = math.atan2(forward_initial.x, -forward_initial.z)
	main_camera_entity.pitch = math.asin(clamp(forward_initial.y, -1.0, 1.0))

	sam.Main_Camera.transform = linalg.matrix4_inverse(
		linalg.matrix4_look_at_f32(main_camera_entity.position, target, up)
	)
}

Update :: proc(delta : f64) {

	global_time += delta

	f32_delta := f32(delta)
	f32_global_time := f32(global_time)

	using input := &event.Input_State
	using cam := &main_camera_entity

	delta_f32 := f32(delta)

	move_forward := f32(i32(key_down[Scancode.W])) - f32(i32(key_down[Scancode.S]))
	move_right := f32(i32(key_down[Scancode.D])) - f32(i32(key_down[Scancode.A]))
	move_local := [3]f32{move_right, 0., -move_forward}
	if move_local != ZERO3 {
		move_local = linalg.vector_normalize(move_local)
	}
	move_local *= move_speed * delta_f32

	rotate_up := f32(i32(key_down[Scancode.UP])) - f32(i32(key_down[Scancode.DOWN]))
	rotate_right := f32(i32(key_down[Scancode.RIGHT])) - f32(i32(key_down[Scancode.LEFT]))
	rotate_up *= math.to_radians_f32(rotate_speed) * delta_f32
	rotate_right *= math.to_radians_f32(rotate_speed) * delta_f32

	pitch += rotate_up
	pitch = math.min(math.max(pitch, math.to_radians_f32(-89.9)), math.to_radians_f32(89.9))
	yaw += rotate_right

	forward : [3]f32 = {
		math.cos(pitch) * math.sin(yaw),
		math.sin(pitch),
		-math.cos(pitch) * math.cos(yaw),
	}

	world := linalg.matrix4_inverse(
		linalg.matrix4_look_at_f32(position, position + forward, [3]f32{0., 1., 0.})
	)

	move_world := linalg.mul(world, [4]f32{move_local.x, move_local.y, move_local.z, 0.})
	position += {move_world.x, move_world.y, move_world.z}

	sam.Main_Camera.transform = world
}
