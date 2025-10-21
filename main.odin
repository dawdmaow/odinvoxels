package main

import "base:intrinsics"
import "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:sort"
import "core:strings"
import rl "vendor:raylib"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600

VECTOR3_FORWARD :: rl.Vector3{0, 0, 1}
VECTOR3_UP :: rl.Vector3{0, 1, 0}
VECTOR3_RIGHT :: rl.Vector3{1, 0, 0}

sky_color := rl.Color{135, 206, 235, 255}

// fog parameters
fog_shader: rl.Shader
fog_color := rl.Color{135, 206, 235, 255} // Same as sky color
fog_density: f32 = 0.05
fog_start: f32 = 10.0
fog_end: f32 = 60.0

dt :: #force_inline proc() -> f32 {
	return rl.GetFrameTime()
}

main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Odin Voxels")
	defer rl.CloseWindow()

	rl.SetTargetFPS(60)
	rl.DisableCursor()
	rl.SetTraceLogLevel(.WARNING)

	player_camera = rl.Camera3D {
		target     = rl.Vector3{0, 0, 0},
		up         = VECTOR3_UP,
		fovy       = 75,
		projection = .PERSPECTIVE,
	}

	player_pos = rl.Vector3{0, CHUNK_HEIGHT, 0}
	player_pitch_in_radians = 0
	player_yaw_in_radians = 0

	chunks = make(map[Chunk_Pos]Chunk)
	defer delete(chunks)

	chunks_loading = make([dynamic]Chunk_Pos)
	defer delete(chunks_loading)

	chunks_unloading = make([dynamic]Chunk_Pos)
	defer delete(chunks_unloading)

	atlas_texture = create_atlas_texture()
	defer rl.UnloadTexture(atlas_texture)

	// load fog shader
	fog_shader = rl.LoadShader("shaders/fog.vs", "shaders/fog.fs")
	defer rl.UnloadShader(fog_shader)

	if fog_shader.id == 0 {
		fmt.println("ERROR: Failed to load fog shader!")
	} else {
		fmt.println("SUCCESS: Fog shader loaded successfully!")
	}

	bloom_shader := rl.LoadShader(nil, "shaders/bloom.fs")
	defer rl.UnloadShader(bloom_shader)

	target := rl.LoadRenderTexture(SCREEN_WIDTH, SCREEN_HEIGHT)
	defer rl.UnloadRenderTexture(target)

	for !rl.WindowShouldClose() {
		{
			rl.BeginTextureMode(target)
			rl.ClearBackground(sky_color)
			{
				rl.BeginMode3D(player_camera)
				update_player()
				chunks_tick()
				render_loaded_chunks()
				rl.EndMode3D()
			}
			rl.EndTextureMode()
		}
		{
			rl.BeginDrawing()
			rl.ClearBackground(sky_color)
			{
				rl.BeginShaderMode(bloom_shader)
				rl.DrawTexturePro(
					target.texture,
					rl.Rectangle{0, 0, f32(target.texture.width), -f32(target.texture.height)},
					rl.Rectangle{0, 0, f32(SCREEN_WIDTH), f32(SCREEN_HEIGHT)},
					rl.Vector2{0, 0},
					0,
					rl.WHITE,
				)
				rl.EndShaderMode()
			}

			// render underwater blue tint overlay
			if is_player_camera_underwater() {
				underwater_tint := rl.Color{64 / 2, 164 / 2, 255 / 2, 200} // Blue tint with transparency
				rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, underwater_tint)

				if game_mode == .Swimming {
					swimming_overlay := rl.Color{32 / 2, 132 / 2, 235 / 2, 50} // Additional blue overlay
					rl.DrawRectangle(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT, swimming_overlay)
				}
			}

			debug_info := get_debug_info()
			render_debug_info(debug_info)
			rl.EndDrawing()
		}
	}
}
