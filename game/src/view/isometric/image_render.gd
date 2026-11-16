class_name IsometricImageRender
extends IsometricConstants


@warning_ignore_start("integer_division")


const RASTER_BAND_HEIGHT := 128
# Godot rejects an image with more pixels than this
const MAXIMUM_IMAGE_PIXELS := 268435456
# the largest band of the native full-color raster
const MAXIMUM_ARTWORK_BAND_PIXELS := 16777216
# the longest edge of a structure, in tiles
const MAXIMUM_STRUCTURE_EDGE := 4

static var _patch_context: CityGpuBuildContext
static var _patch_revision := 0


# the whole city in the native painter. an index palette gives an LA8 image with
# a transparent background, or an L8 image. moving objects and special overlays
# are painted with their tiles. `progress` receives the painted fraction.
# a nonzero `maximum_size` reduces the output by a whole factor until it fits.
# `tiles` with an area paints only the pixels of those tiles: the result has the
# place of its image in the whole picture as `origin`
static func create_image(
	city: CityState,
	palette: Sc2Palette,
	sprites: Sc2SpriteArchive,
	view_size := VIEW_LARGE,
	animation_phase := 0,
	include_moving_things := true,
	transparent_background := false,
	validate_required_assets := true,
	include_special_overlays := true,
	progress := Callable(),
	maximum_size := Vector2i.ZERO,
	artwork_factor := 0,
	tiles := Rect2i()
) -> AssetImageResult:
	var map_edge: int = city.map_size if city != null else 128

	if city == null or not city.is_valid():
		return AssetImageResult.failure("city is invalid")

	if palette == null or not palette.is_valid():
		return AssetImageResult.failure("palette is invalid")

	if sprites == null or not sprites.is_valid():
		return AssetImageResult.failure("large sprite archive is invalid")

	if IsometricGeometry.view_configuration(view_size) == null:
		return AssetImageResult.failure("city view size is invalid")

	var context := CityGpuBuildContext.new()
	var failure := context.prepare(city, palette, sprites, view_size, CityViewMode.Mode.CITY, true, true, true, 0, false,
		include_special_overlays, animation_phase, true, artwork_factor > 0)

	if failure.is_empty() and include_moving_things:
		failure = context.set_moving(city, palette, sprites, _moving_commands(city, sprites, view_size, animation_phase))

	if not failure.is_empty():
		return AssetImageResult.failure(failure)

	var size := IsometricGeometry.output_size_for_view(view_size, map_edge)
	var bounds := Rect2i(Vector2i.ZERO, size)

	if tiles.has_area():
		bounds = tile_area_bounds(context, tiles, view_size, map_edge)

		if not bounds.has_area():
			return AssetImageResult.failure("the tile area has no image")
	elif validate_required_assets:
		# the check paints each tile of the city. the painter of a tile area
		# fails on the first sprite that it lacks
		var asset_errors := context.missing_sprite_errors()

		if not asset_errors.is_empty():
			return AssetImageResult.failure(asset_errors[0])

	var background := Color.TRANSPARENT if transparent_background else Color("18242c")

	if artwork_factor > 0:
		return paint_artwork(context, bounds, background, artwork_factor, progress)

	return paint_region(context, bounds, background, palette.is_index_encoding and transparent_background,
		palette.is_index_encoding and not transparent_background, progress, reduction_to_fit(bounds.size, maximum_size))


