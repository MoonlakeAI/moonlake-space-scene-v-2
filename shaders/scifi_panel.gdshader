shader_type canvas_item;

// Sci-Fi HUD Panel Shader with animated corner brackets, scan lines, and glowing edges

uniform vec4 border_color : source_color = vec4(0.0, 0.7, 0.85, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 0.9, 1.0, 0.6);
uniform vec4 bg_color : source_color = vec4(0.0, 0.03, 0.06, 0.85);
uniform float border_width : hint_range(1.0, 5.0) = 1.5;
uniform float corner_size : hint_range(5.0, 40.0) = 18.0;
uniform float corner_thickness : hint_range(1.0, 4.0) = 2.0;
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.8;
uniform float glow_size : hint_range(0.0, 20.0) = 8.0;
uniform float scanline_opacity : hint_range(0.0, 0.3) = 0.08;
uniform float scanline_speed : hint_range(0.0, 50.0) = 15.0;
uniform float scanline_count : hint_range(10.0, 200.0) = 80.0;
uniform float pulse_speed : hint_range(0.0, 5.0) = 1.5;
uniform float pulse_intensity : hint_range(0.0, 0.5) = 0.15;
uniform float inner_line_offset : hint_range(0.0, 10.0) = 4.0;
uniform bool show_inner_frame = true;
uniform bool show_data_lines = true;
uniform float data_line_opacity : hint_range(0.0, 0.5) = 0.12;

// Pixel size in UV space
varying vec2 pixel_size;

void vertex() {
	pixel_size = TEXTURE_PIXEL_SIZE;
}

float rectangle_sdf(vec2 p, vec2 half_size) {
	vec2 d = abs(p) - half_size;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void fragment() {
	vec2 uv = UV;
	vec2 size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 pos = uv * size;
	vec2 center = size * 0.5;
	
	float time = TIME;
	
	// Pulsing effect
	float pulse = 1.0 + sin(time * pulse_speed) * pulse_intensity;
	
	// Base background
	vec4 color = bg_color;
	
	// Scanlines (horizontal, moving)
	float scanline = sin((uv.y * scanline_count + time * scanline_speed) * 3.14159) * 0.5 + 0.5;
	scanline = pow(scanline, 3.0);
	color.rgb -= vec3(scanline * scanline_opacity);
	
	// Add subtle vertical scan sweep
	float sweep = fract(time * 0.3);
	float sweep_line = smoothstep(sweep - 0.02, sweep, uv.y) - smoothstep(sweep, sweep + 0.02, uv.y);
	color.rgb += glow_color.rgb * sweep_line * 0.15;
	
	// Data lines (small horizontal dashes on the sides)
	if (show_data_lines) {
		float data_y = fract(uv.y * 20.0 + time * 0.5);
		float data_mask_left = step(uv.x, 0.03) * step(0.3, data_y) * step(data_y, 0.7);
		float data_mask_right = step(0.97, uv.x) * step(0.3, data_y) * step(data_y, 0.7);
		color.rgb += border_color.rgb * (data_mask_left + data_mask_right) * data_line_opacity;
	}
	
	// Calculate distances for borders
	float dist_to_edge_h = min(pos.x, size.x - pos.x);
	float dist_to_edge_v = min(pos.y, size.y - pos.y);
	float dist_to_edge = min(dist_to_edge_h, dist_to_edge_v);
	
	// Outer border glow
	float glow = smoothstep(glow_size, 0.0, dist_to_edge);
	color.rgb += glow_color.rgb * glow * glow_intensity * pulse * 0.5;
	
	// Main border
	float border = smoothstep(border_width + 0.5, border_width - 0.5, dist_to_edge);
	color.rgb = mix(color.rgb, border_color.rgb * pulse, border * border_color.a);
	
	// Inner frame line (offset from edge)
	if (show_inner_frame) {
		float inner_dist = abs(dist_to_edge - inner_line_offset);
		float inner_line = smoothstep(1.0, 0.0, inner_dist);
		color.rgb += border_color.rgb * inner_line * 0.3 * pulse;
	}
	
	// Corner brackets
	float corner_bracket = 0.0;
	
	// Top-left corner
	if (pos.x < corner_size && pos.y < corner_thickness) corner_bracket = 1.0;
	if (pos.x < corner_thickness && pos.y < corner_size) corner_bracket = 1.0;
	
	// Top-right corner
	if (pos.x > size.x - corner_size && pos.y < corner_thickness) corner_bracket = 1.0;
	if (pos.x > size.x - corner_thickness && pos.y < corner_size) corner_bracket = 1.0;
	
	// Bottom-left corner
	if (pos.x < corner_size && pos.y > size.y - corner_thickness) corner_bracket = 1.0;
	if (pos.x < corner_thickness && pos.y > size.y - corner_size) corner_bracket = 1.0;
	
	// Bottom-right corner
	if (pos.x > size.x - corner_size && pos.y > size.y - corner_thickness) corner_bracket = 1.0;
	if (pos.x > size.x - corner_thickness && pos.y > size.y - corner_size) corner_bracket = 1.0;
	
	// Apply corner brackets with glow
	color.rgb = mix(color.rgb, glow_color.rgb * pulse * 1.2, corner_bracket);
	
	// Corner glow effect
	float corner_glow = 0.0;
	vec2 corners[4] = vec2[4](
		vec2(0.0, 0.0),
		vec2(size.x, 0.0),
		vec2(0.0, size.y),
		vec2(size.x, size.y)
	);
	for (int i = 0; i < 4; i++) {
		float d = length(pos - corners[i]);
		corner_glow += smoothstep(corner_size * 1.5, 0.0, d) * 0.15;
	}
	color.rgb += glow_color.rgb * corner_glow * pulse;
	
	COLOR = color;
}
