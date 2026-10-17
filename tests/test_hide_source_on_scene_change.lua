-- Timing and scene-matching rules for obs-scripts/hide-source-on-scene-change.lua.
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
	check("blank scene list matches every scene", scene_hide_allows("", "Cam"))
	check("whitespace scene list matches every scene", scene_hide_allows("   ", "Cam"))
	check("nil scene list matches every scene", scene_hide_allows(nil, "Desk"))
	check("listed scene matches exactly", scene_hide_allows("Cam, BRB", "BRB"))
	check("listed scene trims spaces", scene_hide_allows(" Cam , BRB ", "Cam"))
	check("unlisted scene does not match", not scene_hide_allows("Cam, BRB", "Desk"))
	check("partial names do not match", not scene_hide_allows("Cam", "Camera"))
	check("newline separated scenes match", scene_hide_allows("Cam\nDesk", "Desk"))
end

do
	local watch_state = { seen = false, last = nil }
	check("empty scene name is ignored", scene_hide_observe(watch_state, "") == "ignore")
	check("first scene is remembered", scene_hide_observe(watch_state, "Intro") == "remember")
	check("same scene does not hide again", scene_hide_observe(watch_state, "Intro") == "ignore")
	check("a new scene triggers", scene_hide_observe(watch_state, "Gameplay") == "trigger")
	check("nil name does not replace the last scene", scene_hide_observe(watch_state, nil) == "ignore" and watch_state.last == "Gameplay")
	check("returning to a scene triggers again", scene_hide_observe(watch_state, "Intro") == "trigger")
end

do
	check("blocked when scene not allowed", not scene_hide_should_trigger(true, true, false))
	check("blocked when source not in scene", not scene_hide_should_trigger(true, false, true))
	check("runs when allowed and in scene", scene_hide_should_trigger(true, true, true))
	check("legacy off still runs without in-scene check", scene_hide_should_trigger(false, false, true))
end

if failures > 0 then
	io.write(string.format("%d test(s) failed\n", failures))
	os.exit(1)
end

io.write("all tests passed\n")