# the pixels that the tiles of `tiles` paint, in the picture of the whole
# city: the sprites of each tile, and the whole sprite of each structure that
# has a part in the area. an area outside the map gives an empty rectangle
static func tile_area_bounds(context: CityGpuBuildContext, tiles: Rect2i, view_size: int, map_edge: int) -> Rect2i:
	var configuration := IsometricGeometry.view_configuration(view_size)
	var map := Rect2i(0, 0, map_edge, map_edge)
	var area := tiles.intersection(map)

	if configuration == null or not area.has_area():
		return Rect2i()

	var result := Rect2i()
	# the painter gives the sprite of a structure to its left tile on the
	# screen: the lowest x and the highest y. that tile can be this far outside
	# the area
	var reach := MAXIMUM_STRUCTURE_EDGE - 1
	var searched := Rect2i(area.position - Vector2i(reach, 0), area.size + Vector2i(reach, reach)).intersection(map)

	for x in range(searched.position.x, searched.end.x):
		for y in range(searched.position.y, searched.end.y):
			var inside := area.has_point(Vector2i(x, y))
			var records: PackedInt64Array = context.tile_draws([Vector2i(x, y)] as Array[Vector2i]).get("records", PackedInt64Array())

			for at in range(0, records.size(), CityGpuBuildContext.RECORD_SIZE):
				var sprite := Rect2i(records[at], records[at + 1], records[at + 2], records[at + 3])
				# a sprite wider than one tile stands on that many tiles to each side
				var edge := ceili(float(sprite.size.x) / configuration.tile_width)

				if inside or (edge > 1 and Rect2i(x, y - edge + 1, edge, edge).intersects(area)):
					result = result.merge(sprite) if result.has_area() else sprite

	return result.intersection(Rect2i(Vector2i.ZERO, IsometricGeometry.output_size_for_view(view_size, map_edge)))


# the smallest whole factor that makes `size` fit in `maximum_size`.
# a zero maximum keeps the full size
static func reduction_to_fit(size: Vector2i, maximum_size: Vector2i) -> int:
	if maximum_size.x <= 0 or maximum_size.y <= 0:
		return 1

	return maxi(1, maxi(ceili(float(size.x) / maximum_size.x), ceili(float(size.y) / maximum_size.y)))


# the draw commands of the moving objects, without the special overlays
static func _moving_commands(city: CityState, sprites: Sc2SpriteArchive, view_size: int, animation_phase: int
) -> Array[CityDynamicCommand]:
	var moving: Array[CityDynamicCommand] = []

	for command in IsometricDynamicCommands.dynamic_draw_commands(city, sprites, view_size, animation_phase):
		if command.overlay < 0:
			moving.append(command)

	return moving


# every sprite that the painted city needs and the archive lacks, with moving
# objects and special overlays
static func missing_sprite_errors(city: CityState, sprites: Sc2SpriteArchive, view_size: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var context := CityGpuBuildContext.new()
	var failure := context.prepare(city, Sc2Palette.index_encoding(), sprites, view_size, CityViewMode.Mode.CITY, true, true, true,
		0, false, true)
	var moving := _moving_commands(city, sprites, view_size, 0)
	var missing: Dictionary[int, bool] = {}

	for command in moving:
		if sprites.find_sprite(command.sprite_id) == null:
			missing[command.sprite_id] = true

	if failure.is_empty() and missing.is_empty():
		failure = context.set_moving(city, Sc2Palette.index_encoding(), sprites, moving)

	if not failure.is_empty():
		errors.append(failure)

		return errors

	for sprite_id in context.builder.missing_sprites():
		missing[sprite_id] = true

	var ids := missing.keys()
	ids.sort()

	for sprite_id: int in ids:
		errors.append("required large sprite %d is missing" % sprite_id)

	return errors


# paint a prepared native painter over the whole output in bands, so a long
# export reports its progress. index images convert to LA8 or L8. a
# `reduction` above one shrinks each band by that factor before it is copied,
# so the full-size image is never held. do not reduce index images
static func paint_whole_city(context: CityGpuBuildContext, size: Vector2i, background: Color, index_alpha: bool,
		index_opaque: bool, progress := Callable(), reduction := 1) -> AssetImageResult:
	return paint_region(context, Rect2i(Vector2i.ZERO, size), background, index_alpha, index_opaque, progress, reduction)


# paint the pixels of `bounds` only, as `paint_whole_city` paints the whole
# output. `bounds` must be inside the output. the result has the place of
# `bounds` as its `origin`
static func paint_region(context: CityGpuBuildContext, bounds: Rect2i, background: Color, index_alpha: bool,
		index_opaque: bool, progress := Callable(), reduction := 1) -> AssetImageResult:
	var size := bounds.size
	var output_size := Vector2i(ceili(float(size.x) / reduction), ceili(float(size.y) / reduction))

	if output_size.x <= 0 or output_size.y <= 0:
		return AssetImageResult.failure("city image is empty")

	if output_size.x * output_size.y > MAXIMUM_IMAGE_PIXELS:
		return AssetImageResult.failure("city image of %d × %d pixels is too large" % [output_size.x, output_size.y])

	var output := Image.create(output_size.x, output_size.y, false, Image.FORMAT_RGBA8)
	var band_height := reduction * maxi(1, RASTER_BAND_HEIGHT / reduction)

	for top in range(0, size.y, band_height):
		var band := Rect2i(bounds.position.x, bounds.position.y + top, size.x, mini(band_height, size.y - top))
		var painted := context.raster(band, background)

		if painted.has("error"):
			return AssetImageResult.failure(painted.error)

		var image: Image = painted.image

		if reduction > 1:
			image.resize(output_size.x, ceili(float(band.size.y) / reduction), Image.INTERPOLATE_TRILINEAR)

		output.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, top / reduction))

		if progress.is_valid():
			progress.call(float(top + band.size.y) / size.y)

	if index_alpha:
		output.convert(Image.FORMAT_LA8)
	elif index_opaque:
		output.convert(Image.FORMAT_L8)

	var result := AssetImageResult.new()
	result.ok = true
	result.image = output
	result.error = ""
	result.origin = bounds.position

	return result


