package render

import "core:fmt"
import s3 "vendor:sdl3"
import gl "vendor:OpenGL"
import "core:c"
import "core:os"
import "core:strings"
import "core:math"
import "core:math/linalg"
import me "../memory/"
import sam "../scene/"
import "../entity/"

OutlineProgram :: struct {
	program : u32,
	u_view_proj : i32,
	u_viewport : i32,
	u_tan_half_fov : i32,
	u_depth_texture : i32,
	u_fade_range : i32,
	u_occluded_alpha : i32,
}

OutlineFillProgram :: struct {
	program : u32,
	u_view_proj : i32,
	u_viewport : i32,
	u_depth_texture : i32,
	u_fade_range : i32,
	u_occluded_alpha : i32,
}

OutlineFillVertex :: struct {
	position : [3]f32,
	color : [3]f32,
}

outline_line : OutlineProgram
outline_ellipse : OutlineProgram
outline_fill : OutlineFillProgram

outline_fade_range : f32 = 0.002
outline_occluded_alpha : f32 = 0.2

outline_line_vao : u32
outline_line_vbo : u32
outline_line_capacity : int
outline_ellipse_vao : u32
outline_ellipse_vbo : u32
outline_ellipse_capacity : int
outline_quad_vbo : u32
outline_quad_ebo : u32

outline_fill_vao : u32
outline_fill_vbo : u32
outline_fill_capacity : int

outline_arrow_lines : [dynamic]entity.Line
outline_arrow_triangles : [dynamic]OutlineFillVertex

ARROW_HEAD_HEIGHT_RATIO :: 1.46
ARROW_ARC_SEGMENTS :: 24

outlineInstanceAttrib :: proc(location : u32, component_count : i32, offset_bytes : uintptr, stride : i32) {
	gl.EnableVertexAttribArray(location)
	gl.VertexAttribPointer(location, component_count, gl.FLOAT, false, stride, offset_bytes)
	gl.VertexAttribDivisor(location, 1)
}

outlineVertexAttrib :: proc(location : u32, component_count : i32, offset_bytes : uintptr, stride : i32) {
	gl.EnableVertexAttribArray(location)
	gl.VertexAttribPointer(location, component_count, gl.FLOAT, false, stride, offset_bytes)
}

makeOutlineProgram :: proc(vert_path, frag_path : string) -> OutlineProgram {
	result : OutlineProgram
	vs := compileShader(gl.VERTEX_SHADER, vert_path)
	fs := compileShader(gl.FRAGMENT_SHADER, frag_path)
	result.program = linkProgram(vs, fs)
	result.u_view_proj = gl.GetUniformLocation(result.program, cstring("u_view_proj"))
	result.u_viewport = gl.GetUniformLocation(result.program, cstring("u_viewport"))
	result.u_tan_half_fov = gl.GetUniformLocation(result.program, cstring("u_tan_half_fov"))
	result.u_depth_texture = gl.GetUniformLocation(result.program, cstring("u_depth_texture"))
	result.u_fade_range = gl.GetUniformLocation(result.program, cstring("u_fade_range"))
	result.u_occluded_alpha = gl.GetUniformLocation(result.program, cstring("u_occluded_alpha"))
	return result
}

makeOutlineFillProgram :: proc(vert_path, frag_path : string) -> OutlineFillProgram {
	result : OutlineFillProgram
	vs := compileShader(gl.VERTEX_SHADER, vert_path)
	fs := compileShader(gl.FRAGMENT_SHADER, frag_path)
	result.program = linkProgram(vs, fs)
	result.u_view_proj = gl.GetUniformLocation(result.program, cstring("u_view_proj"))
	result.u_viewport = gl.GetUniformLocation(result.program, cstring("u_viewport"))
	result.u_depth_texture = gl.GetUniformLocation(result.program, cstring("u_depth_texture"))
	result.u_fade_range = gl.GetUniformLocation(result.program, cstring("u_fade_range"))
	result.u_occluded_alpha = gl.GetUniformLocation(result.program, cstring("u_occluded_alpha"))
	return result
}

outlineAxisColor :: proc(axis_index : int) -> [3]f32 {
	if axis_index == 1 {
		return {0., 1., 0.}
	}
	if axis_index == 2 {
		return {0., 0., 1.}
	}
	return {1., 0., 0.}
}

