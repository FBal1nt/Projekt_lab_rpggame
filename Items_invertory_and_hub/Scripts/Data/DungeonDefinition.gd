class_name DungeonDefinition
extends Resource

## Data-only description of a dungeon. Add a .tres file under Data/Dungeons/.
@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Leave empty until a playable dungeon scene is implemented. Set to a res:// path later.
@export_file("*.tscn") var scene_path: String = ""
@export var base_spawn_rate_multiplier: float = 1.0
## Difficulty resources with a matching dungeon_id become available automatically.
@export var recommended_level_min: int = 1
@export var recommended_level_max: int = 5