# The whole city with its full-color art, at `factor` (1, 2 or 4) pixels for
# each view pixel. Call `prepare` with `with_artwork` first.
static func paint_whole_city_artwork(context: CityGpuBuildContext, size: Vector2i, background: Color, factor: int,
		progress := Callable()) -> AssetImageResult:
	return paint_artwork(context, Rect2i(Vector2i.ZERO, size), background, factor, progress)


# The view pixels of `bounds` with the full-color art, at `factor` (1, 2 or 4)
# pixels for each view pixel. Call `prepare` with `with_artwork` first.
static func paint_artwork(context: CityGpuBuildContext, bounds: Rect2i, background: Color, factor: int,
		progress := Callable()) -> AssetImageResult:
	var output_size := bounds.size * factor

	if output_size.x <= 0 or output_size.y <= 0:
		return AssetImageResult.failure("city image is empty")

	if output_size.x * output_size.y > MAXIMUM_IMAGE_PIXELS:
		return AssetImageResult.failure("city image of %d × %d pixels is too large" % [output_size.x, output_size.y])

	var output := Image.create(output_size.x, output_size.y, false, Image.FORMAT_RGBA8)
	# each native band holds at most MAXIMUM_ARTWORK_BAND_PIXELS output pixels
	var band_height := clampi(MAXIMUM_ARTWORK_BAND_PIXELS / (output_size.x * factor), 1, RASTER_BAND_HEIGHT)

	for top in range(bounds.position.y, bounds.end.y, band_height):
		var band := Rect2i(bounds.position.x, top, bounds.size.x, mini(band_height, bounds.end.y - top))
		var painted := context.raster_artwork(band, background, factor)

		if painted.has("error"):
			return AssetImageResult.failure(painted.error)

		var image: Image = painted.image
		var placed: Rect2i = painted.bounds
		output.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), (placed.position - bounds.position) * factor)

		if progress.is_valid():
			progress.call(float(band.end.y - bounds.position.y) / bounds.size.y)

	var result := AssetImageResult.new()
	result.ok = true
	result.image = output
	result.error = ""
	result.origin = bounds.position

	return result


