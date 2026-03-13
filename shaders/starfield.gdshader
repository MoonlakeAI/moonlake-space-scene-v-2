shader_type canvas_item;

// Space background with flickering stars - semi-transparent black overlay

uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float overlay_opacity : hint_range(0.0, 1.0) = 0.5;  // Black overlay opacity
uniform float star_density : hint_range(0.01, 0.2) = 0.08;
uniform float flicker_speed : hint_range(0.5, 5.0) = 1.5;
uniform vec2 screen_size = vec2(1920.0, 1080.0);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Multiple flicker patterns - full fade in/out
float get_flicker(float time, vec2 id, float base_speed) {
    float r = hash(id);
    float r2 = hash(id + 500.0);
    float r3 = hash(id + 1000.0);
    
    // Assign to different timing groups (0-5)
    int group = int(r * 6.0);
    
    // Each group has different base phase offset
    float group_phase = float(group) * 1.047; // ~60 degrees apart
    
    // Individual star variation within group
    float star_phase = r2 * 6.28;
    
    // Speed variation per star
    float speed_mult = 0.4 + r3 * 0.8; // 0.4 to 1.2x speed
    
    // Main wave for fade in/out
    float wave1 = sin(time * base_speed * speed_mult + group_phase + star_phase);
    
    // Secondary wave for variation
    float wave2 = sin(time * base_speed * speed_mult * 0.6 + star_phase * 1.5) * 0.3;
    
    // Combine and map to 0-1 range (full fade out to full brightness)
    float combined = (wave1 + wave2) * 0.5 + 0.5;
    
    // Apply power curve for sharper on/off feel
    return pow(clamp(combined, 0.0, 1.0), 1.5);
}

void fragment() {
    // Fix aspect ratio
    float aspect = screen_size.x / screen_size.y;
    vec2 uv = UV;
    uv.x *= aspect;
    
    // Start with black overlay
    vec3 col = vec3(0.0);
    float time = TIME;
    
    // Layer 1 - Large bright stars
    vec2 uv1 = uv * 35.0;
    vec2 id1 = floor(uv1);
    vec2 lv1 = fract(uv1) - 0.5;
    
    float r1 = hash(id1);
    if (r1 < star_density) {
        vec2 offset = vec2(hash(id1 + 10.0), hash(id1 + 20.0)) - 0.5;
        float d = length(lv1 - offset * 0.5);
        float flicker = get_flicker(time, id1, flicker_speed);
        float star = smoothstep(0.08, 0.0, d) * flicker;
        float color_rand = hash(id1 + 30.0);
        vec3 star_color = mix(vec3(1.0), vec3(1.0, 0.95, 0.7), color_rand * 0.6);
        col += star_color * star;
    }
    
    // Layer 2 - Medium stars
    vec2 uv2 = uv * 60.0;
    vec2 id2 = floor(uv2);
    vec2 lv2 = fract(uv2) - 0.5;
    
    float r2 = hash(id2 + 50.0);
    if (r2 < star_density * 1.3) {
        vec2 offset = vec2(hash(id2 + 60.0), hash(id2 + 70.0)) - 0.5;
        float d = length(lv2 - offset * 0.5);
        float flicker = get_flicker(time, id2 + 1000.0, flicker_speed * 0.85);
        float star = smoothstep(0.06, 0.0, d) * flicker * 0.85;
        float color_rand = hash(id2 + 80.0);
        vec3 star_color = mix(vec3(1.0), vec3(1.0, 0.9, 0.6), color_rand * 0.5);
        col += star_color * star;
    }
    
    // Layer 3 - Small stars
    vec2 uv3 = uv * 100.0;
    vec2 id3 = floor(uv3);
    vec2 lv3 = fract(uv3) - 0.5;
    
    float r3 = hash(id3 + 100.0);
    if (r3 < star_density * 1.5) {
        vec2 offset = vec2(hash(id3 + 110.0), hash(id3 + 120.0)) - 0.5;
        float d = length(lv3 - offset * 0.5);
        float flicker = get_flicker(time, id3 + 2000.0, flicker_speed * 0.7);
        float star = smoothstep(0.045, 0.0, d) * flicker * 0.7;
        vec3 star_color = vec3(1.0, 1.0, 0.95);
        col += star_color * star;
    }
    
    // Layer 4 - Tiny dense stars
    vec2 uv4 = uv * 180.0;
    vec2 id4 = floor(uv4);
    vec2 lv4 = fract(uv4) - 0.5;
    
    float r4 = hash(id4 + 200.0);
    if (r4 < star_density * 2.0) {
        vec2 offset = vec2(hash(id4 + 210.0), hash(id4 + 220.0)) - 0.5;
        float d = length(lv4 - offset * 0.5);
        float flicker = get_flicker(time, id4 + 3000.0, flicker_speed * 0.55);
        float star = smoothstep(0.03, 0.0, d) * flicker * 0.5;
        col += vec3(star);
    }
    
    // Layer 5 - Extra tiny background stars
    vec2 uv5 = uv * 300.0;
    vec2 id5 = floor(uv5);
    vec2 lv5 = fract(uv5) - 0.5;
    
    float r5 = hash(id5 + 300.0);
    if (r5 < star_density * 2.5) {
        vec2 offset = vec2(hash(id5 + 310.0), hash(id5 + 320.0)) - 0.5;
        float d = length(lv5 - offset * 0.5);
        float flicker = get_flicker(time, id5 + 4000.0, flicker_speed * 0.4);
        float star = smoothstep(0.025, 0.0, d) * flicker * 0.35;
        col += vec3(star);
    }
    
    // Black overlay with stars on top
    COLOR = vec4(col, overlay_opacity * opacity);
}
