class_name DownloadConfig
extends RefCounted

# HTTPRequestPool Configuration (for UI image loading)
const UI_IMAGE_LOAD_TIMEOUT: float = 100.0  # Timeout for loading images in UI (multiple choice, etc.)
const HTTP_POOL_CLEANUP_DELAY: float = 60.0  # Idle time before cleaning up HTTPRequest nodes

# Asset Download Timeouts (for large files from S3)
const DOWNLOAD_TIMEOUT_PER_ATTEMPT: float = 120.0  # Single download attempt timeout
const DOWNLOAD_MAX_TOTAL_TIMEOUT: float = 600.0  # Total timeout across all retries

# Retry Configuration
const RETRY_MAX_ATTEMPTS: int = 3  # Maximum retry attempts for failed downloads
const RETRY_BACKOFF_DELAYS: Array[float] = [10.0, 20.0, 40.0]  # Exponential backoff delays between retries

# Worker Pool Configuration
const WORKER_POOL_SIZE: int = 6  # Number of concurrent download workers
const WORKER_DEBUG_DELAY: float = 0.0  # Artificial delay for testing progress UI

# Debug Configuration
const DEBUG_FORCE_MESH_DOWNLOAD_FAILURE: bool = false  # Force all mesh downloads to fail (for testing error cylinders)
const UPLOAD_DEBUG_DELAY: float = 0.0  # Artificial delay for testing upload progress UI (0.0 to disable)
const MESSAGE_RESPONSE_DEBUG_DELAY: float = 0.0  # Artificial delay for all message responses (for testing waiting messages, 0.0 to disable)
