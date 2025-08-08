//This file is the starting point of your game.
//
//Some important procedures are:
//- game_init_window: Opens the window
//- game_init: Sets up the game state
//- game_update: Run once per frame
//- game_should_close: For stopping your game when close button is pressed
//- game_shutdown: Shuts down game and frees memory
//- game_shutdown_window: Closes window
//
//The procs above are used regardless if you compile using the `build_release`
//script or the `build_hot_reload` script. However, in the hot reload case, the
//contents of this file is compiled as part of `build/hot_reload/game.dll` (or
//.dylib/.so on mac/linux). In the hot reload cases some other procedures are
//also used in order to facilitate the hot reload functionality:
//
//- game_memory: Run just before a hot reload. That way game_hot_reload.exe has a
//      pointer to the game's memory that it can hand to the new game DLL.
//- game_hot_reloaded: Run after a hot reload so that the `g_mem` global
//      variable can be set to whatever pointer it was in the old DLL.
//
//NOTE: When compiled as part of `build_release`, `build_debug` or `build_web`
//then this whole package is just treated as a normal Odin package. No DLL is
//created.

package game

import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"

PIXEL_WINDOW_HEIGHT :: 180

//TODO(Fausto): reconsider this
Rotations :: enum {
	_0_DEG   = 0,
	_90_DEG  = 90,
	_180_DEG = 180,
	_270_DEG = 270,
}

//TOOD(Fausto): Will we weven need more?
EntityKind :: enum {
	PIPE,
}

// Generic entity type. Contains everything. DiscUnion ?
Entity :: struct {
	//TODO(Fausto): Add members for location in atlas
	pos:       rl.Vector2,
	kind:      EntityKind,
	specifics: EntityTypes,
	selected:  bool,
}

Pipe :: struct {
	is_elbow: bool,
	rotation: Rotations, //only 4 options?
	flow:     f32, // from 0 -> 1
}

EntityTypes :: union {
	Pipe,
}

PIPE_SPRITE_SIZE :: 68
PIPE_WIDTH :: 34
PIPE_HEIGHT :: 34

reset_pipe_grid :: proc() {
	//first cleanup
	//for &ent in g_mem.entities {
	//	free(&ent)
	//}
	clear_dynamic_array(&g_mem.entities)

	//then lets recreate our entity array
	//TODO(Fausto): Revisit how we think about doing this
	//Make some number of pipes idk
	//max_grid_size_pixels := rl.GetScreenHeight() //Always take screen height instaead of min whatever...
	//grid_start := max_grid_size_pixels / 2
	//grid_end := rl.GetScreenWidth() - max_grid_size_pixels / 2
	grid_size := g_mem.grid_size - 1 //Want modularity
	step_size := cast(f32)(PIPE_WIDTH + 1) // add a tad of padding
	idx := 0
	for col in 0 ..= grid_size {
		for row in 0 ..= grid_size {
			//Lets come up with a dynamic way to draw the grid. It should always be in the middle of the screen
			pos := rl.Vector2{step_size * f32(row), step_size * f32(col)} //TODO(Fausto):wasteful
			//pos := rl.Vector2{f32(row), f32(col)}
			is_elbow := (col % 2 == 0 && row % 2 != 0) //random-ish for now
			//TODO(Fausto): Revisit returning pointers into dynamic arry
			rotation := Rotations._0_DEG
			if col % 2 == 0 && row % 2 != 0 {
				rotation = Rotations._0_DEG
			} else if col % 2 == 0 && row % 2 == 0 {
				rotation = Rotations._90_DEG
			} else if col % 2 != 0 && row % 2 == 0 {
				rotation = Rotations._180_DEG
			} else if col % 2 != 0 && row % 2 != 0 {
				rotation = Rotations._270_DEG
			}
			entity := make_pipe_entity(pos, is_elbow, rotation)
			append(&g_mem.entities, entity)
			//g_mem.entities[idx] = entity
			idx += 1
			g_mem.pipes_appended += 1
		}
	}

}

