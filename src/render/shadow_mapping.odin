package render

import gl "vendor:OpenGL"
import "core:fmt"
import "core:math"
import sam "../scene"
import me "../memory"
import "core:math/linalg"

ShadowMappingProgram :: struct {
	program : u32,
	u_light_mvp : i32,
	u_light_position : i32,
	u_light_direction : i32,
	u_shadow_mode : i32,

	u_has_normal_texture : i32,
	u_normal_texture : i32,

	m_model : i32,

	u_base_color_factor : i32,
	u_has_base_color_texture : i32,
	u_alpha_test : i32,
	u_alpha_cutoff : i32,

	u_light_intensity : i32,
	u_light_range : i32,
	u_cosine_inner_cone_angle : i32,
	u_cosine_outer_cone_angle : i32,
	
	//something parameter
	direction_light_resolution_width : i32,
	direction_light_resolution_height : i32,

	point_light_resolution_width : i32,
	point_light_resolution_height : i32,

	spot_light_resolution_width : i32,
	spot_light_resolution_height : i32,
}

shadow_mapping_program : ShadowMappingProgram

POINT_MODE :: 0
DIRECTION_MODE :: 1
SPOT_MODE :: 2

point_light_pcf_taps : i32 = 32

DIRECTION_SHADOW_UNIT :: DEPTH_COLOR_TEXTURE_UNIT + 1
POINT_SHADOW_UNIT :: DIRECTION_SHADOW_UNIT + sam.MAX_LIGHT_COUNT
SPOT_SHADOW_UNIT :: POINT_SHADOW_UNIT + sam.MAX_POINT_LIGHT_COUNT

direction_shadow_texture : u32
direction_shadow_depth_texture : u32
point_shadow_texture : u32
point_shadow_depth_texture : u32
spot_shadow_texture : u32
spot_shadow_depth_texture : u32
shadow_fbo : u32

direction_shadow_depth_renderbuffer : u32
point_shadow_depth_renderbuffer : u32
spot_shadow_depth_renderbuffer : u32

empty_cube_texture : u32

CreateEmptyCubeTexture :: proc() {
	gl.GenTextures(1, &empty_cube_texture)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, empty_cube_texture)
	for face in 0 ..< 6 {
		gl.TexImage2D(
			gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(face), 0,
			gl.DEPTH_COMPONENT24, 1, 1, 0, gl.DEPTH_COMPONENT, gl.FLOAT, nil,
		)
	}
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, 0)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, 0)
}

