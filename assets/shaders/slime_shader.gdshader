shader_type spatial;

render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.32, 0.055, 0.48, 1.0);
uniform vec4 edge_color : source_color = vec4(0.25, 1.0, 0.72, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float specular_level : hint_range(0.0, 1.0) = 0.9;
uniform float translucency : hint_range(0.0, 1.0) = 0.3;
uniform float subsurface_strength : hint_range(0.0, 2.0) = 0.55;
uniform vec4 subsurface_color : source_color = vec4(0.8, 0.12, 0.55, 1.0);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float edge_emission_strength : hint_range(0.0, 8.0) = 2.2;
uniform float displacement_amplitude : hint_range(0.0, 0.5) = 0.075;
uniform float displacement_frequency : hint_range(0.1, 12.0) = 3.2;
uniform float displacement_speed : hint_range(0.0, 8.0) = 1.8;
uniform float pulse_strength : hint_range(0.0, 0.15) = 0.025;
uniform float pulse_speed : hint_range(0.0, 6.0) = 1.15;
uniform float pulse_phase : hint_range(0.0, 6.283) = 0.0;
uniform float vein_strength : hint_range(0.0, 1.0) = 0.16;

void vertex() {
	vec3 p = VERTEX;
	float wave_a = sin(p.y * displacement_frequency + TIME * displacement_speed);
	float wave_b = sin((p.x + p.z) * displacement_frequency * 1.37 - TIME * displacement_speed * 0.73);
	float wave_c = cos(length(p.xz) * displacement_frequency * 1.8 + TIME * displacement_speed * 1.21);
	float pulse = (wave_a * 0.45 + wave_b * 0.35 + wave_c * 0.20);
	float breathing = sin(TIME * pulse_speed + p.z * 0.7 + pulse_phase) * pulse_strength;
	VERTEX += NORMAL * (pulse * displacement_amplitude + breathing);
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 view_direction = normalize(VIEW);
	float facing = clamp(dot(normal, view_direction), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);
	float backlight = pow(1.0 - facing, 2.0) * subsurface_strength;

	float veins = pow(abs(sin((VERTEX.x - VERTEX.z) * 8.0 + VERTEX.y * 3.0)), 18.0) * vein_strength;
	ALBEDO = mix(base_color.rgb * 0.72, base_color.rgb * 1.25 + subsurface_color.rgb * 0.08, fresnel);
	ALBEDO += subsurface_color.rgb * veins;
	ROUGHNESS = roughness;
	SPECULAR = specular_level;
	EMISSION = base_color.rgb * 0.08 + edge_color.rgb * fresnel * edge_emission_strength;
	EMISSION += subsurface_color.rgb * backlight;
	ALPHA = mix(1.0, base_color.a, translucency);
}
