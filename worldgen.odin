package main

import "core:math/linalg"
import "core:math/rand"
import rl "vendor:raylib"

Height_Map_Value :: struct {
	in_cubes: i32,
	relative: f32,
}

Biome :: enum u8 {
	Ocean,
	Beach,
	Scorched,
	Bare,
	Tundra,
	Snow,
	Temperate_Desert,
	Shrubland,
	Taiga,
	Temperate_Rain_Forest,
	Temperate_Deciduous_Forest,
	Grassland,
	Subtropical_Desert,
	Tropical_Seasonal_Forest,
	Tropical_Rain_Forest,
}


Height_Map :: [CHUNK_WIDTH][CHUNK_WIDTH]Height_Map_Value
Moisture_Map :: [CHUNK_WIDTH][CHUNK_WIDTH]f32
Biome_Map :: [CHUNK_WIDTH][CHUNK_WIDTH]Biome

// generate_heightmap :: proc(chunk_coords: Chunk_Coords) -> (result: Height_Map) {
// 	x_world := i32(chunk_coords.x * CHUNK_SIZE)
// 	y_world := i32(chunk_coords.y * CHUNK_SIZE)
// 	heightmap1 := rl.GenImagePerlinNoise(CHUNK_SIZE, CHUNK_SIZE, x_world, y_world, 1)
// 	heightmap2 := rl.GenImagePerlinNoise(
// 		CHUNK_SIZE,
// 		CHUNK_SIZE,
// 		x_world * 2 + 1,
// 		y_world * 2 + 10,
// 		1,
// 	)
// 	heightmap3 := rl.GenImagePerlinNoise(
// 		CHUNK_SIZE,
// 		CHUNK_SIZE,
// 		x_world * 4 + 20,
// 		y_world * 4 + 3,
// 		1,
// 	)

// 	defer rl.UnloadImage(heightmap1)
// 	defer rl.UnloadImage(heightmap2)
// 	defer rl.UnloadImage(heightmap3)

// 	for x in 0 ..< i32(CHUNK_SIZE) {
// 		for z in 0 ..< i32(CHUNK_SIZE) {
// 			noise1 := f32(rl.GetImageColor(heightmap1, x, z).r) / 255 * 1
// 			noise2 := f32(rl.GetImageColor(heightmap2, z, x).r) / 255 * 0.5
// 			noise3 := f32(rl.GetImageColor(heightmap3, x, z).r) / 255 * 0.25
// 			noise := (noise1 + noise2 + noise3) / (1 + 0.5 + 0.25)

// 			FLATNESS :: 2
// 			relative := math.pow(noise, FLATNESS)
// 			in_cubes := i32(clamp(relative * f32(CHUNK_HEIGHT), 1, f32(CHUNK_HEIGHT) - 1))
// 			result[x][z] = Height_Map_Value {
// 				in_cubes = in_cubes,
// 				relative = relative,
// 			}
// 		}
// 	}
// 	return
// }

generate_heightmap :: proc(chunk_coords: Chunk_Pos) -> (result: Height_Map) {
	// generate a larger noise map that includes neighboring areas for smooth transitions
	NOISE_SIZE :: CHUNK_WIDTH + 2
	x_world := i32(chunk_coords.x * CHUNK_WIDTH - 1) // offset by 1 for padding
	y_world := i32(chunk_coords.y * CHUNK_WIDTH - 1)

	heightmap := rl.GenImagePerlinNoise(NOISE_SIZE, NOISE_SIZE, x_world, y_world, 0.2)
	defer rl.UnloadImage(heightmap)

	for x in 0 ..< i32(CHUNK_WIDTH) {
		for y in 0 ..< i32(CHUNK_WIDTH) {
			// sample from the padded noise map (offset by 1)
			relative := f32(rl.GetImageColor(heightmap, x + 1, y + 1).r) / 255
			// in_cubes := clamp(i32(relative * CHUNK_HEIGHT), 1, CHUNK_HEIGHT - 1)
			// in_cubes := clamp(i32(relative * CHUNK_HEIGHT), 1, CHUNK_HEIGHT - 1)
			in_cubes := linalg.lerp(f32(1), f32(CHUNK_HEIGHT) - 1, relative)
			result[x][y] = Height_Map_Value {
				in_cubes = i32(in_cubes),
				relative = relative,
			}
		}
	}
	return
}

generate_moisture_map :: proc(chunk: Chunk_Pos) -> (result: Moisture_Map) {
	x := i32(chunk.x * CHUNK_WIDTH)
	y := i32(chunk.y * CHUNK_WIDTH)
	moisture_map := rl.GenImagePerlinNoise(CHUNK_WIDTH, CHUNK_WIDTH, x, y, 1)
	defer rl.UnloadImage(moisture_map)

	for x in 0 ..< i32(CHUNK_WIDTH) {
		for z in 0 ..< i32(CHUNK_WIDTH) {
			noise := f32(rl.GetImageColor(moisture_map, x, z).r) / 255
			result[x][z] = noise
		}
	}
	return
}

