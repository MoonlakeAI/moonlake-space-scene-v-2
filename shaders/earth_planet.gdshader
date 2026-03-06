shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Textures
uniform sampler2D earth_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D clouds_texture : source_color, filter_linear_mipmap, repeat_enable;

// Cloud settings
uniform float cloud_intensity : hint_range(0.0, 2.0) = 1.2;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.002;

// Ocean settings
uniform vec3 ocean_color : source_color = vec3(0.05, 0.3, 0.6);
uniform float ocean_boost : hint_range(0.0, 2.0) = 1.3;

// Atmosphere settings
uniform vec3 atmosphere_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float atmosphere_intensity : hint_range(0.0, 3.0) = 1.5;
uniform float atmosphere_falloff : hint_range(0.5, 8.0) = 3.0;

// Lighting
uniform float ambient_boost : hint_range(0.0, 1.0) = 0.15;

varying vec3 world_normal;
varying vec3 world_position;

void vertex() {
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Sample base earth texture
	vec3 earth = texture(earth_texture, UV).rgb;
	
	// Animate clouds slightly (drifting effect)
	vec2 cloud_uv = UV + vec2(TIME * cloud_speed, 0.0);
	float clouds = texture(clouds_texture, cloud_uv).r * cloud_intensity;
	
	// Detect ocean areas (darker blue regions in texture)
	float ocean_mask = smoothstep(0.15, 0.35, earth.b - max(earth.r, earth.g) * 0.5);
	
	// Enhance ocean color
	vec3 enhanced_ocean = mix(earth, ocean_color, ocean_mask * ocean_boost * 0.5);
	
	// Blend clouds over land and ocean
	vec3 surface = mix(enhanced_ocean, vec3(1.0), clouds * 0.85);
	
	// Fresnel for atmosphere rim glow
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_position);
	float fresnel = pow(1.0 - max(dot(normalize(world_normal), view_dir), 0.0), atmosphere_falloff);
	
	// Add atmospheric rim glow
	vec3 atmosphere = atmosphere_color * fresnel * atmosphere_intensity;
	
	// Final color
	ALBEDO = surface + atmosphere * 0.3;
	
	// Slight emission for atmosphere glow
	EMISSION = atmosphere * 0.5;
	
	// Surface properties
	ROUGHNESS = mix(0.9, 0.4, ocean_mask); // Ocean is smoother
	METALLIC = 0.0;
	
	// Ambient occlusion boost for darker side
	AO = 1.0 - ambient_boost;
}
