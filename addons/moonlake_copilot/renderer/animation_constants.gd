@tool
extends RefCounted

## AnimationConstants
##
## Shared constants for typewriter animation across all renderers.
## Centralizes animation timing and buffering settings.

## Character typing speed (seconds per character) - SOURCE OF TRUTH
const CHAR_DELAY = 0.05  # 20 chars/sec

## Typewriter animation speed (characters revealed per second)
const CHARS_PER_SEC = 1.0 / CHAR_DELAY  # 20.0 (slow - for empty state)

## Fast typewriter speed for message rendering (characters per second)
const FAST_CHARS_PER_SEC = 200.0  # 200 chars/sec (for text, thinking, tool streaming)

## Timer update interval (60fps = 16ms)
const TIMER_INTERVAL = 0.016

## Characters revealed per frame (calculated from slow speed)
const CHARS_PER_FRAME = CHARS_PER_SEC * TIMER_INTERVAL  # ~0.33 chars/frame

## Fast characters revealed per frame (for message rendering)
const FAST_CHARS_PER_FRAME = FAST_CHARS_PER_SEC * TIMER_INTERVAL  # ~1.6 chars/frame

## Maximum buffer size for streaming content (10KB)
const MAX_BUFFER_SIZE = 10 * 1024

## Empty State Animation Settings (pause/fade only, typing speed uses CHAR_DELAY)
## Pause duration after completing a prompt (seconds)
const EMPTY_STATE_PAUSE_DURATION = 2.0

## Fade out duration between prompts (seconds)
const EMPTY_STATE_FADE_DURATION = 0.5

## Minimum time a collapsible widget must stay expanded before auto-collapse (seconds)
const MIN_EXPAND_DURATION = 2.0

## Collapsible Widget Heights
## Height when widget is collapsed (header only)
const COLLAPSED_HEIGHT = 40.0

## Minimum height when widget is expanded (prevents too-small widgets)
const MIN_EXPANDED_HEIGHT = 100.0
