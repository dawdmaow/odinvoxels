package main

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

Game_Mode :: enum {
	Flying,
	Walking,
	Swimming,
}

// player bounding box size (should be smaller than cube size for proper collision)
PLAYER_SIZE :: rl.Vector3{0.8, 1.8, 0.8} // Width, Height, Depth

ACCELERATION :: 10.0
FRICTION :: 8.0

MAX_FALL_VELOCITY :: 100
GRAVITY_ACCELERATION :: 9.81 * 2
WALK_SPEED :: 6
RUN_SPEED :: 11
JUMP_VELOCITY :: 7

BASE_MOVEMENT_SPEED :: 20
BASE_ROTATION_SPEED :: 0.5
SPEED_BOOST_MULTIPLIER :: 2

// swimming physics constants
SWIM_SPEED :: 6.0
SWIM_ACCELERATION :: 8.0
SWIM_FRICTION :: 6.0
SWIM_BUOYANCY :: 4.0 // upward force when underwater (increased for easier floating)
SWIM_GRAVITY_REDUCTION :: 0.3
SWIM_JUMP_VELOCITY :: 8.0 // upward velocity when swimming up (increased for easier water exit)
SWIM_EXIT_BOOST :: 2.0

WALK_FOV :: 80.0
RUN_FOV :: 80.0

player_camera: rl.Camera3D
player_pos, player_vel: rl.Vector3
player_pitch_in_radians, player_yaw_in_radians: f32
player_rotation: rl.Quaternion
game_mode: Game_Mode = .Walking

is_player_colliding_with_cubes :: proc() -> bool {
	player_chunk := chunk_from_worldpos(player_pos)

	// check surrounding chunks to handle cross-chunk collisions
	for x_offset in -1 ..= 1 {
		for z_offset in -1 ..= 1 {
			chunk_coords := Chunk_Pos{player_chunk.x + x_offset, player_chunk.y + z_offset}

			chunk, chunk_exists := chunks[chunk_coords]
			if !chunk_exists do continue

			for cube, index in chunk.cubes {
				if cube.kind != .Air && cube.kind != .Water {
					cube_coords := array_index_to_cube_coords(index)
					cube_world_pos := cube_coords_to_world(chunk_coords, cube_coords)

					// Check bounding box collision using Raylib
					player_box := rl.BoundingBox {
						min = player_pos - PLAYER_SIZE / 2,
						max = player_pos + PLAYER_SIZE / 2,
					}

					cube_box := rl.BoundingBox {
						min = cube_world_pos - rl.Vector3{CUBE_SIZE, CUBE_SIZE, CUBE_SIZE} / 2,
						max = cube_world_pos + rl.Vector3{CUBE_SIZE, CUBE_SIZE, CUBE_SIZE} / 2,
					}

					if rl.CheckCollisionBoxes(player_box, cube_box) {
						return true
					}
				}
			}
		}
	}
	return false
}

update_player_velocity_flying :: proc(input: rl.Vector3) {
	if (input != rl.Vector3{0, 0, 0}) {
		input_movement_world := rl.Vector3RotateByQuaternion(input, player_rotation)

		// movement_speed: f32 =
		// 	rl.IsKeyDown(.LEFT_SHIFT) ? BASE_MOVEMENT_SPEED * SPEED_BOOST_MULTIPLIER : BASE_MOVEMENT_SPEED
		movement_speed: f32 = BASE_MOVEMENT_SPEED

		vel_diff := input_movement_world * movement_speed - player_vel
		player_vel += vel_diff * ACCELERATION * dt()
	} else {
		player_vel = player_vel * (1.0 - FRICTION * dt())
	}
}

is_player_standing_on_ground :: proc() -> (result: bool) {
	// return player_on_ground
	cube_global := cube_global_from_world(player_pos + {0, -1, 0})
	// rl.DrawPoint3D(rl.Vector3{f32(cube_global.x), f32(cube_global.y), f32(cube_global.z)}, rl.RED)
	// rl.DrawPoint3D(player_pos - rl.Vector3{0, 5, 0}, rl.RED)
	// rl.DrawPoint3D(rl.Vector3{0, 0, 0}, rl.RED)
	cube := cube_from_global(cube_global)
	result = cube != nil && cube.kind != .Air && cube.kind != .Water
	return
}

is_player_underwater :: proc() -> bool {
	cube_global := cube_global_from_world(player_pos)
	cube := cube_from_global(cube_global)
	return cube != nil && cube.kind == .Water
}

