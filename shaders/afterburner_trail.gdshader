shader_type canvas_item;

// Neon afterburner trail effect for ship acceleration
// Creates a glowing rectangular trail with hot core and soft blended edges

uniform vec4 core_color : source_color = vec4(1.0, 0.95, 0.8, 1.0); // Hot white-yellow core
uniform vec4 glow_color : source_color = vec4(0.0, 0.8, 1.0, 1.0);  // Cyan neon glow
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int direction : hint_range(-1, 1) = 1; // 1 = moving right, -1 = moving left
uniform float fade_progress : hint_range(0.0, 1.0) = 0.0; // 0 = no fade, 1 = fully faded
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float pulse_time : hint_range(0.0, 100.0) = 0.0; // For animated pulsing

void fragment() {
	// Determine position along trail where 0 = head (ship/newest), 1 = tail (origin/oldest)
	float tail_distance;
	if (direction > 0) {
		// Moving right: right edge is head (ship), left edge is tail
		tail_distance = 1.0 - UV.x;
	} else {
		// Moving left: left edge is head (ship), right edge is tail
		tail_distance = UV.x;
	}
	
	// Base gradient: bright at head, fades toward tail
	float gradient = 1.0 - tail_distance;
	gradient = pow(gradient, 0.5); // Softer falloff for more visible trail
	
	// Vertical distance from center (0 at center, 1 at edges)
	float vertical_dist = abs(UV.y - 0.5) * 2.0;
	
	// Soft gaussian-like falloff for vertical edges (e^(-x^2) shape)
	float soft_falloff = exp(-vertical_dist * vertical_dist * 3.0);
	
	// Core: narrow bright center with soft edges
	float core_width = 0.3;
	float core_factor = exp(-pow(vertical_dist / core_width, 2.0) * 2.0);
	core_factor *= gradient;
	
	// Outer glow: very soft, wide falloff for smooth blending
	float glow_factor = exp(-vertical_dist * vertical_dist * 1.5);
	glow_factor *= gradient;
	
	// Add subtle pulse animation
	float pulse = 1.0 + sin(pulse_time * 6.0 + UV.x * 8.0) * 0.15;
	
	// Progressive fade: tail fades out first
	float fade_factor = smoothstep(fade_progress, fade_progress + 0.3, 1.0 - tail_distance);
	
	// Mix core and glow colors
	vec3 final_rgb = mix(glow_color.rgb * glow_intensity, core_color.rgb * 1.2, core_factor);
	
	// Calculate alpha with soft vertical blend
	float alpha = (core_factor * 0.8 + glow_factor * 0.5) * soft_falloff * fade_factor * opacity * pulse;
	
	// Boost at head
	float head_boost = smoothstep(0.4, 0.0, tail_distance) * 0.3;
	final_rgb += vec3(head_boost);
	alpha = min(alpha + head_boost * soft_falloff * fade_factor * opacity, 1.0);
	
	COLOR = vec4(final_rgb, alpha);
}
