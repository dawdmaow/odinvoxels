package main

import "core:slice"
import rl "vendor:raylib"


// TODO: reuse chunks memory using pooling

WATER_TOP_HEIGHT_OFFSET :: CUBE_SIZE / 8

Face :: enum u8 {
	Right,
	Left,
	Top,
	Bottom,
	Front,
	Back,
}

Cube_Kind :: enum u8 {
	Air,
	Grass,
	Dirt,
	Stone,
	Water,
	Sand,
	Oak_Log,
	Oak_Leaves,
}

Cube :: struct {
	kind:  Cube_Kind,
	biome: Biome,
}

Chunk :: struct {
	cubes:             [CUBES_PER_CHUNK]Cube,
	opaque_model:      rl.Model,
	transparent_model: rl.Model,
	model_ready:       bool,
}

CHUNK_WIDTH :: 16
CHUNK_HEIGHT :: 64
CUBES_PER_CHUNK :: CHUNK_WIDTH * CHUNK_HEIGHT * CHUNK_WIDTH

CUBE_SIZE :: 1.0

VERTICES_PER_CUBE :: 4
VERTICES_PER_TRIANGLE :: 3

MAX_CHUNKS_LOADED_OR_UNLOADED_PER_FRAME :: 1

PLAYER_CHUNKS_RANGE :: 4

chunks: map[Chunk_Pos]Chunk
chunks_loading, chunks_unloading: [dynamic]Chunk_Pos
wireframe_mode: bool = false

get_cube_textures :: proc(cube: Cube) -> [Face]Texture_Id {
	switch cube.kind {
	case .Air:
		panic("Invalid cube kind")
	case .Grass:
		return [Face]Texture_Id {
			.Top = .Grass_Block_Top,
			.Bottom = .Dirt,
			.Right = .Grass_Block_Side,
			.Left = .Grass_Block_Side,
			.Front = .Grass_Block_Side,
			.Back = .Grass_Block_Side,
		}
	case .Dirt:
		return [Face]Texture_Id {
			.Top = .Dirt,
			.Bottom = .Dirt,
			.Right = .Dirt,
			.Left = .Dirt,
			.Front = .Dirt,
			.Back = .Dirt,
		}
	case .Stone:
		panic("Unhandled cube kind")
	case .Water:
		return [Face]Texture_Id {
			.Top = .Water_Still,
			.Bottom = .Water_Still,
			.Right = .Water_Still,
			.Left = .Water_Still,
			.Front = .Water_Still,
			.Back = .Water_Still,
		}
	case .Sand:
		return [Face]Texture_Id {
			.Top = .Sand,
			.Bottom = .Sand,
			.Right = .Sand,
			.Left = .Sand,
			.Front = .Sand,
			.Back = .Sand,
		}
	case .Oak_Log:
		return [Face]Texture_Id {
			.Top = .Oak_Log_Top,
			.Bottom = .Oak_Log_Top,
			.Right = .Oak_Log,
			.Left = .Oak_Log,
			.Front = .Oak_Log,
			.Back = .Oak_Log,
		}
	case .Oak_Leaves:
		return [Face]Texture_Id {
			.Top = .Oak_Leaves,
			.Bottom = .Oak_Leaves,
			.Right = .Oak_Leaves,
			.Left = .Oak_Leaves,
			.Front = .Oak_Leaves,
			.Back = .Oak_Leaves,
		}
	}
	panic("Unhandled cube kind")
}

get_biome_grass_tint :: proc(biome: Biome) -> rl.Color {
	#partial switch biome {
	case .Ocean, .Beach:
		return rl.Color{85, 255, 85, 255} // Bright green
	case .Temperate_Rain_Forest, .Tropical_Rain_Forest:
		return rl.Color{50, 200, 50, 255} // Dark lush green
	case .Temperate_Deciduous_Forest, .Tropical_Seasonal_Forest:
		return rl.Color{80, 220, 80, 255} // Medium forest green
	case .Taiga:
		return rl.Color{60, 180, 100, 255} // Cool green
	case .Grassland:
		return rl.Color{120, 255, 120, 255} // Bright grassland green
	case .Shrubland:
		return rl.Color{140, 200, 90, 255} // Yellowish green
	case .Tundra, .Snow:
		return rl.Color{180, 220, 180, 255} // Pale green
	case .Temperate_Desert, .Subtropical_Desert:
		return rl.Color{200, 200, 120, 255} // Dry yellowish
	case .Scorched, .Bare:
		return rl.Color{160, 140, 100, 255} // Brown-green
	case:
		return rl.Color{100, 200, 100, 255} // Default green
	}
}