generate_biome_map :: proc(height: Height_Map, moisture: Moisture_Map) -> (result: Biome_Map) {
	for x in 0 ..< i32(CHUNK_WIDTH) {
		for z in 0 ..< i32(CHUNK_WIDTH) {
			height_val := height[x][z]
			moisture_val := moisture[x][z]

			switch height_val.relative {
			case 0.0 ..< 0.1:
				result[x][z] = .Ocean
			case 0.1 ..< 0.12:
				result[x][z] = .Beach
			case 0.12 ..< 0.3:
				switch moisture_val {
				case 0.0 ..< 0.16:
					result[x][z] = .Subtropical_Desert
				case 0.16 ..< 0.33:
					result[x][z] = .Grassland
				case 0.33 ..< 0.66:
					result[x][z] = .Tropical_Seasonal_Forest
				case 0.66 ..= 1.0:
					result[x][z] = .Tropical_Rain_Forest
				}
			case 0.3 ..< 0.6:
				switch moisture_val {
				case 0.0 ..< 0.16:
					result[x][z] = .Temperate_Desert
				case 0.16 ..< 0.5:
					result[x][z] = .Grassland
				case 0.5 ..< 0.83:
					result[x][z] = .Temperate_Deciduous_Forest
				case 0.83 ..= 1.0:
					result[x][z] = .Temperate_Rain_Forest
				}
			case 0.6 ..< 0.8:
				switch moisture_val {
				case 0.0 ..< 0.33:
					result[x][z] = .Temperate_Desert
				case 0.33 ..< 0.66:
					result[x][z] = .Shrubland
				case 0.66 ..= 1.0:
					result[x][z] = .Taiga
				}
			case 0.8 ..= 1.0:
				switch moisture_val {
				case 0.0 ..< 0.1:
					result[x][z] = .Scorched
				case 0.1 ..< 0.2:
					result[x][z] = .Bare
				case 0.2 ..< 0.5:
					result[x][z] = .Tundra
				case 0.5 ..= 1.0:
					result[x][z] = .Snow
				}
			case:
				panic("Invalid height value")
			}
		}
	}
	return
}

