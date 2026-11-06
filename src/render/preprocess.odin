package render

import gl "vendor:OpenGL"

Preprocess :: struct {
	tex_depth : u32,
	fbo_depth : u32,
}

preprocess : Preprocess

initPreprocess :: proc() {
	gl.GenFramebuffers(1, &preprocess.fbo_depth)
	setPreprocessWindowSize()
}

setPreprocessWindowSize :: proc() {
	gl.DeleteTextures(1, &preprocess.tex_depth)
	gl.GenTextures(1, &preprocess.tex_depth)

	gl.BindTexture(gl.TEXTURE_2D, preprocess.tex_depth)
	gl.TexImage2D(
		gl.TEXTURE_2D,
		0,
		gl.DEPTH_COMPONENT24,
		window_width,
		window_height,
		0,
		gl.DEPTH_COMPONENT,
		gl.FLOAT,
		nil,
	)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

	gl.BindFramebuffer(gl.FRAMEBUFFER, preprocess.fbo_depth)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, preprocess.tex_depth, 0)
	gl.DrawBuffer(gl.NONE)
	gl.ReadBuffer(gl.NONE)

	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
		gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
		gl.BindTexture(gl.TEXTURE_2D, 0)
		return
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	gl.BindTexture(gl.TEXTURE_2D, 0)
}

resolvePreprocess :: proc() {
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, after.multisample_fbo)
	gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, preprocess.fbo_depth)
	gl.BlitFramebuffer(
		0, 0, window_width, window_height,
		0, 0, window_width, window_height,
		gl.DEPTH_BUFFER_BIT,
		gl.NEAREST,
	)
	gl.BindFramebuffer(gl.FRAMEBUFFER, after.multisample_fbo)
}
