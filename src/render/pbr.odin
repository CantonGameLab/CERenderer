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

PBRProgram :: struct {
	vs : u32,
	fs : u32,
	program : u32,
	//locations
	m_proj : i32,
	m_view : i32,
	m_model : i32,
	m_normal : i32,
	u_base_color_factor : i32,
	u_base_color_texture : i32,
	u_has_base_color_texture : i32,
	u_normal_texture : i32,
	u_has_normal_texture : i32,
	u_normal_scale : i32,
	u_has_metallic_roughness_texture : i32,
	u_metallic_roughness_texture : i32,
	u_metallic_factor : i32,
	u_roughness_factor : i32,
	u_emissive_factor : i32,
	u_emissive_strength : i32,
	u_ambient : i32,

	u_light_count : i32,
	u_light_positions : i32,
	u_light_colors : i32,
	u_light_intensities : i32,
	u_light_directions : i32,
	u_light_has_shadow : i32,
	u_light_width : i32,
	u_light_texel_worlds : i32,
	u_light_view_projs : [sam.MAX_LIGHT_COUNT]i32,
	u_direction_shadow_maps : i32,

	u_point_light_count : i32,
	u_point_light_positions : i32,
	u_point_light_colors : i32,
	u_point_light_intensities : i32,
	u_point_light_ranges : i32,
	u_point_light_has_shadow : i32,
	u_point_light_width : i32,
	u_point_light_taps : i32,
	u_point_shadow_maps : i32,

	u_spot_light_count : i32,
	u_spot_light_positions : i32,
	u_spot_light_colors : i32,
	u_spot_light_intensities : i32,
	u_spot_light_ranges : i32,
	u_spot_light_directions : i32,
	u_spot_light_angle_scales : i32,
	u_spot_light_angle_offsets : i32,
	u_spot_light_has_shadow : i32,
	u_spot_light_width : i32,
	u_spot_light_texel_scales : i32,
	u_spot_shadow_maps : i32,
	u_spot_light_view_projs : [sam.MAX_SPOT_LIGHT_COUNT]i32,

	u_camera_transform : i32,
	u_shininess : i32,
	u_specular_strength : i32,
	u_double_sided : i32,
	u_alpha_mode : i32,
	u_alpha_cutoff : i32,

}

DrawIterm :: struct{
	primitive_id : u32,
	node_id : u32,
	distance : f32,
	cull : bool,
}

// Unit 0 is the base colour texture, so the normal map sits on the next one. The
// shadow maps start after both of them.
NORMAL_TEXTURE_UNIT :: 1
METALLIC_ROUGHNESS_TEXTURE_UNIT :: 5

ambient : f32 = 0.12

program : PBRProgram

solid_draw_list : [dynamic]DrawIterm
transparent_draw_list : [dynamic]DrawIterm

