@tool
extends Control

## Terrain Root - Container for terrain creation interface
##
## Holds references to plugin and python_bridge passed from create_dock

var plugin_ref = null  # EditorPlugin reference
var python_bridge = null  # PythonBridge reference