initShadowMapping :: proc() {
	using it_doesnt_matter := &shadow_mapping_program

	vs := compileShader(gl.VERTEX_SHADER, "resource/shaders/shadow_mapping.vert")
	fs := compileShader(gl.FRAGMENT_SHADER, "resource/shaders/shadow_mapping.frag")
	program = linkProgram(vs, fs)

	u_light_mvp = gl.GetUniformLocation(program, cstring("u_light_mvp"))
	u_light_position = gl.GetUniformLocation(program, cstring("u_light"))
	u_light_direction = gl.GetUniformLocation(program, cstring("u_light_direction"))
	u_shadow_mode = gl.GetUniformLocation(program, cstring("u_shadow_mode"))
	m_model = gl.GetUniformLocation(program, cstring("m_model"))
	u_base_color_factor = gl.GetUniformLocation(program, cstring("u_base_color_factor"))
	u_has_base_color_texture = gl.GetUniformLocation(program, cstring("u_has_base_color_texture"))
	u_alpha_test = gl.GetUniformLocation(program, cstring("u_alpha_test"))
	u_alpha_cutoff = gl.GetUniformLocation(program, cstring("u_alpha_cutoff"))
	u_has_normal_texture = gl.GetUniformLocation(program, cstring("u_has_normal_texture"))
	u_normal_texture = gl.GetUniformLocation(program, cstring("u_normal_texture"))
	u_light_intensity = gl.GetUniformLocation(program, cstring("u_light_intensity"))
	u_light_range = gl.GetUniformLocation(program, cstring("u_light_range"))
	u_cosine_inner_cone_angle = gl.GetUniformLocation(program, cstring("u_cosine_inner_cone_angle"))
	u_cosine_outer_cone_angle = gl.GetUniformLocation(program, cstring("u_cosine_outer_cone_angle"))

	for i in 0 ..< sam.MAX_LIGHT_COUNT {
		pbr.u_light_view_projs[i] = gl.GetUniformLocation(
			pbr.program,
			fmt.ctprintf("u_light_view_projs[%d]", i),
		)
	}
	pbr.u_light_count = gl.GetUniformLocation(pbr.program, cstring("u_light_count"))
	pbr.u_light_positions = gl.GetUniformLocation(pbr.program, cstring("u_light_positions"))
	pbr.u_light_colors = gl.GetUniformLocation(pbr.program, cstring("u_light_colors"))
	pbr.u_light_intensities = gl.GetUniformLocation(pbr.program, cstring("u_light_intensities"))
	pbr.u_light_directions = gl.GetUniformLocation(pbr.program, cstring("u_light_directions"))
	pbr.u_light_has_shadow = gl.GetUniformLocation(pbr.program, cstring("u_light_has_shadow"))
	pbr.u_light_width = gl.GetUniformLocation(pbr.program, cstring("u_light_width"))
	pbr.u_light_texel_worlds = gl.GetUniformLocation(pbr.program, cstring("u_light_texel_worlds"))
	pbr.u_direction_shadow_maps = gl.GetUniformLocation(pbr.program, cstring("u_direction_shadow_maps[0]"))

	pbr.u_point_light_count = gl.GetUniformLocation(pbr.program, cstring("u_point_light_count"))
	pbr.u_point_light_positions = gl.GetUniformLocation(pbr.program, cstring("u_point_light_positions"))
	pbr.u_point_light_colors = gl.GetUniformLocation(pbr.program, cstring("u_point_light_colors"))
	pbr.u_point_light_intensities = gl.GetUniformLocation(pbr.program, cstring("u_point_light_intensities"))
	pbr.u_point_light_has_shadow = gl.GetUniformLocation(pbr.program, cstring("u_point_light_has_shadow"))
	pbr.u_point_light_width = gl.GetUniformLocation(pbr.program, cstring("u_point_light_width"))
	pbr.u_point_light_ranges = gl.GetUniformLocation(pbr.program, cstring("u_point_light_ranges"))
	pbr.u_point_light_taps = gl.GetUniformLocation(pbr.program, cstring("u_point_light_taps"))
	pbr.u_point_shadow_maps = gl.GetUniformLocation(pbr.program, cstring("u_point_shadow_maps[0]"))

	for i in 0 ..< sam.MAX_SPOT_LIGHT_COUNT {
		pbr.u_spot_light_view_projs[i] = gl.GetUniformLocation(
			pbr.program,
			fmt.ctprintf("u_spot_light_view_projs[%d]", i),
		)
	}
	pbr.u_spot_light_count = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_count"))
	pbr.u_spot_light_positions = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_positions"))
	pbr.u_spot_light_colors = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_colors"))
	pbr.u_spot_light_intensities = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_intensities"))
	pbr.u_spot_light_ranges = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_ranges"))
	pbr.u_spot_light_directions = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_directions"))
	pbr.u_spot_light_angle_scales = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_angle_scales"))
	pbr.u_spot_light_angle_offsets = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_angle_offsets"))
	pbr.u_spot_light_has_shadow = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_has_shadow"))
	pbr.u_spot_shadow_maps = gl.GetUniformLocation(pbr.program, cstring("u_spot_shadow_maps[0]"))
	pbr.u_spot_light_width = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_width"))
	pbr.u_spot_light_texel_scales = gl.GetUniformLocation(pbr.program, cstring("u_spot_light_texel_scales"))

	max_texture_units : i32
	gl.GetIntegerv(gl.MAX_TEXTURE_IMAGE_UNITS, &max_texture_units)
	required_texture_units := i32(SPOT_SHADOW_UNIT + sam.MAX_SPOT_LIGHT_COUNT)
	if max_texture_units < required_texture_units {
		fmt.eprintln("[x] the pbr program needs", required_texture_units, "fragment texture units, but this GL only has", max_texture_units)
	}

	gl.UseProgram(pbr.program)
	direction_shadow_units : [sam.MAX_LIGHT_COUNT]i32
	for i in 0 ..< sam.MAX_LIGHT_COUNT {
		direction_shadow_units[i] = DIRECTION_SHADOW_UNIT + i32(i)
	}
	gl.Uniform1iv(pbr.u_direction_shadow_maps, sam.MAX_LIGHT_COUNT, &direction_shadow_units[0])
	point_shadow_units : [sam.MAX_POINT_LIGHT_COUNT]i32
	for i in 0 ..< sam.MAX_POINT_LIGHT_COUNT {
		point_shadow_units[i] = POINT_SHADOW_UNIT + i32(i)
	}
	gl.Uniform1iv(pbr.u_point_shadow_maps, sam.MAX_POINT_LIGHT_COUNT, &point_shadow_units[0])
	spot_shadow_units : [sam.MAX_SPOT_LIGHT_COUNT]i32
	for i in 0 ..< sam.MAX_SPOT_LIGHT_COUNT {
		spot_shadow_units[i] = SPOT_SHADOW_UNIT + i32(i)
	}
	gl.Uniform1iv(pbr.u_spot_shadow_maps, sam.MAX_SPOT_LIGHT_COUNT, &spot_shadow_units[0])

	gl.UseProgram(program)
	gl.Uniform1i(gl.GetUniformLocation(program, cstring("u_base_color_texture")), 0)
	gl.Uniform1i(u_normal_texture, 1)

	direction_light_resolution_width = 512
	direction_light_resolution_height = 512
	point_light_resolution_width = 512
	point_light_resolution_height = 512
	spot_light_resolution_width = 512
	spot_light_resolution_height = 512

	CreateShadowTextures()
	CreateEmptyCubeTexture()
}

