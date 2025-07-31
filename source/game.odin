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
	_0_DEG,
	_90_DEG,
	_180_DEG,
	_270_DEG,
}

//TOOD(Fausto): Will we weven need more?
EntityKind :: enum {
	PIPE,
}

// Generic entity type. Contains everything. DiscUnion ?
Entity :: struct {
	texture:   rl.Texture,
	pos:       rl.Vector2,
	kind:      EntityKind,
	specifics: EntityTypes,
}

Pipe :: struct {
	is_elbow: bool,
	rotation: Rotations, //only 4 options?
}

EntityTypes :: union {
	Pipe,
}

//TODO(Fausto): Revisit returning pointers into dynamic arry
make_pipe_entity :: proc(
	texture: rl.Texture,
	pos: rl.Vector2,
	is_elbow: bool,
	rot: Rotations,
) -> ^Entity {

	ent := new(Entity)
	ent^ = Entity {
		texture = texture,
		pos     = pos,
		kind    = EntityKind.PIPE,
	}

	ent.specifics = Pipe {
		is_elbow = is_elbow,
		rotation = rot,
	}

	return ent
}

draw_entity :: proc(e: ^Entity) {
	switch e.kind {
	case .PIPE:
		{
			pipe_specifics := e.specifics.(Pipe) //shorthand
			if pipe_specifics.is_elbow {
				rect := rl.Rectangle{0, 0, 68, 69} // Guesstimated based on asesprite
				rl.DrawTextureRec(e.texture, rect, e.pos, rl.WHITE) // Cat texture
			} else {
				rect := rl.Rectangle{68, 69, 68, 69} // Guesstimated based on asesprite
				rl.DrawTextureRec(e.texture, rect, e.pos, rl.WHITE) // Cat texture
			}
		}
	}
}

Game_Memory :: struct {
	player_pos:  rl.Vector2,
	entities:    [dynamic]Entity, //TODO(Fausto):dynamic?
	some_number: int,
	run:         bool,
}

g_mem: ^Game_Memory

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {zoom = h / PIXEL_WINDOW_HEIGHT, target = g_mem.player_pos, offset = {w / 2, h / 2}}
}

ui_camera :: proc() -> rl.Camera2D {
	return {zoom = f32(rl.GetScreenHeight()) / PIXEL_WINDOW_HEIGHT}
}

update :: proc() {
	input: rl.Vector2

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
	g_mem.some_number += 1

	if rl.IsKeyPressed(.ESCAPE) {
		g_mem.run = false
	}
}

//draw a grid of nxn squares
draw_square_grid :: proc(n: int) {
	color := []rl.Color{rl.PURPLE, rl.GRAY}
	selected_color := 0
	size: f32 = 25
	for col in 0 ..= n {
		for row in 0 ..= n {
			rl.DrawRectangleV(
				{size * f32(row), size * f32(col)},
				{size, size},
				color[selected_color],
			)
			selected_color = (selected_color + 1) % 2 // toggle
		}
	}
}

draw :: proc() {
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLUE)

	rl.BeginMode2D(game_camera())
	//grid is lowest priorty
	//draw_square_grid(8)

	//rl.DrawRectangleV({20, 20}, {10, 10}, rl.RED)
	//rl.DrawRectangleV({-30, -20}, {10, 10}, rl.GREEN)
	for &ent in g_mem.entities {
		draw_entity(&ent)
	}
	rl.EndMode2D()

	rl.BeginMode2D(ui_camera())

	// NOTE: `fmt.ctprintf` uses the temp allocator. The temp allocator is
	// cleared at the end of the frame by the main application, meaning inside
	// `main_hot_reload.odin`, `main_release.odin` or `main_web_entry.odin`.
	rl.DrawText(
		fmt.ctprintf(
			"WELCOME TO RAY GUI LIB some_number: %v\nplayer_pos: %v",
			g_mem.some_number,
			rl.GetMousePosition(),
		),
		5,
		5,
		8,
		rl.WHITE,
	)

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

@(export)
game_init :: proc() {
	g_mem = new(Game_Memory)

	pipe_texture := rl.LoadTexture("assets/Bioshockhacking.png") // NOTE this is a spritesheet

	entities := make_dynamic_array([dynamic]Entity)

	//TODO(Fausto): Revisit how we think about doing this
	//Make some number of pipes idk
	//size: f32 = 25 //TODO(Fausto) magic num
	for col in 0 ..= 8 {
		for row in 0 ..= 8 {
			//pos := rl.Vector2{size * f32(row), size * f32(col)}
			pos := rl.Vector2{f32(row), f32(col)}
			is_elbow := (col % 2 == 0 && row % 2 != 0) //random-ish for now
			//TODO(Fausto): Revisit returning pointers into dynamic arry
			entity := make_pipe_entity(pipe_texture, pos, is_elbow, Rotations._0_DEG)
			append(&entities, entity^)
		}
	}
	pos := rl.Vector2{f32(200), f32(200)}
	entity := make_pipe_entity(pipe_texture, pos, true, Rotations._0_DEG)
	append(&entities, entity^)


	g_mem^ = Game_Memory {
		run         = true,
		some_number = 100,

		// You can put textures, sounds and music in the `assets` folder. Those
		// files will be part any release or web build.
		//player_texture = rl.LoadATexture("assets/round_cat.png"),
		entities    = entities,
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
	for &ent in g_mem.entities {
		free(&ent)
	}
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
