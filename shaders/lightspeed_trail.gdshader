shader_type canvas_item;

// Gradient trail for lightspeed jump effect
// Creates a high-quality trail with bright core and soft transparent glow
// Supports progressive fade_progress for natural smoke-like dissipation

uniform vec4 trail_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int direction : hint_range(-1, 1) = 1; // 1 = moving right, -1 = moving left
uniform float fade_progress : hint_range(0.0, 1.0) = 0.0; // 0 = no fade, 1 = fully faded from tail
uniform float core_intensity : hint_range(0.0, 2.0) = 1.2;
uniform float glow_softness : hint_range(0.1, 2.0) = 0.6;

void fragment() {
	// Determine position along trail where 0 = head (ship/newest), 1 = tail (origin/oldest)
	float tail_distance;
	if (direction > 0) {
		// Moving right: right edge is head (ship), left edge is tail (origin)
		tail_distance = 1.0 - UV.x;
	} else {
		// Moving left: left edge is head (ship), right edge is tail (origin)
		tail_distance = UV.x;
	}
	
	// Base gradient: bright at head (tail_distance=0), fades toward tail (tail_distance=1)
	float gradient = 1.0 - tail_distance;
	gradient = pow(gradient, 0.7); // Softer falloff curve
	
	// Progressive fade: tail fades out first as fade_progress increases
	float fade_threshold = fade_progress;
	float fade_factor = smoothstep(fade_threshold, fade_threshold + 0.25, 1.0 - tail_distance);
	
	// Vertical position from center (0 = center, 1 = edge)
	float vertical_dist = abs(UV.y - 0.5) * 2.0;
	
	// Multi-layered vertical profile for high quality look:
	// 1. Bright narrow core
	float core = exp(-vertical_dist * vertical_dist * 12.0);
	// 2. Medium glow layer
	float mid_glow = exp(-vertical_dist * vertical_dist * 4.0);
	// 3. Soft outer glow
	float outer_glow = exp(-vertical_dist * vertical_dist * 1.5 * glow_softness);
	
	// Combine layers with different intensities
	float core_layer = core * core_intensity;
	float glow_layer = mix(outer_glow, mid_glow, 0.5) * 0.4;
	
	// Blend core (white-ish) with trail color for glow
	vec3 core_rgb = core_color.rgb * core_layer;
	vec3 glow_rgb = trail_color.rgb * glow_layer;
	vec3 combined_rgb = core_rgb + glow_rgb;
	
	// Alpha: core is more opaque, glow is more transparent
	float combined_alpha = (core * 0.7 + glow_layer * 0.5) * gradient * fade_factor * opacity;
	
	// Add subtle head glow boost (brighter at the ship end)
	float head_boost = smoothstep(0.7, 1.0, gradient) * 0.3;
	combined_alpha += head_boost * core * fade_factor * opacity;
	
	// Clamp and apply transparency
	combined_alpha = clamp(combined_alpha, 0.0, 0.85);
	
	COLOR = vec4(combined_rgb, combined_alpha);
}
