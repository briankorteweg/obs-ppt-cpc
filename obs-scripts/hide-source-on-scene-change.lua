-- Fade a source out when the program scene changes, keep it hidden, then fade it back in.
--
-- Install in OBS:
--   1. Tools → Scripts → + (Add Scripts)
--   2. Select this file
--   3. Choose the source and the timing
--
-- OBS remembers the script path, so leave this file where you added it from.
-- The script adds a Color Correction filter named "Scene Change Hide" to the
-- chosen source and disables that filter while the source is fully visible.

local obs = obslua

local FILTER_NAME = "Scene Change Hide"
local DEFAULT_OFF_SECONDS = 2
local DEFAULT_FADE_OUT_MS = 400
local DEFAULT_FADE_IN_MS = 400

local enabled = true
local source_name = ""
local off_seconds = DEFAULT_OFF_SECONDS
local fade_out_ms = DEFAULT_FADE_OUT_MS
local fade_in_ms = DEFAULT_FADE_IN_MS
local scene_filter = ""
local mute_audio = false

local model = nil
local watch = { seen = false, last = nil }
local pushed_opacity = nil
local opacity_percent = nil
local mute_restore = nil
local missing_logged_for = nil
local tick_error_logged = false
local startup_restore = true
local ignore_scene_changes = false
local callback_added = false

local function smoothstep(t)
	if t <= 0 then
		return 0
	end
	if t >= 1 then
		return 1
	end
	return t * t * (3 - 2 * t)
end

function scene_hide_new(off_ms, fade_out, fade_in)
	return {
		phase = "idle",
		opacity = 1,
		elapsed_ms = 0,
		fade_from = 1,
		off_ms = math.max(0, off_ms),
		fade_out_ms = math.max(0, fade_out),
		fade_in_ms = math.max(0, fade_in),
	}
end

function scene_hide_configure(state, off_ms, fade_out, fade_in)
	state.off_ms = math.max(0, off_ms)
	state.fade_out_ms = math.max(0, fade_out)
	state.fade_in_ms = math.max(0, fade_in)
end

local function begin_fade_in(state)
	state.elapsed_ms = 0
	state.fade_from = state.opacity
	if state.fade_in_ms <= 0 then
		state.opacity = 1
		state.phase = "idle"
	else
		state.phase = "fade_in"
	end
end

function scene_hide_begin(state)
	state.elapsed_ms = 0
	state.fade_from = state.opacity
	if state.fade_out_ms <= 0 or state.opacity <= 0.0001 then
		state.opacity = 0
		state.phase = "hold"
		state.elapsed_ms = 0
		if state.off_ms <= 0 then
			begin_fade_in(state)
		end
	else
		state.phase = "fade_out"
	end
end

function scene_hide_show(state)
	state.opacity = 1
	state.phase = "idle"
	state.elapsed_ms = 0
	state.fade_from = 1
end

function scene_hide_step(state, dt_ms)
	if dt_ms == nil or dt_ms <= 0 or state.phase == "idle" then
		return
	end

	local guard = 0
	while dt_ms > 0 and state.phase ~= "idle" and guard < 5 do
		guard = guard + 1
		if state.phase == "fade_out" then
			if state.fade_out_ms <= 0 then
				state.opacity = 0
				state.elapsed_ms = 0
				state.phase = "hold"
				if state.off_ms <= 0 then
					begin_fade_in(state)
				end
			else
				local remain = state.fade_out_ms - state.elapsed_ms
				if dt_ms < remain then
					state.elapsed_ms = state.elapsed_ms + dt_ms
					local t = state.elapsed_ms / state.fade_out_ms
					state.opacity = state.fade_from * (1 - smoothstep(t))
					return
				end
				dt_ms = dt_ms - remain
				state.opacity = 0
				state.elapsed_ms = 0
				state.phase = "hold"
				if state.off_ms <= 0 then
					begin_fade_in(state)
				end
			end
		elseif state.phase == "hold" then
			if state.off_ms <= 0 then
				begin_fade_in(state)
			else
				local remain = state.off_ms - state.elapsed_ms
				if dt_ms < remain then
					state.elapsed_ms = state.elapsed_ms + dt_ms
					state.opacity = 0
					return
				end
				dt_ms = dt_ms - remain
				state.opacity = 0
				begin_fade_in(state)
			end
		elseif state.phase == "fade_in" then
			if state.fade_in_ms <= 0 then
				state.opacity = 1
				state.phase = "idle"
				state.elapsed_ms = 0
			else
				local remain = state.fade_in_ms - state.elapsed_ms
				if dt_ms < remain then
					state.elapsed_ms = state.elapsed_ms + dt_ms
					local t = state.elapsed_ms / state.fade_in_ms
					state.opacity = state.fade_from + (1 - state.fade_from) * smoothstep(t)
					return
				end
				dt_ms = dt_ms - remain
				state.opacity = 1
				state.phase = "idle"
				state.elapsed_ms = 0
			end
		else
			return
		end
	end
