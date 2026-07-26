shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_atlas : source_color, filter_nearest_mipmap_anisotropic;
uniform sampler2D night_emission_atlas : source_color, filter_nearest_mipmap_anisotropic;
uniform sampler2D specular_atlas : hint_default_white, filter_nearest_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float night_emission_energy : hint_range(0.0, 4.0) = 1.45;

void fragment() {
	vec4 atlas_color = texture(albedo_atlas, UV);
	vec3 night_color = texture(night_emission_atlas, UV).rgb;
	float material_response = dot(
		texture(specular_atlas, UV).rgb,
		vec3(0.333333)
	);

	ALBEDO = atlas_color.rgb * tint.rgb;
	ROUGHNESS = mix(0.88, 0.32, material_response);
	METALLIC = mix(0.03, 0.38, material_response);
	SPECULAR = mix(0.28, 0.72, material_response);
	EMISSION = night_color * night_emission_energy;
}