CreateShadowTextures :: proc() {
	res_w := shadow_mapping_program.direction_light_resolution_width
	res_h := shadow_mapping_program.direction_light_resolution_height

	gl.GenTextures(1, &direction_shadow_texture)
	gl.BindTexture(gl.TEXTURE_2D_ARRAY, direction_shadow_texture)
	gl.TexImage3D(
		gl.TEXTURE_2D_ARRAY,
		0,
		gl.R32F,
		res_w,
		res_h,
		i32(sam.MAX_LIGHT_COUNT),
		0,
		gl.RED,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &direction_shadow_depth_texture)
	gl.BindTexture(gl.TEXTURE_2D_ARRAY, direction_shadow_depth_texture)
	gl.TexImage3D(
		gl.TEXTURE_2D_ARRAY,
		0,
		gl.DEPTH_COMPONENT24,
		res_w,
		res_h,
		i32(sam.MAX_LIGHT_COUNT),
		0,
		gl.DEPTH_COMPONENT,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenRenderbuffers(1, &direction_shadow_depth_renderbuffer)
	gl.BindRenderbuffer(gl.RENDERBUFFER, direction_shadow_depth_renderbuffer)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, res_w, res_h)

	res_w = shadow_mapping_program.point_light_resolution_width
	res_h = shadow_mapping_program.point_light_resolution_height

	gl.GenTextures(1, &point_shadow_texture)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP_ARRAY, point_shadow_texture)
	gl.TexImage3D(
		gl.TEXTURE_CUBE_MAP_ARRAY,
		0,
		gl.R32F,
		res_w,
		res_h,
		i32(sam.MAX_POINT_LIGHT_COUNT * 6),
		0,
		gl.RED,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &point_shadow_depth_texture)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP_ARRAY, point_shadow_depth_texture)
	gl.TexImage3D(
		gl.TEXTURE_CUBE_MAP_ARRAY,
		0,
		gl.DEPTH_COMPONENT24,
		res_w,
		res_h,
		i32(sam.MAX_POINT_LIGHT_COUNT * 6),
		0,
		gl.DEPTH_COMPONENT,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP_ARRAY, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenRenderbuffers(1, &point_shadow_depth_renderbuffer)
	gl.BindRenderbuffer(gl.RENDERBUFFER, point_shadow_depth_renderbuffer)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, res_w, res_h)

	res_w = shadow_mapping_program.spot_light_resolution_width
	res_h = shadow_mapping_program.spot_light_resolution_height

	gl.GenTextures(1, &spot_shadow_texture)
	gl.BindTexture(gl.TEXTURE_2D_ARRAY, spot_shadow_texture)
	gl.TexImage3D(
		gl.TEXTURE_2D_ARRAY,
		0,
		gl.R32F,
		res_w,
		res_h,
		i32(sam.MAX_SPOT_LIGHT_COUNT),
		0,
		gl.RED,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &spot_shadow_depth_texture)
	gl.BindTexture(gl.TEXTURE_2D_ARRAY, spot_shadow_depth_texture)
	gl.TexImage3D(
		gl.TEXTURE_2D_ARRAY,
		0,
		gl.DEPTH_COMPONENT24,
		res_w,
		res_h,
		i32(sam.MAX_SPOT_LIGHT_COUNT),
		0,
		gl.DEPTH_COMPONENT,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D_ARRAY, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenRenderbuffers(1, &spot_shadow_depth_renderbuffer)
	gl.BindRenderbuffer(gl.RENDERBUFFER, spot_shadow_depth_renderbuffer)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH_COMPONENT24, res_w, res_h)

	gl.GenFramebuffers(1, &shadow_fbo)
}


