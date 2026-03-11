shader_type canvas_item;

// Simple gradient trail for lightspeed jump effect
// Creates a rectangle that fades from bright at origin to transparent at end

uniform vec4 trail_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int direction : hint_range(-1, 1) = 1; // 1 = right (fade to right), -1 = left (fade to left)

void fragment() {
	// Gradient from full opacity at start to zero at end
	float gradient;
	if (direction > 0) {
		// Moving right: bright on left, fades to right
		gradient = 1.0 - UV.x;
	} else {
		// Moving left: bright on right, fades to left
		gradient = UV.x;
	}
	
	// Smooth falloff with slight curve
	gradient = gradient * gradient;
	
	// Also fade slightly at vertical edges for softer look
	float vertical_fade = 1.0 - abs(UV.y - 0.5) * 0.5;
	
	vec4 final_color = trail_color;
	final_color.a *= gradient * vertical_fade * opacity;
	
	COLOR = final_color;
}