get_biome_leaves_tint :: proc(biome: Biome) -> rl.Color {
	#partial switch biome {
	case .Temperate_Rain_Forest, .Tropical_Rain_Forest:
		return rl.Color{30, 150, 30, 255} // Dark forest green
	case .Temperate_Deciduous_Forest:
		return rl.Color{60, 180, 60, 255} // Medium green
	case .Tropical_Seasonal_Forest:
		return rl.Color{40, 160, 40, 255} // Tropical green
	case .Taiga:
		return rl.Color{45, 120, 80, 255} // Cool dark green
	case .Grassland, .Shrubland:
		return rl.Color{80, 160, 80, 255} // Lighter green
	case:
		return rl.Color{50, 140, 50, 255} // Default dark green
	}
}

get_cube_base_color :: proc(cube: Cube) -> rl.Color {
	// return rl.Color{255, 255, 255, 255}
	// return get_biome_grass_tint(cube.biome)
	switch cube.kind {
	case .Air:
		panic("Invalid cube kind")
	case .Grass:
		return get_biome_grass_tint(cube.biome)
	case .Dirt:
		return get_biome_grass_tint(cube.biome)
	case .Stone:
		return rl.Color{120, 120, 120, 255}
	case .Water:
		return rl.Color{64, 164, 223, 255}
	case .Sand:
		return rl.Color{238, 203, 173, 255}
	case .Oak_Log:
		return rl.Color{139, 115, 85, 255}
	case .Oak_Leaves:
		return get_biome_leaves_tint(cube.biome)
	}
	return rl.WHITE
}

cube_index :: proc(cube: Cube_Pos_Local) -> int {
	return cube.z * CHUNK_WIDTH * CHUNK_HEIGHT + cube.y * CHUNK_WIDTH + cube.x
}

array_index_to_cube_coords :: proc(index: int) -> Cube_Pos_Local {
	return Cube_Pos_Local {
		int(index % CHUNK_WIDTH),
		int((index / CHUNK_WIDTH) % CHUNK_HEIGHT),
		int(index / (CHUNK_WIDTH * CHUNK_HEIGHT)),
	}
}

texture_coords_to_atlas_uv :: proc(
	face_texcoords: [4]rl.Vector2,
	texture_id: Texture_Id,
) -> (
	result: [4]rl.Vector2,
) {
	atlas_rect := atlas_rectangle(texture_id)

	for i in 0 ..< 4 {
		result[i] = rl.Vector2 {
			(atlas_rect.x + face_texcoords[i].x * atlas_rect.width) / f32(ATLAS_WIDTH),
			(atlas_rect.y + face_texcoords[i].y * atlas_rect.height) / f32(ATLAS_HEIGHT),
		}
	}

	return result
}

unload_chunk :: proc(chunk: ^Chunk) {
	// unload opaque model
	if chunk.opaque_model.meshes != nil {
		assert(chunk.opaque_model.meshes[0] != {})
		rl.UnloadMesh(chunk.opaque_model.meshes[0])
		chunk.opaque_model.meshes[0] = {}
	}

	// Unload transparent model
	if chunk.transparent_model.meshes != nil {
		assert(chunk.transparent_model.meshes[0] != {})
		rl.UnloadMesh(chunk.transparent_model.meshes[0])
		chunk.transparent_model.meshes[0] = {}
	}
}