outlineProject :: proc(view_proj : matrix[4,4]f32, point : [3]f32) -> (ndc : [2]f32, ok : bool) {
	clip := linalg.mul(view_proj, [4]f32{point.x, point.y, point.z, 1.0})
	if clip.w <= 1e-5 {
		return [2]f32{}, false
	}
	inv_w := 1.0 / clip.w
	return [2]f32{clip.x * inv_w, clip.y * inv_w}, true
}

outlinePixel :: proc(ndc : [2]f32) -> [2]f32 {
	return [2]f32{
		(ndc.x * 0.5 + 0.5) * f32(window_width),
		(ndc.y * 0.5 + 0.5) * f32(window_height),
	}
}

outlineProjectedPixels :: proc(view_proj : matrix[4,4]f32, a, b : [3]f32) -> f32 {
	ndc_a, ok_a := outlineProject(view_proj, a)
	ndc_b, ok_b := outlineProject(view_proj, b)
	if !ok_a || !ok_b {
		return 0
	}
	return linalg.length(outlinePixel(ndc_a) - outlinePixel(ndc_b))
}

outlineScreenLengthToWorld :: proc(view_proj : matrix[4,4]f32, origin : [3]f32, direction : [3]f32, screen_length : f32, probe : f32) -> f32 {
	measured := outlineProjectedPixels(view_proj, origin, origin + direction * probe)
	if measured < 1e-4 {
		return 0
	}
	return probe * screen_length / measured
}

outlineTransformAxis :: proc(transform : matrix[4,4]f32, axis_index : int) -> [3]f32 {
	column := [4]f32{}
	column[axis_index] = 1.0
	transformed := linalg.mul(transform, column)
	direction := [3]f32{transformed.x, transformed.y, transformed.z}
	if linalg.length(direction) <= 1e-8 {
		return [3]f32{0, 0, 0}
	}
	return linalg.vector_normalize(direction)
}

outlineConeBasis :: proc(axis : [3]f32) -> (u, v : [3]f32) {
	reference := [3]f32{0, 1, 0}
	if abs(axis.y) > 0.99 {
		reference = [3]f32{1, 0, 0}
	}
	u = linalg.vector_normalize(linalg.cross(reference, axis))
	v = linalg.cross(axis, u)
	return
}

outlineConeBasePoint :: proc(center, u, v : [3]f32, radius : f32, angle : f32) -> [3]f32 {
	return center + u * (radius * math.cos(angle)) + v * (radius * math.sin(angle))
}

outlineAppendLine :: proc(a, b : [3]f32, color : [3]f32, thickness : f32) {
	append(&outline_arrow_lines, entity.Line{a = a, b = b, color = color, thickness = thickness})
}

outlineAppendTriangle :: proc(a, b, c : [3]f32, color : [3]f32) {
	append(&outline_arrow_triangles, OutlineFillVertex{position = a, color = color})
	append(&outline_arrow_triangles, OutlineFillVertex{position = b, color = color})
	append(&outline_arrow_triangles, OutlineFillVertex{position = c, color = color})
}

outlineAppendDisk :: proc(center, u, v : [3]f32, radius : f32, color : [3]f32) {
	for index in 0 ..< ARROW_ARC_SEGMENTS {
		angle_a := 2.0 * math.PI * f32(index) / f32(ARROW_ARC_SEGMENTS)
		angle_b := 2.0 * math.PI * f32(index + 1) / f32(ARROW_ARC_SEGMENTS)
		outlineAppendTriangle(
			center,
			outlineConeBasePoint(center, u, v, radius, angle_a),
			outlineConeBasePoint(center, u, v, radius, angle_b),
			color,
		)
	}
}

