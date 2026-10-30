--[[
    InlineBaleShutdown.lua -- quitting a savegame that has an inline bale (a chain of bales on a string) can fail with "invalid key to 'next'" and hang the game
    until it is force-closed. Details and the suggested game fix: docs/INLINE_BALE_SHUTDOWN.md.

    The server deletes its objects in a loop (NetworkNode:delete: for _, object in pairs(self.objects) do ... object:delete() end). Deleting a bale of an inline
    bale calls InlineBale:onBaleDeleted -> openBale, which makes new Bale objects and registers them (new keys in the table being walked) and deletes the neighbours.
    When the table happens to need more room, the walk breaks. Whether it does depends on the object count, so a save works on one day and not the next.

    The chain has nothing left to re-link when the whole session is being deleted, so while the network node is deleting, onBaleDeleted does nothing.
]]
InlineBaleShutdown = {}

local function closing(node)
    return node ~= nil and node.rfClosing == true
end

function InlineBaleShutdown.isClosing()
    return closing(g_server) or closing(g_client)
end

if NetworkNode ~= nil and NetworkNode.delete ~= nil and InlineBale ~= nil and InlineBale.onBaleDeleted ~= nil and Utils ~= nil
    and not InlineBaleShutdown.hooked then
    InlineBaleShutdown.hooked = true
    -- the flag lives on the node (a new session makes a new node), so there is nothing to reset
    NetworkNode.delete = Utils.prependedFunction(NetworkNode.delete, function(self)
        self.rfClosing = true
    end)
    InlineBale.onBaleDeleted = Utils.overwrittenFunction(InlineBale.onBaleDeleted, function(self, superFunc, ...)
        if InlineBaleShutdown.isClosing() then
            return
        end
        return superFunc(self, ...)
    end)
    print("[RandomFixes] inline bales: not re-linked while the session is being deleted (quit)")
end
