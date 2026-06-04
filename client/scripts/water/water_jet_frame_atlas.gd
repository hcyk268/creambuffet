extends RefCounted
class_name WaterJetFrameAtlas


static func make_frame_texture(
	texture: Texture2D,
	frame_size: Vector2,
	column: int,
	row: int,
	crop_top: float = 0.0,
	crop_height: float = -1.0,
	crop_left: float = 0.0,
	crop_width: float = -1.0
) -> AtlasTexture:
	var target_crop_height := frame_size.y if crop_height < 0.0 else crop_height
	var target_crop_width := frame_size.x if crop_width < 0.0 else crop_width
	var safe_column := clampi(column, 0, 3)
	var safe_row := clampi(row, 0, 3)
	var safe_crop_top := clampf(crop_top, 0.0, frame_size.y - 1.0)
	var safe_crop_height := clampf(target_crop_height, 1.0, frame_size.y - safe_crop_top)
	var safe_crop_left := clampf(crop_left, 0.0, frame_size.x - 1.0)
	var safe_crop_width := clampf(target_crop_width, 1.0, frame_size.x - safe_crop_left)
	var frame_texture := AtlasTexture.new()
	frame_texture.atlas = texture
	frame_texture.region = Rect2(
		Vector2(safe_column * frame_size.x + safe_crop_left, safe_row * frame_size.y + safe_crop_top),
		Vector2(safe_crop_width, safe_crop_height)
	)
	return frame_texture


static func frame_bounds(row: int, column: int) -> Rect2:
	var safe_row := clampi(row, 0, 3)
	var safe_column := clampi(column, 0, 3)
	match safe_row:
		0:
			match safe_column:
				0:
					return Rect2(74, 30, 116, 233)
				1:
					return Rect2(88, 42, 76, 210)
				2:
					return Rect2(75, 44, 89, 206)
				_:
					return Rect2(77, 56, 74, 181)
		1:
			match safe_column:
				0:
					return Rect2(53, 82, 157, 117)
				1:
					return Rect2(62, 103, 127, 76)
				2:
					return Rect2(41, 98, 157, 85)
				_:
					return Rect2(37, 102, 153, 77)
		2:
			match safe_column:
				0:
					return Rect2(44, 46, 175, 177)
				1:
					return Rect2(45, 49, 162, 171)
				2:
					return Rect2(43, 57, 154, 156)
				_:
					return Rect2(43, 63, 141, 143)
		_:
			match safe_column:
				0:
					return Rect2(47, 39, 170, 180)
				1:
					return Rect2(51, 45, 149, 168)
				2:
					return Rect2(48, 49, 144, 160)
				_:
					return Rect2(43, 49, 141, 160)
