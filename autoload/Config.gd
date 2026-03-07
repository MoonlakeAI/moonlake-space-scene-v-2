extends Node
## Global configuration for API endpoints.
## Registered as an autoload to be accessible from anywhere.

## Backend URL for desktop/local development
const LOCAL_BACKEND_URL := "http://127.0.0.1:8742"


## Get the backend base URL based on platform
func get_backend_url() -> String:
	if OS.has_feature("web"):
		# On web, backend is served from same origin
		return JavaScriptBridge.eval("window.location.origin")
	else:
		# Desktop/local development
		return LOCAL_BACKEND_URL


## Construct a full API URL for a given endpoint path
func api_url(endpoint: String) -> String:
	var base := get_backend_url()
	if endpoint.begins_with("/"):
		return base + endpoint
	else:
		return base + "/" + endpoint