end

-- First observation records the current scene without hiding anything.
-- Later changes return "trigger". Blank names are ignored.
function scene_hide_observe(watch_state, scene_name)
	if scene_name == nil or scene_name == "" then
		return "ignore"
	end
	if not watch_state.seen then
		watch_state.seen = true
		watch_state.last = scene_name
		return "remember"
	end
	if scene_name == watch_state.last then
		return "ignore"
	end
	watch_state.last = scene_name
	return "trigger"
end

function scene_hide_allows(filter_text, scene_name)
	if filter_text == nil then
		return true
	end
	local trimmed = filter_text:match("^%s*(.-)%s*$")
	if trimmed == nil or trimmed == "" then
		return true
	end
	if scene_name == nil or scene_name == "" then
		return false
	end
	for token in string.gmatch(filter_text, "[^,\r\n]+") do
		local name = token:match("^%s*(.-)%s*$")
		if name == scene_name then
			return true
		end
	end
	return false
end

model = scene_hide_new(DEFAULT_OFF_SECONDS * 1000, DEFAULT_FADE_OUT_MS, DEFAULT_FADE_IN_MS)

local function log_info(message)
	if obs ~= nil then
		obs.script_log(obs.LOG_INFO, message)
	end
end

local function log_warning(message)
	if obs ~= nil then
		obs.script_log(obs.LOG_WARNING, message)
	end
end

local function with_source(name, fn)
	if obs == nil or name == nil or name == "" then
		return false
	end
	local source = obs.obs_get_source_by_name(name)
	if source == nil then
		return false
	end
	fn(source)
	obs.obs_source_release(source)
	return true
end

local function uses_percent_opacity(filter)
	if opacity_percent ~= nil then
		return opacity_percent
	end
	-- Color Correction v1 stores opacity as 0–100. v2 (OBS 28+) uses 0.0–1.0.
	local settings = obs.obs_source_get_settings(filter)
	local value = obs.obs_data_get_double(settings, "opacity")
	obs.obs_data_release(settings)
	if value > 1.5 then
		opacity_percent = true
		return true
	end
	if obs.obs_get_version ~= nil and math.floor(obs.obs_get_version() / 16777216) < 28 then
		opacity_percent = true
		return true
	end
	opacity_percent = false
	return false
end

local function write_opacity(filter, unit_opacity)
	local settings = obs.obs_source_get_settings(filter)
	if uses_percent_opacity(filter) then
		obs.obs_data_set_int(settings, "opacity", math.floor(unit_opacity * 100 + 0.5))
	else
		obs.obs_data_set_double(settings, "opacity", unit_opacity)
	end
	obs.obs_source_update(filter, settings)
	obs.obs_data_release(settings)
end

local function read_opacity(filter)
	local settings = obs.obs_source_get_settings(filter)
	local value = obs.obs_data_get_double(settings, "opacity")
	obs.obs_data_release(settings)
	if uses_percent_opacity(filter) then
		return value / 100
	end
	return value