// Calculate ambient occlusion for a vertex based on neighboring blocks
vertex_ambient_occlusion :: proc(
	world_pos: Cube_Pos_Global,
	face: Face,
	vertex_index: int,
) -> f32 {
	// Define the 3 neighboring positions that affect each vertex's ambient occlusion
	// This creates the classic Minecraft smooth lighting effect

	ao_offsets: [Face][4][3]Cube_Pos_Global

	// For each face, define the 3 neighbor positions for each of the 4 vertices
	ao_offsets[.Top] = {
		{{-1, 0, -1}, {-1, 0, 0}, {0, 0, -1}}, // vertex 0 (bottom-left)
		{{-1, 0, 0}, {-1, 0, 1}, {0, 0, 1}}, // vertex 1 (top-left)
		{{0, 0, 1}, {1, 0, 1}, {1, 0, 0}}, // vertex 2 (top-right)
		{{1, 0, 0}, {1, 0, -1}, {0, 0, -1}}, // vertex 3 (bottom-right)
	}

	ao_offsets[.Bottom] = {
		{{-1, 0, 0}, {-1, 0, -1}, {0, 0, -1}},
		{{-1, 0, -1}, {-1, 0, 0}, {0, 0, -1}},
		{{0, 0, -1}, {1, 0, -1}, {1, 0, 0}},
		{{1, 0, 0}, {1, 0, -1}, {0, 0, -1}},
	}

	ao_offsets[.Right] = {
		{{0, -1, 0}, {0, -1, -1}, {0, 0, -1}},
		{{0, 0, -1}, {0, 1, -1}, {0, 1, 0}},
		{{0, 1, 0}, {0, 1, 1}, {0, 0, 1}},
		{{0, 0, 1}, {0, -1, 1}, {0, -1, 0}},
	}

	ao_offsets[.Left] = {
		{{0, 0, 1}, {0, -1, 1}, {0, -1, 0}},
		{{0, 1, 0}, {0, 1, 1}, {0, 0, 1}},
		{{0, 0, -1}, {0, 1, -1}, {0, 1, 0}},
		{{0, -1, 0}, {0, -1, -1}, {0, 0, -1}},
	}

	ao_offsets[.Front] = {
		{{-1, -1, 0}, {-1, 0, 0}, {0, -1, 0}},
		{{-1, 0, 0}, {-1, 1, 0}, {0, 1, 0}},
		{{0, 1, 0}, {1, 1, 0}, {1, 0, 0}},
		{{1, 0, 0}, {1, -1, 0}, {0, -1, 0}},
	}

	ao_offsets[.Back] = {
		{{0, -1, 0}, {1, -1, 0}, {1, 0, 0}},
		{{0, 1, 0}, {1, 1, 0}, {1, 0, 0}},
		{{-1, 0, 0}, {-1, 1, 0}, {0, 1, 0}},
		{{-1, -1, 0}, {-1, 0, 0}, {0, -1, 0}},
	}

	if vertex_index < 0 || vertex_index >= 4 do return 1.0

	offsets := ao_offsets[face][vertex_index]
	blocked_count := 0

	for offset in offsets {
		neighbor_pos := Cube_Pos_Global {
			world_pos.x + offset.x,
			world_pos.y + offset.y,
			world_pos.z + offset.z,
		}

		neighbor_cube := cube_from_global(neighbor_pos)
		if neighbor_cube != nil && is_cube_solid(neighbor_cube.kind) {
			blocked_count += 1
		}
	}

	// convert blocked count to AO factor (more blocked = brighter)
	ao_factor := 0.85 + f32(blocked_count) * 0.05
	return clamp(ao_factor, 0.85, 1.0)
}

is_cube_solid :: proc(kind: Cube_Kind) -> bool {
	return !(kind == .Water || kind == .Air)
}