/*
proc heightmap(chunkPos: ChunkPos): HeightMap =
  let x = chunkPos.x * ChunkSize
  let z = chunkPos.z * ChunkSize
  let heightmap1 = genImagePerlinNoise(ChunkSize, ChunkSize, x, z, 1)
  let heightmap2 = genImagePerlinNoise(ChunkSize, ChunkSize, x * 2 + 1, z * 2 + 10, 1)
  let heightmap3 = genImagePerlinNoise(ChunkSize, ChunkSize, x * 4 + 20, z * 4 + 3, 1)
  for x in 0 ..< ChunkSize:
    for z in 0 ..< ChunkSize:
      let noise1 = heightmap1.getImageColor(x.int32, z.int32).r.float32 / 255 * 1
      let noise2 = heightmap2.getImageColor(z.int32, x.int32).r.float32 / 255 * 0.5
      let noise3 = heightmap3.getImageColor(x.int32, z.int32).r.float32 / 255 * 0.25
      let noise: 0.0 .. 1.0 = (noise1 + noise2 + noise3) / (1 + 0.5 + 0.25)
      # let noise = noise1
      # let height = (noise * ChunkSize).clamp(1, ChunkSize - 1).int
      # let height = (noise * ChunkSize).clamp(1, ChunkSize - 1)
      # dump (noise, noise.pow(2.12))
      const Flatness = 2
      # const FudgeFactor = 1.2
      let float: 0.0 .. 1.0 = (noise).pow(Flatness)
      let int = (float * ChunkSize).clamp(1, ChunkSize - 1).int
      result[x][z] = HeightmapValue(int: int, float: float)

proc moistureMap(chunkPos: ChunkPos): MoistureMap =
  let x = chunkPos.x * ChunkSize
  let z = chunkPos.z * ChunkSize
  let moistureMap = genImagePerlinNoise(ChunkSize, ChunkSize, x, z, 1)
  for x in 0 ..< ChunkSize:
    for z in 0 ..< ChunkSize:
      let noise = moistureMap.getImageColor(x.int32, z.int32).r.float32 / 255
      result[z][x] = noise

#[
function biome(e, m) {
  // these thresholds will need tuning to match your generator
  if (e < 0.1) return OCEAN;
  if (e < 0.12) return BEACH;

  if (e > 0.8) {
    if (m < 0.1) return SCORCHED;
    if (m < 0.2) return BARE;
    if (m < 0.5) return TUNDRA;
    return SNOW;
  }

  if (e > 0.6) {
    if (m < 0.33) return TEMPERATE_DESERT;
    if (m < 0.66) return SHRUBLAND;
    return TAIGA;
  }

  if (e > 0.3) {
    if (m < 0.16) return TEMPERATE_DESERT;
    if (m < 0.50) return GRASSLAND;
    if (m < 0.83) return TEMPERATE_DECIDUOUS_FOREST;
    return TEMPERATE_RAIN_FOREST;
  }

  if (m < 0.16) return SUBTROPICAL_DESERT;
  if (m < 0.33) return GRASSLAND;
  if (m < 0.66) return TROPICAL_SEASONAL_FOREST;
  return TROPICAL_RAIN_FOREST;
}
]#

proc biomeMap(heightmap: HeightMap, moistureMap: MoistureMap): BiomeMap =
  for x in 0 ..< ChunkSize:
    for z in 0 ..< ChunkSize:
      let height = heightmap[x][z]
      let moisture = moistureMap[x][z]
      result[x][z] =
        if height.float < 0.1:
          Ocean
        elif height.float < 0.12:
          Beach
        elif height.float > 0.8:
          if moisture.float < 0.1:
            Scorched
          elif moisture.float < 0.2:
            Bare
          elif moisture.float < 0.5:
            Tundra
          else:
            Snow
        elif height.float > 0.6:
          if moisture.float < 0.33:
            TemperateDesert
          elif moisture.float < 0.66:
            Shrubland
          else:
            Taiga
        elif height.float > 0.3:
          if moisture.float < 0.16:
            TemperateDesert
          elif moisture.float < 0.5:
            Grassland
          elif moisture.float < 0.83:
            TemperateDeciduousForest
          else:
            TemperateRainForest
        elif moisture.float < 0.16:
          SubtropicalDesert
        elif moisture.float < 0.33:
          Grassland
        elif moisture.float < 0.66:
          TropicalSeasonalForest
        else:
          TropicalRainForest

proc genChunk*(chunkPos: ChunkPos): Chunk =
  let heightmap = heightmap(chunkPos)
  let moistureMap = moistureMap(chunkPos)
  let biomeMap = biomeMap(heightmap, moistureMap)
  result = Chunk(offset: chunkPos, biomeMap: biomeMap)
  for x in 0 ..< ChunkSize:
    for z in 0 ..< ChunkSize:
      let height = heightmap[x][z]
      for y in 0 ..< height.int:
        # result[cubePos(x, y, z)] = Cube(kind: sample {Grass .. Sand})
        # result[cubePos(x, y, z)] = Cube(kind: sample {Grass, Dirt})
        result[cubePos(x, y, z)] = Cube(kind: Grass)
*/

// Tree generation functions
Tree_Type :: enum {
	Oak,
}

can_place_tree :: proc(chunk: ^Chunk, x, z: int, surface_y: int, tree_height: int) -> bool {
	// check if tree fits within chunk bounds
	if surface_y + tree_height >= CHUNK_HEIGHT do return false

	// check if the surface block is grass
	surface_coords := Cube_Pos_Local{x, surface_y, z}
	surface_cube := &chunk.cubes[cube_index(surface_coords)]
	if surface_cube.kind != .Grass do return false

	// check if there's enough space above for the tree
	for y in surface_y + 1 ..< surface_y + tree_height {
		tree_coords := Cube_Pos_Local{x, y, z}
		if tree_coords.y >= CHUNK_HEIGHT do return false
		tree_cube := &chunk.cubes[cube_index(tree_coords)]
		if tree_cube.kind != .Air do return false
	}

	return true
}

place_tree :: proc(chunk: ^Chunk, x, z: int, surface_y: int, tree_type: Tree_Type, biome: Biome) {
	switch tree_type {
	case .Oak:
		place_oak_tree(chunk, x, z, surface_y, biome)
	}
}

