package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

Debug_Info :: struct {
	total_vertices:       int,
	opaque_vertices:      int,
	transparent_vertices: int,
	chunks_rendered:      int,
	triangles_rendered:   int,
}

get_debug_info :: proc() -> Debug_Info {
	info := Debug_Info{}

	for coords, &chunk in chunks {
		info.chunks_rendered += 1

		// count opaque vertices
		if chunk.opaque_model.meshes != nil && chunk.opaque_model.meshes[0] != {} {
			opaque_vertex_count := int(chunk.opaque_model.meshes[0].vertexCount)
			info.opaque_vertices += opaque_vertex_count
			info.triangles_rendered += opaque_vertex_count / 3
		}

		// count transparent vertices
		if chunk.transparent_model.meshes != nil && chunk.transparent_model.meshes[0] != {} {
			transparent_vertex_count := int(chunk.transparent_model.meshes[0].vertexCount)
			info.transparent_vertices += transparent_vertex_count
			info.triangles_rendered += transparent_vertex_count / 3
		}
	}

	info.total_vertices = info.opaque_vertices + info.transparent_vertices
	return info
}

render_debug_info :: proc(info: Debug_Info) {
	// set up debug text styling
	debug_font_size: f32 = 16
	debug_text_color := rl.WHITE
	debug_bg_color := rl.BLACK
	debug_bg_color.a = 128

	fps_text := fmt.aprintf("FPS: %d", rl.GetFPS())
	defer delete(fps_text)

	triangles_text := fmt.aprintf("Triangles: %d", info.triangles_rendered)
	defer delete(triangles_text)

	chunks_text := fmt.aprintf("Chunks: %d", info.chunks_rendered)
	defer delete(chunks_text)

	chunks_loading_text := fmt.aprintf(
		"Loading: %d, Unloading: %d",
		len(chunks_loading),
		len(chunks_unloading),
	)
	defer delete(chunks_loading_text)

	// player position
	player_chunk_x := int(player_pos.x) / CHUNK_WIDTH
	player_chunk_z := int(player_pos.z) / CHUNK_WIDTH
	player_pos_text := fmt.aprintf(
		"Player: (%.1f, %.1f, %.1f) Chunk: (%d, %d)",
		player_pos.x,
		player_pos.y,
		player_pos.z,
		player_chunk_x,
		player_chunk_z,
	)
	defer delete(player_pos_text)

	wireframe_status_text := fmt.aprintf(
		"Wireframe: %s (Press V to toggle)",
		wireframe_mode ? "ON" : "OFF",
	)
	defer delete(wireframe_status_text)

	game_mode_text := fmt.aprintf(
		"Mode: %s (Press G to toggle)",
		game_mode == .Flying ? "FLYING" : game_mode == .Walking ? "WALKING" : "SWIMMING",
	)
	defer delete(game_mode_text)

	// calculate text positions (top-left corner with padding)
	padding: f32 = 10
	line_height: f32 = 20
	current_y: f32 = padding

	text_lines := []string {
		fps_text,
		triangles_text,
		chunks_text,
		chunks_loading_text,
		player_pos_text,
		wireframe_status_text,
		game_mode_text,
	}

	max_width: f32 = 0
	for line in text_lines {
		width := rl.MeasureText(strings.clone_to_cstring(line), i32(debug_font_size))
		max_width = max(max_width, f32(width))
	}

	bg_rect := rl.Rectangle {
		padding - 5,
		padding - 5,
		max_width + 10,
		f32(len(text_lines)) * line_height + 10,
	}
	rl.DrawRectangleRounded(bg_rect, 0.1, 8, debug_bg_color)

	// draw text lines
	lines := []string {
		fps_text,
		triangles_text,
		chunks_text,
		chunks_loading_text,
		player_pos_text,
		wireframe_status_text,
		game_mode_text,
	}

	for line, i in lines {
		rl.DrawText(
			strings.clone_to_cstring(line),
			i32(padding),
			i32(current_y),
			i32(debug_font_size),
			debug_text_color,
		)
		current_y += line_height
	}
}