is_player_camera_underwater :: proc() -> bool {
	cube_global := cube_global_from_world(player_camera.position)
	cube := cube_from_global(cube_global)
	if cube != nil && cube.kind == .Water {
		cube_above := cube_from_global(
			Cube_Pos_Global{cube_global.x, cube_global.y + 1, cube_global.z},
		)
		if cube_above != nil && cube_above.kind != .Water {
			water_top_y := f32(cube_global.y) * CUBE_SIZE + CUBE_SIZE - WATER_TOP_HEIGHT_OFFSET
			return player_camera.position.y < water_top_y
		} else {
			return true
		}
	}
	return false
}

is_player_in_water :: proc() -> bool {
	// check if player's body is in water (not just eyes)
	body_pos := player_pos + rl.Vector3{0, PLAYER_SIZE.y / 2, 0} // Check middle of player body
	cube_global := cube_global_from_world(body_pos)
	cube := cube_from_global(cube_global)
	return cube != nil && cube.kind == .Water
}

update_game_mode :: proc() {
	// automatically switch between walking and swimming based on water detection
	is_in_water := is_player_in_water()

	switch game_mode {
	case .Walking:
		if is_in_water {
			game_mode = .Swimming
			// reduce velocity when entering water for smoother transition
			player_vel *= 0.5
		}
	case .Swimming:
		if !is_in_water {
			game_mode = .Walking
			// give extra upward boost when exiting water (like Minecraft)
			if player_vel.y > 0 {
				player_vel.y += SWIM_EXIT_BOOST
			}
			// reduce horizontal velocity when exiting water
			player_vel.x *= 0.7
			player_vel.z *= 0.7
		}
	case .Flying:
	}
}

update_player_velocity_swimming :: proc(input: rl.Vector3) {
	direction := rl.Vector3RotateByQuaternion(input, player_rotation)

	movement_speed: f32 = SWIM_SPEED
	acceleration_multiplier: f32 = 1.0
	friction_multiplier: f32 = 1.0

	// buoyancy
	player_vel.y += SWIM_BUOYANCY * dt()

	// reduced gravity
	player_vel.y -= GRAVITY_ACCELERATION * SWIM_GRAVITY_REDUCTION * dt()

	// limit fall velocity in water
	if player_vel.y < -MAX_FALL_VELOCITY * SWIM_GRAVITY_REDUCTION {
		player_vel.y = -MAX_FALL_VELOCITY * SWIM_GRAVITY_REDUCTION
	}

	// swimming up/down with Space/Shift
	if rl.IsKeyDown(.SPACE) {
		player_vel.y += SWIM_JUMP_VELOCITY * dt() * SWIM_ACCELERATION
	}
	// if rl.IsKeyDown(.LEFT_SHIFT) {
	// 	player_vel.y -= SWIM_JUMP_VELOCITY * dt() * SWIM_ACCELERATION
	// }

	// smooth acceleration/friction to all movement (including vertical)
	if rl.Vector3Length(direction) > 0 {
		target_vel := direction * movement_speed

		vel_diff := target_vel - player_vel
		acceleration := vel_diff * SWIM_ACCELERATION * acceleration_multiplier * dt()

		player_vel += acceleration
	} else {
		// friction when no input
		friction := SWIM_FRICTION * friction_multiplier * dt()
		player_vel *= (1.0 - friction)
	}
}

update_player_velocity_gravity :: proc(input: rl.Vector3) {
	direction := rl.Vector3RotateByQuaternion({input.x, 0, input.z}, player_rotation)

	// shift for running, otherwise walk
	// movement_speed: f32 = rl.IsKeyDown(.LEFT_SHIFT) ? RUN_SPEED : WALK_SPEED
	movement_speed: f32 = WALK_SPEED
	acceleration_multiplier: f32 = 1.0
	friction_multiplier: f32 = 1.0

	is_on_ground := is_player_standing_on_ground()

	if is_on_ground {
		player_vel.y = 0
		if rl.IsKeyDown(.SPACE) {
			player_vel.y = JUMP_VELOCITY
		}
		// increase responsiveness on ground
		acceleration_multiplier = 3.0
		friction_multiplier = 2.5
	} else {
		movement_speed *= 0.8 // less severe reduction
		acceleration_multiplier = 1.5 // better air control
		friction_multiplier = 0.3 // some air friction but not too much

		// apply gravity
		player_vel.y -= GRAVITY_ACCELERATION * dt()
		if player_vel.y < -MAX_FALL_VELOCITY {
			player_vel.y = -MAX_FALL_VELOCITY
		}
	}

	// smooth acceleration/friction to horizontal movement
	if rl.Vector3Length(direction) > 0 {
		target_vel := direction * movement_speed

		vel_diff := target_vel - rl.Vector3{player_vel.x, 0, player_vel.z}
		acceleration := vel_diff * ACCELERATION * acceleration_multiplier * dt()

		player_vel.x += acceleration.x
		player_vel.z += acceleration.z
	} else {
		// friction when no input
		friction := FRICTION * friction_multiplier * dt()
		player_vel.x *= (1.0 - friction)
		player_vel.z *= (1.0 - friction)
	}
}