# paint the tiles that can reach the dirty tiles again into a copy of
# `base_image`. the main thread keeps one native painter for these patches
static func patch_static_image(
	base_image: Image,
	city: CityState,
	palette: Sc2Palette,
	sprites: Sc2SpriteArchive,
	dirty_indices: PackedInt32Array,
	view_size := VIEW_LARGE,
	copy_image := true
) -> PatchResult:
	var map_edge: int = city.map_size if city != null else 128

	if base_image == null or base_image.is_empty():
		return PatchResult.rejected("base city image is invalid")

	if city == null or not city.is_valid():
		return PatchResult.rejected("city is invalid")

	if palette == null or not palette.is_valid() or not palette.is_index_encoding:
		return PatchResult.rejected("indexed palette is invalid")

	if sprites == null or not sprites.is_valid():
		return PatchResult.rejected("sprite archive is invalid")

	var configuration := IsometricGeometry.view_configuration(view_size)

	if configuration == null:
		return PatchResult.rejected("city view size is invalid")

	var native_size := IsometricGeometry.output_size_for_view(view_size, map_edge)
	var output_scale := 1

	if base_image.get_size() == IsometricGeometry.output_size_for_view(VIEW_LARGE, map_edge):
		output_scale = configuration.divisor
	elif base_image.get_size() != native_size:
		return PatchResult.rejected("base city image has the wrong size")

	var native_rect := IsometricGeometry.dirty_screen_rect(
		dirty_indices, sprites, view_size, IsometricGeometry.maximum_sprite_size(sprites), map_edge
	)

	if native_rect.get_area() <= 0:
		return PatchResult.rejected("dirty city region is empty")

	if _patch_context == null:
		_patch_context = CityGpuBuildContext.new()

	_patch_revision += 1
	var failure := _patch_context.prepare(city, palette, sprites, view_size, CityViewMode.Mode.CITY, true, true, true,
		_patch_revision, false)

	if not failure.is_empty():
		return PatchResult.rejected(failure)

	var painted := _patch_context.raster(native_rect, Color.TRANSPARENT)

	if painted.has("error"):
		return PatchResult.rejected(painted.error)

	var region: Image = painted.image
	region.convert(Image.FORMAT_LA8)
	var output_rect := native_rect

	if output_scale > 1:
		region.resize(
			region.get_width() * output_scale,
			region.get_height() * output_scale,
			Image.INTERPOLATE_NEAREST
		)
		output_rect = Rect2i(
			native_rect.position * output_scale,
			native_rect.size * output_scale
		)

	var patched := base_image.duplicate() if copy_image else base_image

	if patched.get_format() != region.get_format():
		region.convert(patched.get_format())

	patched.blit_rect(
		region, Rect2i(Vector2i.ZERO, region.get_size()), output_rect.position
	)

	var result := PatchResult.new()
	result.ok = true
	result.image = patched
	result.native_rect = native_rect
	result.output_rect = output_rect
	result.error = ""

	return result


# paint the moving object of one visual into `output`
# shadow commands darken the pixels that are already present
# `offset` shifts every command, for painting into a sub-rectangle
static func draw_moving_thing(
	output: Variant,
	city: CityState,
	palette: Sc2Palette,
	sprites: Sc2SpriteArchive,
	cache: Dictionary,
	visual: IsometricMovingVisuals.Visual,
	configuration: CityViewConfiguration,
	offset := Vector2i.ZERO
) -> void:
	for command in IsometricDynamicCommands.moving_thing_draw_commands_for_visual(
		city, sprites, visual, configuration
	):
		var sprite := IsometricPixelOperations.sprite_image(
			sprites, palette, cache, command.sprite_id, command.flip
		)
		var position: Vector2i = command.position + offset

		if command.shadow:
			IsometricPixelOperations._blend_shadow(output, sprite, palette, position)
		else:
			output.blend_rect(
				sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), position
			)


class PatchResult extends AssetImageResult:
	var native_rect := Rect2i()
	var output_rect := Rect2i()

	static func rejected(message: String) -> PatchResult:
		var result := PatchResult.new()
		result.error = message

		return result
