shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

// Cloud layer with varying opacity and movement
uniform sampler2D clouds_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float cloud_opacity : hint_range(0.0, 1.0) = 0.6;
uniform float cloud_speed : hint_range(0.0, 0.1) = 0.008;
uniform float opacity_variation : hint_range(0.0, 1.0) = 0.4;
uniform vec3 cloud_tint : source_color = vec3(1.0, 1.0, 1.0);

// Noise for opacity variation
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
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

float fbm(vec2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * noise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

void fragment() {
    // Animate cloud UV for rotation effect
    vec2 cloud_uv = UV + vec2(TIME * cloud_speed, 0.0);
    
    // Sample cloud texture
    float clouds = texture(clouds_texture, cloud_uv).r;
    
    // Add varying opacity using noise
    float variation = fbm(UV * 5.0 + TIME * 0.02);
    float opacity_mod = 1.0 - (variation * opacity_variation);
    
    // Create wispy cloud effect
    clouds = smoothstep(0.2, 0.8, clouds);
    
    // Final opacity
    float final_alpha = clouds * cloud_opacity * opacity_mod;
    
    // Soft edges near terminator (day/night boundary feel)
    final_alpha *= smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x);
    
    ALBEDO = cloud_tint;
    ALPHA = final_alpha;
}
