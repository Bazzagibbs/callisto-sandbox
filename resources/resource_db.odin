package callisto_resource_db

import "../callisto"
import "../callisto/common"

model_id :: enum {
    suzanne,
    z_up_basis,
    lanternpole_body,
    lanternpole_chain,
    lanternpole_lantern,
}


//                         vvvv  Maybe this could be distinct per gali type
models :: [model_id]common.Uuid {
    .suzanne = 2141239479862346002, // TODO: generate from file header
}


// Editor: "unique name" field when name is already in asset db
// And/or have several enums/arrays for each asset pack
//
// Changing asset pack is an intentional action, in-editor


// UUID in asset file justification:
// - User can move the asset to different directory - not reliant on file system
// - Strongly typed references, static analysis with basic editor tools
// - Same API for debug and release builds
//      - debug: file system lookup from non-checked-in file path dictionary
//      - release: asset pack lookup from manifest
