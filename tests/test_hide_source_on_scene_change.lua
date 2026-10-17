-- Timing rules for obs-scripts/hide-source-on-scene-change.lua.
-- Run from the repo root: lua5.1 tests/test_hide_source_on_scene_change.lua

local failures = 0

local function check(name, cond)
	if cond then
		io.write("ok  " .. name .. "\n")
	else
		failures = failures + 1
		io.write("FAIL " .. name .. "\n")
	end
end

local function near(actual, expected)
	return math.abs(actual - expected) < 0.0001
end

dofile("obs-scripts/hide-source-on-scene-change.lua")

local function fresh()
	return scene_hide_new(2000, 400, 400)
end

do
	local state = fresh()
	scene_hide_begin(state)
	check("fade out starts from fully visible", state.phase == "fade_out" and near(state.opacity, 1))

	scene_hide_step(state, 200)
	check("halfway through the fade out is half opacity", state.phase == "fade_out" and near(state.opacity, 0.5))

	scene_hide_step(state, 200)
	check("fade out ends fully hidden", state.phase == "hold" and near(state.opacity, 0))

	scene_hide_step(state, 1999)
	check("stays hidden for just under two seconds", state.phase == "hold" and near(state.opacity, 0))

	scene_hide_step(state, 1)
	check("fade in starts when the hidden time ends", state.phase == "fade_in" and near(state.opacity, 0))

	scene_hide_step(state, 200)
	check("halfway through the fade in", state.phase == "fade_in" and near(state.opacity, 0.5))

	scene_hide_step(state, 200)
	check("fade in ends fully visible", state.phase == "idle" and near(state.opacity, 1))
end

do
	local state = fresh()
	scene_hide_begin(state)
	scene_hide_step(state, 2800)
	check("one long step finishes the whole cycle", state.phase == "idle" and near(state.opacity, 1))
end

do
	local state = fresh()
	scene_hide_begin(state)
	scene_hide_step(state, 400)
	scene_hide_step(state, 1500)
	scene_hide_begin(state)
	check("another scene change restarts the hidden timer", state.phase == "hold" and near(state.elapsed_ms, 0))
	scene_hide_step(state, 1999)
	check("restarted hide still waits the full two seconds", state.phase == "hold")
	scene_hide_step(state, 1)
	check("restarted hide then fades in", state.phase == "fade_in")
end

do
	local state = fresh()
	scene_hide_begin(state)
	scene_hide_step(state, 2600)
	check("interrupted during fade in", state.phase == "fade_in" and state.opacity > 0 and state.opacity < 1)
	local partial = state.opacity
	scene_hide_begin(state)
	check("new scene change fades back out from the current opacity", state.phase == "fade_out" and near(state.fade_from, partial))
	scene_hide_step(state, 400)
	check("fade out from a partial opacity still reaches hidden", state.phase == "hold" and near(state.opacity, 0))
end

do
	local state = scene_hide_new(2000, 0, 0)
	scene_hide_begin(state)
	check("zero fades cut the source off", state.phase == "hold" and near(state.opacity, 0))
	scene_hide_step(state, 2000)
	check("zero fade in cuts the source back on", state.phase == "idle" and near(state.opacity, 1))
end

do
	local state = scene_hide_new(0, 400, 400)
	scene_hide_begin(state)
	scene_hide_step(state, 400)
	check("no hidden hold goes straight into the fade in", state.phase == "fade_in" and near(state.opacity, 0))
	scene_hide_step(state, 400)
	check("fade in completes with no hold", state.phase == "idle" and near(state.opacity, 1))
end

do
	local state = fresh()
	scene_hide_begin(state)
	scene_hide_step(state, -50)
	check("negative time does not move the fade", state.phase == "fade_out" and near(state.opacity, 1))
	scene_hide_show(state)
	check("show restores a full visible idle source", state.phase == "idle" and near(state.opacity, 1))
end

do
	local state = fresh()
	scene_hide_configure(state, -5, -10, -15)
	check("negative timings clamp to zero", state.off_ms == 0 and state.fade_out_ms == 0 and state.fade_in_ms == 0)
end

do
	local watch_state = { seen = false, last = nil }
	local action, pending = scene_hide_observe(watch_state, "")
	check("empty scene name is ignored", action == "ignore" and pending == nil)
	action, pending = scene_hide_observe(watch_state, "Intro")
	check("first scene is remembered", action == "remember" and pending == nil)
	action, pending = scene_hide_observe(watch_state, "Intro")
	check("same scene does not hide again", action == "ignore" and pending == nil)
	action, pending = scene_hide_observe(watch_state, "Gameplay")
	check("a new scene triggers", action == "trigger" and pending == "Gameplay")
	action, pending = scene_hide_observe(watch_state, nil)
	check("nil name does not replace the last scene", action == "ignore" and watch_state.last == "Intro")
	scene_hide_commit(watch_state, "Gameplay")
	action, pending = scene_hide_observe(watch_state, "Intro")
	check("returning to a scene triggers again", action == "trigger" and pending == "Intro")
end

if failures > 0 then
	io.write(string.format("%d test(s) failed\n", failures))
	os.exit(1)
end

io.write("all tests passed\n")
