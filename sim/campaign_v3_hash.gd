class_name CampaignV3Hash
extends RefCounted

## V3 uses a versioned canonical-document payload. Because normalize_data owns
## exact key order and nested canonicality, every persisted field is included;

const MAGIC := "PTD-CAMPAIGN-HASH"
const CORE_MAGIC := "PTD-CAMPAIGN-CORE-HASH"
const VERSION := 3
const FNV_OFFSET := -3750763034362895579
const FNV_PRIME := 1099511628211
const CODEC_PATH := "res://sim/campaign_v3_codec.gd"
const CanonicalJsonScript := preload("res://sim/canonical_json.gd")
const HeroIdentityScript := preload("res://sim/hero_identity.gd")


static func of_data(value: Variant, context: Dictionary) -> Dictionary:
	var bytes := bytes_of(value, context)
	if not bytes["accepted"]:
		return bytes
	return _hash_encoded(bytes["bytes"])


## Internal companion to CampaignV3Codec._encode_normalized_save().
static func _of_normalized_data(value: Dictionary) -> Dictionary:
	return _hash_encoded(_bytes_of_normalized(value)["bytes"])


static func of_core(value: Variant, context: Dictionary) -> Dictionary:
	var normalized: Dictionary = load(CODEC_PATH).call("normalize_core", value, context)
	if not normalized["accepted"]:
		return normalized
	return _of_normalized_core(normalized["value"])


## Internal codec seam. Callers must supply the exact canonical normalize_core output.
static func _of_normalized_core(value: Dictionary) -> Dictionary:
	return _hash_encoded(_bytes_of_normalized(_core_hash_payload(value), CORE_MAGIC)["bytes"])


static func _core_hash_payload(value: Dictionary) -> Dictionary:
	var codec: GDScript = load(CODEC_PATH) as GDScript
	var legacy := {}
	for key: String in codec.LEGACY_CORE_KEYS:
		if key == "heroes":
			var heroes: Array[Dictionary] = []
			for source: Dictionary in value["heroes"]:
				var row := {}
				for hero_key: String in codec.LEGACY_HERO_KEYS:
					row[hero_key] = source[hero_key]
				heroes.append(row)
			legacy[key] = heroes
		else:
			legacy[key] = value[key]
	return legacy


static func bytes_of(value: Variant, context: Dictionary) -> Dictionary:
	var normalized: Dictionary = load(CODEC_PATH).call("normalize_data", value, context)
	if not normalized["accepted"]:
		return normalized
	return _bytes_of_normalized(normalized["value"])


static func _bytes_of_normalized(value: Dictionary, magic: String = MAGIC) -> Dictionary:
	var payload := PackedByteArray()
	payload.append_array(magic.to_ascii_buffer())
	payload.append(0)
	for shift: int in [0, 8, 16, 24]:
		payload.append((VERSION >> shift) & 0xFF)
	payload.append_array(CanonicalJsonScript.text(value).to_utf8_buffer())
	return {"accepted": true, "error_code": &"", "bytes": payload}


static func _hash_encoded(bytes: PackedByteArray) -> Dictionary:
	var bits := FNV_OFFSET
	for byte: int in bytes:
		bits ^= byte
		bits *= FNV_PRIME
	return {
		"accepted": true,
		"error_code": &"",
		"bits": bits,
		"hex": HeroIdentityScript.format_u64_hex(bits),
		"bytes": bytes,
	}
