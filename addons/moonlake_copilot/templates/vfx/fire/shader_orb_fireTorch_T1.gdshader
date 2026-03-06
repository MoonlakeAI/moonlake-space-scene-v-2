shader_type spatial;
render_mode unshaded; // or alpha_hash

uniform float speed = 2.0;
uniform float wobble_strength = 0.2;
uniform sampler2D noise_texture;

uniform vec2 noise_scale_xy = vec2(1.000000, 1.000000);

uniform vec2 Scale_XY2 = vec2(1.000000, 1.000000);
uniform vec2 Speed_XY2;

uniform vec2 substract_Speed_XY;

uniform sampler2D Base_noise2 : source_color, repeat_enable;
uniform sampler2D Texture_add : source_color, hint_default_black, repeat_disable;
uniform sampler2D Texture_substract : source_color, repeat_enable;
uniform sampler2D Gradient_Color_1D2 : source_color, repeat_disable;
uniform float Color_Intensity2 = 1;
uniform float Fill : hint_range(0, 1) = 1;
uniform sampler2D tex_frg_58 : source_color;

uniform bool enable_vertex_movement = true;

void vertex() {
	if (enable_vertex_movement){
			

	    // Use polar coordinates for more natural circular wobble
	    float radius = length(vec2(VERTEX.x, VERTEX.z));
	    float angle = atan(VERTEX.z, VERTEX.x);

	    // Sample noise using polar coordinates
	    vec2 noise_uv = vec2(angle * 0.5 + TIME * speed, radius * 0.5);
	    vec4 noise = texture(noise_texture, noise_uv * noise_scale_xy);

	    // Height-based intensity
	    float height_effect = VERTEX.y * wobble_strength;

	    // Circular wobble - push vertices outward based on noise
	    float push_strength = (noise.r - 0.5) * height_effect;

	    VERTEX.x += push_strength * cos(angle);
	    VERTEX.z += push_strength * sin(angle);

	    // Add some vertical flicker
	    VERTEX.y += (noise.g - 0.5) * height_effect * 0.5;
	}
}
void fragment() {


	vec2 n_out39p0 = UV * Scale_XY2 ;

	vec2 n_out38p0 = Speed_XY2 * vec2(TIME) + n_out39p0;

	float n_out44p0 = texture(Base_noise2, n_out38p0).r + texture(Texture_add, UV).r;

	float n_out36p1 = texture(Texture_substract, UV + substract_Speed_XY * vec2(TIME) ).r;

	float n_out45p0 = n_out44p0 - n_out36p1;

	float n_out57p0 = clamp(n_out45p0, 0.0, 1.0);

	vec4 n_out48p0 = texture(Gradient_Color_1D2, vec2(n_out57p0));


	vec3 n_out49p0 = vec3(n_out48p0.xyz) * vec3(Color_Intensity2);

	float n_out58p1 = texture(tex_frg_58, UV).r;

	float n_out59p0 = smoothstep(Fill,0.0,n_out58p1);


	float n_out61p0 = n_out48p0.a * n_out59p0;

// Output:0
	ALBEDO = n_out49p0;
	ALPHA = n_out61p0;
	//ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
	//ALPHA_HASH_SCALE = alpha_threshold;

}