shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Shape-first material: nearly black fill and one restrained silhouette rim.
// The legacy parameter names remain so MonsterCore can keep one shared material.
uniform vec4 base_color : source_color = vec4(0.009, 0.011, 0.016, 1.0);
uniform vec4 vein_color : source_color = vec4(0.009, 0.011, 0.016, 1.0);
uniform vec4 edge_glow_color : source_color = vec4(0.018, 0.42, 0.29, 1.0);
uniform float pulse_speed : hint_range(0.0, 8.0) = 1.1;
uniform float pulse_phase : hint_range(0.0, 6.283) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.5) = 0.065;
uniform float edge_emission_strength : hint_range(0.0, 5.0) = 0.62;

instance uniform float displacement_multiplier : hint_range(0.0, 1.5) = 1.0;

varying float slow_pulse;

void vertex() {
	vec3 p = VERTEX;
	float time = TIME * pulse_speed * 0.28 + pulse_phase;
	float broad_wave = sin(dot(p, vec3(1.7, -1.1, 1.35)) + time);
	broad_wave += sin(dot(p, vec3(-2.3, 1.5, 0.8)) - time * 0.71) * 0.48;
	broad_wave += sin(dot(p, vec3(3.1, 2.2, -1.8)) + time * 0.43) * 0.22;
	VERTEX += NORMAL * broad_wave * distortion_strength * displacement_multiplier;
	slow_pulse = 0.5 + 0.5 * sin(time * 0.63 + dot(p, vec3(0.31, 0.23, -0.27)));
}

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(0.14, 0.92, 1.0 - facing);
	float breathing_rim = 0.82 + slow_pulse * 0.18;
	ALBEDO = base_color.rgb + edge_glow_color.rgb * rim * 0.09;
	ROUGHNESS = mix(0.24, 0.52, slow_pulse);
	SPECULAR = 0.72;
	EMISSION = edge_glow_color.rgb * rim * edge_emission_strength * breathing_rim * 1.35;
	ALPHA = base_color.a;
}
