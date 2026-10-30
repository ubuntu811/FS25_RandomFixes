# AI helper only knows the preparer's crops on a header with a cutter and a fruit preparer

**Status:** diagnosed from the game scripts and the XML of the mod where it was seen; fixed in this mod (`scripts/PreparerCrops.lua`), 14 offline checks (a fake engine);
**confirmed in the running game (2026-10-30): the AI helper works the pea field with the multifruit header, without touching the other mod.**
**Game version:** FS25 as installed 2026-10-30, scripts as read from the game archive.

## Symptom

A multi-crop harvester header (mod `FS25_harvestgiant`, "RMF9R for Multifruit": cutter `sugarBeet potato sugarCane carrot parsnip beetroot pea spinach greenBean onion`, fruit preparer
`sugarBeet potato sugarCane beetroot`) harvests peas by hand without trouble. Starting the AI helper on a pea field stops it at once:
`AI worker has stopped work unexpectedly - field not ready for this work or already worked!` (`ai_messageErrorFieldNotReady`). The same header's other variants, where the
preparer lists the same crops as the cutter, do not have the problem; harvesters without a preparer do not either.

## Cause

* The AI helper plans a field course from the crops the vehicle's implements say they work (`AIImplement` `requiredFruitTypes`, turned into a `FieldCropsQuery`). When the
  course has no segments, `AIDriveStrategyFieldCourse:onFieldCourseLoadedCallback` stops the job with `AIMessageErrorFieldNotReady`.
* The cutter fills that list in `Cutter:onAIImplementStart` (every crop it takes) and updates it after working. `FruitPreparer` overrides `getAllowCutterAIFruitRequirements` to return
  `false`, which switches **both** off for any vehicle that also has the fruit preparer specialization.
* What is left is what `FruitPreparer:onLoad` adds from its own `fruitTypes`. A crop the cutter takes but the preparer does not list is never in the list, the pea field has
  nothing the AI recognises as workable, and the course comes out empty.

## Suggested change for the game

Make the override per crop instead of all-or-nothing: the preparer keeps the requirements for its own crops, and the cutter adds the rest (what `onAIImplementStart` does for a header
without a preparer). Or, in `FruitPreparer:getAllowCutterAIFruitRequirements`, return `true` when the cutter's crops are not all in the preparer's list.

## What this mod does

After a vehicle has loaded (`AIImplement:onPostLoad`, so every specialization has read its XML, whichever mod the vehicle comes from), when the vehicle has a cutter and a fruit preparer
and the cutter's own AI list is switched off, each crop the cutter takes that neither the preparer lists nor the AI already has is added with the cutter's normal harvest growth states
(`minHarvestingGrowthState`, or `minForageGrowthState` for a forage cutter, to `maxHarvestingGrowthState`). The list is not touched later by the game in that case (the update after working is
switched off by the same override), so the addition stays. One log line per vehicle xml names the crops that were added. Nothing changes for a vehicle where the cutter's own list is on or where
the preparer lists everything. `PreparerCrops.ENABLED = false` switches it off.

Not done (as the cutter does for its list): no check that the combine can take that crop at the moment; that depends on what is in the tank, which a start-up patch cannot know.

## Verification status

* Offline: 14 checks (crops added with the right growth states, no duplicates on a second run, nothing when the preparer lists everything / the cutter manages itself / there is no preparer
  or cutter / the function is gone after a game update, forage states, unknown crop skipped, switched off, an error inside is caught).
* Read in the game scripts: events are raised as `spec[eventName](object, ...)`, so the patched `AIImplement.onPostLoad` runs; the requirement list is not rewritten after load when the cutter's
  list is off.
* **Seen in the game:** the AI helper with the multifruit header on a pea field works.
* Open: whether the preparer defoliating a crop it does not list changes anything for the AI is not examined; by hand the header already works on those crops.
