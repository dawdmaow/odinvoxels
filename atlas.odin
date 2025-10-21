package main

import rl "vendor:raylib"

Texture_Id :: enum u8 {
	Grass_Block_Top  = 0,
	Grass_Block_Side = 1,
	Dirt             = 2,
	Water_Still      = 3,
	Sand             = 4,
	Oak_Log          = 5,
	Oak_Log_Top      = 6,
	Oak_Leaves       = 7,
}

TEXTURE_PATHS :: [Texture_Id]cstring {
	.Grass_Block_Top  = "assets/textures/block/grass_block_top.png",
	.Grass_Block_Side = "assets/textures/block/grass_block_side.png",
	.Dirt             = "assets/textures/block/dirt.png",
	.Water_Still      = "assets/textures/block/water_overlay.png",
	.Sand             = "assets/textures/block/sand.png",
	.Oak_Log          = "assets/textures/block/oak_log.png",
	.Oak_Log_Top      = "assets/textures/block/oak_log_top.png",
	.Oak_Leaves       = "assets/textures/block/oak_leaves.png",
}

PIXELS_PER_SIDE :: 16
TILES_PER_ROW :: 9999
ATLAS_WIDTH :: PIXELS_PER_SIDE * len(TEXTURE_PATHS)
ATLAS_HEIGHT :: PIXELS_PER_SIDE

atlas_texture: rl.Texture2D


atlas_rectangle :: proc(tex_id: Texture_Id) -> rl.Rectangle {
	return rl.Rectangle {
		f32(i32(tex_id) % TILES_PER_ROW * PIXELS_PER_SIDE),
		f32(i32(tex_id) / TILES_PER_ROW * PIXELS_PER_SIDE),
		f32(PIXELS_PER_SIDE),
		f32(PIXELS_PER_SIDE),
	}
}

create_atlas_texture :: proc() -> rl.Texture2D {
	atlas_image := rl.GenImageColor(ATLAS_WIDTH, ATLAS_HEIGHT, rl.PINK)
	defer rl.UnloadImage(atlas_image)

	for tex_path, tex_id in TEXTURE_PATHS {
		image := rl.LoadImage(tex_path)
		defer rl.UnloadImage(image)

		assert(rl.IsImageValid(image))
		assert(rl.IsImageReady(image))
		assert(image.width == PIXELS_PER_SIDE)
		assert(image.height == PIXELS_PER_SIDE)

		x := i32(tex_id) % TILES_PER_ROW * PIXELS_PER_SIDE
		y := i32(tex_id) / TILES_PER_ROW * PIXELS_PER_SIDE

		rl.ImageDraw(
			&atlas_image,
			image,
			rl.Rectangle{0, 0, PIXELS_PER_SIDE, PIXELS_PER_SIDE},
			rl.Rectangle{f32(x), f32(y), PIXELS_PER_SIDE, PIXELS_PER_SIDE},
			rl.WHITE,
		)
	}

	// rl.ExportImage(atlas_image, "atlas.png")

	return rl.LoadTextureFromImage(atlas_image)
}