end

local function ensure_filter(source)
	local filter = obs.obs_source_get_filter_by_name(source, FILTER_NAME)
	if filter ~= nil then
		return filter
	end
	filter = obs.obs_source_create("color_filter", FILTER_NAME, nil, nil)
	if filter == nil then
		log_warning("Could not create a Color Correction filter on '" .. source_name .. "'.")
		return nil
	end
	obs.obs_source_filter_add(source, filter)
	return filter
end

local function visible_opacity(source)
	local filter = obs.obs_source_get_filter_by_name(source, FILTER_NAME)
	if filter == nil or not obs.obs_source_enabled(filter) then
		if filter ~= nil then
			obs.obs_source_release(filter)
		end
		return 1
	end
	local value = read_opacity(filter)
	obs.obs_source_release(filter)
	return value
end

local function push_opacity(source, unit_opacity)
	if pushed_opacity ~= nil and math.abs(pushed_opacity - unit_opacity) < 0.001 then
		return
	end
	local filter = ensure_filter(source)
	if filter == nil then
		return
	end
	obs.obs_source_set_enabled(filter, true)
	write_opacity(filter, unit_opacity)
	obs.obs_source_release(filter)
	pushed_opacity = unit_opacity
end

local function release_mute(source)
	if mute_restore == nil then
		return
	end
	if not mute_restore then
		obs.obs_source_set_muted(source, false)
	end
	mute_restore = nil
end

local function hold_mute(source)
	if not mute_audio or mute_restore ~= nil then
		return
	end
	mute_restore = obs.obs_source_muted(source)
	if not mute_restore then
		obs.obs_source_set_muted(source, true)
	end
end

local function show_source(source)
	local filter = obs.obs_source_get_filter_by_name(source, FILTER_NAME)
	if filter ~= nil then
		write_opacity(filter, 1)
		obs.obs_source_set_enabled(filter, false)
		obs.obs_source_release(filter)
	end
	pushed_opacity = nil
	release_mute(source)
end

local function apply_model(source)
	if model.phase == "idle" then
		show_source(source)
	else
		push_opacity(source, model.opacity)
		hold_mute(source)
	end
end

local function restore_source(name)
	with_source(name, function(source)
		show_source(source)
	end)
	scene_hide_show(model)
	pushed_opacity = nil
end

local function preview_scene_name()
	if obs.obs_frontend_preview_program_mode_active == nil then
		return nil
	end
	if not obs.obs_frontend_preview_program_mode_active() then
		return nil
	end
	local preview = obs.obs_frontend_get_current_scene()
	if preview == nil then
		return nil
	end
	local name = obs.obs_source_get_name(preview)
	obs.obs_source_release(preview)
	return name
end

-- The program transition points at the destination scene as soon as a
-- transition starts, which is earlier than the frontend "scene changed"
-- event (that fires when the transition finishes). Reading it every frame
-- also covers studio mode, scene transition overrides, and hard cuts.
local function program_scene_name()
	if obs == nil then
		return nil
	end
	local output = obs.obs_get_output_source(0)
	if output == nil then
		return nil
	end
	local active = obs.obs_transition_get_active_source(output)
	obs.obs_source_release(output)
	if active == nil then
		return nil
	end
	local name = obs.obs_source_get_name(active)
	obs.obs_source_release(active)
	if name ~= nil and name ~= "" then
		return name
	end
	return preview_scene_name()
end

local function start_cycle(scene_name_now)
	if source_name == nil or source_name == "" then
		return
	end
	local found = with_source(source_name, function(source)
		model.opacity = visible_opacity(source)
		scene_hide_begin(model)
		apply_model(source)
	end)
	if not found then
		if missing_logged_for ~= source_name then
			missing_logged_for = source_name
			log_warning("Source not found: " .. source_name)
		end
		return
	end
	missing_logged_for = nil
	log_info(string.format(
		"Scene '%s': hiding '%s' for %.2f s (fade out %d ms, fade in %d ms)",
		scene_name_now,
		source_name,
		off_seconds,
		fade_out_ms,
		fade_in_ms
	))
