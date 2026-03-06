shader_type canvas_item;

// Animated Gradient Text Shader
//
// Creates a flowing 3-color gradient effect through text
// Inspired by Google Gemini/NotebookLM loading animations
// Modern alternative to traditional shimmer effects

uniform vec4 gradient_color_1 : source_color = vec4(0.3, 0.5, 0.9, 1.0); // Blue
uniform vec4 gradient_color_2 : source_color = vec4(0.6, 0.3, 0.9, 1.0); // Purple
uniform vec4 gradient_color_3 : source_color = vec4(0.9, 0.3, 0.6, 1.0); // Pink
uniform float animation_speed = 0.4; // Complete cycle every 2.5 seconds
uniform float gradient_width = 3.0; // 300% width for smooth movement

void fragment() {
	// Sample the original texture (text rendering)
	vec4 tex = texture(TEXTURE, UV);

	// Only apply gradient where text exists (non-transparent pixels)
	if (tex.a >= 0.01) {
		// Calculate animated gradient position
		// Extends from -1.0 to 2.0 to allow gradient to enter/exit smoothly
		float time_mod = mod(TIME * animation_speed, 1.0);
		float gradient_pos = time_mod * gradient_width - 1.0;

		// Map UV.x to gradient position (0.0 to 1.0)
		float sample_pos = UV.x - gradient_pos;

		// Normalize to 0.0-1.0 range for gradient sampling
		sample_pos = clamp(sample_pos, 0.0, 1.0);

		// Create 3-color gradient with smooth transitions
		vec3 final_color;
		if (sample_pos < 0.5) {
			// First half: blend gradient_1 → gradient_2
			float t = sample_pos * 2.0; // Map 0.0-0.5 to 0.0-1.0
			final_color = mix(gradient_color_1.rgb, gradient_color_2.rgb, t);
		} else {
			// Second half: blend gradient_2 → gradient_3
			float t = (sample_pos - 0.5) * 2.0; // Map 0.5-1.0 to 0.0-1.0
			final_color = mix(gradient_color_2.rgb, gradient_color_3.rgb, t);
		}

		// Apply gradient to text, preserving original alpha
		COLOR = vec4(final_color, tex.a);
	} else {
		// Transparent area
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
