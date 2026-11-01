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

## Second cause: the preparer's own list loses crops (found with a potato field, 2026-10-31)

**Symptom:** the multifruit header of FS25_harvestgiant (`rmf9R`, preparer listing `sugarBeet potato sugarCane beetroot`) is fine by hand on a potato field in state "Remove foliage" (growth state 6), but the AI helper stops with the same "field not ready for this work or already worked". The first fix did not help for potatoes: its log line listed only the cutter-only crops, and it skipped every crop the preparer lists.

**Cause (current game archive, `FruitPreparer.onLoad` and `AIImplement`):** for each crop in the preparer's list that has a preparing state (potato haulm, beet leaves), the game calls `setAIFruitRequirements`, and `AIImplement:setAIFruitRequirements` is `clearAIFruitRequirements()` followed by `addAIFruitRequirement`. So each such crop clears whatever the crops before it put into the AI list. With several crops only the last crop with a preparing state is left (and the crops after it that have none). A single-crop header (`rmf9RP`, potato only) is fine, which is why the bug hides in the multifruit one.

**Suggested game change:** `setAIFruitRequirements` should only be called for the first crop (or the loop should `addAIFruitRequirement` for the later ones).

**What this mod does:** for every crop the preparer lists, it checks the AI list for what `FruitPreparer` meant to add (the preparing states, and the prepared state when `aiUsePreparedState` is on, which is the default for a vehicle with a cutter; any other crop its harvest states) and adds what is missing. Nothing is cleared or changed. Logged once per vehicle xml.

**Status:** offline tests only (25 checks, with a fixture that loses a crop the way the game does); not yet seen in the game. After a restart the log should show the potato entries (`POTATO 6-6, POTATO 7-7`, and the same for the other crops that lost theirs) for `rmf9R.xml`, and `rfAiCrops` should list them. The helper's other conditions (the field's growth state matching) are unchanged.

## The probe (`rfAiCrops`)

When the helper stops with "field not ready for this work or already worked", the console command `rfAiCrops` (stand in the field, next to the machine) writes to the log and the console what the helper is told to harvest for every vehicle and implement within 40 m (its AI crop list with the growth states it accepts, and whether the cutter's own list is on), and what the ground under you is: the crop, its growth state, and whether that is inside the crop's harvest window ("NOT RIPE YET", "PAST the harvest window"). That tells a header that does not list a crop apart from a field that is not ready, or already harvested.