update_player_rotation :: proc() {
	mouse_delta := rl.GetMouseDelta()

	// update yaw and pitch from mouse input
	// TODO pitch and yaw should be read from the quaternion, instead of storing it as a separate variable
	player_yaw_in_radians -= mouse_delta.x * BASE_ROTATION_SPEED * dt()
	player_pitch_in_radians += mouse_delta.y * BASE_ROTATION_SPEED * dt()

	// clamp pitch to prevent flipping
	player_pitch_in_radians = clamp(
		player_pitch_in_radians,
		math.to_radians_f32(-89.0),
		math.to_radians_f32(89.0),
	)

	player_rotation = rl.QuaternionFromEuler(player_pitch_in_radians, player_yaw_in_radians, 0)
}

get_player_movement_input :: proc() -> (result: rl.Vector3) {
	if rl.IsKeyDown(.W) do result.z += 1
	if rl.IsKeyDown(.S) do result.z -= 1
	if rl.IsKeyDown(.A) do result.x += 1 // TODO why do we have to invert the signs on x?
	if rl.IsKeyDown(.D) do result.x -= 1
	if rl.IsKeyDown(.SPACE) do result.y += 1
	if rl.IsKeyDown(.LEFT_CONTROL) do result.y -= 1

	return rl.Vector3Normalize(result)
}

apply_player_velocity :: proc() {
	old_pos := player_pos
	movement := player_vel * dt()

	// try sliding collision - test each axis separately
	// try x movement
	player_pos.x += movement.x
	if game_mode == .Walking || game_mode == .Swimming {
		if is_player_colliding_with_cubes() {
			player_pos.x = old_pos.x // Rollback X
			player_vel.x = 0
		}
	}

	// try y movement
	player_pos.y += movement.y
	if game_mode == .Walking || game_mode == .Swimming {
		if is_player_colliding_with_cubes() {
			player_pos.y = old_pos.y // Rollback Y
			player_vel.y = 0
		}
	}

	// try z movement
	player_pos.z += movement.z
	if game_mode == .Walking || game_mode == .Swimming {
		if is_player_colliding_with_cubes() {
			player_pos.z = old_pos.z //
			player_vel.z = 0
		}
	}
}

update_player_camera :: proc() {
	player_camera.position = player_pos + rl.Vector3{0, PLAYER_SIZE.y - 0.8, 0}
	player_camera.target =
		player_camera.position + rl.Vector3RotateByQuaternion(VECTOR3_FORWARD, player_rotation)

	// adjust FOV based on movement state
	if game_mode == .Walking {
		// Check if player is running (holding shift and moving)
		// is_running :=
		// 	rl.IsKeyDown(.LEFT_SHIFT) &&
		// 	rl.Vector3Length(rl.Vector3{player_vel.x, 0, player_vel.z}) > 0.1
		is_running := false
		player_camera.fovy = is_running ? RUN_FOV : WALK_FOV
	} else {
		player_camera.fovy = WALK_FOV
	}
}

player_surrounding_chunks :: proc() -> (result: [9]Chunk_Pos) {
	player_chunk := player_chunk()
	index := 0

	result[0] = player_chunk

	for x in -1 ..= 1 {
		for y in -1 ..= 1 {
			if !(x == 0 && y == 0) {
				result[index] = Chunk_Pos{player_chunk.x + x, player_chunk.y + y}
				index += 1
			}
		}
	}

	return
}

ACTIVE_CUBE_MAX_DISTANCE :: 1000

