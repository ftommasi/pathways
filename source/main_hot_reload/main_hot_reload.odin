/*
Development game exe. Loads build/hot_reload/game.dll and reloads it whenever it
changes.
*/

package main

import "core:c/libc"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:path/filepath"
//import "core:strings"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
	BUILD_COMMAND :: []string{"build_hot_reload.bat"}
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
	BUILD_COMMAND :: []string{"sh", "build_hot_reload.sh"}
} else {
	DLL_EXT :: ".so"
	BUILD_COMMAND :: []string{"bash", "build_hot_reload.sh"}
}

GAME_DLL_DIR :: "build/hot_reload/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	copy_err := os2.copy_file(to, GAME_DLL_PATH)

	if copy_err != nil {
		fmt.printfln("Failed to copy " + GAME_DLL_PATH + " to {0}: %v", to, copy_err)
		return false
	}

	return true
}

Game_API :: struct {
	lib:               dynlib.Library,
	init_window:       proc(),
	init:              proc(),
	update:            proc(),
	should_run:        proc() -> bool,
	shutdown:          proc(),
	shutdown_window:   proc(),
	memory:            proc() -> rawptr,
	memory_size:       proc() -> int,
	hot_reloaded:      proc(mem: rawptr),
	force_reload:      proc() -> bool,
	force_restart:     proc() -> bool,
	modification_time: os.File_Time,
	api_version:       int,
}

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name(GAME_DLL_PATH)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of " + GAME_DLL_PATH + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	fmt.printf("About to load" + GAME_DLL_DIR + "game_{0}" + DLL_EXT, api_version)
	fmt.println()
	game_dll_name := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api_version)
	err := copy_dll(game_dll_name) 
	if !err{
		fmt.println("Error copying dll")
	}

	// This proc matches the names of the fields in Game_API to symbols in the
	// game DLL. It actually looks for symbols starting with `game_`, which is
	// why the argument `"game_"` is there.
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln(
			"Failed to remove {0}game_{1}" + DLL_EXT + " copy",
			GAME_DLL_DIR,
			api.api_version,
		)
	}
}

hot_reload_compile :: proc() -> bool {
	proc_desc: os2.Process_Desc
	proc_desc.command = BUILD_COMMAND 
	proc_desc.working_dir = "./"

	fmt.println("About to run build_hot_reload")
	state, stdout, stderr, hot_reload_err := os2.process_exec(proc_desc, context.temp_allocator)
	if hot_reload_err != nil {
		fmt.println("Error during hot_reload_build")
		fmt.println("out: {0}",stdout)
		fmt.println("err: {0}",stderr)
		return false
	}
	fmt.println(
		"build_hot_reload done. I believe successfully... here is what I got",
		state,
		string(stdout),
		string(stderr),
	)
	return true
}