buildArrowGeometry :: proc(view_proj : matrix[4,4]f32, camera_position : [3]f32) {
	clear(&outline_arrow_lines)
	clear(&outline_arrow_triangles)

	forward_4 := linalg.mul(sam.Main_Camera.transform, [4]f32{0.0, 0.0, -1.0, 0.0})
	camera_forward := linalg.vector_normalize([3]f32{forward_4.x, forward_4.y, forward_4.z})

	for handle in entity.arrow_handles[:] {
		transform := handle.transform
		origin_4 := linalg.mul(transform, [4]f32{0.0, 0.0, 0.0, 1.0})
		origin := [3]f32{origin_4.x, origin_4.y, origin_4.z}

		for axis_index in 0 ..< 3 {
			axis := outlineTransformAxis(transform, axis_index)
			if linalg.length(axis) <= 1e-6 {
				continue
			}

			color := outlineAxisColor(axis_index)
			thickness := handle.thickness
			origin_to_camera := camera_position - origin
			origin_probe := max(f32(1e-4), linalg.length(origin_to_camera) * 1e-3)

			length := outlineScreenLengthToWorld(view_proj, origin, axis, handle.length, origin_probe)
			if length <= 1e-5 {
				continue
			}
			view_forward_component := linalg.dot(camera_forward, axis)
			if view_forward_component < -1e-5 {
				origin_view_depth := linalg.dot(camera_forward, origin - camera_position)
				length_limit := (origin_view_depth - sam.Main_Camera.near) / -view_forward_component
				if length_limit > 0.0 {
					length = min(length, length_limit * 0.9)
				}
			}
			if length <= 1e-5 {
				continue
			}

			tip := origin + axis * length
			_, tip_ok := outlineProject(view_proj, tip)
			if !tip_ok {
				continue
			}

			tip_to_camera := camera_position - tip
			tip_distance := linalg.length(tip_to_camera)
			if tip_distance <= 1e-5 {
				continue
			}
			view_direction := linalg.vector_normalize(tip_to_camera)
			across := linalg.cross(axis, view_direction)
			if linalg.length(across) < 1e-4 {
				reference := [3]f32{0, 1, 0}
				if abs(axis.y) > 0.99 {
					reference = [3]f32{1, 0, 0}
				}
				across = linalg.cross(axis, reference)
			}
			across = linalg.vector_normalize(across)

			tip_probe := max(f32(1e-4), tip_distance * 1e-3)
			width := outlineScreenLengthToWorld(view_proj, tip, across, handle.arrow_length, tip_probe)
			if width <= 1e-5 {
				continue
			}

			radius := width * 0.5
			height := width * ARROW_HEAD_HEIGHT_RATIO
			if height > length * 0.9 {
				height = length * 0.9
			}
			base_center := tip - axis * height
			u, v := outlineConeBasis(axis)

			outlineAppendLine(origin, base_center, color, thickness)

			denominator := linalg.dot(tip - camera_position, axis)
			if abs(denominator) < 1e-5 {
				outlineAppendDisk(base_center, u, v, radius, color)
				continue
			}

			tangent_parameter := height / denominator
			probe_point := tip + (camera_position - tip) * tangent_parameter
			base_to_probe := probe_point - base_center
			distance := linalg.length(base_to_probe)
			if distance <= radius * 1.001 {
				outlineAppendDisk(base_center, u, v, radius, color)
				continue
			}

			phi := math.atan2(linalg.dot(base_to_probe, v), linalg.dot(base_to_probe, u))
			alpha := math.acos(clamp(radius / distance, -1.0, 1.0))
			angle_a := phi - alpha
			angle_b := phi + alpha

			midpoint_a := outlineConeBasePoint(base_center, u, v, radius, phi)
			midpoint_b := outlineConeBasePoint(base_center, u, v, radius, phi + math.PI)
			distance_a := outlineProjectedPixels(view_proj, tip, midpoint_a)
			distance_b := outlineProjectedPixels(view_proj, tip, midpoint_b)

			arc_start, arc_end : f32
			if distance_a >= distance_b {
				arc_start = angle_a
				arc_end = angle_b
			} else {
				arc_start = angle_b
				arc_end = angle_a + 2.0 * math.PI
			}

			for index in 0 ..< ARROW_ARC_SEGMENTS {
				angle_start := arc_start + (arc_end - arc_start) * f32(index) / f32(ARROW_ARC_SEGMENTS)
				angle_end := arc_start + (arc_end - arc_start) * f32(index + 1) / f32(ARROW_ARC_SEGMENTS)
				outlineAppendTriangle(
					tip,
					outlineConeBasePoint(base_center, u, v, radius, angle_start),
					outlineConeBasePoint(base_center, u, v, radius, angle_end),
					color,
				)
			}
		}
	}
}

