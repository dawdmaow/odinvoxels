package main

import "core:math"
import "core:math/linalg"
import rl "vendor:raylib"

Cube_Pos_Local :: distinct [3]int
Cube_Pos_Global :: distinct [3]int // Global world coordinates
Chunk_Pos :: distinct [2]int

cube_global_from_world :: proc(world_pos: rl.Vector3) -> Cube_Pos_Global {
	return Cube_Pos_Global {
		int(math.floor(math.floor(world_pos.x))),
		int(math.floor(math.floor(world_pos.y))),
		int(math.floor(math.floor(world_pos.z))),
	}
}

cube_pos_local_valid :: proc(cube: Cube_Pos_Local) -> bool {
	return(
		cube.x >= 0 &&
		cube.x < CHUNK_WIDTH &&
		cube.y >= 0 &&
		cube.y < CHUNK_HEIGHT &&
		cube.z >= 0 &&
		cube.z < CHUNK_WIDTH \
	)
}

chunk_coords_to_pos :: proc(chunk_coords: Chunk_Pos) -> rl.Vector3 {
	return rl.Vector3{f32(chunk_coords.x * CHUNK_WIDTH), 0, f32(chunk_coords.y * CHUNK_WIDTH)}
}

is_chunk_closer_to_player :: proc(a, b: Chunk_Pos) -> bool {
	player_chunk := player_chunk()
	player_chunk_f32 := rl.Vector2{f32(player_chunk.x), f32(player_chunk.y)}
	a_f32 := rl.Vector2{f32(a.x), f32(a.y)}
	b_f32 := rl.Vector2{f32(b.x), f32(b.y)}
	a_distance := linalg.distance(a_f32, player_chunk_f32)
	b_distance := linalg.distance(b_f32, player_chunk_f32)
	return a_distance < b_distance
}

cube_coords_to_world :: proc(chunk_coords: Chunk_Pos, cube_coords: Cube_Pos_Local) -> rl.Vector3 {
	return(
		chunk_coords_to_pos(chunk_coords) +
		rl.Vector3{f32(cube_coords.x), f32(cube_coords.y), f32(cube_coords.z)} * CUBE_SIZE +
		CUBE_SIZE / 2 \
	)
}

chunk_from_worldpos :: proc(pos: rl.Vector3) -> Chunk_Pos {
	return Chunk_Pos{int(pos.x / CHUNK_WIDTH), int(pos.z / CHUNK_WIDTH)}
}
