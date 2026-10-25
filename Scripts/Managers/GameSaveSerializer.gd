extends RefCounted

## Converts persistent game objects into a JSON-compatible dictionary and writes it.
## Loading/migration remains in GameState because it depends on runtime registries.


static func build_payload(
	characters: Array[CharacterProfile],
	gold: int,
	active_character_id: String,
	stash: Inventory,
	run_state: Dictionary,
	save_version: int,
	default_backpack_size: Vector2i,
	default_stash_size: Vector2i
) -> Dictionary:
	var character_entries: Array[Dictionary] = []
	for character in characters:
		if character == null:
			continue
		character_entries.append({
			"id": character.id,
			"name": character.character_name,
			"class_id": String(character.class_id),
			"archetype": String(character.archetype),
			"level": character.level,
			"xp": character.xp,
			"current_health": character.current_health,
			"current_mana": character.current_mana,
			"stress": character.stress,
			"quirk_ids": Array(character.quirk_ids),
			"attributes": character.attributes.duplicate(true),
			"stat_modifiers": character.stat_modifiers.duplicate(true),
			"status_effects": character.status_effects.duplicate(true),
			"ability_cooldowns": character.ability_cooldowns.duplicate(true),
			"persistent_data": character.persistent_data.duplicate(true),
			"equipment": serialize_equipment(character.equipment),
			"inventory": serialize_inventory(character.inventory, default_backpack_size)
		})

	return {
		"version": save_version,
		"gold": gold,
		"active_character_id": active_character_id,
		"characters": character_entries,
		"stash": serialize_inventory(stash, default_stash_size),
		"run_state": run_state.duplicate(true)
	}


static func save_payload(path: String, payload: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Nem sikerült megnyitni a mentési fájlt: " + path)
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


static func serialize_item(item: InventoryItem) -> Dictionary:
	if item == null or item.item_data == null:
		return {}
	return {
		"resource_path": item.item_data.resource_path,
		"id": String(item.item_data.id),
		"x": item.position.x,
		"y": item.position.y,
		"amount": item.amount,
		"upgrade_level": item.upgrade_level,
		"enchantment_ids": Array(item.enchantment_ids)
	}


static func serialize_equipment(equipment: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for slot in equipment:
		var item := equipment[slot] as InventoryItem
		if item == null or item.item_data == null:
			continue
		result[String(slot)] = serialize_item(item)
	return result


static func serialize_inventory(inventory: Inventory, fallback_size: Vector2i) -> Dictionary:
	if inventory == null:
		return {
			"width": maxi(fallback_size.x, 1),
			"height": maxi(fallback_size.y, 1),
			"items": []
		}

	var item_entries: Array[Dictionary] = []
	for item in inventory.items:
		if item == null or item.item_data == null:
			continue
		item_entries.append(serialize_item(item))

	return {
		"width": inventory.width,
		"height": inventory.height,
		"items": item_entries
	}
