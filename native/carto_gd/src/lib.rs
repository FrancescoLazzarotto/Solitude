use godot::prelude::*;

struct CartoExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CartoExtension {}
