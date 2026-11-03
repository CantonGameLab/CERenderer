package render

import "core:fmt"
import s3 "vendor:sdl3"
import gl "vendor:OpenGL"
import "core:c"
import "core:os"
import "core:strings"
import "core:math/linalg"
import me "../memory/"
import sam "../scene/"
import "core:slice"


DepthTest :: struct {
	program : u32,
	u_base_color_factor : i32,
	u_base_color_texture : i32,
	u_alpha_cutoff : i32,
	u_alpha_mode : i32,
	u_has_base_color_texture : i32,
	m_proj : i32,
	m_view : i32,
	m_model : i32,
}
depth_test : DepthTest

DEPTH_COLOR_TEXTURE_UNIT :: 6

initPreDepthTest :: proc() {
	vs, fs : u32
	vs = compileShader(gl.VERTEX_SHADER, "resource/shaders/depth.vert")
	fs = compileShader(gl.FRAGMENT_SHADER, "resource/shaders/depth.frag")
	depth_test.program = linkProgram(vs, fs)
	depth_test.u_base_color_factor = gl.GetUniformLocation(depth_test.program, cstring("u_base_color_factor"))
	depth_test.u_base_color_texture = gl.GetUniformLocation(depth_test.program, cstring("u_base_color_texture"))
	depth_test.u_has_base_color_texture = gl.GetUniformLocation(depth_test.program, cstring("u_has_base_color_texture"))
	depth_test.u_alpha_cutoff = gl.GetUniformLocation(depth_test.program, cstring("u_alpha_cutoff"))
	depth_test.u_alpha_mode = gl.GetUniformLocation(depth_test.program, cstring("u_alpha_mode"))
	depth_test.m_proj = gl.GetUniformLocation(depth_test.program, cstring("m_proj"))
	depth_test.m_view = gl.GetUniformLocation(depth_test.program, cstring("m_view"))
	depth_test.m_model = gl.GetUniformLocation(depth_test.program, cstring("m_model"))

	gl.UseProgram(depth_test.program)
	gl.Uniform1i(depth_test.u_base_color_texture, DEPTH_COLOR_TEXTURE_UNIT)
}

drawDepthBuffer :: proc() {

	gl.UseProgram(depth_test.program)

	aspect := f32(window_width) / f32(window_height)

	view_matrix := sam.ViewMatrix(&sam.Main_Camera)
	proj_matrix := sam.ProjMatrix(&sam.Main_Camera, aspect)

	gl.UniformMatrix4fv(depth_test.m_view, 1, false, &view_matrix[0,0])
	gl.UniformMatrix4fv(depth_test.m_proj, 1, false, &proj_matrix[0,0])

	gl.DepthMask(true)
	gl.DepthFunc(gl.LEQUAL)
	
	for node_index in u32(1) ..= sam.nodes.next {
		
		node := me.ArrayGet(&sam.nodes, node_index)
		if node == nil do continue

		gl.UniformMatrix4fv(depth_test.m_model, 1, false, &node.transform[0,0])

		mesh := me.RefGet(&sam.meshes, node.mesh_id)
		if mesh == nil do continue
		
		for &p, p_index in mesh.primitives {
			mat := me.RefGet(&sam.materials, p.material_id)
			if mat == nil do continue

			has_tex := i32(mat.base_color_texture.texture_id != 0)

			uploadTexture(DEPTH_COLOR_TEXTURE_UNIT, mat.base_color_texture.texture_id, depth_test.u_base_color_texture)

			gl.Uniform4fv(depth_test.u_base_color_factor, 1, raw_data(&mat.base_color_factor))
			gl.Uniform1i(depth_test.u_has_base_color_texture, has_tex)
			gl.Uniform1i(depth_test.u_alpha_mode, i32(mat.alpha_mode))
			gl.Uniform1f(depth_test.u_alpha_cutoff, mat.alpha_cutoff)
			gl.BindVertexArray(p.gl_vao_id)
			gl.DrawElements(gl.TRIANGLES, i32(p.indices_count), gl.UNSIGNED_INT, nil)
		}
	}

	uploadTexture :: proc(unit : u32, texture_id : u32, location : i32) {
		if texture_id != 0 {
			tex := me.RefGet(&sam.textures, texture_id)
			if tex != nil {
				gl.ActiveTexture(gl.TEXTURE0 + unit)
				gl.BindTexture(gl.TEXTURE_2D, tex.gl_texture_id)
				gl.ActiveTexture(gl.TEXTURE0)
			}
		}
	}
}
