shader_type canvas_item;

// Recolors only low-saturation (gray/neutral) pixels — the plain jumpsuit
// fabric on every PixelLab character — to a vivid team color, replacing hue
// and saturation but keeping the pixel's own value (brightness), so existing
// shading/highlights on the fabric survive. Skin, hair, and colored
// accessories already have their own saturation and are left alone.

uniform vec4 team_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float saturation_threshold : hint_range(0.0, 1.0) = 0.16;
uniform float falloff : hint_range(0.01, 0.5) = 0.06;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(tex.rgb);
	vec3 team_hsv = rgb2hsv(team_color.rgb);

	float mask = 1.0 - smoothstep(saturation_threshold, saturation_threshold + falloff, hsv.y);
	vec3 recolored = hsv2rgb(vec3(team_hsv.x, max(hsv.y, team_hsv.y), hsv.z));

	COLOR = vec4(mix(tex.rgb, recolored, mask), tex.a);
}