// Puts the shadow pass's program into the same alpha-test state the lighting pass's
// program is in for this material. Only MASK carries an alpha test: OPAQUE ignores the
// alpha channel outright, and BLEND's open question is how it composites, not whether it
// blocks light.
bindShadowAlphaTest :: proc(material : ^sam.Material) {
	if material != nil && material.alpha_mode == .Mask {
		has_tex : i32 = 0
		tex := me.RefGet(&sam.textures, material.base_color_texture.texture_id)
		if tex != nil {
			has_tex = 1
			gl.ActiveTexture(gl.TEXTURE0)
			gl.BindTexture(gl.TEXTURE_2D, tex.gl_texture_id)
		}
		gl.Uniform4fv(shadow_mapping_program.u_base_color_factor, 1, raw_data(&material.base_color_factor))
		gl.Uniform1i(shadow_mapping_program.u_has_base_color_texture, has_tex)
		gl.Uniform1f(shadow_mapping_program.u_alpha_cutoff, material.alpha_cutoff)
		gl.Uniform1i(shadow_mapping_program.u_alpha_test, 1)
		return
	}

	gl.Uniform1i(shadow_mapping_program.u_alpha_test, 0)
}

RasterizeShadowMap :: proc() {
	// Shadow casters are rasterised from both sides. A closed mesh pays only the extra
	// fragments, because a back face sits behind its front face and the depth test throws
	// it away, while a thin sheet -- a leaf, a curtain -- blocks light from both sides only
	// if both faces reach the map. Culling here would in any case be reading state the
	// previous frame happened to leave behind, which is a coincidence of draw order rather
	// than a decision.
	gl.Disable(gl.CULL_FACE)
	defer gl.Enable(gl.CULL_FACE)

	gl.UseProgram(shadow_mapping_program.program)

	for id in u32(1) ..= sam.direction_lights.next {
		if !sam.direction_lights.in_use[id] do continue
		if sam.direction_lights.data[id].light_fbo == {} {
			CreateDirectionLightShadowMap(id)
		}
		RasterizationDirectionLightShadowMap(&sam.direction_lights.data[id])
	}

	for id in u32(1) ..= sam.point_lights.next {
		if !sam.point_lights.in_use[id] do continue
		if sam.point_lights.data[id].light_fbo == {} {
			CreatePointLightShadowMap(id)
		}
		RasterizationPointLightShadowMap(&sam.point_lights.data[id])
	}

	for id in u32(1) ..= sam.spot_lights.next {
		if !sam.spot_lights.in_use[id] do continue
		if sam.spot_lights.data[id].light_fbo == {} {
			CreateSpotLightShadowMap(id)
		}
		RasterizationSpotLightShadowMap(&sam.spot_lights.data[id])
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

UniformShadowMapping :: proc() {
	using it_doesnt_matter := &pbr

	gl.UseProgram(program)

	// The light pools are sparse once a slot has been freed, so what the shader sees
	// is a compact copy: shader index i has to be the i-th live light, not pool slot i,
	// or a freed slot turns into a hole in the middle of the array while the count
	// still claims the array is dense.
	direction_count : i32
	direction_positions : [sam.MAX_LIGHT_COUNT][3]f32
	direction_colors : [sam.MAX_LIGHT_COUNT][3]f32
	direction_intensities : [sam.MAX_LIGHT_COUNT]f32
	direction_directions : [sam.MAX_LIGHT_COUNT][3]f32
	direction_widths : [sam.MAX_LIGHT_COUNT]f32
	direction_texel_worlds : [sam.MAX_LIGHT_COUNT]f32
	direction_has_shadow : [sam.MAX_LIGHT_COUNT]i32

	for id in u32(1) ..= sam.direction_lights.next {
		if !sam.direction_lights.in_use[id] do continue
		light := &sam.direction_lights.data[id]
		index := int(direction_count)

		gl.ActiveTexture(gl.TEXTURE0 + u32(DIRECTION_SHADOW_UNIT) + u32(index))
		gl.BindTexture(gl.TEXTURE_2D, light.tex_distance)

		direction_positions[index] = light.position
		direction_colors[index] = light.color
		direction_intensities[index] = light.intensity
		direction_directions[index] = light.direction
		direction_widths[index] = light.pcss_width
		direction_texel_worlds[index] = 2 * light.half_extent / f32(shadow_mapping_program.direction_light_resolution_width)
		direction_has_shadow[index] = light.tex_distance != 0 ? 1 : 0

		gl.UniformMatrix4fv(u_light_view_projs[index], 1, false, &light.proj_view[0, 0])

		direction_count += 1
	}

	gl.Uniform1iv(u_light_has_shadow, sam.MAX_LIGHT_COUNT, &direction_has_shadow[0])
	gl.Uniform1i(u_light_count, direction_count)

	if direction_count > 0 {
		gl.Uniform3fv(u_light_positions, direction_count, &direction_positions[0][0])
		gl.Uniform3fv(u_light_colors, direction_count, &direction_colors[0][0])
		gl.Uniform1fv(u_light_intensities, direction_count, &direction_intensities[0])
		gl.Uniform3fv(u_light_directions, direction_count, &direction_directions[0][0])
		gl.Uniform1fv(u_light_width, direction_count, &direction_widths[0])
		gl.Uniform1fv(u_light_texel_worlds, direction_count, &direction_texel_worlds[0])
	}

	//the point light

	point_count : i32
	point_positions : [sam.MAX_POINT_LIGHT_COUNT][3]f32
	point_colors : [sam.MAX_POINT_LIGHT_COUNT][3]f32
	point_intensities : [sam.MAX_POINT_LIGHT_COUNT]f32
	point_ranges : [sam.MAX_POINT_LIGHT_COUNT]f32
	point_widths : [sam.MAX_POINT_LIGHT_COUNT]f32
	point_has_shadow : [sam.MAX_POINT_LIGHT_COUNT]i32

	for id in u32(1) ..= sam.point_lights.next {
		if !sam.point_lights.in_use[id] do continue
		light := &sam.point_lights.data[id]
		index := int(point_count)

		gl.ActiveTexture(gl.TEXTURE0 + u32(POINT_SHADOW_UNIT) + u32(index))
		gl.BindTexture(gl.TEXTURE_CUBE_MAP, light.tex_distance)

		point_positions[index] = light.position
		point_colors[index] = light.color
		point_intensities[index] = light.intensity
		point_ranges[index] = light.range
		point_widths[index] = light.pcss_width
		point_has_shadow[index] = light.tex_distance != 0 ? 1 : 0

		point_count += 1
	}

	gl.Uniform1iv(u_point_light_has_shadow, sam.MAX_POINT_LIGHT_COUNT, &point_has_shadow[0])
	gl.Uniform1i(u_point_light_count, point_count)
	gl.Uniform1i(u_point_light_taps, point_light_pcf_taps)

	if point_count > 0 {
		gl.Uniform3fv(u_point_light_positions, point_count, &point_positions[0][0])
		gl.Uniform3fv(u_point_light_colors, point_count, &point_colors[0][0])
		gl.Uniform1fv(u_point_light_intensities, point_count, &point_intensities[0])
		gl.Uniform1fv(u_point_light_ranges, point_count, &point_ranges[0])
		gl.Uniform1fv(u_point_light_width, point_count, &point_widths[0])
	}

	//the spot light

	spot_count : i32
	spot_positions : [sam.MAX_SPOT_LIGHT_COUNT][3]f32
	spot_colors : [sam.MAX_SPOT_LIGHT_COUNT][3]f32
	spot_intensities : [sam.MAX_SPOT_LIGHT_COUNT]f32
	spot_ranges : [sam.MAX_SPOT_LIGHT_COUNT]f32
	spot_directions : [sam.MAX_SPOT_LIGHT_COUNT][3]f32
	spot_angle_scales : [sam.MAX_SPOT_LIGHT_COUNT]f32
	spot_angle_offsets : [sam.MAX_SPOT_LIGHT_COUNT]f32
	spot_widths : [sam.MAX_SPOT_LIGHT_COUNT]f32
	spot_texel_scales : [sam.MAX_SPOT_LIGHT_COUNT]f32
	spot_has_shadow : [sam.MAX_SPOT_LIGHT_COUNT]i32

	for id in u32(1) ..= sam.spot_lights.next {
		if !sam.spot_lights.in_use[id] do continue
		light := &sam.spot_lights.data[id]
		index := int(spot_count)

		gl.ActiveTexture(gl.TEXTURE0 + u32(SPOT_SHADOW_UNIT) + u32(index))
		gl.BindTexture(gl.TEXTURE_2D, light.tex_distance)

		cos_inner := math.cos(light.inner_cone_angle)
		cos_outer := math.cos(light.outer_cone_angle)
		angle_scale := 1.0 / max(f32(0.001), cos_inner - cos_outer)

		spot_positions[index] = light.position
		spot_colors[index] = light.color
		spot_intensities[index] = light.intensity
		spot_ranges[index] = light.range
		spot_directions[index] = light.direction
		spot_angle_scales[index] = angle_scale
		spot_angle_offsets[index] = -cos_outer * angle_scale
		spot_widths[index] = light.pcss_width
		spot_texel_scales[index] = 2 * math.tan(light.fov_y * 0.5) / f32(shadow_mapping_program.spot_light_resolution_width)
		spot_has_shadow[index] = light.tex_distance != 0 ? 1 : 0

		gl.UniformMatrix4fv(u_spot_light_view_projs[index], 1, false, &light.proj_view[0, 0])

		spot_count += 1
	}

	gl.Uniform1iv(u_spot_light_has_shadow, sam.MAX_SPOT_LIGHT_COUNT, &spot_has_shadow[0])
	gl.Uniform1i(u_spot_light_count, spot_count)

	if spot_count > 0 {
		gl.Uniform3fv(u_spot_light_positions, spot_count, &spot_positions[0][0])
		gl.Uniform3fv(u_spot_light_colors, spot_count, &spot_colors[0][0])
		gl.Uniform1fv(u_spot_light_intensities, spot_count, &spot_intensities[0])
		gl.Uniform1fv(u_spot_light_ranges, spot_count, &spot_ranges[0])
		gl.Uniform3fv(u_spot_light_directions, spot_count, &spot_directions[0][0])
		gl.Uniform1fv(u_spot_light_angle_scales, spot_count, &spot_angle_scales[0])
		gl.Uniform1fv(u_spot_light_angle_offsets, spot_count, &spot_angle_offsets[0])
		gl.Uniform1fv(u_spot_light_width, spot_count, &spot_widths[0])
		gl.Uniform1fv(u_spot_light_texel_scales, spot_count, &spot_texel_scales[0])
	}

	gl.ActiveTexture(gl.TEXTURE0)
}

CreatePointLightShadowMap :: proc(id : u32) {
	res_w := shadow_mapping_program.point_light_resolution_width
	res_h := shadow_mapping_program.point_light_resolution_height

	light := &sam.point_lights.data[id]

	// The distance cube. R32F rather than a depth format because the value has to survive as a
	// distance in metres: a depth attachment's contents are pinned to [0, 1] and mapped onto
	// [near, far] by the driver, so a distance written there arrives divided by the far plane
	// and a distance read from there has to be multiplied back. This one holds the metres.
	gl.GenTextures(1, &light.tex_distance)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, light.tex_distance)
	for face in 0 ..< 6 {
		gl.TexImage2D(
			gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(face),
			0,
			gl.R32F,
			res_w,
			res_h,
			0,
			gl.RED,
			gl.FLOAT,
			nil,
		)
	}
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)   // ← 0x8072
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_normal)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, light.tex_normal)
	for face in 0 ..< 6 {
		gl.TexImage2D(
			gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(face),
			0,
			gl.RGBA16F,
			res_w,
			res_h,
			0,
			gl.RGBA,
			gl.HALF_FLOAT,
			nil,
		)
	}
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_radiance)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, light.tex_radiance)
	for face in 0 ..< 6 {
		gl.TexImage2D(
			gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(face),
			0,
			gl.RGBA16F,
			res_w,
			res_h,
			0,
			gl.RGBA,
			gl.HALF_FLOAT,
			nil,
		)
	}
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_position)
	gl.BindTexture(gl.TEXTURE_CUBE_MAP, light.tex_position)
	for face in 0 ..< 6 {
		gl.TexImage2D(
			gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(face),
			0,
			gl.RGBA32F,
			res_w,
			res_h,
			0,
			gl.RGBA,
			gl.FLOAT,
			nil,
		)
	}
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenFramebuffers(1, &light.fbo)
	attachTextureToFramebuffer(light.light_fbo, gl.TEXTURE_CUBE_MAP_POSITIVE_X, point_shadow_depth_renderbuffer)
}

