---
name: save-systems
description: "Design game saves, versioned schemas, migrations, slots, autosave, and crash-safe writes."
---

# Save systems

A save file is a **serialized snapshot of game state** that survives restarts.
The hard parts aren't writing bytes — they're choosing *what* to save, writing it
so a crash mid-save can't corrupt it, and handling the explicitly supported save
versions. Reol's support boundary is defined in [compatibility policy](../../../docs/COMPATIBILITY.md).

## When to use

- Use to persist progress: player stats, inventory, world flags, settings,
  positions — across sessions and game updates.
- Use to design save slots, quicksave/autosave, and crash-safe writes.
- Use when old save files break after a content/code change (versioning &
  migration).

**When *not* to use:** for Roblox cloud persistence specifics, use
`roblox-datastores`. For the data model the save serializes (resources/SOs), use
`godot-resources` / `unity-scriptableobjects`. For Godot's `FileAccess`/
`ResourceSaver` and `user://` paths, defer to the Godot engine skill while
applying the patterns here.

## Core workflow

1. **Decide what state is authoritative.** Save the *data* (hp, position, seed,
   unlocked flags), not engine objects or scene nodes. You will reconstruct
   objects from data on load — never serialize live node references.
2. **Define a versioned schema.** Every save embeds a `version` integer. This is
   the single most important field for a game you intend to patch.
3. **Pick a format.** JSON/text for readability and debuggability; a binary
   format for size/speed or mild tamper-resistance. Start with JSON.
4. **Write atomically.** Serialize to a temp file, flush, then rename over the
   real file. A crash leaves either the old save or the new one — never a
   half-written one.
5. **Load defensively.** Read and validate the version; migrate only explicitly
   supported inputs into the one current model, reject unsupported versions
   clearly, then validate and construct an independent candidate. Publish only
   after complete validation, preserving live state and source saves on failure.
6. **Autosave on safe boundaries** (level change, checkpoint), throttled, and to a
   separate slot so it can't clobber a manual save.
7. **Verify**: save, fully quit, relaunch, load — and confirm by inspection that
   state matches. Test every supported migration boundary and rejection of
   unsupported versions; do not rewrite fixtures or user saves to make tests pass.

## Patterns

### 1. Serialize state as plain data (not engine objects)

```gdscript
# Member variables in this illustrative script belong to an independent candidate.
# Build a dictionary of pure data. Each savable object reports its own state.
func capture_state() -> Dictionary:
    return {
        "version": SAVE_VERSION,                 # ALWAYS stamp the schema version
        "player": { "hp": player.hp, "pos": [player.position.x, player.position.y] },
        "inventory": player.inventory.to_array(),  # ids + counts, not Item nodes
        "flags": world.flags,                    # e.g. {"met_guard": true}
        "seed": world.seed,                      # regenerate procedural content
    }

# After version/shape validation, apply to an independent candidate, never the
# active world; publish the candidate only after all validation has succeeded.
func apply_state(data: Dictionary) -> void:
    player.hp = data["player"]["hp"]
    player.position = Vector2(data["player"]["pos"][0], data["player"]["pos"][1])
    player.inventory.from_array(data["inventory"])
    world.flags = data["flags"]
```

### 2. Atomic, crash-safe write (temp + rename)

```gdscript
# Illustrative Godot 4.7 I/O only; see Reol's implementation for strict loading
# and backup decisions. Write a temp file, keep the previous save, then rename.
func save_atomic(path: String, data: Dictionary) -> Error:
    var tmp := path + ".tmp"
    var f := FileAccess.open(tmp, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()       # disk full, read-only, no permission...
    if not f.store_string(JSON.stringify(data)):
        return ERR_FILE_CANT_WRITE
    f.close()                                    # flushes Godot's buffer to the OS
    if FileAccess.file_exists(path):
        DirAccess.rename_absolute(path, path + ".bak")   # keep the last good save
    return DirAccess.rename_absolute(tmp, path)

func load_save(path: String) -> Dictionary:      # empty = nothing loadable
    for p in [path, path + ".bak"]:              # .bak covers a crash between renames
        if FileAccess.file_exists(p):
            var data = JSON.parse_string(FileAccess.get_file_as_string(p))
            if data is Dictionary and data.has("version"):
                if not is_valid_integer_version(data["version"]):
                    return {}                    # reject invalid versions, don't coerce
                return data
    return {}
# WRONG: opening `path` directly and writing in place — a crash mid-write leaves a
# truncated, unloadable save and destroys the player's progress.
```