update_chunk_meshes :: proc(chunk: ^Chunk, chunk_coords: Chunk_Pos) {
	if chunk.model_ready do return

	FACE_BRIGHTNESS := [Face]f32 {
		.Right  = 0.8,
		.Left   = 0.8,
		.Top    = 1.0,
		.Bottom = 0.7,
		.Front  = 0.9,
		.Back   = 0.9,
	}

	FACE_VERTICES := [Face][4]rl.Vector3 {
		.Right  = {
			rl.Vector3{1, 0, 0},
			rl.Vector3{1, 1, 0},
			rl.Vector3{1, 1, 1},
			rl.Vector3{1, 0, 1},
		},
		.Left   = {
			rl.Vector3{0, 0, 1},
			rl.Vector3{0, 1, 1},
			rl.Vector3{0, 1, 0},
			rl.Vector3{0, 0, 0},
		},
		.Top    = {
			rl.Vector3{0, 1, 0},
			rl.Vector3{0, 1, 1},
			rl.Vector3{1, 1, 1},
			rl.Vector3{1, 1, 0},
		},
		.Bottom = {
			rl.Vector3{0, 0, 1},
			rl.Vector3{0, 0, 0},
			rl.Vector3{1, 0, 0},
			rl.Vector3{1, 0, 1},
		},
		.Front  = {
			rl.Vector3{0, 0, 0},
			rl.Vector3{0, 1, 0},
			rl.Vector3{1, 1, 0},
			rl.Vector3{1, 0, 0},
		},
		.Back   = {
			rl.Vector3{1, 0, 1},
			rl.Vector3{1, 1, 1},
			rl.Vector3{0, 1, 1},
			rl.Vector3{0, 0, 1},
		},
	}

	FACE_TEXCOORDS := [4]rl.Vector2 {
		rl.Vector2{0, 1}, // bottom-left
		rl.Vector2{0, 0}, // top-left
		rl.Vector2{1, 0}, // top-right
		rl.Vector2{1, 1}, // bottom-right
	}

	// create separate meshes for opaque and transparent cubes

	opaque_vertices := make(
		[dynamic]rl.Vector3,
		0,
		CUBES_PER_CHUNK * VERTICES_PER_CUBE,
		allocator = rl.MemAllocator(),
	)

	opaque_colors := make(
		[dynamic]u8,
		0,
		CUBES_PER_CHUNK * VERTICES_PER_CUBE * 4,
		allocator = rl.MemAllocator(),
	)

	opaque_texcoords := make(
		[dynamic]rl.Vector2,
		0,
		CUBES_PER_CHUNK * VERTICES_PER_CUBE,
		allocator = rl.MemAllocator(),
	)

	transparent_vertices := make(
		[dynamic]rl.Vector3,
		0,
		CUBES_PER_CHUNK * VERTICES_PER_CUBE,
		allocator = rl.MemAllocator(),
	)

	transparent_colors := make(
		[dynamic]u8,
		0,
		CUBES_PER_CHUNK * VERTICES_PER_CUBE * 4,
		allocator = rl.MemAllocator(),
	)

	transparent_texcoords := make(
		[dynamic]rl.Vector2,
		0,
		CUBES_PER_CHUNK * VERTICES_PER_CUBE,
		allocator = rl.MemAllocator(),
	)

	for cube, index in chunk.cubes {
		if cube.kind == .Air do continue
		local_cube_coords := array_index_to_cube_coords(index)
		world_cube_coords := cube_global_from_local(chunk_coords, local_cube_coords)

		// check neighbors using world coordinates (can span across chunks)
		neighbors := [Face]^Cube {
			.Right  = cube_from_global(
				Cube_Pos_Global{world_cube_coords.x + 1, world_cube_coords.y, world_cube_coords.z},
			),
			.Left   = cube_from_global(
				Cube_Pos_Global{world_cube_coords.x - 1, world_cube_coords.y, world_cube_coords.z},
			),
			.Top    = world_cube_coords.y + 1 < CHUNK_HEIGHT ? cube_from_global(Cube_Pos_Global{world_cube_coords.x, world_cube_coords.y + 1, world_cube_coords.z}) : nil,
			.Bottom = world_cube_coords.y - 1 >= 0 ? cube_from_global(Cube_Pos_Global{world_cube_coords.x, world_cube_coords.y - 1, world_cube_coords.z}) : nil,
			.Front  = cube_from_global(
				Cube_Pos_Global{world_cube_coords.x, world_cube_coords.y, world_cube_coords.z - 1},
			),
			.Back   = cube_from_global(
				Cube_Pos_Global{world_cube_coords.x, world_cube_coords.y, world_cube_coords.z + 1},
			),
		}

		cube_solid := is_cube_solid(cube.kind)

		target_vertices := cube_solid ? &opaque_vertices : &transparent_vertices
		target_colors := cube_solid ? &opaque_colors : &transparent_colors
		target_texcoords := cube_solid ? &opaque_texcoords : &transparent_texcoords

		for face in Face {
			// only render face if neighbor is nil (edge of world) or should be visible
			should_render_face := false
			neighbor := neighbors[face]

			if neighbor == nil {
				should_render_face = true
			} else {
				neighbor_solid := is_cube_solid(neighbor.kind)

				if neighbor.kind == .Air {
					should_render_face = true
				}
				if cube_solid && !neighbor_solid {
					should_render_face = true
				}
			}

			if should_render_face {
				face_verts := FACE_VERTICES[face]
				base_color := get_cube_base_color(cube)
				face_brightness := FACE_BRIGHTNESS[face]

				cube_pos :=
					rl.Vector3 {
						f32(local_cube_coords.x),
						f32(local_cube_coords.y),
						f32(local_cube_coords.z),
					} *
					CUBE_SIZE

				v1 := face_verts[0] + cube_pos
				v2 := face_verts[1] + cube_pos
				v3 := face_verts[2] + cube_pos
				v4 := face_verts[3] + cube_pos

				cube_above := cube_from_global(
					Cube_Pos_Global {
						world_cube_coords.x,
						world_cube_coords.y + 1,
						world_cube_coords.z,
					},
				)

				top_of_water :=
					cube.kind == .Water &&
					face == .Top &&
					(cube_above == nil || cube_above.kind != .Water)

				// adjust water cube height for top face (like Minecraft)
				if top_of_water {
					v1 -= rl.Vector3{0, WATER_TOP_HEIGHT_OFFSET, 0}
					v4 -= rl.Vector3{0, WATER_TOP_HEIGHT_OFFSET, 0}
					v2 -= rl.Vector3{0, WATER_TOP_HEIGHT_OFFSET, 0}
					v3 -= rl.Vector3{0, WATER_TOP_HEIGHT_OFFSET, 0}
				}

				cube_textures := get_cube_textures(cube)
				face_texture_id := cube_textures[face]
				atlas_uv := texture_coords_to_atlas_uv(FACE_TEXCOORDS, face_texture_id)

				ao_values := [4]f32 {
					vertex_ambient_occlusion(world_cube_coords, face, 0),
					vertex_ambient_occlusion(world_cube_coords, face, 1),
					vertex_ambient_occlusion(world_cube_coords, face, 2),
					vertex_ambient_occlusion(world_cube_coords, face, 3),
				}

				vertex_colors := [4]rl.Color{}
				alpha_value := u8(255)
				if cube.kind == .Water {
					alpha_value = u8(200)
				}

				for i in 0 ..< 4 {
					total_brightness := face_brightness * ao_values[i]
					vertex_colors[i] = rl.Color {
						u8(clamp(f32(base_color.r) * total_brightness, 0, 255)),
						u8(clamp(f32(base_color.g) * total_brightness, 0, 255)),
						u8(clamp(f32(base_color.b) * total_brightness, 0, 255)),
						alpha_value,
					}
				}

				// first triangle: v1, v2, v3 (vertices 0, 1, 2)
				append(target_vertices, v1, v2, v3)
				append(target_texcoords, atlas_uv[0], atlas_uv[1], atlas_uv[2])
				append(
					target_colors,
					vertex_colors[0].r,
					vertex_colors[0].g,
					vertex_colors[0].b,
					vertex_colors[0].a,
				)
				append(
					target_colors,
					vertex_colors[1].r,
					vertex_colors[1].g,
					vertex_colors[1].b,
					vertex_colors[1].a,
				)
				append(
					target_colors,
					vertex_colors[2].r,
					vertex_colors[2].g,
					vertex_colors[2].b,
					vertex_colors[2].a,
				)

				// second triangle: v1, v3, v4 (vertices 0, 2, 3)
				append(target_vertices, v1, v3, v4)
				append(target_texcoords, atlas_uv[0], atlas_uv[2], atlas_uv[3])
				append(
					target_colors,
					vertex_colors[0].r,
					vertex_colors[0].g,
					vertex_colors[0].b,
					vertex_colors[0].a,
				)
				append(
					target_colors,
					vertex_colors[2].r,
					vertex_colors[2].g,
					vertex_colors[2].b,
					vertex_colors[2].a,
				)
				append(
					target_colors,
					vertex_colors[3].r,
					vertex_colors[3].g,
					vertex_colors[3].b,
					vertex_colors[3].a,
				)

				// add double-sided face for water top (visible from underwater)
				if top_of_water {
					// first triangle (reversed winding): v3, v2, v1 (vertices 2, 1, 0)
					append(target_vertices, v3, v2, v1)
					append(target_texcoords, atlas_uv[2], atlas_uv[1], atlas_uv[0])
					append(
						target_colors,
						vertex_colors[2].r,
						vertex_colors[2].g,
						vertex_colors[2].b,
						vertex_colors[2].a,
					)
					append(
						target_colors,
						vertex_colors[1].r,
						vertex_colors[1].g,
						vertex_colors[1].b,
						vertex_colors[1].a,
					)
					append(
						target_colors,
						vertex_colors[0].r,
						vertex_colors[0].g,
						vertex_colors[0].b,
						vertex_colors[0].a,
					)

					// second triangle (reversed winding): v4, v3, v1 (vertices 3, 2, 0)
					append(target_vertices, v4, v3, v1)
					append(target_texcoords, atlas_uv[3], atlas_uv[2], atlas_uv[0])
					append(
						target_colors,
						vertex_colors[3].r,
						vertex_colors[3].g,
						vertex_colors[3].b,
						vertex_colors[3].a,
					)
					append(
						target_colors,
						vertex_colors[2].r,
						vertex_colors[2].g,
						vertex_colors[2].b,
						vertex_colors[2].a,
					)
					append(
						target_colors,
						vertex_colors[0].r,
						vertex_colors[0].g,
						vertex_colors[0].b,
						vertex_colors[0].a,
					)
				}
			}
		}
	}

	// clean up existing models if they were previously generated
	unload_chunk(chunk)

	// create opaque model
	if len(opaque_vertices) > 0 {
		opaque_mesh: rl.Mesh
		opaque_mesh.vertexCount = i32(len(opaque_vertices))
		opaque_mesh.triangleCount = opaque_mesh.vertexCount / 3
		opaque_mesh.vertices = cast(^f32)&opaque_vertices[0]
		opaque_mesh.colors = cast(^u8)&opaque_colors[0]
		opaque_mesh.texcoords = cast(^f32)&opaque_texcoords[0]

		rl.UploadMesh(&opaque_mesh, false)

		chunk.opaque_model = rl.LoadModelFromMesh(opaque_mesh)

		rl.SetMaterialTexture(&chunk.opaque_model.materials[0], .ALBEDO, atlas_texture)
		chunk.opaque_model.materials[0].shader = fog_shader

		rl.SetModelMeshMaterial(&chunk.opaque_model, 0, 0)
	}

	// create transparent model
	if len(transparent_vertices) > 0 {
		transparent_mesh: rl.Mesh
		transparent_mesh.vertexCount = i32(len(transparent_vertices))
		transparent_mesh.triangleCount = transparent_mesh.vertexCount / 3
		transparent_mesh.vertices = cast(^f32)&transparent_vertices[0]
		transparent_mesh.colors = cast(^u8)&transparent_colors[0]
		transparent_mesh.texcoords = cast(^f32)&transparent_texcoords[0]

		rl.UploadMesh(&transparent_mesh, false)

		chunk.transparent_model = rl.LoadModelFromMesh(transparent_mesh)

		rl.SetMaterialTexture(&chunk.transparent_model.materials[0], .ALBEDO, atlas_texture)
		chunk.transparent_model.materials[0].shader = fog_shader

		rl.SetModelMeshMaterial(&chunk.transparent_model, 0, 0)
	}

	chunk.model_ready = true
}

