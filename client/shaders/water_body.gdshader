shader_type canvas_item;
render_mode blend_mix, unshaded;

uniform vec2 flow_direction = vec2(1.0, 0.18);
uniform float flow_speed = 0.35;
uniform float distortion_px = 0.75;
uniform float shimmer_strength = 0.14;
uniform float foam_strength = 0.4;
uniform float depth_darkening = 0.18;
uniform float surface_band_px = 18.0;
uniform float wave_height_px = 2.2;
uniform float wave_frequency = 0.055;
uniform float secondary_wave_frequency = 0.097;
uniform float wave_speed = 1.2;
uniform vec2 bounds_origin = vec2(0.0, 0.0);
uniform vec2 bounds_size = vec2(64.0, 64.0);
uniform vec2 tile_pixel_size = vec2(16.0, 16.0);
uniform vec4 deep_tint : source_color = vec4(0.08, 0.42, 0.67, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.88, 0.97, 1.0, 1.0);
uniform vec4 shimmer_tint : source_color = vec4(0.35, 0.78, 0.95, 1.0);

varying vec2 local_position;

float surface_wave(float x, float time) {
	return sin(x * wave_frequency + time * wave_speed) * 0.65
		+ sin(x * secondary_wave_frequency - time * wave_speed * 0.72) * 0.35;
}

void vertex() {
	float band = max(surface_band_px, 1.0);
	float relative_top = VERTEX.y - bounds_origin.y;
	float surface_mask = 1.0 - smoothstep(0.0, band, relative_top);
	float wave = surface_wave(VERTEX.x, TIME);
	VERTEX.y += wave * wave_height_px * surface_mask;
	local_position = VERTEX;
}

void fragment() {
	vec4 input_color = COLOR;
	vec2 flow = flow_direction;
	if (length(flow) < 0.001) {
		flow = vec2(1.0, 0.0);
	} else {
		flow = normalize(flow);
	}

	float time = TIME;
	float ripple_a = sin(dot(local_position, flow * vec2(0.065, 0.045)) * 3.7 + time * flow_speed * 6.0);
	float ripple_b = sin(local_position.x * 0.13 - time * (flow_speed * 4.4 + 0.3) + local_position.y * 0.07);
	float ripple_c = sin((local_position.x + local_position.y) * 0.08 + time * (flow_speed * 3.1 + 0.6));
	float shimmer = (ripple_a * 0.5 + ripple_b * 0.3 + ripple_c * 0.2) * 0.5 + 0.5;

	vec2 tile_uv_size = tile_pixel_size * TEXTURE_PIXEL_SIZE;
	vec2 tile_uv_origin = floor(UV / tile_uv_size) * tile_uv_size;
	vec2 uv_padding = TEXTURE_PIXEL_SIZE * 0.5;
	vec2 flow_offset = flow * ((ripple_b + ripple_c) * distortion_px) * TEXTURE_PIXEL_SIZE;
	vec2 warped_uv = clamp(UV + flow_offset, tile_uv_origin + uv_padding, tile_uv_origin + tile_uv_size - uv_padding);
	vec4 tex = texture(TEXTURE, warped_uv);
	vec4 base = tex * input_color;

	float depth = clamp((local_position.y - bounds_origin.y) / max(bounds_size.y, 1.0), 0.0, 1.0);
	float surface = 1.0 - smoothstep(0.0, max(surface_band_px, 1.0), local_position.y - bounds_origin.y);
	float foam = surface * (0.45 + 0.55 * shimmer) * foam_strength;
	float highlight = max(shimmer - 0.52, 0.0) * shimmer_strength;

	vec3 color = base.rgb;
	color = mix(color, color * deep_tint.rgb, depth * depth_darkening);
	color += shimmer_tint.rgb * highlight;
	color = mix(color, foam_tint.rgb, foam);

	COLOR = vec4(color, base.a);
}
