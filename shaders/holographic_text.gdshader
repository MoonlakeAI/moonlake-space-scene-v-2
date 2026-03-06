shader_type canvas_item;

// Holographic flickering text shader

uniform vec4 holo_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float flicker_speed : hint_range(1.0, 20.0) = 8.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_density : hint_range(10.0, 200.0) = 80.0;
uniform float scanline_opacity : hint_range(0.0, 1.0) = 0.15;
uniform float glow_strength : hint_range(0.0, 2.0) = 0.5;
uniform float distortion_amount : hint_range(0.0, 0.02) = 0.003;
uniform float glitch_chance : hint_range(0.0, 1.0) = 0.05;

// Random function
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
    vec2 uv = UV;
    float time = TIME;
    
    // Random glitch offset
    float glitch = step(1.0 - glitch_chance, random(vec2(floor(time * 10.0), 0.0)));
    if (glitch > 0.5) {
        uv.x += (random(vec2(time)) - 0.5) * distortion_amount * 10.0;
    }
    
    // Subtle horizontal distortion
    uv.x += sin(uv.y * 50.0 + time * 5.0) * distortion_amount;
    
    // Sample the texture
    vec4 tex_color = texture(TEXTURE, uv);
    
    // Base holographic color tint
    vec3 holo = holo_color.rgb;
    
    // Flickering effect - multiple frequencies for realism
    float flicker1 = sin(time * flicker_speed) * 0.5 + 0.5;
    float flicker2 = sin(time * flicker_speed * 2.3 + 1.5) * 0.5 + 0.5;
    float flicker3 = sin(time * flicker_speed * 0.7 + 3.0) * 0.5 + 0.5;
    float combined_flicker = (flicker1 + flicker2 + flicker3) / 3.0;
    
    // Random micro-flickers
    float micro_flicker = random(vec2(floor(time * 30.0), uv.y * 10.0));
    micro_flicker = smoothstep(0.3, 0.7, micro_flicker);
    
    float final_flicker = mix(1.0, combined_flicker * micro_flicker, flicker_intensity);
    
    // Scanlines
    float scanline = sin(uv.y * scanline_density + time * 2.0) * 0.5 + 0.5;
    scanline = 1.0 - (scanline * scanline_opacity);
    
    // Color separation (chromatic aberration) for holographic look
    float r = texture(TEXTURE, uv + vec2(0.002, 0.0)).r;
    float g = texture(TEXTURE, uv).g;
    float b = texture(TEXTURE, uv - vec2(0.002, 0.0)).b;
    vec3 separated = vec3(r, g, b);
    
    // Combine effects
    vec3 final_color = separated * holo * final_flicker * scanline;
    
    // Add glow
    final_color += holo * tex_color.a * glow_strength * final_flicker * 0.3;
    
    // Edge glow effect
    float edge = tex_color.a * (1.0 - tex_color.a) * 4.0;
    final_color += holo * edge * glow_strength;
    
    // Output with alpha
    COLOR = vec4(final_color, tex_color.a * final_flicker * 0.9 + 0.1);
}
