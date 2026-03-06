shader_type canvas_item;

// Dark Space Background with Simple Flickering Stars

uniform vec4 background_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);  // Transparent to show image behind
uniform float star_density : hint_range(0.001, 0.02) = 0.008;
uniform float star_brightness : hint_range(0.3, 2.0) = 1.0;
uniform float star_flicker_speed : hint_range(1.0, 15.0) = 6.0;
uniform float star_min_size : hint_range(0.001, 0.01) = 0.003;
uniform float star_max_size : hint_range(0.005, 0.02) = 0.008;

// Random functions
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

vec2 hash2(vec2 p) {
    return fract(sin(vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    float time = TIME;
    
    // Start with transparent - image shows through
    vec3 color = vec3(0.0);
    float alpha = 0.0;
    
    // Simple flickering star dots - multiple layers for depth
    for (int layer = 0; layer < 3; layer++) {
        float layer_scale = 150.0 + float(layer) * 100.0;
        vec2 star_uv = uv * layer_scale;
        vec2 grid = floor(star_uv);
        vec2 local = fract(star_uv) - 0.5;
        
        float rand = hash(grid + float(layer) * 73.156);
        
        // Check if this cell has a star
        if (rand < star_density) {
            // Star position within cell
            vec2 star_pos = hash2(grid + float(layer) * 73.156) - 0.5;
            float dist = length(local - star_pos * 0.8);
            
            // Star size varies
            float size = mix(star_min_size, star_max_size, hash(grid + vec2(float(layer), 1.0)));
            
            // Flickering - different speed and phase per star
            float flicker_phase = rand * 6.28318;
            float flicker_freq = star_flicker_speed * (0.5 + rand * 0.8);
            float flicker = sin(time * flicker_freq + flicker_phase);
            flicker = flicker * 0.4 + 0.6; // Range 0.2 to 1.0
            
            // Random twinkle bursts
            float burst_phase = hash(grid + vec2(float(layer), 2.0)) * 100.0;
            float burst = smoothstep(0.92, 1.0, sin(time * 1.5 + burst_phase)) * 1.5;
            
            // Star intensity
            float star_alpha = smoothstep(size, 0.0, dist);
            star_alpha *= flicker * star_brightness;
            star_alpha += smoothstep(size * 1.5, 0.0, dist) * burst;
            
            // Slight color variation (white to light blue)
            vec3 star_color = mix(vec3(1.0), vec3(0.8, 0.9, 1.0), rand * 0.3);
            
            // Dimmer stars in back layers
            star_alpha *= 1.0 - float(layer) * 0.25;
            
            color += star_color * star_alpha;
            alpha = max(alpha, star_alpha);
        }
    }
    
    COLOR = vec4(color, alpha);
}
