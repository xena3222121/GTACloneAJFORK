shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// A first version displaced vertices with a sine wave for physical ripples,
// but that leaves NORMAL pointing straight up (Godot doesn't auto-recompute
// normals from a custom vertex displacement) while the surface itself tilts -
// harmless from most gameplay camera angles, but from a true top-down view
// (confirmed via a rendered screenshot - notably the minimap camera, which
// looks straight down at the world constantly) it produced a strange dark
// repeating diamond/hole pattern against the ground below. Flat geometry with
// a fragment-only shimmer avoids the mismatch entirely - no vertex movement
// means no normal to get wrong - while still reading as animated water.
uniform vec4 shallow_color : source_color = vec4(0.28, 0.58, 0.56, 0.78);
uniform vec4 deep_color : source_color = vec4(0.05, 0.22, 0.28, 0.88);
uniform float shimmer_speed : hint_range(0.0, 3.0) = 0.5;
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;

void fragment() {
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float shimmer = sin((UV.x + UV.y) * 40.0 + TIME * shimmer_speed) * 0.04;
	ALBEDO = mix(deep_color.rgb, shallow_color.rgb, fresnel) + shimmer;
	ALPHA = mix(deep_color.a, shallow_color.a, fresnel);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