//TODO(Fausto): Revisit returning pointers into dynamic arry
make_pipe_entity :: proc(pos: rl.Vector2, is_elbow: bool, rot: Rotations) -> Entity {
	ent := Entity {
		pos  = pos,
		kind = EntityKind.PIPE,
	}

	ent.specifics = Pipe {
		is_elbow = true,
		rotation = rot,
	}

	return ent
}


//TODO(Fausto) I hate this
draw_entity :: proc(e: ^Entity, selected: bool) {
	switch e.kind {
	case .PIPE:
		{
			pipe_specifics := e.specifics.(Pipe) //shorthand
			//TODO(Fausto): Refactor. Also make dynamic so it alwys fits
			pipe_size: f32 = PIPE_WIDTH //cast(f32)(PIPE_WIDTH * g_mem.grid_size) / cast(f32)rl.GetScreenHeight()
			dest := rl.Rectangle {
				e.pos.x + (pipe_size / 2),
				e.pos.y + (pipe_size / 2),
				pipe_size,
				pipe_size,
			}
			//if e.selected {
			outer := rl.Rectangle {
				dest.x - pipe_size / 2,
				dest.y - pipe_size / 2,
				dest.width,
				dest.height,
			}

			//Before we draw the pipe texture, draw the flow
			//draw_pipe_flow(&pipe_specifics)

			if pipe_specifics.is_elbow {
				rect := rl.Rectangle{0, 0, PIPE_SPRITE_SIZE, PIPE_SPRITE_SIZE} // Guesstimated based on asesprite
				rl.DrawTexturePro(
					g_mem.pipe_texture,
					rect,
					dest,
					rl.Vector2{pipe_size / 2, pipe_size / 2},
					f32(int(e.specifics.(Pipe).rotation)),
					//0,
					rl.WHITE,
				) // Cat texture
				//	rl.ImageDrawRectangleRec(&img, dest, rl.WHITE)
			} else {
				rect := rl.Rectangle {
					PIPE_SPRITE_SIZE,
					PIPE_SPRITE_SIZE,
					PIPE_SPRITE_SIZE,
					PIPE_SPRITE_SIZE,
				} // Guesstimated based on asesprite
				rl.DrawTexturePro(
					g_mem.pipe_texture,
					rect,
					dest,
					rl.Vector2{pipe_size / 2, pipe_size / 2},
					f32(int(e.specifics.(Pipe).rotation)),
					//0,
					rl.WHITE,
				)
				draw_pipe_flow(e)
			}

			if selected {
				rl.DrawRectangleLinesEx(outer, 2, rl.YELLOW)
			}

			//Nice hot reload trick
			if true {
				//Debug draw all outlines
				//rl.DrawRectangleLinesEx(outer, 2, rl.YELLOW)
				rl.DrawText(
					fmt.ctprintf("<%v,%v>%v", e.pos.x, e.pos.y, int(e.specifics.(Pipe).flow)),
					cast(i32)e.pos.x,
					cast(i32)e.pos.y,
					5,
					rl.YELLOW,
				)
			}
		}
	}
}

//Changes to Game_Memory do not reflect without a full shutdown
Game_Memory :: struct {
	player_pos:         rl.Vector2,
	pipe_texture:       rl.Texture, //We opt for identifying the textures individually
	entities:           [dynamic]Entity, //TODO(Fausto):dynamic?
	//entities:           [16]Entity, //TODO(Fausto):dynamic?
	grid_size:          int,
	run:                bool,
	selected_pipe:      int,
	prev_selected_pipe: int,
	pipes_appended:     int,
	init:               bool,
	shader_time_loc:    int,
	time:               f32,
	pipe_flow_shader:   rl.Shader,
}

