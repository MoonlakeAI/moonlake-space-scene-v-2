shader_type canvas_item;

// Plasma afterburner trail effect for ship acceleration
// Creates a sharp, energetic trail with hot core and electric edges

uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0); // White-hot core
uniform vec4 mid_color : source_color = vec4(1.0, 0.6, 0.1, 1.0);  // Orange mid layer
uniform vec4 glow_color : source_color = vec4(0.0, 0.7, 1.0, 1.0); // Cyan outer glow
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform int direction : hint_range(-1, 1) = 1; // 1 = moving right, -1 = moving left
uniform float fade_progress : hint_range(0.0, 1.0) = 0.0;
uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform float pulse_time : hint_range(0.0, 100.0) = 0.0;

void fragment() {
	// Determine position along trail: 0 = head (ship), 1 = tail (origin)
	float tail_distance;
	if (direction > 0) {
		tail_distance = 1.0 - UV.x;
	} else {
		tail_distance = UV.x;
	}
	
	// Sharp gradient with long tail
	float gradient = 1.0 - tail_distance;
	gradient = pow(gradient, 0.6);
	
	// Vertical distance from center (0 at center, 1 at edges)
	float vertical_dist = abs(UV.y - 0.5) * 2.0;
	
	// Tapered width: trail gets narrower toward the tail (plasma stream shape)
	float taper = mix(1.0, 0.3, tail_distance);
	float tapered_dist = vertical_dist / taper;
	
	// Sharp core - tight bright center
	float core_factor = 1.0 - smoothstep(0.0, 0.15, tapered_dist);
	core_factor *= gradient;
	
	// Mid layer - orange transition
	float mid_factor = 1.0 - smoothstep(0.1, 0.4, tapered_dist);
	mid_factor *= gradient;
	
	// Outer glow - sharp cutoff with slight feather
	float glow_factor = 1.0 - smoothstep(0.3, 0.8, tapered_dist);
	glow_factor *= gradient;
	
	// Electric flickering at edges
	float flicker = sin(pulse_time * 15.0 + UV.x * 20.0 + UV.y * 10.0) * 0.5 + 0.5;
	float edge_flicker = smoothstep(0.2, 0.6, tapered_dist) * (1.0 - smoothstep(0.6, 1.0, tapered_dist));
	edge_flicker *= flicker * 0.4 * gradient;
	
	// Subtle pulse
	float pulse = 1.0 + sin(pulse_time * 8.0 + UV.x * 5.0) * 0.1;
	
	// Progressive fade from tail
	float fade_factor = smoothstep(fade_progress, fade_progress + 0.2, 1.0 - tail_distance);
	
	// Layer colors: white core -> orange mid -> cyan glow
	vec3 final_rgb = glow_color.rgb * glow_intensity * glow_factor;
	final_rgb = mix(final_rgb, mid_color.rgb * 1.8, mid_factor);
	final_rgb = mix(final_rgb, core_color.rgb * 2.0, core_factor);
	
	// Add electric edge effect
	final_rgb += glow_color.rgb * edge_flicker * glow_intensity;
	
	// Sharp alpha
	float alpha = max(max(core_factor, mid_factor * 0.9), glow_factor * 0.6);
	alpha += edge_flicker * 0.5;
	alpha *= fade_factor * opacity * pulse;
	
	// Bright head flare
	float head_boost = smoothstep(0.3, 0.0, tail_distance) * (1.0 - smoothstep(0.0, 0.2, tapered_dist));
	final_rgb += vec3(1.0, 0.9, 0.8) * head_boost * 0.8;
	alpha = min(alpha + head_boost * 0.5, 1.0);
	
	// Hard cutoff at edges for clean plasma look
	alpha *= step(tapered_dist, 1.0);
	
	COLOR = vec4(final_rgb, alpha);
}