drawPBR :: proc() {

	defer clear(&solid_draw_list)
	defer clear(&transparent_draw_list)

	gl.UseProgram(program.program)

	aspect := f32(window_width) / f32(window_height)

	// Upload the proj, view matrix and camera transform

	view_matrix := sam.ViewMatrix(&sam.Main_Camera)
	proj_matrix := sam.ProjMatrix(&sam.Main_Camera, aspect)
	proj_view := linalg.mul(proj_matrix, view_matrix)


	gl.UniformMatrix4fv(program.m_view, 1, false, &view_matrix[0,0])
	gl.UniformMatrix4fv(program.m_proj, 1, false, &proj_matrix[0,0])
	gl.UniformMatrix4fv(program.u_camera_transform, 1, false, &sam.Main_Camera.transform[0,0])
	gl.Uniform1f(program.u_ambient, ambient)

	main_camera_position := [3]f32{ 
		sam.Main_Camera.transform[0, 3], 
		sam.Main_Camera.transform[1, 3], 
		sam.Main_Camera.transform[2, 3],
	}

	main_camera_neg_z_vector := [3]f32 {
		-sam.Main_Camera.transform[0, 2],
		-sam.Main_Camera.transform[1, 2],
		-sam.Main_Camera.transform[2, 2],
	}

	for index := u32(1); index <= sam.nodes.next; index += 1 {
		if !sam.nodes.in_use[index] do continue
		node := &sam.nodes.data[index]
		if node == nil do continue
		mesh := me.RefGet(&sam.meshes, node.mesh_id)

		mvp := linalg.mul(proj_view, node.transform)

		position := [3]f32{ node.transform[0, 3], node.transform[1, 3], node.transform[2, 3] }
		
		distance := linalg.dot(
			position - main_camera_position,
			main_camera_neg_z_vector,
		)

		for &p, p_index in mesh.primitives {
			if !sam.IsAABBInNDC(p.aabb, mvp) do continue
			material := me.RefGet(&sam.materials, p.material_id)
			if material == nil do continue

			the_list : ^[dynamic]DrawIterm
			if material.alpha_mode == .Opaque || material.alpha_mode == .Mask {
				the_list = &solid_draw_list
			} else {
				the_list = &transparent_draw_list
			} 
			append(
				the_list, 
				DrawIterm{
					primitive_id = u32(p_index),
					node_id = index,
					distance = distance,
					cull = !material.double_sided,
				},
			)
		}
	}

	compareDrawItermByBiggerDepth :: proc(a, b : DrawIterm) -> bool {
		if a.cull != b.cull {
			return b.cull
		}
		if(a.distance != b.distance) {
			return a.distance > b.distance
		}
		return a.node_id < b.node_id
	}

	compareDrawItermBySmallerDepth :: proc(a, b : DrawIterm) -> bool {
		if a.cull != b.cull {
			return b.cull
		}
		if (a.distance != b.distance) {
			return a.distance < b.distance
		}
		return a.node_id < b.node_id
	}
	
	slice.sort_by(solid_draw_list[:], compareDrawItermBySmallerDepth)
	slice.sort_by(transparent_draw_list[:], compareDrawItermByBiggerDepth)


	
	gl.DepthFunc(gl.LEQUAL)
	gl.DepthMask(true)
	gl.Disable(gl.BLEND)

	drawPrimitves(solid_draw_list[:])

	gl.DepthMask(false)
	defer gl.DepthMask(true)
	gl.Enable(gl.BLEND)
	defer gl.Disable(gl.BLEND)

	drawPrimitves(transparent_draw_list[:])
}

