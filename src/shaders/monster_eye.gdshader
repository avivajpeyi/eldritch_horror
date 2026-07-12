shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform vec4 sclera_color : source_color = vec4(0.72, 0.69, 0.58, 1.0);
uniform vec4 bruised_color : source_color = vec4(0.28, 0.015, 0.025, 1.0);
uniform vec4 iris_color : source_color = vec4(0.64, 0.055, 0.015, 1.0);
uniform vec4 iris_glow : source_color = vec4(1.0, 0.16, 0.015, 1.0);
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float blink : hint_range(0.0, 1.0) = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(1.0, 1.42);
	float radius = length(p);
	float eye_mask = 1.0 - smoothstep(0.46, 0.5, radius);
	float iris_radius = length(p * vec2(1.0, 0.88));
	float iris = 1.0 - smoothstep(0.205, 0.235, iris_radius);
	float pupil_width = mix(0.064, 0.027, agitation);
	float pupil = 1.0 - smoothstep(pupil_width, pupil_width + 0.018, abs(p.x));
	pupil *= 1.0 - smoothstep(0.13, 0.19, abs(p.y));

	float angle = atan(p.y, p.x);
	float fibers = 0.5 + 0.5 * sin(angle * 22.0 + radius * 86.0 - TIME * (0.8 + agitation * 2.8));
	fibers *= iris * smoothstep(0.055, 0.2, iris_radius);
	float veins = smoothstep(0.86, 0.96, sin(angle * 13.0 + radius * 54.0 + hash(floor(p * 37.0)) * 3.0));
	veins *= smoothstep(0.22, 0.46, radius);

	vec3 color = mix(sclera_color.rgb, bruised_color.rgb, veins * 0.62 + radius * 0.22);
	color = mix(color, iris_color.rgb, iris);
	color += iris_glow.rgb * fibers * (0.3 + agitation * 0.72);
	color = mix(color, vec3(0.002, 0.0, 0.0), pupil);
	float wet_highlight = 1.0 - smoothstep(0.018, 0.055, distance(p, vec2(-0.11, -0.105)));
	color += wet_highlight * vec3(1.6, 1.35, 1.15);

	float lid = smoothstep(0.5 - blink * 0.52, 0.54 - blink * 0.52, abs(p.y));
	ALBEDO = mix(color, bruised_color.rgb * 0.22, lid);
	EMISSION = iris_glow.rgb * iris * (0.16 + fibers * 0.34) * (0.6 + agitation);
	ALPHA = eye_mask;
}
