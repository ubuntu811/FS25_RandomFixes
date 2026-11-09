local passed, failed = 0, 0
local function check(name, ok) if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end end
local realPrint = print; print = function() end
dofile("scripts/TurnRadiusDump.lua")
check("the tractor's steering radius gets the 10 percent", math.abs(TurnRadiusDump.combine(6, nil, {}) - 6.6) < 1e-9)
check("the root's own minimum wins when larger", TurnRadiusDump.combine(6, 9, {}) == 9)
check("the worst tool wins when larger", TurnRadiusDump.combine(6, 7, { 8, 12, 3 }) == 12)
check("never below 2.5", TurnRadiusDump.combine(1, nil, {}) == 2.5 and TurnRadiusDump.combine(nil, nil, {}) == 2.5)
check("no vehicle: a hint, not an error", TurnRadiusDump.run():find("sit in the tractor") ~= nil)
print = realPrint
print(string.format("turn_radius_dump_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
