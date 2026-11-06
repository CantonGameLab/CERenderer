package main

import "core:fmt"
import s3 "vendor:sdl3"
import gl "vendor:OpenGL"
import "event/"
import "gui/"
import "render/"
import "scene/"
import "entity/"

now_seconds : f64
last_seconds : f64

getTime :: proc() -> f64 {
	return f64(s3.GetTicksNS()) / f64(1e9)
}

main :: proc() {
	render.Init()
	render.InitShader()
	entity.InitScene()
	gui.InitGUI()

	last_seconds = getTime()

	for {
		now_seconds = getTime()
		delta := now_seconds - last_seconds

		event.FlushInputState()
		if event.Poll(gui.ProcessEventGUI) {
			break
		}

		gui.GUI()

		entity.Update(delta)
		scene.PreComputation()
		render.Render()

		gui.RenderGUI()

		s3.GL_SwapWindow(render.window)

		last_seconds = now_seconds
	}

	return 
}