player_active_cube_global :: proc() -> (cube_pos: Cube_Pos_Global, face: Face, found: bool) {
	ray := rl.GetScreenToWorldRay({SCREEN_WIDTH / 2, SCREEN_HEIGHT / 2}, player_camera)
	// rl.DrawRay(ray, rl.BLUE)

	// voxel ray traversal
	MAX_DISTANCE :: 10.0
	STEP_SIZE :: 0.05

	current_pos := ray.position
	step_vector := rl.Vector3Normalize(ray.direction) * STEP_SIZE
	distance := 0.0
	prev_pos := current_pos

	for distance < MAX_DISTANCE {
		current_cube_pos := cube_global_from_world(current_pos)

		if cube := cube_from_global(current_cube_pos); cube != nil && cube.kind != .Air {
			// now determine which face we hit by comparing
			// the previous position (outside cube) with current position (inside cube)
			prev_cube_pos := cube_global_from_world(prev_pos)

			diff := current_cube_pos - prev_cube_pos

			// determine face based on which coordinate changed
			if diff.x > 0 {
				face = .Left
			} else if diff.x < 0 {
				face = .Right
			} else if diff.y > 0 {
				face = .Bottom
			} else if diff.y < 0 {
				face = .Top
			} else if diff.z > 0 {
				face = .Front
			} else if diff.z < 0 {
				face = .Back
			} else {
				// shouldn't happen but just in case
				face = .Top
			}

			cube_pos = current_cube_pos
			found = true
			return
		}

		// step forward along the ray
		prev_pos = current_pos
		current_pos += step_vector
		distance += STEP_SIZE
	}

	return
}

place_cube_on_face :: proc(cube_pos: Cube_Pos_Global, face: Face) -> bool {
	// don't allow placing cubes on water
	if target_cube := cube_from_global(cube_pos);
	   target_cube != nil && target_cube.kind == .Water {
		return false
	}

	new_cube_pos := cube_pos

	switch face {
	case .Right:
		new_cube_pos.x += 1
	case .Left:
		new_cube_pos.x -= 1
	case .Top:
		new_cube_pos.y += 1
	case .Bottom:
		new_cube_pos.y -= 1
	case .Back:
		new_cube_pos.z += 1
	case .Front:
		new_cube_pos.z -= 1
	}

	if existing_cube := cube_from_global(new_cube_pos);
	   existing_cube != nil && existing_cube.kind != .Air {
		return false // position already occupied
	}

	if new_cube_pos.y >= CHUNK_HEIGHT || new_cube_pos.y < 0 {
		return false
	}

	// convert cube coordinates to world position (cube center)
	new_cube_world_pos :=
		rl.Vector3{f32(new_cube_pos.x), f32(new_cube_pos.y), f32(new_cube_pos.z)} +
		rl.Vector3{CUBE_SIZE, CUBE_SIZE, CUBE_SIZE} / 2

	player_box := rl.BoundingBox {
		min = player_pos - PLAYER_SIZE / 2,
		max = player_pos + PLAYER_SIZE / 2,
	}

	cube_box := rl.BoundingBox {
		min = new_cube_world_pos - rl.Vector3{CUBE_SIZE, CUBE_SIZE, CUBE_SIZE} / 2,
		max = new_cube_world_pos + rl.Vector3{CUBE_SIZE, CUBE_SIZE, CUBE_SIZE} / 2,
	}

	// don't place cube if it would intersect with player
	if rl.CheckCollisionBoxes(player_box, cube_box) {
		return false
	}

	// place the new cube
	if target_cube := cube_from_global(new_cube_pos); target_cube != nil {
		target_cube.kind = .Dirt
		target_cube.biome = .Grassland

		// mark the chunk mesh as needing regeneration
		chunk_coords := Chunk_Pos{new_cube_pos.x / CHUNK_WIDTH, new_cube_pos.z / CHUNK_WIDTH}

		// handle negative coordinates properly for chunk calculation
		if new_cube_pos.x < 0 && new_cube_pos.x % CHUNK_WIDTH != 0 {
			chunk_coords.x -= 1
		}
		if new_cube_pos.z < 0 && new_cube_pos.z % CHUNK_WIDTH != 0 {
			chunk_coords.y -= 1
		}

		if chunk, exists := &chunks[chunk_coords]; exists {
			chunk.model_ready = false
			// Also mark neighboring chunks as stale in case this cube is on the edge
			mark_neighbor_meshes_stale(chunk_coords)
		}
		return true
	}

	return false
}

has_water_neighbor :: proc(cube_pos: Cube_Pos_Global) -> bool {
	neighbor_offsets := [6]Cube_Pos_Global {
		{1, 0, 0},
		{-1, 0, 0},
		{0, 1, 0},
		{0, -1, 0},
		{0, 0, 1},
		{0, 0, -1},
	}

	for offset in neighbor_offsets {
		neighbor_pos := Cube_Pos_Global {
			cube_pos.x + offset.x,
			cube_pos.y + offset.y,
			cube_pos.z + offset.z,
		}

		if neighbor_cube := cube_from_global(neighbor_pos);
		   neighbor_cube != nil && neighbor_cube.kind == .Water {
			return true
		}
	}
	return false
}