end

local function react_to_scene(scene_name_now)
	if not enabled or source_name == nil or source_name == "" then
		return
	end
	if not scene_hide_allows(scene_filter, scene_name_now) then
		if model.phase ~= "idle" then
			restore_source(source_name)
		end
		return
	end
	start_cycle(scene_name_now)
end

local function poll_scene()
	if ignore_scene_changes then
		return
	end
	local action = scene_hide_observe(watch, program_scene_name())
	if action == "trigger" then
		react_to_scene(watch.last)
	end
end

-- A previous run can quit while the filter is still hiding the source.
-- Put it back once the source exists. Keep trying until OBS has finished
-- loading if the source is not available on the first tick.
local function restore_after_startup()
	if not startup_restore or source_name == nil or source_name == "" then
		return
	end
	local found = with_source(source_name, function(source)
		show_source(source)
	end)
	if found or watch.seen then
		startup_restore = false
	end
end

local function advance(seconds)
	if model.phase == "idle" then
		if mute_restore ~= nil then
			with_source(source_name, function(source)
				show_source(source)
			end)
		end
		return
	end
	scene_hide_step(model, (seconds or 0) * 1000)
	with_source(source_name, function(source)
		apply_model(source)
	end)
end

local function describe(property, text)
	if property ~= nil and obs ~= nil and obs.obs_property_set_long_description ~= nil then
		obs.obs_property_set_long_description(property, text)
	end
end