CreateDirectionLightShadowMap :: proc(id : u32) {
	res_w := shadow_mapping_program.direction_light_resolution_width
	res_h := shadow_mapping_program.direction_light_resolution_height

	light := &sam.direction_lights.data[id]

	gl.GenTextures(1, &light.tex_distance)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_distance)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R32F, res_w, res_h, 0, gl.RED, gl.FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_normal)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_normal)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, res_w, res_h, 0, gl.RGBA, gl.HALF_FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_radiance)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_radiance)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, res_w, res_h, 0, gl.RGBA, gl.HALF_FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_position)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_position)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, res_w, res_h, 0, gl.RGBA, gl.FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenFramebuffers(1, &light.fbo)
	attachTextureToFramebuffer(light.light_fbo, gl.TEXTURE_2D, direction_shadow_depth_renderbuffer)
}

CreateSpotLightShadowMap :: proc(id : u32) {
	res_w := shadow_mapping_program.spot_light_resolution_width
	res_h := shadow_mapping_program.spot_light_resolution_height

	light := &sam.spot_lights.data[id]

	gl.GenTextures(1, &light.tex_distance)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_distance)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.R32F, res_w, res_h, 0, gl.RED, gl.FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_normal)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_normal)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, res_w, res_h, 0, gl.RGBA, gl.HALF_FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_radiance)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_radiance)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, res_w, res_h, 0, gl.RGBA, gl.HALF_FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenTextures(1, &light.tex_position)
	gl.BindTexture(gl.TEXTURE_2D, light.tex_position)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA32F, res_w, res_h, 0, gl.RGBA, gl.FLOAT, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0)

	gl.GenFramebuffers(1, &light.fbo)
	attachTextureToFramebuffer(light.light_fbo, gl.TEXTURE_2D, spot_shadow_depth_renderbuffer)
}

