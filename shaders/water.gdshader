shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// See git history for the normal-computation approach (screen-space
// derivatives of the actual displaced position, not a hand-transformed
// analytic slope - Ocean/River are wildly non-uniformly scaled, which makes
// the analytic approach a correctness trap).
//
// depth_mode picks how "distance from shore" is measured, since Ocean and
// River have different shapes: 0 = directional (one shore edge, at local
// Z=-0.5 - matches how Ocean is placed, shore against the beach on its
// north edge, deep water toward its south edge) for the ocean; 1 =
// symmetric (banks on both local X edges, deepest at the center) for the
// river. Set per-instance via a surface material override in World.tscn,
// since both otherwise share this same base material/shader.
uniform int depth_mode = 0;
uniform float depth_falloff : hint_range(0.05, 0.5) = 0.16;

uniform vec4 shore_color : source_color = vec4(0.42, 0.82, 0.75, 0.55);
uniform vec4 shallow_color : source_color = vec4(0.14, 0.48, 0.52, 0.84);
uniform vec4 deep_color : source_color = vec4(0.015, 0.08, 0.2, 0.97);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.92, 0.85);
uniform float wave_height : hint_range(0.0, 1.0) = 0.12;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.6;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.5;

varying vec3 world_pos;
varying vec2 local_xz;

float wave_height_at(vec2 xz, float t) {
	return sin(xz.x * 0.15 + t) + sin(xz.y * 0.22 + t * 1.3) * 0.7;
}

void vertex() {
	local_xz = VERTEX.xz;
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
	NORMAL = normalize((VIEW_MATRIX * vec4(computed_normal, 0.0)).xyz);

	// 0 at the shore, ramping to 1 by depth_falloff fraction of the way
	// across, then staying fully deep for the rest - a real distance-from-
	// shore gradient, not just a view-angle effect.
	float depth_t;
	if (depth_mode == 1) {
		float dist_from_bank = 0.5 - abs(local_xz.x);
		depth_t = clamp(dist_from_bank / depth_falloff, 0.0, 1.0);
	} else {
		depth_t = clamp((local_xz.y + 0.5) / depth_falloff, 0.0, 1.0);
	}
	vec3 depth_rgb = mix(mix(shore_color.rgb, shallow_color.rgb, clamp(depth_t * 2.0, 0.0, 1.0)),
			deep_color.rgb, clamp(depth_t * 2.0 - 1.0, 0.0, 1.0));
	float depth_a = mix(mix(shore_color.a, shallow_color.a, clamp(depth_t * 2.0, 0.0, 1.0)),
			deep_color.a, clamp(depth_t * 2.0 - 1.0, 0.0, 1.0));

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float shimmer = sin((UV.x + UV.y) * 40.0 + TIME * shimmer_speed) * 0.04;
	// Fresnel now only adds a grazing-angle sheen on top of the depth-based
	// color, rather than being the primary color driver like before.
	vec3 base = depth_rgb + vec3(fresnel * 0.12) + shimmer;
	float crest = clamp((1.0 - computed_normal.y) * 4.0, 0.0, 1.0);
	ALBEDO = mix(base, foam_color.rgb, crest * 0.45);
	ALPHA = clamp(depth_a + fresnel * 0.08, 0.0, 1.0);
	ROUGHNESS = 0.04;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
