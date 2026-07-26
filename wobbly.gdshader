shader_type canvas_item;

uniform vec2 size = vec2(8.0, 7.0);
// If you intend to read from mipmaps with `textureLod()` LOD values greater than `0.0`,
// use `filter_nearest_mipmap` instead. This shader doesn't require it.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform sampler2D noise : repeat_enable;
uniform sampler2D noise2 : repeat_enable;

vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec2 center_uv = vec2(0.0, 0.0);
	vec2 center_uv1 = SCREEN_UV;
	vec2 gex = texture(noise2, SCREEN_UV-(TIME*0.25)).rg;
	vec2 lol = texture(noise, center_uv1+(TIME*0.2)).rg - 0.5;
	vec2 lol2 = lol - gex;
	vec2 lol3 = gex - lol;
	vec2 uvf = center_uv1+vec2(lol2.r * 0.4, lol2.g * 0.2) * 0.03;
	vec3 hue_shift = vec3(lol3.r+0.7, lol3.gr);
	vec3 c1 = texture(screen_texture, uvf, 0.0).rgb;
	vec3 c2 = rgb2hsv(c1);
	vec3 c3 = c2 * vec3(hue_shift.r, hue_shift.g, 1.);
	vec3 c4 = hsv2rgb(c3);
	COLOR= vec4(c4, 1.0);
}