attachTextureToFramebuffer :: proc(light_fbo : sam.LightFBO, texture_kind : u32, depth_renderbuffer : u32) {
	gl.BindFramebuffer(gl.FRAMEBUFFER, light_fbo.fbo)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, texture_kind, light_fbo.tex_distance, 0)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, texture_kind, light_fbo.tex_normal, 0)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT2, texture_kind, light_fbo.tex_radiance, 0)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT3, texture_kind, light_fbo.tex_position, 0)
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, depth_renderbuffer)
	draw_buffers : [4]u32 = {gl.COLOR_ATTACHMENT0, gl.COLOR_ATTACHMENT1, gl.COLOR_ATTACHMENT2, gl.COLOR_ATTACHMENT3}
	gl.DrawBuffers(4, &draw_buffers[0])
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	
}

RasterizationPointLightShadowMap :: proc(light : ^sam.PointLight) {
	gl.Viewport(
		0,
		0,
		shadow_mapping_program.point_light_resolution_width,
		shadow_mapping_program.point_light_resolution_height,
	)

	light_pos := light.position
	gl.Uniform3f(shadow_mapping_program.u_light_position, light_pos.x, light_pos.y, light_pos.z)
	gl.Uniform1i(shadow_mapping_program.u_shadow_mode, POINT_MODE)
	gl.Uniform1f(shadow_mapping_program.u_light_intensity, light.intensity)
	gl.Uniform1f(shadow_mapping_program.u_light_range, light.range)

	// A face nothing is drawn into has to read as "no caster", which for a distance means
	// beyond anything the light can reach. The far plane is that bound: every projection matrix
	// in the array was built with it, so a distance past it is a distance past every caster.
	far_plane := light.far
	clear_distance : [4]f32 = {far_plane, far_plane, far_plane, far_plane}
	clear_zero : [4]f32 = {0, 0, 0, 0}

	for face in 0 ..< 6 {
		attachTextureToFramebuffer(light.light_fbo, gl.TEXTURE_CUBE_MAP_POSITIVE_X + u32(face), point_shadow_depth_renderbuffer)
		gl.BindFramebuffer(gl.FRAMEBUFFER, light.fbo)
		gl.ClearBufferfv(gl.COLOR, 0, &clear_distance[0])
		gl.ClearBufferfv(gl.COLOR, 1, &clear_zero[0])
		gl.ClearBufferfv(gl.COLOR, 2, &clear_zero[0])
		gl.ClearBufferfv(gl.COLOR, 3, &clear_zero[0])
		gl.Clear(gl.DEPTH_BUFFER_BIT)

		light_proj_view := light.proj_views[face]
		for node_index in u32(1) ..= sam.nodes.next {
			if !sam.nodes.in_use[node_index] do continue
			if light.light_node_index == node_index do continue
			node := me.ArrayGet(&sam.nodes, node_index)
			if node == nil do continue
			mesh := me.RefGet(&sam.meshes, node.mesh_id)
			if mesh == nil do continue
			light_mvp := linalg.mul(light_proj_view, node.transform)
			gl.UniformMatrix4fv(shadow_mapping_program.u_light_mvp, 1, false, &light_mvp[0, 0])
			gl.UniformMatrix4fv(shadow_mapping_program.m_model, 1, false, &node.transform[0, 0])
			for &p in mesh.primitives {
				if !sam.IsAABBInNDC(p.aabb, light_mvp) do continue
				bindShadowAlphaTest(me.RefGet(&sam.materials, p.material_id))
				gl.BindVertexArray(p.gl_vao_id)
				gl.DrawElements(gl.TRIANGLES, i32(p.indices_count), gl.UNSIGNED_INT, nil)
			}
		}
	}
}

