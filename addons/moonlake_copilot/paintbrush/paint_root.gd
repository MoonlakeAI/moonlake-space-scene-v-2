@tool
extends Control

## Paint Root - Container for paintbrush interface
##
## Holds references to plugin and python_bridge passed from create_dock

var plugin_ref = null  # EditorPlugin reference
var python_bridge = null  # PythonBridge reference
