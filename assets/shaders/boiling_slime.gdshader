shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 flesh_color : source_color = vec4(0.075, 0.004, 0.012, 1.0);
uniform vec4 vein_color : source_color = vec4(0.32, 0.008, 0.015, 1.0);
uniform float boil_strength : hint_range(0.0, 0.3) = 0.065;
uniform float boil_scale : hint_range(0.1, 20.0) = 7.0;
uniform float boil_speed : hint_range(0.0, 8.0) = 1.7;

void vertex() {
	float n1 = sin(VERTEX.x * boil_scale + TIME * boil_speed);
	float n2 = sin(VERTEX.y * boil_scale * 1.37 - TIME * boil_speed * 0.73);
	float n3 = cos(VERTEX.z * boil_scale * 0.81 + TIME * boil_speed * 1.19);
	float jagged = (n1 + n2 + n3) / 3.0;
	VERTEX += NORMAL * jagged * boil_strength;
}

void fragment() {
	float fibers = pow(abs(sin(VERTEX.y * 18.0 + VERTEX.z * 5.0)), 12.0);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	ALBEDO = mix(flesh_color.rgb, vein_color.rgb, fibers * 0.48);
	ALBEDO += vein_color.rgb * fresnel * 0.22;
	ROUGHNESS = 0.05;
	SPECULAR = 1.0;
	EMISSION = vein_color.rgb * (fibers * 0.055 + fresnel * 0.075);
}