RasterizationSpotLightShadowMap :: proc(light : ^sam.SpotLight) {
	attachTextureToFramebuffer(light.light_fbo, gl.TEXTURE_2D, spot_shadow_depth_renderbuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, light.fbo)
	gl.Viewport(
		0,
		0,
		shadow_mapping_program.spot_light_resolution_width,
		shadow_mapping_program.spot_light_resolution_height,
	)

	clear_distance : [4]f32 = {light.far, 0, 0, 0}
	clear_zero : [4]f32 = {0, 0, 0, 0}
	gl.ClearBufferfv(gl.COLOR, 0, &clear_distance[0])
	gl.ClearBufferfv(gl.COLOR, 1, &clear_zero[0])
	gl.ClearBufferfv(gl.COLOR, 2, &clear_zero[0])
	gl.ClearBufferfv(gl.COLOR, 3, &clear_zero[0])
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	light_pos := light.position
	gl.Uniform3f(shadow_mapping_program.u_light_position, light_pos.x, light_pos.y, light_pos.z)
	direction := light.direction
	gl.Uniform3f(shadow_mapping_program.u_light_direction, direction.x, direction.y, direction.z)
	gl.Uniform1i(shadow_mapping_program.u_shadow_mode, SPOT_MODE)
	gl.Uniform1f(shadow_mapping_program.u_light_intensity, light.intensity)
	gl.Uniform1f(shadow_mapping_program.u_light_range, light.range)
	gl.Uniform1f(shadow_mapping_program.u_cosine_inner_cone_angle, math.cos(light.inner_cone_angle))
	gl.Uniform1f(shadow_mapping_program.u_cosine_outer_cone_angle, math.cos(light.outer_cone_angle))

	light_proj_view := light.proj_view

	for i in u32(1) ..= sam.nodes.next {
		if !sam.nodes.in_use[i] do continue
		node := me.ArrayGet(&sam.nodes, i)
		if node == nil do continue
		mesh := me.RefGet(&sam.meshes, node.mesh_id)
		if mesh == nil do continue
		light_mvp := linalg.mul(light_proj_view, node.transform)
		gl.UniformMatrix4fv(shadow_mapping_program.u_light_mvp, 1, false, &light_mvp[0, 0])
		gl.UniformMatrix4fv(shadow_mapping_program.m_model, 1, false, &node.transform[0, 0])
		for &p in mesh.primitives {
			if !sam.IsAABBInNDC(p.aabb, light_mvp) do continue
			bindShadowAlphaTest(me.RefGet(&sam.materials, p.material_id))
			gl.BindVertexArray(p.gl_vao_id)
			gl.DrawElements(gl.TRIANGLES, i32(p.indices_count), gl.UNSIGNED_INT, nil)
		}
	}
}