main :: proc() {
	// Set working dir to dir of executable.
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)

	context.logger = log.create_console_logger()

	default_allocator := context.allocator
	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, default_allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)

	reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
		err := false

		for _, value in a.allocation_map {
			fmt.printf("%v: Leaked %v bytes\n", value.location, value.size)
			err = true
		}

		mem.tracking_allocator_clear(a)
		return err
	}

	game_api_version := 0
	game_api, game_api_ok := load_game_api(game_api_version)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_api_version += 1
	game_api.init_window()
	game_api.init()

	old_game_apis := make([dynamic]Game_API, default_allocator)

	prev_game_dll_mod_err: os.Error = nil
	prev_game_api_modification_time: os.File_Time = 0
	prev_game_dll_mod: os.File_Time = 0
	// prev_mod_time_nsec: i64 = 0

	for game_api.should_run() {
		game_api.update()
		force_reload := game_api.force_reload()
		force_restart := game_api.force_restart()
		reload := force_reload || force_restart

		game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(GAME_DLL_PATH)

		//This needs to be a logic change. I want to go through every (odin?) file that makes up the DLL and recompile DLL if there is a change
		//detected_file_change :: proc(prev_mod_time_nsec: ^i64) -> bool {
		//	path := "."
		//	isDir := os.is_dir_path(path)
		//	if !isDir {
		//		//if its not a directory then its a file. something weird but maybe we check anyways
		//	}
		//	flags := os.O_RDONLY
		//	cstr := strings.clone_to_cstring(path, context.temp_allocator)

		//	handle: os.Handle = os.INVALID_HANDLE
		//	handle = os._unix_open(cstr, i32(flags), u16(0))
		//	defer os._unix_close(handle)
		//	if handle == os.INVALID_HANDLE {
		//		//err := os.get_last_error()
		//		//TOOD something with err
		//	}

		//	cur_dir_info, _ := os.read_dir(handle, -1) //I have no idea what n is for

		//	for file_info in cur_dir_info {
		//		if prev_mod_time_nsec^ != file_info.modification_time._nsec {
		//			prev_mod_time_nsec^ = file_info.modification_time._nsec
		//			fmt.printf("detected change in file :{0}, hot reloading", file_info.name)
		//			return true
		//		}
		//	}
		//	return false
		//}

		if prev_game_dll_mod != game_dll_mod {

			prev_game_dll_mod_err = game_dll_mod_err
			prev_game_api_modification_time = game_api.modification_time
			prev_game_dll_mod = game_dll_mod

			fmt.printf(
				"game_dll_mod_err :{0}, game_api.modification_time: {1}, game_dll_mod  {2}\n",
				game_dll_mod_err,
				game_api.modification_time,
				game_dll_mod,
			)
			reload = true
		}

		if game_api.force_reload() {

			fmt.println("Hot reload compil;ing")
			hot_reload_compile()
		}

		if game_dll_mod_err == nil && prev_game_dll_mod != game_dll_mod {
			reload = true
		}

		if reload {
			new_game_api, new_game_api_ok := load_game_api(game_api_version)

			if new_game_api_ok {
				force_restart =
					force_restart || game_api.memory_size() != new_game_api.memory_size()

				if !force_restart {
					// This does the normal hot reload

					// Note that we don't unload the old game APIs because that
					// would unload the DLL. The DLL can contain stored info
					// such as string literals. The old DLLs are only unloaded
					// on a full reset or on shutdown.
					append(&old_game_apis, game_api)
					game_memory := game_api.memory()
					game_api = new_game_api
					game_api.hot_reloaded(game_memory)
				} else {
					// This does a full reset. That's basically like opening and
					// closing the game, without having to restart the executable.
					//
					// You end up in here if the game requests a full reset OR
					// if the size of the game memory has changed. That would
					// probably lead to a crash anyways.

					game_api.shutdown()
					reset_tracking_allocator(&tracking_allocator)

					for &g in old_game_apis {
						unload_game_api(&g)
					}

					clear(&old_game_apis)
					unload_game_api(&game_api)
					game_api = new_game_api
					game_api.init()
				}

				game_api_version += 1
			}
		}

		if len(tracking_allocator.bad_free_array) > 0 {
			for b in tracking_allocator.bad_free_array {
				log.errorf("Bad free at: %v", b.location)
			}

			// This prevents the game from closing without you seeing the bad
			// frees. This is mostly needed because I use Sublime Text and my game's
			// console isn't hooked up into Sublime's console properly.
			libc.getchar()
			panic("Bad free detected")
		}

		free_all(context.temp_allocator)
	}

	free_all(context.temp_allocator)
	game_api.shutdown()
	if reset_tracking_allocator(&tracking_allocator) {
		// This prevents the game from closing without you seeing the memory
		// leaks. This is mostly needed because I use Sublime Text and my game's
		// console isn't hooked up into Sublime's console properly.
		libc.getchar()
	}

	for &g in old_game_apis {
		unload_game_api(&g)
	}

	delete(old_game_apis)

	game_api.shutdown_window()
	unload_game_api(&game_api)
	mem.tracking_allocator_destroy(&tracking_allocator)
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
