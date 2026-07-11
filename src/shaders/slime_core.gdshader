shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// One synchronized material is shared by the mantle, flesh bridges, and legs.
uniform vec4 base_color : source_color = vec4(0.12, 0.012, 0.025, 1.0);
uniform vec4 vein_color : source_color = vec4(0.34, 0.006, 0.012, 1.0);
uniform vec4 edge_glow_color : source_color = vec4(0.62, 0.006, 0.025, 1.0);
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.15;
uniform float pulse_phase : hint_range(0.0, 6.283) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.5) = 0.22;
uniform float distortion_scale : hint_range(0.1, 12.0) = 2.8;
uniform float edge_emission_strength : hint_range(0.0, 5.0) = 1.2;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.035;
uniform float tissue_roughness : hint_range(0.0, 1.0) = 0.16;

// Thin procedural tubes need less absolute displacement than the large mantle.
// Keeping this per-instance lets every surface still share the same material/time.
instance uniform float displacement_multiplier : hint_range(0.0, 1.5) = 1.0;

varying vec3 flesh_position;
varying float flesh_noise;

// Pseudo-random 3D hash, smoothed into coherent value noise below. Using the
// hash directly on floor() would visibly pop from one random shape to the next.
float hash3D(vec3 p) {
	p = fract(p * vec3(443.8975, 397.2973, 491.1871));
	p += dot(p.xyz, p.yzx + 19.19);
	return fract(p.x * p.y * p.z);
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 blend = fract(p);
	blend = blend * blend * (3.0 - 2.0 * blend);

	float n000 = hash3D(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash3D(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash3D(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash3D(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash3D(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash3D(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash3D(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash3D(cell + vec3(1.0, 1.0, 1.0));

	float lower = mix(mix(n000, n100, blend.x), mix(n010, n110, blend.x), blend.y);
	float upper = mix(mix(n001, n101, blend.x), mix(n011, n111, blend.x), blend.y);
	return mix(lower, upper, blend.z);
}

float organic_noise(vec3 p) {
	float result = value_noise(p) * 0.58;
	result += value_noise(p * 2.03 + vec3(7.1, 2.4, 5.8)) * 0.29;
	result += value_noise(p * 4.17 + vec3(1.7, 9.2, 3.6)) * 0.13;
	return result;
}

float displacement_field(vec3 p) {
	vec3 crawl = vec3(TIME * 0.17, -TIME * 0.11, TIME * 0.13) * pulse_speed;
	float lumps = organic_noise(p * distortion_scale + crawl) * 2.0 - 1.0;
	float wave = sin(TIME * pulse_speed + pulse_phase + p.y * 2.7 + p.x * 1.9 - p.z * 1.3);
	float cross_wave = sin(TIME * pulse_speed * 0.61 - pulse_phase + dot(p, vec3(-1.2, 0.8, 1.55)));
	return lumps * 0.72 + wave * 0.2 + cross_wave * 0.08;
}

void vertex() {
	vec3 local_pos = VERTEX;
	float deformation = displacement_field(local_pos);
	float pulse = sin(TIME * pulse_speed * 0.48 + pulse_phase) * 0.055;
	float displacement = (deformation * distortion_strength + pulse) * displacement_multiplier;

	// Aggressive normal displacement destroys the primitive silhouette. Estimate
	// the field gradient as well so highlights crawl over the new shape instead of
	// revealing the original sphere normals underneath it.
	float epsilon = 0.035;
	vec3 gradient = vec3(
		displacement_field(local_pos + vec3(epsilon, 0.0, 0.0)) - deformation,
		displacement_field(local_pos + vec3(0.0, epsilon, 0.0)) - deformation,
		displacement_field(local_pos + vec3(0.0, 0.0, epsilon)) - deformation
	) / epsilon;
	vec3 tangent_gradient = gradient - NORMAL * dot(gradient, NORMAL);
	NORMAL = normalize(NORMAL - tangent_gradient * distortion_strength * displacement_multiplier);
	VERTEX += NORMAL * displacement;
	flesh_position = local_pos;
	flesh_noise = deformation * 0.5 + 0.5;
}

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 view_direction = normalize(VIEW);
	float facing = clamp(dot(normal, view_direction), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.5);

	// Cellular mottling and thin branching fibers keep broad highlights from
	// reading as smooth toy plastic while retaining a genuinely wet top coat.
	float cells = organic_noise(flesh_position * 3.4 + vec3(TIME * 0.045, 0.0, -TIME * 0.035));
	float fiber_a = abs(sin(flesh_position.y * 10.0 + flesh_position.z * 4.3 + cells * 8.0));
	float fiber_b = abs(sin(flesh_position.x * 7.4 - flesh_position.z * 8.1 - cells * 5.0));
	float fibers = 1.0 - smoothstep(0.025, 0.115, min(fiber_a, fiber_b));
	float bruising = smoothstep(0.2, 0.78, cells + flesh_noise * 0.18);

	vec3 bruised_flesh = mix(base_color.rgb * 0.48, base_color.rgb * 1.32, bruising);
	ALBEDO = mix(bruised_flesh, vein_color.rgb, fibers * 0.76);
	METALLIC = 0.03;
	float wetness = clamp(0.58 + cells * 0.38 - fibers * 0.22, 0.0, 1.0);
	ROUGHNESS = mix(tissue_roughness, wet_roughness, wetness);
	SPECULAR = 0.92;
	CLEARCOAT = mix(0.28, 0.82, wetness);

	// Fresnel separates overlapping tentacles without making the whole body glow.
	EMISSION = edge_glow_color.rgb * fresnel * edge_emission_strength;
	EMISSION += vein_color.rgb * fibers * (0.04 + 0.025 * sin(TIME * pulse_speed + pulse_phase));
}