drawPrimitves :: proc(draw_list : []DrawIterm) {
	if len(draw_list) > 0 && draw_list[0].cull {
		gl.Enable(gl.CULL_FACE)
	}
	for &draw_iterm, index in draw_list {
		
		node := me.ArrayGet(&sam.nodes, draw_iterm.node_id)
		if node == nil do continue
		mesh := me.RefGet(&sam.meshes, node.mesh_id)
		if mesh == nil do continue

		if index > 0 && draw_list[index - 1].cull != draw_iterm.cull {
			if draw_iterm.cull {
				gl.Enable(gl.CULL_FACE)
			} else {
				gl.Disable(gl.CULL_FACE)
			}
		}

		if index == 0 || draw_list[index - 1].node_id != draw_list[index].node_id {
			// When the index switches to a different node, we re-upload all the parameters related to the node
			gl.UniformMatrix4fv(program.m_model, 1, false, &node.transform[0,0])
			m3 := linalg.matrix3_from_matrix4_f32(node.transform)
			normal_matrix := linalg.transpose(linalg.matrix3_inverse_f32(m3))
			gl.UniformMatrix3fv(program.m_normal, 1, false, &normal_matrix[0,0])
		}

		p := &mesh.primitives[draw_iterm.primitive_id]
		
		mat := me.RefGet(&sam.materials, p.material_id)
		if mat == nil do continue

		has_tex := i32(mat.base_color_texture.texture_id != 0)
		has_normal := i32(mat.normal_texture.texture_id != 0)
		has_mr := i32(mat.pbr.metallic_roughness_texture.texture_id != 0)

		uploadTexture(0, mat.base_color_texture.texture_id, program.u_base_color_texture)
		uploadTexture(NORMAL_TEXTURE_UNIT, mat.normal_texture.texture_id, program.u_normal_texture)
		uploadTexture(METALLIC_ROUGHNESS_TEXTURE_UNIT, mat.metallic_roughness_texture.texture_id, program.u_metallic_roughness_texture)
		gl.Uniform1i(program.u_has_normal_texture, has_normal)
		gl.Uniform1f(program.u_normal_scale, mat.normal_texture.scale)
		gl.Uniform1f(program.u_metallic_factor, mat.metallic_factor)
		gl.Uniform1f(program.u_roughness_factor, mat.roughness_factor)
		gl.Uniform1i(program.u_has_metallic_roughness_texture, has_mr)
		gl.Uniform4fv(program.u_base_color_factor, 1, raw_data(&mat.base_color_factor))
		gl.Uniform1i(program.u_has_base_color_texture, has_tex)
		gl.Uniform3fv(program.u_emissive_factor, 1, raw_data(&mat.emissive_factor))
		gl.Uniform1f(program.u_emissive_strength, mat.emissive_strength)
		gl.Uniform1i(program.u_double_sided, i32(mat.double_sided))
		gl.Uniform1i(program.u_alpha_mode, i32(mat.alpha_mode))
		gl.Uniform1f(program.u_alpha_cutoff, mat.alpha_cutoff)
		gl.BindVertexArray(p.gl_vao_id)
		gl.DrawElements(gl.TRIANGLES, i32(p.indices_count), gl.UNSIGNED_INT, nil)
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

initPBR :: proc() {
	program.vs = compileShader(gl.VERTEX_SHADER, "resource/shaders/pbr.vert")
	program.fs = compileShader(gl.FRAGMENT_SHADER, "resource/shaders/pbr.frag")
	program.program = linkProgram(program.vs, program.fs)
	program.m_proj = gl.GetUniformLocation(program.program, cstring("m_proj"))
	program.m_view = gl.GetUniformLocation(program.program, cstring("m_view"))
	program.m_model = gl.GetUniformLocation(program.program, cstring("m_model"))
	program.m_normal = gl.GetUniformLocation(program.program, cstring("m_normal"))
	program.u_base_color_factor = gl.GetUniformLocation(program.program, cstring("u_base_color_factor"))
	program.u_base_color_texture = gl.GetUniformLocation(program.program, cstring("u_base_color_texture"))
	program.u_has_base_color_texture = gl.GetUniformLocation(program.program, cstring("u_has_base_color_texture"))
	program.u_normal_texture = gl.GetUniformLocation(program.program, cstring("u_normal_texture"))
	program.u_has_normal_texture = gl.GetUniformLocation(program.program, cstring("u_has_normal_texture"))
	program.u_normal_scale = gl.GetUniformLocation(program.program, cstring("u_normal_scale"))
	program.u_emissive_factor = gl.GetUniformLocation(program.program, cstring("u_emissive_factor"))
	program.u_emissive_strength = gl.GetUniformLocation(program.program, cstring("u_emissive_strength"))
	program.u_ambient = gl.GetUniformLocation(program.program, cstring("u_ambient"))
	program.u_camera_transform = gl.GetUniformLocation(program.program, cstring("u_camera_transform"))
	program.u_shininess = gl.GetUniformLocation(program.program, cstring("u_shininess"))
	program.u_specular_strength = gl.GetUniformLocation(program.program, cstring("u_specular_strength"))
	program.u_double_sided = gl.GetUniformLocation(program.program, cstring("u_double_sided"))
	program.u_alpha_mode = gl.GetUniformLocation(program.program, cstring("u_alpha_mode"))
	program.u_alpha_cutoff = gl.GetUniformLocation(program.program, cstring("u_alpha_cutoff"))
	program.u_has_metallic_roughness_texture = gl.GetUniformLocation(program.program, cstring("u_has_metallic_roughness_texture"))
	program.u_metallic_roughness_texture = gl.GetUniformLocation(program.program, cstring("u_metallic_roughness_texture"))
	program.u_metallic_factor = gl.GetUniformLocation(program.program, cstring("u_metallic_factor"))
	program.u_roughness_factor = gl.GetUniformLocation(program.program, cstring("u_roughness_factor"))

	gl.UseProgram(program.program)
	gl.Uniform1i(program.u_base_color_texture, 0)
	gl.Uniform1i(program.u_normal_texture, NORMAL_TEXTURE_UNIT)
	gl.Uniform1i(program.u_metallic_roughness_texture, METALLIC_ROUGHNESS_TEXTURE_UNIT)
	gl.Uniform1f(program.u_shininess, 64.0)
	gl.Uniform1f(program.u_specular_strength, 0.35)
}
