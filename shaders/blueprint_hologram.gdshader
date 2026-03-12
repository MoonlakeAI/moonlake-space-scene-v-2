shader_type canvas_item;

// Blueprint hologram shader - ship under construction/modification
// Creates a holographic blueprint look with chunks materializing

uniform vec4 holo_color : source_color = vec4(0.1, 0.6, 0.9, 1.0);
uniform vec4 grid_color : source_color = vec4(0.2, 0.8, 1.0, 0.3);
uniform float chunk_scale : hint_range(1.0, 1000.0) = 550.0;
uniform float chunk_threshold : hint_range(0.0, 1.0) = 0;
uniform float chunk_speed : hint_range(0.1, 2.0) = 0.4;
uniform float scanline_density : hint_range(20.0, 150.0) = 20.0;
uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.20;
uniform float grid_density : hint_range(10.0, 100.0) = 200.0;
uniform float grid_thickness : hint_range(0.01, 0.1) = 0.2;
uniform float edge_glow : hint_range(0.0, 3.0) = 1.5;
uniform float alpha_base : hint_range(0.3, 1.0) = 0.8;

// Noise functions for chunk effect
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal noise for more organic chunks
float fbm(vec2 p, float time_offset) {
    float value = 0.0;
    float amplitude = 0.5;
    vec2 offset = vec2(time_offset * 0.3, time_offset * 0.2);
    
    for (int i = 0; i < 3; i++) {
        value += amplitude * noise(p + offset);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    vec2 uv = UV;
    float time = TIME;
    
    // Sample original texture
    vec4 tex_color = texture(TEXTURE, uv);
    
    // Process only if not fully transparent
    if (tex_color.a >= 0.01) {
        // === CHUNK EFFECT ===
        // Create animated noise for chunk visibility
        vec2 chunk_uv = uv * chunk_scale;
        float chunk_noise = fbm(chunk_uv, time * chunk_speed);
        
        // Add secondary layer for more interesting pattern
        float chunk_noise2 = fbm(chunk_uv * 0.7 + vec2(50.0), time * chunk_speed * 0.6 + 10.0);
        chunk_noise = mix(chunk_noise, chunk_noise2, 0.4);
        
        // Left-to-right sweep: adjust threshold based on x position
        // When threshold=1, all is hologram. When threshold=0, all is solid.
        // Left side (uv.x=0) materializes first, right side (uv.x=1) last
        float sweep_offset = uv.x * 0.5;
        float adjusted_threshold = chunk_threshold * 1.5 - sweep_offset;
        adjusted_threshold = clamp(adjusted_threshold, 0.0, 1.0);
        
        // Determine if this chunk is visible (hologram) based on adjusted threshold
        float chunk_visible = smoothstep(adjusted_threshold - 0.1, adjusted_threshold + 0.1, chunk_noise);
        
        // Edge detection for chunk borders (glowing edges where chunks appear)
        float chunk_edge = abs(chunk_noise - adjusted_threshold);
        chunk_edge = 1.0 - smoothstep(0.0, 0.15, chunk_edge);
        
        // === SCANLINES (left to right) ===
        float scanline = sin(uv.x * scanline_density + time * 1.5) * 0.5 + 0.5;
        scanline = 1.0 - (scanline * scanline * scanline_opacity);
        
        // Vertical scan beam (sweeps left to right)
        float scan_beam = sin(time * 0.8) * 0.5 + 0.5;
        float beam_pos = abs(uv.x - scan_beam);
        float beam = 1.0 - smoothstep(0.0, 0.05, beam_pos);
        
        // === GRID OVERLAY ===
        vec2 grid_uv = uv * grid_density;
        vec2 grid_fract = fract(grid_uv);
        float grid_x = smoothstep(grid_thickness, 0.0, grid_fract.x) + smoothstep(1.0 - grid_thickness, 1.0, grid_fract.x);
        float grid_y = smoothstep(grid_thickness, 0.0, grid_fract.y) + smoothstep(1.0 - grid_thickness, 1.0, grid_fract.y);
        float grid = max(grid_x, grid_y) * tex_color.a * 0.15;
        
        // === EDGE GLOW ===
        // Sample neighbors for edge detection
        float pixel_size = 0.003;
        float a_left = texture(TEXTURE, uv + vec2(-pixel_size, 0.0)).a;
        float a_right = texture(TEXTURE, uv + vec2(pixel_size, 0.0)).a;
        float a_up = texture(TEXTURE, uv + vec2(0.0, -pixel_size)).a;
        float a_down = texture(TEXTURE, uv + vec2(0.0, pixel_size)).a;
        float edge = abs(tex_color.a - a_left) + abs(tex_color.a - a_right) + 
                     abs(tex_color.a - a_up) + abs(tex_color.a - a_down);
        edge = clamp(edge * 2.0, 0.0, 1.0);
        
        // === COMBINE EFFECTS ===
        // Base holographic color (tint the original or use pure holo)
        vec3 base_holo = mix(tex_color.rgb * holo_color.rgb * 1.5, holo_color.rgb, 0.6);
        
        // Apply scanlines
        base_holo *= scanline;
        
        // Add scan beam highlight
        base_holo += holo_color.rgb * beam * 0.4;
        
        // Add grid
        base_holo += grid_color.rgb * grid;
        
        // Add edge glow
        base_holo += holo_color.rgb * edge * edge_glow;
        
        // Add chunk edge glow (bright edges where chunks materialize)
        base_holo += vec3(0.5, 0.9, 1.0) * chunk_edge * 1.5;
        
        // === FINAL OUTPUT ===
        // Blend between original texture (holes) and blueprint effect
        // Where chunk_visible is LOW (holes), show original texture
        // Where chunk_visible is HIGH, show blueprint hologram
        vec3 final_color = mix(tex_color.rgb, base_holo, chunk_visible);
        
        // Alpha: original texture in holes, blueprint alpha elsewhere
        float holo_alpha = tex_color.a * alpha_base;
        holo_alpha += chunk_edge * 0.3 + edge * 0.2;
        float final_alpha = mix(tex_color.a, holo_alpha, chunk_visible);
        
        // Always show chunk edges even in "hole" areas for that materializing effect
        final_color = mix(final_color, vec3(0.5, 0.9, 1.0), chunk_edge * 0.8);
        final_alpha = max(final_alpha, chunk_edge * tex_color.a);
        
        COLOR = vec4(final_color, clamp(final_alpha, 0.0, 1.0));
    } else {
        // Fully transparent pixel
        COLOR = vec4(0.0);
    }
}