is_bottom_layer :: proc(cube_pos: Cube_Pos_Global) -> bool {
	return cube_pos.y == 0
}

dig_cube :: proc(cube_pos: Cube_Pos_Global) {
	if target_cube := cube_from_global(cube_pos); target_cube != nil && target_cube.kind != .Air {
		if target_cube.kind == .Water {
			return // don't allow digging water blocks
		}

		if is_bottom_layer(cube_pos) {
			return // don't allow digging bottom layer blocks
		}

		if has_water_neighbor(cube_pos) {
			return // don't allow digging blocks neighboring water
		}

		// remove the cube by setting it to Air
		target_cube.kind = .Air

		chunk_coords := Chunk_Pos{cube_pos.x / CHUNK_WIDTH, cube_pos.z / CHUNK_WIDTH}

		// handle negative coordinates properly for chunk calculation
		if cube_pos.x < 0 && cube_pos.x % CHUNK_WIDTH != 0 {
			chunk_coords.x -= 1
		}
		if cube_pos.z < 0 && cube_pos.z % CHUNK_WIDTH != 0 {
			chunk_coords.y -= 1
		}

		if chunk, exists := &chunks[chunk_coords]; exists {
			chunk.model_ready = false
			// also mark neighboring chunks as stale in case this cube is on the edge
			if (is_cube_global_on_chunk_boundary(cube_pos)) {
				mark_neighbor_meshes_stale(chunk_coords)
			}
		}
	}
}

update_player :: proc() {
	update_player_rotation()

	// update game mode based on water detection (automatic swimming/walking transitions)
	update_game_mode()

	movement_input := get_player_movement_input()

	// use appropriate movement based on game mode
	switch game_mode {
	case .Flying:
		update_player_velocity_flying(movement_input)
	case .Walking:
		update_player_velocity_gravity(movement_input)
	case .Swimming:
		update_player_velocity_swimming(movement_input)
	}

	apply_player_velocity()
	update_player_camera()

	// highlight the cube the player is looking at
	if cube_pos, face, found := player_active_cube_global(); found {
		// don't highlight water cubes
		if target_cube := cube_from_global(cube_pos);
		   target_cube != nil && target_cube.kind == .Water {
		} else {
			cube_center :=
				rl.Vector3{f32(cube_pos.x), f32(cube_pos.y), f32(cube_pos.z)} +
				rl.Vector3{CUBE_SIZE, CUBE_SIZE, CUBE_SIZE} / 2

			rl.DrawCubeWires(cube_center, CUBE_SIZE, CUBE_SIZE, CUBE_SIZE, rl.BLACK)
		}

		if rl.IsMouseButtonPressed(.RIGHT) {
			place_cube_on_face(cube_pos, face)
		}

		if rl.IsMouseButtonPressed(.LEFT) {
			dig_cube(cube_pos)
		}
	}

	if rl.IsKeyPressed(.V) {
		wireframe_mode = !wireframe_mode
	}

	// handle game mode toggle (flying/walking/swimming)
	if rl.IsKeyPressed(.G) {
		switch game_mode {
		case .Flying:
			game_mode = .Walking
		case .Walking:
			game_mode = .Flying
		case .Swimming:
			game_mode = .Flying // skip swimming in manual toggle
		}
		player_vel = {0, 0, 0}
	}
}

player_chunk :: proc() -> Chunk_Pos {
	return chunk_from_worldpos(player_pos)
}

player_just_entered_new_chunk :: proc() -> (result: bool) {
	@(static) prev_chunk: Chunk_Pos = Chunk_Pos{99999, 99999}
	current_chunk := player_chunk()
	result = current_chunk != prev_chunk
	prev_chunk = current_chunk
	return
}

chunks_in_player_range :: proc() -> (result: map[Chunk_Pos]struct{}) {
	player_chunk := chunk_from_worldpos(player_pos)
	for x in -PLAYER_CHUNKS_RANGE ..< PLAYER_CHUNKS_RANGE {
		for z in -PLAYER_CHUNKS_RANGE ..< PLAYER_CHUNKS_RANGE {
			result[player_chunk + Chunk_Pos{x, z}] = {}
		}
	}
	return
}
