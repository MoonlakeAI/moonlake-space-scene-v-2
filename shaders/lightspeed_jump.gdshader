shader_type canvas_item;

// Lightspeed jump effect - creates glowing trail behind fast-moving ship

uniform float glow_intensity : hint_range(0.0, 3.0) = 0.0;
uniform float trail_length : hint_range(0.0, 20.0) = 0.0;
uniform float trail_opacity : hint_range(0.0, 1.0) = 0.0;
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 trail_color : source_color = vec4(0.4, 0.7, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform int direction : hint_range(-1, 1) = 1; // 1 = right, -1 = left

void fragment() {
	vec2 uv = UV;
	vec4 base_color = texture(TEXTURE, uv);
	
	// Create horizontal light trail by sampling behind the ship
	vec4 trail = vec4(0.0);
	if (trail_length > 0.0 && trail_opacity > 0.0) {
		int samples = 12;
		float trail_step = trail_length / float(samples);
		
		for (int i = 1; i <= samples; i++) {
			float offset = float(i) * trail_step * 0.05;
			vec2 sample_uv = uv;
			
			// Trail extends opposite to movement direction
			if (direction > 0) {
				sample_uv.x += offset;
			} else {
				sample_uv.x -= offset;
			}
			
			if (sample_uv.x >= 0.0 && sample_uv.x <= 1.0) {
				vec4 sample_col = texture(TEXTURE, sample_uv);
				// Fade trail with distance
				float fade = 1.0 - (float(i) / float(samples));
				fade = fade * fade; // Quadratic falloff
				trail += sample_col * fade;
			}
		}
		trail /= float(samples) * 0.5;
	}
	
	// Start with base color
	vec4 final_color = base_color;
	
	// Add colored trail
	vec3 trail_contribution = trail_color.rgb * trail.a * trail_opacity;
	final_color.rgb += trail_contribution;
	final_color.a = max(final_color.a, trail.a * trail_opacity * 0.8);
	
	// Add glow around the ship (blooms outward)
	if (glow_intensity > 0.0) {
		float glow_size = 0.02 * glow_intensity;
		vec4 glow = vec4(0.0);
		int glow_samples = 8;
		for (int i = 0; i < glow_samples; i++) {
			float angle = float(i) * 6.28318 / float(glow_samples);
			vec2 glow_offset = vec2(cos(angle), sin(angle)) * glow_size;
			glow += texture(TEXTURE, uv + glow_offset);
		}
		glow /= float(glow_samples);
		final_color.rgb += glow_color.rgb * glow.a * glow_intensity * 0.5;
	}
	
	// Add flash (white out effect at jump moment)
	final_color.rgb = mix(final_color.rgb, vec3(1.0), flash_intensity * final_color.a);
	
	// Boost brightness during effect
	final_color.rgb *= 1.0 + glow_intensity * 0.2;
	
	COLOR = final_color;
}