is_chunk_model_empty :: proc(chunk: ^Chunk) -> bool {
	return chunk.opaque_model == rl.Model{} && chunk.transparent_model == rl.Model{}
}

cube_global_from_local :: proc(chunk: Chunk_Pos, local: Cube_Pos_Local) -> Cube_Pos_Global {
	return Cube_Pos_Global {
		chunk.x * CHUNK_WIDTH + local.x,
		local.y,
		chunk.y * CHUNK_WIDTH + local.z,
	}
}

cube_from_global :: proc(world_cube_coords: Cube_Pos_Global) -> ^Cube {
	chunk_coords := Chunk_Pos{world_cube_coords.x / CHUNK_WIDTH, world_cube_coords.z / CHUNK_WIDTH}

	// handle negative coordinates properly for chunk calculation
	if world_cube_coords.x < 0 && world_cube_coords.x % CHUNK_WIDTH != 0 {
		chunk_coords.x -= 1
	}
	if world_cube_coords.z < 0 && world_cube_coords.z % CHUNK_WIDTH != 0 {
		chunk_coords.y -= 1
	}

	chunk, chunk_exists := &chunks[chunk_coords]
	if !chunk_exists {
		return nil
	}

	local_cube_coords := Cube_Pos_Local {
		world_cube_coords.x - chunk_coords.x * CHUNK_WIDTH,
		world_cube_coords.y,
		world_cube_coords.z - chunk_coords.y * CHUNK_WIDTH,
	}

	// handle negative local coordinates
	if local_cube_coords.x < 0 {
		local_cube_coords.x += CHUNK_WIDTH
	}
	if local_cube_coords.z < 0 {
		local_cube_coords.z += CHUNK_WIDTH
	}

	// validate local coordinates
	if !cube_pos_local_valid(local_cube_coords) {
		return nil
	}

	return &chunk.cubes[cube_index(local_cube_coords)]
}

