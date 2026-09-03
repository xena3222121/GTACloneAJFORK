shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// v1 shipped flat (no vertex displacement) after a wave-displaced version
// broke: it moved VERTEX.y but left NORMAL untouched, so lighting stayed
// flat everywhere while the surface visually tilted - fine from most
// angles, but produced a dark diamond pattern viewed from directly
// overhead (the minimap camera's angle). This version displaces again, but
// derives NORMAL from the REAL displaced world position via screen-space
// derivatives (dFdx/dFdy) in the fragment shader instead of trying to hand-
// compute and transform an analytic slope through the model matrix - Ocean
// and River are wildly non-uniformly scaled (310x78 vs 30x262), so a normal
// computed in one of those spaces and transformed into the other is a
// correctness trap; derivatives of the actual rendered position sidestep
// that entirely and stay correct from any angle, any instance scale.
uniform vec4 shallow_color : source_color = vec4(0.3, 0.62, 0.6, 0.78);
uniform vec4 deep_color : source_color = vec4(0.05, 0.22, 0.28, 0.9);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.92, 0.85);
uniform float wave_height : hint_range(0.0, 1.0) = 0.12;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.5;

varying vec3 world_pos;

float wave_height_at(vec2 xz, float t) {
	return sin(xz.x * 0.15 + t) + sin(xz.y * 0.22 + t * 1.3) * 0.7;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float wave = wave_height_at(world_pos.xz, t);
	VERTEX.y += wave * wave_height;
	world_pos.y += wave * wave_height;
}

void fragment() {
	vec3 dx = dFdx(world_pos);
	vec3 dy = dFdy(world_pos);
	vec3 computed_normal = normalize(cross(dy, dx));
	// computed_normal is world-space; VIEW_MATRIX's linear part is a pure
	// rotation (cameras don't carry scale), so transforming a direction by
	// it directly is a valid, correct way into the view space NORMAL expects.
	NORMAL = normalize((VIEW_MATRIX * vec4(computed_normal, 0.0)).xyz);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float shimmer = sin((UV.x + UV.y) * 40.0 + TIME * shimmer_speed) * 0.04;
	vec3 base = mix(deep_color.rgb, shallow_color.rgb, fresnel) + shimmer;
	// Cheap crest/foam detector - a steeper local slope (normal tilted away
	// from straight up) reads as a wave crest catching more light/foam.
	float crest = clamp((1.0 - computed_normal.y) * 4.0, 0.0, 1.0);
	ALBEDO = mix(base, foam_color.rgb, crest * 0.45);
	ALPHA = mix(deep_color.a, shallow_color.a, fresnel);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
