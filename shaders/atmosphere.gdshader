shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_front, unshaded;

// Atmosphere appearance
uniform vec3 inner_color : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 outer_color : source_color = vec3(0.1, 0.4, 0.9);
uniform float atmosphere_density : hint_range(0.0, 5.0) = 2.0;
uniform float falloff : hint_range(0.5, 10.0) = 4.0;
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.2;

varying vec3 world_normal;
varying vec3 world_position;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Calculate view direction
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
	vec3 normal = normalize(world_normal);
	
	// Fresnel effect - stronger at edges
	float fresnel = pow(1.0 - abs(dot(normal, view_dir)), falloff);
	
	// Gradient from inner to outer color based on fresnel
	vec3 atmo_color = mix(inner_color, outer_color, fresnel);
	
	// Apply density and intensity
	float alpha = fresnel * atmosphere_density * glow_intensity;
	alpha = clamp(alpha, 0.0, 1.0);
	
	// Output
	ALBEDO = atmo_color * alpha;
	ALPHA = alpha * 0.6;
}
