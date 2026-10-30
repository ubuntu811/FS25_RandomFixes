# Quitting a savegame with an inline bale: "invalid key to 'next'" (NetworkNode:delete)

**Status:** diagnosed from three game logs and the game scripts; fixed in this mod (`scripts/InlineBaleShutdown.lua`), offline tests only (9 checks, a fake engine);
**not yet confirmed in the running game.**
**Game version:** FS25 as installed 2026-10-30, scripts as read from the game archive.

## Symptom

Leaving to the main menu (Save, then Quit) ends with this in `log.txt`, and the game hangs until it is force-closed (`Application exit request forced`, seconds later):

```
Warning: Unable to find bale material 'wrapBale'            (a few pairs of these)
Error: Running LUA method 'mouseEvent'.
invalid key to 'next'
dataS/scripts/network/NetworkNode.lua:96 function delete
dataS/scripts/network/Server.lua:41 function delete
dataS/scripts/BaseMission.lua:200 function delete
...
dataS/scripts/gui/InGameMenu.lua:494 function leaveCurrentGame
```

It was seen at the end of three sessions on the same savegame (2026-10-29 22:12, 2026-10-30 12:36 and 12:41). The sessions before (2026-10-20 ... 2026-10-29 21:33, same
savegame) ended normally, **with the same bale warnings**, so it is not new code that broke it: it depends on how many objects exist when the game quits.

Not a regression of the 10-28 game update: the scripts in the stack (`NetworkNode`, `Server`, `Object`, `Bale`, `InlineBale`) decompile identically from the installed archive
(changed 2026-10-28 22:34) and from an older unpack, the engine build is the same in the logs from before and after, and eight quits after the update were clean. A changed data
file (bale definitions) is not ruled out, but the mechanism below does not need one.

## Root cause

`NetworkNode:delete` walks the object table and deletes every object:

```lua
for _, object in pairs(self.objects) do
    self:unregisterObject(object, true)
    object:delete()
end
```

Deleting a **bale that belongs to an inline bale** calls the inline bale's delete listener (`bale:addDeleteListener(self, "onBaleDeleted")`):

```
NetworkNode:delete -> Bale:delete -> ... -> Object:delete -> InlineBale:onBaleDeleted -> InlineBale:openBale
```

`openBale` is made for a running game, where the chain has to be cut and the neighbouring bales kept: it creates a new `Bale` (`Bale.new`, `loadFromConfigXML`, `newBale:register()`
= **a new key in the table the loop is walking**) and deletes the old one. The log shows exactly this on a good quit: the stack of the "Unable to find bale material" warnings
runs `NetworkNode.lua:98 delete -> Bale:delete -> InlineBale:onBaleDeleted -> InlineBale:openBale -> InlineBale:delete -> ItemSystem:removeItem`.

Adding a key to a table during `pairs` is undefined in Lua. Most of the time the new key fits in the existing room and nothing happens; when the table has to grow (rehash), the next
`next(table, key)` fails with `invalid key to 'next'`. Which day that is depends on the number of objects. The error is raised inside the quit button's callback, so the mission is
never finished deleting and the game stays up in a half-deleted state.

## Suggested change for the game

Either of these, the first is smaller:

* In `InlineBale:onBaleDeleted`, return early when the session is being deleted (nothing needs re-linking; everything is going away).
* Make `NetworkNode:delete` independent of what `object:delete()` does: take a snapshot of the objects first (and repeat while new ones appeared), instead of `pairs` over the live table.

## What this mod does

Marks the network node (`self.rfClosing = true`, a prepended `NetworkNode.delete`) and makes `InlineBale.onBaleDeleted` do nothing while `g_server` or `g_client` is marked. The flag lives on
the node, so a new session starts clean. Nothing else about inline bales changes in a running game.

Side effect: the inline bale objects that are deleted during the quit are not re-linked, which is invisible since the savegame was written before and everything is deleted anyway.

## Verification status

* Offline: 9 checks (flag set during the base delete, the listener silent while closing, running again in a new session, client counted, no nodes at all).
* **Not seen in the game yet:** restart, load the savegame that failed, quit. The log should show `[RandomFixes] inline bales: ...` at start and no `invalid key to 'next'` at the end.
* Not checked: whether the old inline bale object is left in a state that matters for a save made *after* the quit (there is none: the save is written before the quit).
