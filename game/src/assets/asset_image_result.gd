class_name AssetImageResult
extends RefCounted

var ok := false
var error := ""
var image: Image
# the place of `image` in the whole picture, when it shows a part of it
var origin := Vector2i.ZERO


static func failure(message: String) -> AssetImageResult:
	var result := AssetImageResult.new()
	result.error = message

	return result