place_oak_tree :: proc(chunk: ^Chunk, x, z: int, surface_y: int, biome: Biome) {
	trunk_height := 4 + rand.int_max(3)

	// place trunk
	for y in 0 ..< trunk_height {
		trunk_coords := Cube_Pos_Local{x, surface_y + y + 1, z}
		if trunk_coords.y < CHUNK_HEIGHT {
			chunk.cubes[cube_index(trunk_coords)] = Cube {
				kind  = .Oak_Log,
				biome = biome,
			}
		}
	}

	// place leaves in a roughly spherical pattern
	leaves_center_y := surface_y + trunk_height
	leaves_radius := 2

	for dx in -leaves_radius ..= leaves_radius {
		for dz in -leaves_radius ..= leaves_radius {
			for dy in -1 ..= 2 { 	// leaves extend 1 block down and 2 blocks up from center
				leaf_x := x + dx
				leaf_z := z + dz
				leaf_y := leaves_center_y + dy

				if leaf_x < 0 ||
				   leaf_x >= CHUNK_WIDTH ||
				   leaf_z < 0 ||
				   leaf_z >= CHUNK_WIDTH ||
				   leaf_y >= CHUNK_HEIGHT {
					continue
				}

				distance_sq := f32(dx * dx + dy * dy + dz * dz)

				if distance_sq > 6.5 do continue // roughly spherical
				if dx == 0 && dz == 0 && dy >= 0 do continue // don't replace trunk

				// add some randomness to leaf placement
				if distance_sq > 4.0 && rand.float32() > 0.6 do continue

				leaf_coords := Cube_Pos_Local{leaf_x, leaf_y, leaf_z}
				leaf_cube := &chunk.cubes[cube_index(leaf_coords)]

				// only place leaves in inactive spaces
				if leaf_cube.kind == .Air {
					chunk.cubes[cube_index(leaf_coords)] = Cube {
						kind  = .Oak_Leaves,
						biome = biome,
					}
				}
			}
		}
	}
}

should_generate_tree :: proc(biome: Biome, x, z: int, chunk_pos: Chunk_Pos) -> bool {
	world_x := chunk_pos.x * CHUNK_WIDTH + x
	world_z := chunk_pos.y * CHUNK_WIDTH + z

	// generate noise for tree placement
	tree_noise := rl.GenImagePerlinNoise(1, 1, i32(world_x), i32(world_z), 0.1)
	defer rl.UnloadImage(tree_noise)
	noise_val := f32(rl.GetImageColor(tree_noise, 0, 0).r) / 255.0

	// different biomes have different tree densities
	tree_chance: f32
	#partial switch biome {
	case .Temperate_Deciduous_Forest, .Temperate_Rain_Forest:
		tree_chance = 0.15
	case .Tropical_Rain_Forest, .Tropical_Seasonal_Forest:
		tree_chance = 0.12
	case .Taiga:
		tree_chance = 0.08
	case .Grassland:
		tree_chance = 0.02
	case .Shrubland:
		tree_chance = 0.03
	case:
		tree_chance = 0.0
	}

	return noise_val < tree_chance
}

generate_chunk :: proc(chunk: Chunk_Pos) -> (result: Chunk) {
	heightmap := generate_heightmap(chunk)
	biome_map := generate_biome_map(heightmap, generate_moisture_map(chunk))

	SEA_LEVEL :: 20

	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			height := heightmap[x][z]

			for y in 0 ..< height.in_cubes {
				cube_coords := Cube_Pos_Local{x, int(y), z}

				block_kind: Cube_Kind = .Dirt

				if height.in_cubes <= SEA_LEVEL + 3 {
					block_kind = .Sand
				}

				result.cubes[cube_index(cube_coords)] = Cube {
					kind  = block_kind,
					biome = biome_map[x][z],
				}
			}

			// fill with water up to sea level if terrain is below sea level
			if height.in_cubes < SEA_LEVEL {
				for y in height.in_cubes ..< SEA_LEVEL {
					if y < CHUNK_HEIGHT {
						cube_coords := Cube_Pos_Local{x, int(y), z}
						result.cubes[cube_index(cube_coords)] = Cube {
							kind  = .Water,
							biome = biome_map[x][z],
						}
					}
				}
			}
		}
	}

	// generate trees after terrain generation
	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			height := heightmap[x][z]
			biome := biome_map[x][z]

			// only place trees on land above sea level
			if height.in_cubes > SEA_LEVEL && should_generate_tree(biome, x, z, chunk) {
				surface_y := int(height.in_cubes) - 1 // surface is the top block
				max_tree_height := 8 // maximum tree height including leaves

				if can_place_tree(&result, x, z, surface_y, max_tree_height) {
					place_tree(&result, x, z, surface_y, .Oak, biome)
				}
			}
		}
	}

	// Convert top dirt blocks to grass (post-processing step)
	for x in 0 ..< CHUNK_WIDTH {
		for z in 0 ..< CHUNK_WIDTH {
			height := heightmap[x][z]

			if height.in_cubes > SEA_LEVEL {
				surface_y := int(height.in_cubes) - 1
				surface_coords := Cube_Pos_Local{x, surface_y, z}
				surface_cube := &result.cubes[cube_index(surface_coords)]

				// convert dirt to grass if it's the top block and has air above it
				if surface_cube.kind == .Dirt {
					// check if there's air above (or we're at the top of the chunk)
					has_air_above := true
					if surface_y + 1 < CHUNK_HEIGHT {
						above_coords := Cube_Pos_Local{x, surface_y + 1, z}
						above_cube := &result.cubes[cube_index(above_coords)]
						has_air_above = above_cube.kind == .Air
					}

					if has_air_above {
						surface_cube.kind = .Grass
					}
				}
			}
		}
	}

	return
}