mark_neighbor_meshes_stale :: proc(chunk_coords: Chunk_Pos) {
	neighbor_offsets := [4]Chunk_Pos{{-1, 0}, {1, 0}, {0, -1}, {0, 1}}

	for offset in neighbor_offsets {
		neighbor_coords := chunk_coords + offset

		if neighbor_chunk, exists := &chunks[neighbor_coords]; exists {
			neighbor_chunk.model_ready = false
		}
	}
}


render_loaded_chunks :: proc() {
	rl.SetShaderValue(
		fog_shader,
		rl.GetShaderLocation(fog_shader, "cameraPosition"),
		&player_camera.position,
		.VEC3,
	)

	fog_color_f32 := rl.Vector3 {
		f32(fog_color.r) / 255,
		f32(fog_color.g) / 255,
		f32(fog_color.b) / 255,
	}
	rl.SetShaderValue(
		fog_shader,
		rl.GetShaderLocation(fog_shader, "fogColor"),
		&fog_color_f32,
		.VEC4,
	)

	rl.SetShaderValue(
		fog_shader,
		rl.GetShaderLocation(fog_shader, "fogDensity"),
		&fog_density,
		.FLOAT,
	)

	rl.SetShaderValue(fog_shader, rl.GetShaderLocation(fog_shader, "fogStart"), &fog_start, .FLOAT)
	rl.SetShaderValue(fog_shader, rl.GetShaderLocation(fog_shader, "fogEnd"), &fog_end, .FLOAT)

	fog_enabled_int := wireframe_mode ? 0 : 1
	rl.SetShaderValue(
		fog_shader,
		rl.GetShaderLocation(fog_shader, "fogEnabled"),
		&fog_enabled_int,
		.INT,
	)

	// render opaque chunks first (no alpha blending needed)
	for coords, &chunk in chunks {
		update_chunk_meshes(&chunk, coords)
		chunk_pos := chunk_coords_to_pos(coords)

		if chunk.opaque_model.meshes != nil && chunk.opaque_model.meshes[0] != {} {
			if wireframe_mode {
				rl.DrawModelWires(chunk.opaque_model, chunk_pos, 1, rl.Color{0, 0, 0, 255})

				// draw chunk boundary
				rl.DrawBoundingBox(
					rl.BoundingBox {
						min = chunk_pos,
						max = chunk_pos + rl.Vector3{CHUNK_WIDTH, CHUNK_HEIGHT, CHUNK_WIDTH},
					},
					rl.RED,
				)
			} else {
				rl.DrawModel(chunk.opaque_model, chunk_pos, 1, rl.Color{255, 255, 255, 255})
			}
		}
	}

	// enable alpha blending for transparent chunks
	rl.BeginBlendMode(.ALPHA)

	// render transparent chunks second (with alpha blending)
	for coords, &chunk in chunks {
		chunk_pos := chunk_coords_to_pos(coords)

		if chunk.transparent_model.meshes != nil && chunk.transparent_model.meshes[0] != {} {
			if wireframe_mode {
				rl.DrawModelWires(chunk.transparent_model, chunk_pos, 1, rl.Color{0, 0, 0, 255})
			} else {
				rl.DrawModel(chunk.transparent_model, chunk_pos, 1, rl.Color{255, 255, 255, 255})
			}
		}
	}

	// End alpha blending
	rl.EndBlendMode()
}

