-- plain Lua: the hooks round NetworkNode.delete and InlineBale.onBaleDeleted
local passed, failed = 0, 0
local function check(name, ok)
    if ok then passed = passed + 1 else failed = failed + 1; print("  FAIL " .. name) end
end

Utils = {
    prependedFunction = function(old, new) return function(...) new(...); return old(...) end end,
    overwrittenFunction = function(old, new) return function(self, ...) return new(self, old, ...) end end,
}
local walked = {}
NetworkNode = { delete = function(self) walked[#walked + 1] = "delete" end }
InlineBale = { onBaleDeleted = function(self, bale) self.opened = (self.opened or 0) + 1; return "opened" end }
g_server, g_client = { }, { }

dofile("scripts/InlineBaleShutdown.lua")

local chain = {}
check("running game: the chain is re-linked as before", InlineBale.onBaleDeleted(chain, "b") == "opened" and chain.opened == 1)

-- the server starts deleting: the base delete runs (here a fake) and a bale deleted meanwhile does not open anything
local seen
NetworkNode.delete = (function(old) return function(self) seen = InlineBaleShutdown.isClosing(); return old(self) end end)(NetworkNode.delete)
check("not closing before the delete", InlineBaleShutdown.isClosing() == false)
NetworkNode.delete(g_server)
check("the base delete still runs", #walked == 1)
check("during and after the delete the node is marked", g_server.rfClosing == true and InlineBaleShutdown.isClosing())
check("a bale deleted while closing opens nothing", InlineBale.onBaleDeleted(chain, "b") == nil and chain.opened == 1)

-- a new session: new nodes, the flag is gone
g_server, g_client = { }, { }
check("a new session: not closing", InlineBaleShutdown.isClosing() == false)
check("... and the chain is re-linked again", InlineBale.onBaleDeleted(chain, "b") == "opened" and chain.opened == 2)

-- a client that is deleted first (multiplayer client leaving)
g_client.rfClosing = true
check("the client closing counts too", InlineBaleShutdown.isClosing() and InlineBale.onBaleDeleted(chain, "b") == nil)
g_server, g_client = nil, nil
check("no nodes at all: not closing, no error", InlineBaleShutdown.isClosing() == false)

print(string.format("inline_bale_shutdown_test: %d/%d passed", passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
