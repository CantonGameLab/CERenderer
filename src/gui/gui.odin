package gui

import s3 "vendor:sdl3"
import gl "vendor:OpenGL"
import im "vendor:imgui"
import im_gl3 "vendor:imgui/backends/opengl3"
import im_sdl3 "vendor:imgui/backends/sdl3"
import render "../render"

bloom_strength_location : i32

rgb :: proc(hex: u32, alpha : f32 = 1.0) -> im.Vec4 {
	return im.Vec4{
		f32((hex >> 16) & 0xFF) / 255.0,
		f32((hex >> 8) & 0xFF) / 255.0,
		f32(hex & 0xFF) / 255.0,
		alpha,
	}
}

applyTheme :: proc() {
	im.StyleColorsDark()
	style := im.GetStyle()

	style.Alpha = 1.0
	style.DisabledAlpha = 0.55
	style.WindowPadding = im.Vec2{8.0, 8.0}
	style.FramePadding = im.Vec2{10.0, 6.0}
	style.CellPadding = im.Vec2{6.0, 4.0}
	style.ItemSpacing = im.Vec2{8.0, 6.0}
	style.ItemInnerSpacing = im.Vec2{6.0, 5.0}
	style.IndentSpacing = 20.0
	style.ScrollbarSize = 16.0
	style.GrabMinSize = 14.0

	style.WindowRounding = 4.0
	style.ChildRounding = 4.0
	style.FrameRounding = 3.0
	style.PopupRounding = 4.0
	style.ScrollbarRounding = 3.0
	style.GrabRounding = 3.0
	style.TabRounding = 4.0

	style.WindowBorderSize = 2.0
	style.ChildBorderSize = 1.0
	style.PopupBorderSize = 2.0
	style.FrameBorderSize = 1.0
	style.TabBarBorderSize = 1.0
	style.WindowTitleAlign = im.Vec2{0.5, 0.5}
	style.WindowMinSize = im.Vec2{160.0, 60.0}
	style.FontSizeBase = 18.0

	colors := &style.Colors
	colors[im.Col.Text] = rgb(0xF2E7D3)
	colors[im.Col.TextDisabled] = rgb(0x6E7C77)
	colors[im.Col.WindowBg] = rgb(0x263C5E)
	colors[im.Col.ChildBg] = rgb(0x1E2E44)
	colors[im.Col.PopupBg] = rgb(0x2E4460)
	colors[im.Col.Border] = rgb(0x8FB4D8)
	colors[im.Col.BorderShadow] = rgb(0x000000, 0.0)
	colors[im.Col.FrameBg] = rgb(0x0B131C)
	colors[im.Col.FrameBgHovered] = rgb(0x152534)
	colors[im.Col.FrameBgActive] = rgb(0x0F3A2C)

	colors[im.Col.TitleBg] = rgb(0x3A2521)
	colors[im.Col.TitleBgActive] = rgb(0x5E332C)
	colors[im.Col.TitleBgCollapsed] = rgb(0x2A1B18)
	colors[im.Col.MenuBarBg] = rgb(0x263C5E)

	colors[im.Col.ScrollbarBg] = rgb(0x0B131C)
	colors[im.Col.ScrollbarGrab] = rgb(0x0F6A4E)
	colors[im.Col.ScrollbarGrabHovered] = rgb(0x0A8A62)
	colors[im.Col.ScrollbarGrabActive] = rgb(0x00974C)

	colors[im.Col.CheckMark] = rgb(0x7ADE7A)
	colors[im.Col.CheckboxSelectedBg] = rgb(0x0F6A4E)
	colors[im.Col.SliderGrab] = rgb(0xF0B070)
	colors[im.Col.SliderGrabActive] = rgb(0xFFD5A8)
	colors[im.Col.Button] = rgb(0x0E7A58)
	colors[im.Col.ButtonHovered] = rgb(0x14A870)
	colors[im.Col.ButtonActive] = rgb(0x0B5C44)
	colors[im.Col.Header] = rgb(0x00974C)
	colors[im.Col.HeaderHovered] = rgb(0x10B060)
	colors[im.Col.HeaderActive] = rgb(0x007A3E)

	colors[im.Col.Separator] = rgb(0x3E5A78)
	colors[im.Col.SeparatorHovered] = rgb(0xF0B070)
	colors[im.Col.SeparatorActive] = rgb(0xFFD5A8)
	colors[im.Col.ResizeGrip] = rgb(0x0F6A4E, 0.4)
	colors[im.Col.ResizeGripHovered] = rgb(0x0A8A62, 0.7)
	colors[im.Col.ResizeGripActive] = rgb(0x00974C)
	colors[im.Col.InputTextCursor] = rgb(0xF2E7D3)

	colors[im.Col.Tab] = rgb(0x1B2C42)
	colors[im.Col.TabHovered] = rgb(0x27455F)
	colors[im.Col.TabSelected] = rgb(0x00974C)
	colors[im.Col.TabSelectedOverline] = rgb(0x7ADE7A)
	colors[im.Col.TabDimmed] = rgb(0x142033)
	colors[im.Col.TabDimmedSelected] = rgb(0x0F6A4E)
	colors[im.Col.TabDimmedSelectedOverline] = rgb(0x7ADE7A, 0.3)
	colors[im.Col.DockingPreview] = rgb(0xF0B070, 0.6)
	colors[im.Col.DockingEmptyBg] = rgb(0x1E2E44)

	colors[im.Col.PlotLines] = rgb(0xF2E7D3)
	colors[im.Col.PlotLinesHovered] = rgb(0xFFAE79)
	colors[im.Col.PlotHistogram] = rgb(0xFFAE79)
	colors[im.Col.PlotHistogramHovered] = rgb(0xFFD5A8)

	colors[im.Col.TableHeaderBg] = rgb(0x263C5E)
	colors[im.Col.TableBorderStrong] = rgb(0x0B131C)
	colors[im.Col.TableBorderLight] = rgb(0x3E5A78)
	colors[im.Col.TableRowBg] = rgb(0x000000, 0.0)
	colors[im.Col.TableRowBgAlt] = rgb(0xFFFFFF, 0.06)

	colors[im.Col.TextLink] = rgb(0x7ADE7A)
	colors[im.Col.TextSelectedBg] = rgb(0x882016, 0.7)
	colors[im.Col.TreeLines] = rgb(0x4A6A8A)
	colors[im.Col.DragDropTarget] = rgb(0xFFAE79)
	colors[im.Col.DragDropTargetBg] = rgb(0xFFAE79, 0.12)
	colors[im.Col.UnsavedMarker] = rgb(0xFF6A5A)
	colors[im.Col.NavCursor] = rgb(0xFFAE79)
	colors[im.Col.NavWindowingHighlight] = rgb(0xF2E7D3)
	colors[im.Col.NavWindowingDimBg] = rgb(0x000000, 0.6)
	colors[im.Col.ModalWindowDimBg] = rgb(0x000000, 0.8)
}

