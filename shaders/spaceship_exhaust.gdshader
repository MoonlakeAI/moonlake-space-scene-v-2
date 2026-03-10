shader_type canvas_item;
render_mode blend_add;

// =============================================================================
// SPACESHIP EXHAUST SHADER
// A highly customizable animated sci-fi engine exhaust effect
// =============================================================================

group_uniforms Color;
/// Core color of the exhaust (center glow)
uniform vec4 core_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
/// Mid color of the exhaust (transition zone)
uniform vec4 mid_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
/// Outer color of the exhaust (edge glow)
uniform vec4 outer_color : source_color = vec4(0.1, 0.3, 0.9, 1.0);
/// Color falloff power (higher = sharper color transitions)
uniform float color_falloff : hint_range(0.5, 5.0) = 1.5;

group_uniforms Shape;
/// Length of the exhaust trail (1.0 = full UV width)
uniform float exhaust_length : hint_range(0.1, 2.0) = 1.0;
/// Spread/width of the exhaust at the source (nozzle end)
uniform float spread_start : hint_range(0.05, 1.0) = 0.3;
/// Spread/width of the exhaust at the tail end
uniform float spread_end : hint_range(0.0, 1.0) = 0.6;
/// Shape taper curve (1.0 = linear, <1 = fast taper, >1 = slow taper)
uniform float taper_curve : hint_range(0.2, 3.0) = 1.2;
/// Core thickness (inner bright region)
uniform float core_thickness : hint_range(0.01, 0.5) = 0.15;
/// Edge softness (how soft/hard the edges are)
uniform float edge_softness : hint_range(0.01, 1.0) = 0.3;

group_uniforms Animation;
/// Animation speed multiplier
uniform float anim_speed : hint_range(0.0, 10.0) = 2.0;
/// Flicker intensity (brightness variation)
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.15;
/// Flicker speed
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;
/// Flow speed (how fast the exhaust flows outward)
uniform float flow_speed : hint_range(0.0, 5.0) = 1.5;

group_uniforms Turbulence;
/// Enable turbulence/noise effect
uniform bool enable_turbulence = true;
/// Turbulence intensity (displacement amount)
uniform float turbulence_intensity : hint_range(0.0, 0.5) = 0.08;
/// Turbulence scale (noise frequency)
uniform float turbulence_scale : hint_range(1.0, 20.0) = 6.0;
/// Turbulence flow speed
uniform float turbulence_speed : hint_range(0.0, 5.0) = 1.0;

group_uniforms Advanced;
/// Flip the exhaust direction horizontally
uniform bool flip_horizontal = true;
/// Overall intensity/brightness multiplier
uniform float intensity : hint_range(0.0, 3.0) = 1.0;
/// Fade out at the tail end
uniform float tail_fade : hint_range(0.0, 1.0) = 0.8;
/// Hotspot at nozzle (brighter near source)
uniform float hotspot_intensity : hint_range(0.0, 2.0) = 0.5;
/// Hotspot size
uniform float hotspot_size : hint_range(0.0, 0.5) = 0.15;

// Simplex-like noise functions
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	
	return mix(
		mix(dot(hash2(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
			dot(hash2(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
		mix(dot(hash2(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
			dot(hash2(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p, float time) {
	float value = 0.0;
	float amplitude = 0.5;
	vec2 shift = vec2(time * turbulence_speed, 0.0);
	
	for (int i = 0; i < 3; i++) {
		value += amplitude * noise(p + shift);
		p *= 2.0;
		amplitude *= 0.5;
		shift *= 1.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float time = TIME * anim_speed;
	
	// Flip UV horizontally if needed (so nozzle is on the right, near the ship)
	if (flip_horizontal) {
		uv.x = 1.0 - uv.x;
	}
	
	// X: 0 = nozzle (bright), 1 = tail end (fades)
	float along = uv.x / exhaust_length;
	float across = uv.y - 0.5; // -0.5 to 0.5
	
	// Apply turbulence displacement
	if (enable_turbulence) {
		vec2 noise_uv = uv * turbulence_scale;
		float turb = fbm(noise_uv, time);
		across += turb * turbulence_intensity * (1.0 - along * 0.5);
	}
	
	// Calculate spread at current position (tapers outward)
	float taper_t = pow(along, taper_curve);
	float current_spread = mix(spread_start, spread_end, taper_t);
	
	// Normalized distance from center line (0 = center, 1 = edge)
	float dist_from_center = abs(across) / (current_spread * 0.5);
	
	// Core region (bright center)
	float core_width = core_thickness / current_spread;
	float core_mask = 1.0 - smoothstep(0.0, core_width, dist_from_center);
	
	// Mid region
	float mid_mask = 1.0 - smoothstep(core_width, 0.6, dist_from_center);
	
	// Outer region with soft edge
	float outer_mask = 1.0 - smoothstep(1.0 - edge_softness, 1.0, dist_from_center);
	
	// Combine colors based on distance
	vec4 color = vec4(0.0);
	float t = pow(dist_from_center, color_falloff);
	
	if (dist_from_center < core_width) {
		color = mix(core_color, mid_color, dist_from_center / core_width);
	} else if (dist_from_center < 0.6) {
		float local_t = (dist_from_center - core_width) / (0.6 - core_width);
		color = mix(mid_color, outer_color, local_t);
	} else {
		color = outer_color;
	}
	
	// Apply outer mask for soft edges
	float alpha = outer_mask;
	
	// Tail fade (fades out toward the end)
	float tail_mask = 1.0 - smoothstep(1.0 - tail_fade, 1.0, along);
	alpha *= tail_mask;
	
	// Cut off if beyond exhaust length
	if (along > 1.0) {
		alpha = 0.0;
	}
	
	// Hotspot near nozzle
	float hotspot = (1.0 - smoothstep(0.0, hotspot_size, along)) * hotspot_intensity;
	color.rgb += vec3(hotspot);
	
	// Animated flicker
	float flicker = 1.0 + sin(time * flicker_speed + along * 10.0) * flicker_intensity;
	flicker *= 1.0 + sin(time * flicker_speed * 1.7 + along * 7.0) * flicker_intensity * 0.5;
	
	// Flow animation (subtle brightness waves)
	float flow_wave = sin((along - time * flow_speed * 0.1) * 15.0) * 0.1 + 0.9;
	
	// Combine all effects
	color.rgb *= flicker * flow_wave * intensity;
	color.a = alpha * intensity;
	
	// Ensure we don't exceed valid ranges
	color = clamp(color, 0.0, 1.0);
	
	COLOR = color;
}