initOutline :: proc() {
	outline_line = makeOutlineProgram("resource/shaders/outline_line.vert", "resource/shaders/outline_line.frag")
	outline_ellipse = makeOutlineProgram("resource/shaders/outline_ellipse.vert", "resource/shaders/outline_ellipse.frag")
	outline_fill = makeOutlineFillProgram("resource/shaders/outline_fill.vert", "resource/shaders/outline_fill.frag")

	quad_vertices := [4][2]f32{{-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
	quad_indices := [6]u32{0, 1, 2, 0, 2, 3}

	gl.GenBuffers(1, &outline_quad_vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_quad_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, size_of(quad_vertices), raw_data(quad_vertices[:]), gl.STATIC_DRAW)

	gl.GenVertexArrays(1, &outline_line_vao)
	gl.GenBuffers(1, &outline_line_vbo)
	gl.BindVertexArray(outline_line_vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_line_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, 0, nil, gl.DYNAMIC_DRAW)
	outlineInstanceAttrib(0, 3, offset_of(entity.Line, a), i32(size_of(entity.Line)))
	outlineInstanceAttrib(1, 3, offset_of(entity.Line, b), i32(size_of(entity.Line)))
	outlineInstanceAttrib(2, 4, offset_of(entity.Line, color), i32(size_of(entity.Line)))
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_quad_vbo)
	outlineVertexAttrib(3, 2, 0, i32(size_of([2]f32)))
	gl.GenBuffers(1, &outline_quad_ebo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, outline_quad_ebo)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(quad_indices), raw_data(quad_indices[:]), gl.STATIC_DRAW)

	gl.GenVertexArrays(1, &outline_fill_vao)
	gl.GenBuffers(1, &outline_fill_vbo)
	gl.BindVertexArray(outline_fill_vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_fill_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, 0, nil, gl.DYNAMIC_DRAW)
	outlineVertexAttrib(0, 3, offset_of(OutlineFillVertex, position), i32(size_of(OutlineFillVertex)))
	outlineVertexAttrib(1, 3, offset_of(OutlineFillVertex, color), i32(size_of(OutlineFillVertex)))

	gl.GenVertexArrays(1, &outline_ellipse_vao)
	gl.GenBuffers(1, &outline_ellipse_vbo)
	gl.BindVertexArray(outline_ellipse_vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_ellipse_vbo)
	gl.BufferData(gl.ARRAY_BUFFER, 0, nil, gl.DYNAMIC_DRAW)
	outlineInstanceAttrib(0, 3, offset_of(entity.Ellipse, normal), i32(size_of(entity.Ellipse)))
	outlineInstanceAttrib(1, 3, offset_of(entity.Ellipse, centor), i32(size_of(entity.Ellipse)))
	outlineInstanceAttrib(2, 2, offset_of(entity.Ellipse, major_half), i32(size_of(entity.Ellipse)))
	outlineInstanceAttrib(3, 4, offset_of(entity.Ellipse, color), i32(size_of(entity.Ellipse)))
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_quad_vbo)
	outlineVertexAttrib(4, 2, 0, i32(size_of([2]f32)))
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, outline_quad_ebo)

	gl.BindVertexArray(0)
	gl.BindBuffer(gl.ARRAY_BUFFER, 0)
}

uploadOutlineInstances :: proc(vbo : u32, data : rawptr, size : int, capacity : ^int) {
	gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
	if size > capacity^ {
		gl.BufferData(gl.ARRAY_BUFFER, size, nil, gl.DYNAMIC_DRAW)
		capacity^ = size
	}
	if size > 0 {
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, size, data)
	}
}

uploadOutlineTriangles :: proc(data : rawptr, size : int) {
	gl.BindBuffer(gl.ARRAY_BUFFER, outline_fill_vbo)
	if size > outline_fill_capacity {
		gl.BufferData(gl.ARRAY_BUFFER, size, nil, gl.DYNAMIC_DRAW)
		outline_fill_capacity = size
	}
	if size > 0 {
		gl.BufferSubData(gl.ARRAY_BUFFER, 0, size, data)
	}
}

