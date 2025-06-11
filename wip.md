# Work in progress

### Content browser

- Navigate the raw content directories
- File types that generate multiple assets can have an "expand" icon
- Selecting a raw file reveals its import metadata menu


### Asset database

- Manifest stores locations of assets on disk
    - Map UUID -> (type, path, (offset?))
    - Also store refcount?
- Lookaside maps
    - addressable -> UUID
- Batched load/unload
    - load_batch_begin()
    - Provide a scene, UUID, list of UUID to unload
    - Provide a scene, UUID, list of UUID to load
    - load_batch_end()
    - Perform any refcount increments then decrements. Tag any "dirty" refcounters that need to be loaded/unloaded.
    - Iterate over asset db and resolve the dirty assets.
    - Any handles returned are not valid until load_batch_end() returns (or semaphore/mutex for async?)


### Scene authoring

- Entity definitions, variants?
- Entity instances/spawners in scenes
    - Name
    - Pos/rot/scale
    - Definition UUID
- Model editor
- Level brushes?
    - BSP
    - Heightmap
    - Triggers


### Gizmos

- Line
- Circle
- Rectangle
- Capsule
- Cube


### Editor actions

Command pattern?
- g: Grab (move)
- r: Rotate
- s: Scale
- x: Delete
