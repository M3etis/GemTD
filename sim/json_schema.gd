class_name JsonSchema
extends RefCounted
## Минимальный валидатор подмножества JSON Schema:
## type, properties, required, items, minItems, maxItems, minimum, maximum, enum, additionalProperties.


static func validate(value: Variant, schema: Dictionary, path: String = "$") -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	_validate(value, schema, path, errors)
	return errors


static func _type_ok(value: Variant, t: String) -> bool:
	match t:
		"object":
			return value is Dictionary
		"array":
			return value is Array
		"string":
			return value is String
		"boolean":
			return value is bool
		"number":
			return value is float or value is int
		"integer":
			if value is int:
				return true
			# JSON парсер Godot отдаёт все числа как float.
			return value is float and is_equal_approx(float(value), roundf(float(value)))
	return true


static func _validate(value: Variant, schema: Dictionary, path: String, errors: PackedStringArray) -> void:
	if schema.has("type") and not _type_ok(value, String(schema["type"])):
		errors.append("%s: ожидался тип %s" % [path, schema["type"]])
		return
	if schema.has("enum") and not (schema["enum"] as Array).has(value):
		errors.append("%s: значение %s не из списка %s" % [path, str(value), str(schema["enum"])])
	if value is float or value is int:
		var n: float = float(value)
		if schema.has("minimum") and n < float(schema["minimum"]):
			errors.append("%s: %s < минимума %s" % [path, str(value), str(schema["minimum"])])
		if schema.has("maximum") and n > float(schema["maximum"]):
			errors.append("%s: %s > максимума %s" % [path, str(value), str(schema["maximum"])])
	if value is Array:
		var arr: Array = value
		if schema.has("minItems") and arr.size() < int(schema["minItems"]):
			errors.append("%s: элементов меньше %d" % [path, int(schema["minItems"])])
		if schema.has("maxItems") and arr.size() > int(schema["maxItems"]):
			errors.append("%s: элементов больше %d" % [path, int(schema["maxItems"])])
		if schema.has("items"):
			for i: int in arr.size():
				_validate(arr[i], schema["items"], "%s[%d]" % [path, i], errors)
	if value is Dictionary:
		var dict: Dictionary = value
		if schema.has("required"):
			for key: Variant in schema["required"]:
				if not dict.has(key):
					errors.append("%s: нет обязательного поля «%s»" % [path, key])
		var props: Dictionary = schema.get("properties", {})
		for key: Variant in dict.keys():
			var sub_path: String = "%s.%s" % [path, key]
			if props.has(key):
				_validate(dict[key], props[key], sub_path, errors)
			elif schema.has("additionalProperties") and schema["additionalProperties"] is Dictionary:
				_validate(dict[key], schema["additionalProperties"], sub_path, errors)