g_mem: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	//return {zoom = h / PIXEL_WINDOW_HEIGHT, target = g_mem.player_pos, offset = {w / 2, h / 2}}
	target := rl.Vector2{0, 0}
	formula := len(g_mem.entities) / 4 - 1
	if formula > 0 {
		target = g_mem.entities[formula].pos
	}

	target = rl.Vector2 {
		cast(f32)(PIPE_WIDTH * g_mem.grid_size / 2),
		cast(f32)(PIPE_WIDTH * g_mem.grid_size / 2),
	}

	return {zoom = h / PIXEL_WINDOW_HEIGHT, target = target, offset = {w / 2, h / 2}}
}

ui_camera :: proc() -> rl.Camera2D {
	return {zoom = f32(rl.GetScreenHeight()) / PIXEL_WINDOW_HEIGHT}
}

draw_pipe_flow :: proc(pipe: ^Entity) {
	//Here we are concerned with drawing the shapes/textures/shaders associated with the flow of the pipe once that has been figured out
	blue := cast(u8)pipe.specifics.(Pipe).flow % 255
	rl.DrawRectangle(
		cast(i32)pipe.pos.x + PIPE_WIDTH / 2,
		cast(i32)pipe.pos.y + PIPE_WIDTH / 2,
		cast(i32)PIPE_WIDTH / 2,
		cast(i32)PIPE_WIDTH / 2,
		rl.Color{0, 0, blue, 1},
	)

}

GRID_SIZE :: 4

update :: proc() {
	input: rl.Vector2
	g_mem.grid_size = 3
	if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
		input.y -= 1
	}
	if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
		input.y += 1
	}
	if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
		input.x -= 1
	}
	if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
		input.x += 1
	}

	input = linalg.normalize0(input)
	g_mem.player_pos += input * rl.GetFrameTime() * 100

	if rl.IsKeyPressed(.ESCAPE) {
		g_mem.run = false

	}

	//TODO these arent unified. Just accepting that R hot reloads...
	if rl.IsKeyPressed(.R) {
		g_mem.init = false

	}

	if rl.IsMouseButtonReleased(.LEFT) {
		//TODO(Optimize checking for what pipe is being selected
		mouse_pos := rl.GetScreenToWorld2D(rl.GetMousePosition(), game_camera())
		//TODO(Fausto): Refactor. Also make dynamic so it alwys fits
		pipe_size: f32 = PIPE_WIDTH //cast(f32)(PIPE_WIDTH * g_mem.grid_size) / cast(f32)rl.GetScreenHeight()
		for &ent, idx in g_mem.entities {
			if mouse_pos.x >= ent.pos.x &&
			   mouse_pos.x <= ent.pos.x + pipe_size &&
			   mouse_pos.y >= ent.pos.y &&
			   mouse_pos.y <= ent.pos.y + pipe_size {
				if g_mem.prev_selected_pipe != g_mem.selected_pipe {
					g_mem.prev_selected_pipe = g_mem.selected_pipe
				}
				g_mem.selected_pipe = idx
			}
		}
	}

	if g_mem.selected_pipe > -1 {
		g_mem.entities[g_mem.selected_pipe].selected = true
		//Tick flow on selected pipe
		//TODO(Fausto): NOTE that we did selected just to develop the flow feature, make sure to actually implement the flow and remove the selected bit 
		//NOTE:Assume you can only select pipes....
		prev := g_mem.entities[g_mem.selected_pipe].specifics.(Pipe)
		g_mem.entities[g_mem.selected_pipe].specifics = Pipe {
			is_elbow = prev.is_elbow,
			rotation = prev.rotation, //only 4 options?
			flow     = prev.flow + rl.GetFrameTime(), // from 0 -> 1
		}
		if g_mem.prev_selected_pipe != g_mem.selected_pipe && g_mem.prev_selected_pipe > -1 {
			temp := g_mem.entities[g_mem.selected_pipe].pos
			g_mem.entities[g_mem.selected_pipe].pos = g_mem.entities[g_mem.prev_selected_pipe].pos
			g_mem.entities[g_mem.prev_selected_pipe].pos = temp

			//After swap is done. Deselect
			g_mem.prev_selected_pipe = -1
			g_mem.selected_pipe = -1
		}
	}


	//if len(g_mem.entities) != g_mem.grid_size * g_mem.grid_size {
	if !g_mem.init {
		reset_pipe_grid() //Lets scrap and start from scratch
		// Probably made a hot reload change..
		g_mem.init = true
	}
}


draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.Color{45, 37, 34, 1})

	rl.BeginMode2D(game_camera())
	//grid is lowest priorty
	//draw_square_grid(8)

	//rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)
	//rl.DrawRectangleV({-30, -20}, {10, 10}, rl.GREEN)
	//lets draw pipes only on the screen coordinates not world coords
	for &ent, idx in g_mem.entities {
		if idx < g_mem.pipes_appended {
			draw_entity(&ent, idx == g_mem.selected_pipe) //TODO(Fausto) I hate this
		}
	}
	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	if false {
		rl.DrawText(
			fmt.ctprintf(
				"WELCOME TO RAY GUI LIB grid_size: %v\nmouse_pos: %v\npipe_size: %v\nselected: %v\nprev: %v",
				g_mem.grid_size,
				rl.GetScreenToWorld2D(rl.GetMousePosition(), game_camera()),
				cast(f32)PIPE_WIDTH,
				g_mem.selected_pipe,
				g_mem.prev_selected_pipe,
			),
			5,
			5,
			8,
			rl.WHITE,
		)
	}

	rl.EndMode2D()

	rl.EndDrawing()
}

@(export)
game_update :: proc() {
	update()
	draw()
}

@(export)
game_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(1280, 720, "Odin + Raylib + Hot Reload template!")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
	rl.SetExitKey(nil)
}


//Changes in game_init do not reflect without a full shutdown. Remember that
@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	pipe_texture := rl.LoadTexture("assets/Bioshockhacking_transparent.png") // NOTE this is a spritesheet
	//pipe_flow_shader := rl.LoadShader("shaders/pipe_flow.fs", 330)
	//shader_time_loc := rl.GetShaderLocation(pipe_flow_shader, "uTime")
	//time: f32 = 0
	//rl.SetShaderValue(pipe_flow_shader, shader_time_loc, &time, rl.SHADER_UNIFROM_FLOAT)
	entities := make_dynamic_array([dynamic]Entity)
	//entities := [100]Entity

	g_mem^ = Game_Memory {
		run           = true,
		grid_size     = 8,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		//player_texture = rl.LoadATexture("assets/round_cat.png"),
		pipe_texture  = pipe_texture, //TODO(Fausto): Look at this
		entities      = entities,
		selected_pipe = -1,
		//pipe_flow_shader = pipe_flow_shader,
		//pipe_texture     = pipe_texture,
	}

	game_hot_reloaded(g_mem)
}

@(export)
game_should_run :: proc() -> bool {
	when ODIN_OS != .JS {
		// Never run this proc in browser. It) contains a 16 ms sleep on web!
		if rl.WindowShouldClose() {
			return false
		}
	}

	return g_mem.run
}

@(export)
game_shutdown :: proc() {
	//g_mem.Textures
	rl.UnloadTexture(g_mem.pipe_texture)
	clear_dynamic_array(&g_mem.entities)
	delete_dynamic_array(g_mem.entities)
	free(g_mem)
}

@(export)
game_shutdown_window :: proc() {
	rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)

	// Here you can also set your own global variables. A good idea is to make
	// your global variables into pointers that point to something inside
	// `g_mem`.
}

@(export)
game_force_reload :: proc() -> bool {
	return rl.IsKeyPressed(.R)
}

@(export)
game_force_restart :: proc() -> bool {
	return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
	rl.SetWindowSize(i32(w), i32(h))
}