RasterizationDirectionLightShadowMap :: proc(light : ^sam.DirectionLight) {
	attachTextureToFramebuffer(light.light_fbo, gl.TEXTURE_2D, direction_shadow_depth_renderbuffer)
	gl.BindFramebuffer(gl.FRAMEBUFFER, light.fbo)
	gl.Viewport(
		0,
		0,
		shadow_mapping_program.direction_light_resolution_width,
		shadow_mapping_program.direction_light_resolution_height,
	)

	clear_distance : [4]f32 = {abs(light.far), 0, 0, 0}
	clear_zero : [4]f32 = {0, 0, 0, 0}
	gl.ClearBufferfv(gl.COLOR, 0, &clear_distance[0])
	gl.ClearBufferfv(gl.COLOR, 1, &clear_zero[0])
	gl.ClearBufferfv(gl.COLOR, 2, &clear_zero[0])
	gl.ClearBufferfv(gl.COLOR, 3, &clear_zero[0])
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	light_pos := light.position
	gl.Uniform3f(shadow_mapping_program.u_light_position, light_pos.x, light_pos.y, light_pos.z)
	direction := light.direction
	gl.Uniform3f(shadow_mapping_program.u_light_direction, direction.x, direction.y, direction.z)
	gl.Uniform1i(shadow_mapping_program.u_shadow_mode, DIRECTION_MODE)
	gl.Uniform1f(shadow_mapping_program.u_light_intensity, light.intensity)

	light_proj_view := light.proj_view

	for i in u32(1) ..= sam.nodes.next {
		if !sam.nodes.in_use[i] do continue
		node := me.ArrayGet(&sam.nodes, i)
		if node == nil do continue
		mesh := me.RefGet(&sam.meshes, node.mesh_id)
		if mesh == nil do continue
		light_mvp := linalg.mul(light_proj_view, node.transform)
		gl.UniformMatrix4fv(shadow_mapping_program.u_light_mvp, 1, false, &light_mvp[0, 0])
		gl.UniformMatrix4fv(shadow_mapping_program.m_model, 1, false, &node.transform[0, 0])
		for &p in mesh.primitives {
			if !sam.IsAABBInNDC(p.aabb, light_mvp) do continue
			bindShadowAlphaTest(me.RefGet(&sam.materials, p.material_id))
			gl.BindVertexArray(p.gl_vao_id)
			gl.DrawElements(gl.TRIANGLES, i32(p.indices_count), gl.UNSIGNED_INT, nil)
		}
	}
}