InitGUI :: proc() -> bool {
	im.CHECKVERSION()
	im.CreateContext()

	io := im.GetIO()
	io.ConfigFlags = {.NavEnableKeyboard, .DockingEnable, .ViewportsEnable}
	io.IniFilename = cstring("imgui.ini")

	applyTheme()

	font := im.FontAtlas_AddFontFromFileTTF(io.Fonts, cstring("resource/fonts/Karmina Regular/Karmina Regular.otf"), 18.0)
	if font != nil {
		io.FontDefault = font
	}

	if !im_sdl3.InitForOpenGL(render.window, rawptr(render.gl_context)) do return false
	if !im_gl3.Init(cstring("#version 440 core")) do return false

	bloom_strength_location = gl.GetUniformLocation(render.blit_program, cstring("u_bloom_strength"))
	return true
}


GUI :: proc() {

	im_gl3.NewFrame()
	im_sdl3.NewFrame()
	im.NewFrame()
	im.DockSpaceOverViewport(0, nil, {.PassthruCentralNode})

	//actually layout the gui

	if im.Begin(cstring("Renderer Settings"), nil) {
		im.Text(cstring("Post-process and output"))
		im.Separator()
		im.SetNextItemWidth(240.0)
		im.SliderFloat(cstring("Exposure"), &render.exposure, 0.05, 3.0, "%.3f")
		im.SetNextItemWidth(240.0)
		im.SliderFloat(cstring("Bloom threshold"), &render.bloom.threshold, 0.0, 5.0, "%.3f")
		im.SetNextItemWidth(240.0)
		im.SliderFloat(cstring("Bloom strength"), &render.bloom.strength, 0.0, 2.0, "%.3f")
		im.SetNextItemWidth(240.0)
		im.SliderFloat(cstring("Ambient"), &render.ambient, 0.0, 0.5, "%.3f")
	}
	im.End()
}



RenderGUI :: proc() {

	im.Render()
	draw_data := im.GetDrawData()

	w, h := render.GetWindowSize()
	gl.Viewport(0, 0, w, h)
	gl.Disable(gl.FRAMEBUFFER_SRGB)
	im_gl3.RenderDrawData(draw_data)

	if .ViewportsEnable in im.GetIO().ConfigFlags {
		backup_window := s3.GL_GetCurrentWindow()
		backup_context := s3.GL_GetCurrentContext()

		im.UpdatePlatformWindows()
		im.RenderPlatformWindowsDefault(nil, nil)

		s3.GL_MakeCurrent(backup_window, backup_context)
	}

	gl.Enable(gl.FRAMEBUFFER_SRGB)
}