chunks_tick :: proc() {
	// only update the list of chunks that are in relation to player's current chunk if the player has in fact entered a new chunk
	if player_just_entered_new_chunk() {
		chunks_in_range := chunks_in_player_range()

		clear(&chunks_loading)
		clear(&chunks_unloading)

		// update the list of chunks waiting to load
		for pos in chunks_in_range {
			if pos not_in chunks && !slice.contains(chunks_loading[:], pos) {
				append(&chunks_loading, pos)
			}
		}

		// update the list of chunks waiting to unload
		for pos in chunks {
			if pos not_in chunks_in_range && !slice.contains(chunks_unloading[:], pos) {
				append(&chunks_unloading, pos)
			}
		}
	}

	loaded_or_unloaded := 0

	slice.sort_by(chunks_loading[:], proc(a, b: Chunk_Pos) -> bool {
		return !is_chunk_closer_to_player(a, b)
	})

	loaded := 0

	#reverse for chunk in chunks_loading {
		chunks[chunk] = generate_chunk(chunk)
		mark_neighbor_meshes_stale(chunk)
		loaded += 1
		loaded_or_unloaded += 1
		if loaded_or_unloaded >= MAX_CHUNKS_LOADED_OR_UNLOADED_PER_FRAME {
			break
		}
	}

	resize(&chunks_loading, len(chunks_loading) - loaded)

	if loaded_or_unloaded < MAX_CHUNKS_LOADED_OR_UNLOADED_PER_FRAME {
		slice.sort_by(chunks_unloading[:], proc(a, b: Chunk_Pos) -> bool {
			return !is_chunk_closer_to_player(a, b)
		})

		unloaded := 0

		#reverse for pos in chunks_unloading {
			unload_chunk(&chunks[pos])
			delete_key(&chunks, pos)
			unloaded += 1
			loaded_or_unloaded += 1
			if loaded_or_unloaded >= MAX_CHUNKS_LOADED_OR_UNLOADED_PER_FRAME {
				break
			}
		}

		resize(&chunks_unloading, len(chunks_unloading) - unloaded)
	}
}

is_cube_global_on_chunk_boundary :: proc(cube_pos: Cube_Pos_Global) -> bool {
	return(
		cube_pos.x % CHUNK_WIDTH == 0 ||
		cube_pos.z % CHUNK_WIDTH == 0 ||
		cube_pos.x % CHUNK_WIDTH == CHUNK_WIDTH - 1 ||
		cube_pos.z % CHUNK_WIDTH == CHUNK_WIDTH - 1 \
	)
}