A crash can leave the old save, the new one, or (between the two renames) only
the `.bak`; recovery must follow the explicit backup policy. Two limits to know: `rename()` replaces
the target atomically on POSIX (same volume), but Godot's Windows `rename_absolute`
deletes the target and then moves, so that platform relies on the `.bak` too; and
neither `flush()` nor `close()` calls `fsync`, so a power cut right after a save
can still lose the newest file. Check the returned `Error` and tell the player
when a save fails instead of carrying on.

### 3. Versioned load with migration

```python
SAVE_VERSION = 3

def load_save(raw_bytes):
    data = parse(raw_bytes)                  # JSON/binary -> independent dict
    v = read_version(data)                   # reject missing or invalid versions
    if v not in SUPPORTED_VERSIONS:
        raise UnsupportedSaveError(v)        # clearly refuse newer or retired saves
    validate_source(data, v)                 # validate before migration changes shape
    while v < SAVE_VERSION:                  # only explicitly supported migrations
        data = MIGRATIONS[v](data)
        v += 1
        data["version"] = v
    validate(data)                           # check required keys / ranges
    return construct_candidate(data)         # publish only after all validation

# Each migration is a pure function from one version's shape to the next.
def migrate_1_to_2(d):
    d["flags"] = {k: True for k in d.pop("completed_quests", [])}  # list -> set-map
    return d
def migrate_2_to_3(d):
    d.setdefault("difficulty", "normal")      # new field: old saves get the default
    return d
SUPPORTED_VERSIONS = {1, 2, 3}               # illustrative finite support window
MIGRATIONS = {1: migrate_1_to_2, 2: migrate_2_to_3}
```

### 4. Save slots + throttled autosave

```gdscript
const SLOT_PATH := "user://save_%d.json"      # manual slots 0..N
const AUTOSAVE_PATH := "user://autosave.json"  # separate file: never clobbers a slot
var _autosave_cooldown := 0.0

func autosave_if_due(dt: float) -> void:
    _autosave_cooldown -= dt
    if _autosave_cooldown <= 0.0:
        save_atomic(AUTOSAVE_PATH, capture_state())
        _autosave_cooldown = 60.0             # throttle: at most once a minute
# Trigger an immediate autosave on checkpoints/level transitions, not mid-combat.
```

## Pitfalls

- **Serializing engine objects/node paths** ties saves to scene structure;
  renaming a node breaks every old save. Save data, rebuild objects on load.
- **No version field.** The day you ship a patch, every existing save is a
  guessing game. Stamp `version` from version 1.
- **In-place writes** corrupt saves on crash/power loss. Always temp-write then
  rename; keep a `.bak`.
- **Trusting the file blindly.** Saves get truncated or hand-edited. Validate
  each independent candidate and preserve live state on failure; backup policy
  must not silently turn an unsupported version into a different history.
- **Floats and locale.** Text serializers can drop precision or use comma
  decimal separators in some locales. Use a locale-invariant serializer.
- **Godot JSON turns every number into a float**: `version` 3 loads as `3.0`,
  so `migrations.has(data["version"])` is false and integers above 2^53 (64-bit
  IDs, big seeds) lose digits. Convert with `int()` on load, store IDs as
  strings, or wrap the state in `JSON.from_native()` / `JSON.to_native()`, which
  round-trip `int`, `Vector2` and other engine types exactly.
- **Loading objects from save files.** Godot `str_to_var`/`get_var` with objects
  allowed, a `ConfigFile` that stores objects, or `ResourceLoader` on a `.tres`
  the player can swap will instantiate an object with a script attached, and that
  script runs during the load. Saves get shared online; keep them plain data.
- **Autosave clobbering manual saves**, or firing mid-action and saving an
  inconsistent state. Use a dedicated autosave slot and save on safe boundaries.
- **Storing secrets or trusting client saves in multiplayer.** A local save is
  player-controlled; never treat it as authoritative for online state. For cloud,
  handle the device's data limits and conflicts (`roblox-datastores`).

## References

- `references/versioning-and-migration.md` — schema evolution strategies, the
  supported migration boundary, backups/rollback, format trade-offs (JSON vs binary), a
  load-time validation checklist, and where saves live per engine plus Steam
  Cloud setup.

## Related skills

- `roblox-datastores` — cloud persistence, request limits, session locking.
- `godot-resources`, `unity-scriptableobjects` — the data model you serialize.
- `procedural-gen` — store the seed to regenerate worlds instead of saving them.
- `rpg`, `survival-crafting`, `visual-novel` — genres that compose this skill.