drawOutline :: proc() {
	lines := entity.lines[:]
	ellipses := entity.ellipses[:]

	aspect := f32(window_width) / f32(window_height)
	proj_matrix := sam.ProjMatrix(&sam.Main_Camera, aspect)
	view_matrix := sam.ViewMatrix(&sam.Main_Camera)
	view_proj := linalg.mul(proj_matrix, view_matrix)

	camera_4 := linalg.mul(sam.Main_Camera.transform, [4]f32{0.0, 0.0, 0.0, 1.0})
	camera_position := [3]f32{camera_4.x, camera_4.y, camera_4.z}
	buildArrowGeometry(view_proj, camera_position)

	line_count := len(lines)
	ellipse_count := len(ellipses)
	arrow_line_count := len(outline_arrow_lines)
	triangle_count := len(outline_arrow_triangles)
	if line_count == 0 && ellipse_count == 0 && arrow_line_count == 0 && triangle_count == 0 {
		return
	}

	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.DepthMask(false)
	gl.DepthFunc(gl.LEQUAL)
	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)

	gl.ActiveTexture(gl.TEXTURE0)
	gl.BindTexture(gl.TEXTURE_2D, preprocess.tex_depth)

	if line_count > 0 || arrow_line_count > 0 {
		gl.UseProgram(outline_line.program)
		gl.UniformMatrix4fv(outline_line.u_view_proj, 1, false, &view_proj[0, 0])
		gl.Uniform2f(outline_line.u_viewport, f32(window_width), f32(window_height))
		gl.Uniform1i(outline_line.u_depth_texture, 0)
		gl.Uniform1f(outline_line.u_fade_range, outline_fade_range)
		gl.Uniform1f(outline_line.u_occluded_alpha, outline_occluded_alpha)
	}

	if line_count > 0 {
		uploadOutlineInstances(
			outline_line_vbo,
			raw_data(lines),
			line_count * size_of(entity.Line),
			&outline_line_capacity,
		)
		gl.BindVertexArray(outline_line_vao)
		gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil, i32(line_count))
	}

	if arrow_line_count > 0 {
		uploadOutlineInstances(
			outline_line_vbo,
			raw_data(outline_arrow_lines[:]),
			arrow_line_count * size_of(entity.Line),
			&outline_line_capacity,
		)
		gl.BindVertexArray(outline_line_vao)
		gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil, i32(arrow_line_count))
	}

	if triangle_count > 0 {
		gl.UseProgram(outline_fill.program)
		gl.UniformMatrix4fv(outline_fill.u_view_proj, 1, false, &view_proj[0, 0])
		gl.Uniform2f(outline_fill.u_viewport, f32(window_width), f32(window_height))
		gl.Uniform1i(outline_fill.u_depth_texture, 0)
		gl.Uniform1f(outline_fill.u_fade_range, outline_fade_range)
		gl.Uniform1f(outline_fill.u_occluded_alpha, outline_occluded_alpha)
		uploadOutlineTriangles(
			raw_data(outline_arrow_triangles[:]),
			triangle_count * size_of(OutlineFillVertex),
		)
		gl.BindVertexArray(outline_fill_vao)
		gl.DrawArrays(gl.TRIANGLES, 0, i32(triangle_count))
	}

	if ellipse_count > 0 {
		gl.UseProgram(outline_ellipse.program)
		gl.UniformMatrix4fv(outline_ellipse.u_view_proj, 1, false, &view_proj[0, 0])
		gl.Uniform2f(outline_ellipse.u_viewport, f32(window_width), f32(window_height))
		gl.Uniform1f(outline_ellipse.u_tan_half_fov, 1.0 / proj_matrix[1, 1])
		gl.Uniform1i(outline_ellipse.u_depth_texture, 0)
		gl.Uniform1f(outline_ellipse.u_fade_range, outline_fade_range)
		gl.Uniform1f(outline_ellipse.u_occluded_alpha, outline_occluded_alpha)
		uploadOutlineInstances(
			outline_ellipse_vbo,
			raw_data(ellipses),
			ellipse_count * size_of(entity.Ellipse),
			&outline_ellipse_capacity,
		)
		gl.BindVertexArray(outline_ellipse_vao)
		gl.DrawElementsInstanced(gl.TRIANGLES, 6, gl.UNSIGNED_INT, nil, i32(ellipse_count))
	}

	gl.DepthMask(true)
	gl.Disable(gl.BLEND)
	gl.BlendFunc(gl.ONE, gl.ZERO)
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
}