local function collect_source_names()
	local names = {}
	local function add_list(list)
		if list == nil then
			return
		end
		pcall(function()
			for _, source in ipairs(list) do
				local name = obs.obs_source_get_name(source)
				if name ~= nil and name ~= "" then
					names[name] = true
				end
			end
		end)
		pcall(obs.source_list_release, list)
	end

	add_list(obs.obs_enum_sources())
	if obs.obs_frontend_get_scenes ~= nil then
		local ok, scenes = pcall(obs.obs_frontend_get_scenes)
		if ok then
			add_list(scenes)
		end
	end

	local ordered = {}
	for name in pairs(names) do
		ordered[#ordered + 1] = name
	end
	table.sort(ordered, function(a, b)
		return a:lower() < b:lower()
	end)
	return ordered
end

function script_description()
	return "When the program scene changes, fade out one source, keep it fully hidden, then fade it back in.\n\n"
		.. "Hidden duration is how long the source stays fully invisible (2 seconds by default). "
		.. "Fade out and fade in are extra and can be 0 for a hard cut.\n\n"
		.. "Leave the scene list blank to do this on every scene change, or enter scene names separated by commas. "
		.. "Preview changes in studio mode are ignored. "
		.. "Check mute only if this source's audio should go silent while it is hidden.\n\n"
		.. "A Color Correction filter named \"" .. FILTER_NAME .. "\" is added to the source. "
		.. "Leave that filter on the source; it is turned off while the source is fully visible. "
		.. "OBS does not apply Color Correction to HDR sources, so the fade will not show on those."
end

function script_properties()
	local props = obs.obs_properties_create()

	obs.obs_properties_add_bool(props, "enabled", "Enabled")

	local source_list = obs.obs_properties_add_list(
		props,
		"source",
		"Source",
		obs.OBS_COMBO_TYPE_EDITABLE,
		obs.OBS_COMBO_FORMAT_STRING
	)
	for _, name in ipairs(collect_source_names()) do
		obs.obs_property_list_add_string(source_list, name, name)
	end
	describe(source_list, "The source to fade out on a scene change. You can type a name that is not in the list, such as a group.")

	local hidden = obs.obs_properties_add_float_slider(
		props,
		"off_seconds",
		"Hidden duration (seconds)",
		0,
		60,
		0.1
	)
	describe(hidden, "How long the source stays fully invisible after the fade out. This does not include the fades.")

	local fade_out = obs.obs_properties_add_int_slider(
		props,
		"fade_out_ms",
		"Fade out (milliseconds)",
		0,
		5000,
		50
	)
	describe(fade_out, "How long the source takes to fade from visible to hidden. 0 cuts it off.")

	local fade_in = obs.obs_properties_add_int_slider(
		props,
		"fade_in_ms",
		"Fade in (milliseconds)",
		0,
		5000,
		50
	)
	describe(fade_in, "How long the source takes to fade back in. 0 cuts it back on.")

	local scenes = obs.obs_properties_add_text(
		props,
		"scenes",
		"Only these scenes",
		obs.OBS_TEXT_DEFAULT
	)
	describe(scenes, "Comma-separated scene names. Blank means every program scene change.")

	local mute = obs.obs_properties_add_bool(props, "mute_audio", "Mute audio while hidden")
	describe(mute, "Also silence this source until it has faded back in. A source that was already muted stays muted.")

	return props
end

function script_defaults(settings)
	obs.obs_data_set_default_bool(settings, "enabled", true)
	obs.obs_data_set_default_double(settings, "off_seconds", DEFAULT_OFF_SECONDS)
	obs.obs_data_set_default_int(settings, "fade_out_ms", DEFAULT_FADE_OUT_MS)
	obs.obs_data_set_default_int(settings, "fade_in_ms", DEFAULT_FADE_IN_MS)
	obs.obs_data_set_default_string(settings, "scenes", "")
	obs.obs_data_set_default_bool(settings, "mute_audio", false)
end

function script_update(settings)
	local previous_source = source_name
	local was_enabled = enabled
	local was_mute = mute_audio

	enabled = obs.obs_data_get_bool(settings, "enabled")
	source_name = obs.obs_data_get_string(settings, "source") or ""
	off_seconds = obs.obs_data_get_double(settings, "off_seconds")
	fade_out_ms = obs.obs_data_get_int(settings, "fade_out_ms")
	fade_in_ms = obs.obs_data_get_int(settings, "fade_in_ms")
	scene_filter = obs.obs_data_get_string(settings, "scenes") or ""
	mute_audio = obs.obs_data_get_bool(settings, "mute_audio")

	scene_hide_configure(model, off_seconds * 1000, fade_out_ms, fade_in_ms)

	if previous_source ~= nil and previous_source ~= "" and previous_source ~= source_name then
		restore_source(previous_source)
		with_source(source_name, function(source)
			show_source(source)
		end)
	end
	if was_enabled and not enabled then
		restore_source(source_name)
	end
	if was_mute and not mute_audio then
		with_source(source_name, function(source)
			release_mute(source)
		end)
	end
end

local function on_frontend_event(event)
	local changing = obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGING
	local cleanup = obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CLEANUP
	local changed = obs.OBS_FRONTEND_EVENT_SCENE_COLLECTION_CHANGED
	if event == changing or event == cleanup then
		ignore_scene_changes = true
		restore_source(source_name)
	elseif event == changed then
		watch.seen = false
		watch.last = nil
		ignore_scene_changes = false
	end
end

function script_load(settings)
	watch.seen = false
	watch.last = nil
	tick_error_logged = false
	if not callback_added then
		obs.obs_frontend_add_event_callback(on_frontend_event)
		callback_added = true
	end
end

function script_unload()
	if callback_added then
		obs.obs_frontend_remove_event_callback(on_frontend_event)
		callback_added = false
	end
	restore_source(source_name)
end

function script_tick(seconds)
	if obs == nil then
		return
	end
	local ok, err = pcall(function()
		poll_scene()
		restore_after_startup()
		advance(seconds)
	end)
	if not ok and not tick_error_logged then
		tick_error_logged = true
		log_warning("Scene hide stopped after an error: " .. tostring(err))
	end
end
