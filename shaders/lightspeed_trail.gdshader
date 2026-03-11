shader_type canvas_item;

// Gradient trail for lightspeed jump effect
// Creates a rectangle that fades from bright at ship (head) to transparent at tail (origin)
// Supports progressive fade_progress for natural smoke-like dissipation

uniform vec4 trail_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int direction : hint_range(-1, 1) = 1; // 1 = moving right, -1 = moving left
uniform float fade_progress : hint_range(0.0, 1.0) = 0.0; // 0 = no fade, 1 = fully faded from tail

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
	gradient = sqrt(gradient); // Softer falloff curve (more visible)
	
	// Progressive fade: tail fades out first as fade_progress increases
	// fade_progress=0: full trail visible
	// fade_progress=1: entire trail faded out
	float fade_threshold = fade_progress;
	float fade_factor = smoothstep(fade_threshold, fade_threshold + 0.3, 1.0 - tail_distance);
	
	// Vertical fade for softer edges
	float vertical_fade = 1.0 - abs(UV.y - 0.5) * 0.5;
	
	vec4 final_color = trail_color;
	final_color.a *= gradient * vertical_fade * fade_factor * opacity;
	
	COLOR = final_color;
}
