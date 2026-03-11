shader_type canvas_item;

uniform vec4 center_color : source_color = vec4(0.0, 0.05, 0.1, 0.8);
uniform float fade_strength : hint_range(0.5, 3.0) = 1.5;

void fragment() {
	// Calculate distance from center (0.5, 0.5) normalized
	vec2 center = vec2(0.5, 0.5);
	vec2 uv = UV - center;
	
	// Elliptical distance for better horizontal fade
	float dist = length(vec2(uv.x * 1.4, uv.y * 1.5));
	
	// Fade from center to edges
	float alpha = center_color.a * (1.0 - smoothstep(0.0, 0.5, dist * fade_strength));
	
	COLOR = vec4(center_color.rgb, alpha);
}
