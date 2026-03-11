shader_type canvas_item;

// Hangar frame shader - makes cyan colors breathe/flicker
// Supports launch mode where cyan switches to yellow with siren pulse
uniform float breath_speed : hint_range(0.5, 5.0) = 2.0;
uniform float breath_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float flicker_speed : hint_range(5.0, 30.0) = 15.0;
uniform float flicker_intensity : hint_range(0.0, 0.5) = 0.25;
uniform float cyan_hue_min : hint_range(0.0, 1.0) = 0.40;  // Wider cyan/teal range
uniform float cyan_hue_max : hint_range(0.0, 1.0) = 0.58;  // Include more blue-cyan
uniform float saturation_threshold : hint_range(0.0, 1.0) = 0.15;  // Lower threshold

// Launch mode uniforms
uniform float launch_progress : hint_range(0.0, 1.0) = 0.0;  // 0 = normal cyan, 1 = yellow launch mode
uniform float yellow_hue : hint_range(0.0, 1.0) = 0.12;  // Yellow hue target
uniform float siren_speed : hint_range(1.0, 10.0) = 0.5;  // Siren pulse frequency (cycles per second)
uniform float siren_min_brightness : hint_range(0.0, 1.0) = 0.8;  // Minimum brightness during pulse
uniform float siren_max_brightness : hint_range(1.0, 2.0) = 1.1;  // Maximum brightness during pulse

// Convert RGB to HSV
vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

// Convert HSV to RGB
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    vec3 hsv = rgb2hsv(tex_color.rgb);
    
    // Check if pixel is in cyan hue range (smooth transition at edges)
    float in_hue_range = smoothstep(cyan_hue_min - 0.03, cyan_hue_min, hsv.x) * 
                         (1.0 - smoothstep(cyan_hue_max, cyan_hue_max + 0.03, hsv.x));
    
    // Check for sufficient saturation (colored pixels, not gray)
    float is_saturated = smoothstep(saturation_threshold, saturation_threshold + 0.15, hsv.y);
    
    // Combined mask
    float is_cyan = in_hue_range * is_saturated;
    
    if (is_cyan > 0.01) {
        // Check if in launch mode (direct switch, no lerp)
        bool in_launch_mode = launch_progress > 0.5;
        
        if (in_launch_mode) {
            // LAUNCH MODE: Yellow with siren pulse
            // Switch hue directly to yellow
            hsv.x = yellow_hue;
            
            // Siren pulse - predictable sine wave oscillation
            float siren_phase = sin(TIME * siren_speed * TAU) * 0.5 + 0.5;
            float brightness_mult = mix(siren_min_brightness, siren_max_brightness, siren_phase);
            
            // Apply siren brightness
            hsv.z = clamp(hsv.z * brightness_mult, 0.0, 1.0);
            // Boost saturation for vivid yellow
            hsv.y = clamp(hsv.y * 1.2, 0.0, 1.0);
        } else {
            // NORMAL MODE: Cyan with breathing/flicker
            // Breathing effect (slow sine wave)
            float breath = sin(TIME * breath_speed) * 0.5 + 0.5;
            
            // Flicker effect (layered sine waves for organic feel)
            float flicker = sin(TIME * flicker_speed) * 0.5 + 0.5;
            flicker *= sin(TIME * flicker_speed * 0.7 + 1.0) * 0.5 + 0.5;
            
            // Combine effects with the cyan mask
            float intensity = is_cyan * (breath * breath_intensity + flicker * flicker_intensity);
            
            // Boost saturation and value (brightness) for glow effect
            hsv.y = clamp(hsv.y * (1.0 + intensity * 0.8), 0.0, 1.0);
            hsv.z = clamp(hsv.z * (1.0 + intensity * 0.6), 0.0, 1.0);
        }
        
        tex_color.rgb = hsv2rgb(hsv);
    }
    
    COLOR = tex_color;
}
