# Retail Professions

An [AzerothCore](https://www.azerothcore.org/) (WotLK 3.3.5a) module and addon that replace the
old trade skill window with a **retail-style profession window**, in the spirit of WoW Forever's:
one clear window with search, filters and skill-up odds, recipes you haven't learned yet and
where to get them, a recipe tracker and a professions book on **K**.

Crafting itself doesn't change. Every craft is the client's own `DoTradeSkill`, so skill-ups,
cooldowns, discoveries and other modules' hooks behave as before. The server adds two things
of its own: **Milling and Prospecting** from the window, which the client can only do one stack
and one loot window at a time, and retail's crafting stats, **Multicraft, Resourcefulness and
crafting speed**, earned by skill.

## What players get

**The profession window**
- **Profession tabs** down the right edge, like the spellbook: switch between your professions without the spellbook. With ArchaeologyUI loaded, Archaeology has one too; it opens the research view as a page of this window (races in the list column, the project on the card, your skill on the bar), as DragonUI's window does, the profession staying open behind it. An ArchaeologyUI older than 0.4.0 opens its own research window in place of this one.
- The profession's **portrait**, a **skill bar** across the window ("Blacksmithing 24/75", with a bonus
  from equipment, racials or a lure in green as the Skills tab writes it: "300 (+15)/300"; hover
  it for your rank and the skill you count as) and a **chat link** button that shows everyone your recipes.
- **Search** (the box at the top of the list) matches recipe names and **reagents** ("silk" finds
  everything made from silk); recipes found by name come first, then the ones that use it. Hover
  the box for a reminder.
- **Filters**: Have materials, Has skill-up, Slot (head, chest, weapon ...; for enchants, the
  slot they go on), Show unlearned recipes, Only ones I can learn now, Count the reagent bank, plus expand / collapse all.
- Recipes sit under gold category bars that fold. Each has a **skill-up chevron** in its colour
  (orange = sure, yellow = likely, green = unlikely, none = no more skill-ups) and how many you
  can make in brackets, with what the reagent bank adds in blue: `Copper Bracers [3+2]`.
- **Favorites**: the star beside a recipe's name puts it in a Favorites group at the top.
- **Unlearned recipes**, greyed, grouped by skill tier (Journeyman, Expert ...) with the skill
  they need.

**The recipe**
- A round icon, the name, a favorite star and what it **requires** (tools, a forge, a fire; red
  when you don't have it), what it makes and any cooldown.
- Hover a recipe (in the list, or its icon) for the **chance to raise your skill**, exactly as the
  server works it out, and the skill where it turns yellow, green and grey. With
  `SkillGain.Crafting` above 1 it says how many points a skill-up gives.
- Hold **Shift** over a recipe, its icon or a tracked recipe to compare what it makes with what
  you have equipped, as with any other item.
- **Reagents** as `have/need Name` (red when short), plus what's in the reagent bank.
- **Track Recipe**, and under the recipe **Create All [n]**, the amount and **Create**. For
  enchants, an **Enchant** slot: drop the item on it once and every cast goes straight onto that
  item, no clicking the item each time. **Shift-click** Enchant to also skip the "replace the
  enchant?" and "binds it to you" questions for that cast (handy for enchanting skill-ups).
- **Use reagent bank** (with ReagentBankUI, on by default): Create and Create All count the bank
  and take whatever your bags are missing out of it before crafting, through ReagentBankUI's
  Withdraw Needed. If the game insists on a click to start the craft once the reagents have
  arrived, it says so.
- **Deposit leftovers** (with ReagentBankUI): when you close the window, reagents that came out
  of the bank for a craft and weren't used go back into it. What was in your bags before stays.
- **Add to Shopping List** (with ReagentBankUI): set the amount you want to make, and when your
  bags and reagent bank together fall short the recipe says so ("Short for 18  46 Bolt of Woolen
  Cloth - about 5g 94s", priced from the auction house when
  [mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah) is there) with a button
  that puts the shortfall on your shopping list. Only what isn't on the list yet is added, so
  asking twice doesn't double it (Shift-click adds it all on top, for a second recipe that needs
  the same reagent). RetailAH's Buy tab opens on that list and counts it down as you buy.
  Recipes you haven't learned yet have the amount and the button too, so the materials can be
  bought before the recipe.
- For a recipe you haven't learned: **where to learn it**, written like a guide. Hover a line
  for the details.
  - Trainers, nearest first, with the cost and the skill they teach it at. Death knights' runes
    come from their class trainer.
  - People and objects that teach it through a script (Henry Stern's tea, Knot Thimblejack's
    ogre suit, the teleporter engineers, the books in Blackrock Depths, Gloom'rel's Smelt Dark
    Iron) with what the option asks for: skill, specialization, an item, a quest done first.
  - Vendors: the price in gold or in tokens ("3 Dalaran Cooking Award", badges, honor), limited
    stock, the reputation needed, and the holiday for vendors that only come with one (Winter
    Veil, the Darkmoon Faire).
  - Drops: creature, zone or dungeon, level, chance (a loot group's share when the row has no
    chance of its own), rare spawns and bosses marked. Pickpocketing and skinning too.
  - World drops say where they really drop: "from trash in Black Temple", or the continents.
  - Bags, crates and lockboxes say where they come from: the quest that rewards them (a daily
    or not, and where), the vendor, the creatures, the fishing spot, the mail, or that it's
    locked.
  - Quests show their giver and where they stand (profession quests have no zone of their own),
    the level, the skill they ask for, the quest before them and whether they repeat.
  - Discoveries, and a last line for sources on a continent your progression hasn't opened.
  - The recipe item shows its lowest buyout when RetailAH is on the realm.
  - **Map** puts a flag on a trainer, vendor, teacher, dropping creature, object or quest giver.

**Milling and Prospecting**
- A **Milling** tab (scribes) and a **Prospecting** tab (jewelcrafters) under the profession
  tabs. The professions book has a button for each too.
- Every herb or ore is a row, like a recipe: the ones you have enough of on top with how many
  times you can do it (`Peacebloom [4+2]`, the reagent bank's in blue), the rest greyed below,
  with the skill they need in red when yours is too low.
- The pane shows what five of it give: every pigment or gem with how many and how likely, as the
  server's loot tables have it. Search finds herbs and ore by what they give ("golden pigment").
- **Mill All [n]** / **Prospect All [n]**, or an amount and **Mill** / **Prospect**. The server
  works through your bags at the spell's own cast time and puts the results straight into your
  bags: no clicking a stack, no loot window. Five can come from more than one stack.
- **Stop** ends it. So does moving, combat, casting something else, opening a trade or closing
  the window, like a cast being interrupted. What doesn't fit in your bags is mailed to you.
- **Use reagent bank** works here too: herbs and ore come out of the bank first.
- Same rules as the spells: you need to know Milling or Prospecting and have the skill the herb
  or ore asks for. `SkillChance.Milling` / `SkillChance.Prospecting` skill-ups still apply. The
  spells in the spellbook work as before.

**Multicraft, Resourcefulness and crafting speed**
- Retail's crafting stats, earned by skill instead of gear. A recipe gets nothing while it's
  orange, more from where it turns yellow to where it turns grey, and the most from then on: a
  recipe that still teaches you is slow and single, one you've outgrown is quick to make in bulk.
  - **Multicraft**: a chance that a craft makes a second batch (up to 25%). Only for things that
    stack: bars, bolts, leather, inks, bandages, food, scopes and powders. Not gear, not cut
    gems (they don't stack), and nothing in Enchanting.
  - **Resourcefulness**: a chance (up to 20%) to get 30% of the reagents back. A fraction of a
    unit is a roll, so it is 30% on average, and a proc on a recipe that uses one of each can
    give nothing.
  - **Cast**: up to 50% shorter, so a Create All of a grey recipe takes half the time.
- The recipe shows its numbers at your skill ("Multicraft 18%   Resourcefulness 14%   Cast 1.6
  sec"; hover for what they mean), its tooltip too, and the window says when one procs.
- Each proc also shows as scrolling text: in [MikScrollingBattleText](https://www.curseforge.com/wow/addons/mik-scrolling-battle-text)'s
  Notification area when MSBT is loaded, otherwise in the game's floating combat text when
  that's on.
- **Craft procs log** (the note button beside the chat link, or `/prof log`): every Multicraft
  and Resourcefulness with the recipe, the items and what they're worth at auction-house prices,
  plus how often each comes up (procs per craft) for this session and all time on the character.
  Every craft started from a profession window counts, Create All included; the rate only
  counts procs from those crafts. A proc's worth is priced when it happens, so procs before the
  addon has auction prices count as unpriced. A checkbox there turns the scrolling text off.
- Extras that don't fit in your bags are mailed.
- Three kinds of recipe only get the speed:
  - the ones the core already rolls extra items for through an alchemy mastery: most potions,
    elixirs, flasks and transmutes (`skill_extra_item_template`). Their own proc stands in,
    and that holds for an alchemist without the mastery too;
  - recipes that can be crafted back into their own reagents (elemental, primal and eternal
    transmutes, prismatic shards), where a proc would mint materials out of nothing;
  - recipes made only from what vendors sell without limit, where a second batch would be gold
    out of nothing.
- Skill counts with its bonuses (a racial +15), as the window shows it. Bots only get the speed (and the
  skill-scaled cast time below, like everyone).
- Recipes at the very top of an era's skill cap never turn grey, so they get little or nothing.
  `RetailProfessions.Perks.*.Min` gives every recipe a base if you want one.

**Training**, **Profit** and **Equipment** (the book, coin and hammer-and-wrench tabs at the top of the column on the right)
- Pages that look across every profession you have, in the spirit of TradeSkillMaster's
  crafting overview, in place of the list and the recipe until you pick a profession tab again.
- **Training**: your professions with their skill bars down the left (scrolling when you know
  more than fit; Herbalism, Skinning and Fishing too), and **Next steps** beside
  them, most urgent first:
  - cooldowns that are over (all transmutes on one line, since they share a timer),
  - tracked recipes you now have the materials for,
  - per profession: the next rank to train (from 25 points short of the cap, with the level the
    trainer asks for, and where: the nearest trainer, the book and who sells it, or the quest,
    the others in its tooltip; click it to flag it on your map), new recipes waiting at the
    trainer, what to make next for skill, and herbs to mill or ore to prospect.
- **What to make next** follows the leveling routes of the
  [wow-professions.com WotLK guides](https://www.wow-professions.com/wotlk-classic) (1-450) for
  Alchemy, Blacksmithing, Enchanting, Engineering, Inscription, Jewelcrafting, Leatherworking,
  Tailoring, Cooking and First Aid: "Level Alchemy: 25 Elixir of Healing Power", with how many the
  step still needs. Where the guide offers a choice, a recipe you know and have the materials for
  comes first. A recipe you don't know yet says where it's learned. The tooltip shows the route
  ahead; clicking opens the recipe with the amount set; Shift-click puts its materials on your
  shopping list. Where the guide only describes what to make ("any orange Glyph", "uncommon
  Northrend gems") or has nothing for your skill, the best skill-up you know stands in (one you
  can make now first, then the likeliest skill-up, then the cheapest).
- **Profit**: the most profitable crafts, every recipe you know that makes money at today's prices (priced
  as below), with how many you can make, what that earns in all and how many sold lately. Click
  a column to sort by it; **Can make now** hides the rest; **Refresh** asks for prices again. The
  line under it says what everything your materials make would earn.
- Click a line to go to its recipe. A line in another profession opens that profession first.
  Clicking those doesn't work in combat.
- The client only lists the open profession's recipes, so these pages keep a note of what each
  profession knows (and its cooldowns) whenever you open it. A profession you haven't opened yet
  says "Open ... once".

**Craft for profit** (with [mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah)'s server)
- The **coin button** beside Filter turns the list into a ranking of the recipes you know, in the
  spirit of TradeSkillMaster: what the item sells for on the auction house (after the house cut)
  minus what the materials cost, best first.
  - **Craft now**: you have the materials, in your bags or the reagent bank (when it's counted).
  - **Buy materials and craft**: still worth it when you buy everything.
  - **Not worth it** and **No price** start folded.
- The search and the filters work as usual, and every row shows its profit per craft. Hover a
  row for the sale price, the materials, the profit and how much you make crafting everything
  you can.
- The recipe pane gets an **Auction house** block: what it sells for and where that price comes
  from, how many are listed and how many sold in the last 14 days, the materials (hover for each
  reagent's price and source) and the profit. It shows for recipes you haven't learned too, so
  you can see whether one is worth learning.
- How it prices:
  - **Selling**: the lowest buyout, or with nothing listed, what it sold for lately. When the AH
    bot buyer pays more (it buys every time it looks), that instead. A vendor's price when that's
    more still. Items that bind on pickup are worth their vendor price only. Your own auctions
    aren't counted.
  - **Materials**: the cheaper of a vendor and the lowest buyout. Materials you already have
    count at that price too, since crafting has to beat selling them as they are. A material
    nothing sells counts at its vendor price if you have enough of it.
- Prices are the auction house of your own faction (the neutral one with two-side trading), from
  anywhere: no need to stand at an auctioneer. They stay good for 3 minutes; Shift-click the coin
  to ask again. Enchants aren't listed, since they make no item.

**Tracking**
- Right-click a recipe (or tick **Track recipe**) to put it on a list on your screen, like a
  tracked quest. It shows every reagent you still need for the number of crafts you want (right-
  click it: make 1, 2, 3, 5, 10, 20), turns green when you have it all and counts the reagent
  bank. Click a tracked recipe to show it in the window. Drag the title to move the list.

**Professions book (K)**
- Every profession and secondary skill with its rank and skill bar, an **Open** button, the
  gathering action where there is one (Find Herbs, Find Minerals, Smelting, Fishing) and
  **Unlearn**. For Inscription and Jewelcrafting, a **Milling** / **Prospecting** button that
  opens the window on your herbs or ore. The addon binds **K** the first time, if K is free; otherwise set it under
  Key Bindings > Retail Professions. `/prof` also opens it.
- **Archaeology** (from [mod-archaeology](https://github.com/buildthehomelab/wow-mod-archaeology)),
  with its ArchaeologyUI addon loaded: a row under Secondary Skills whose **Open** shows its
  research window and **Survey** surveys, and a row in Training's professions column. It shows
  whether or not the client patch makes Archaeology a skill line; it can't be unlearned here.

**Other**
- `/prof classic` switches back to the old Blizzard window, `/prof retail` returns.
- `/prof reset` puts the windows back where they started.
- `/prof log` opens the craft procs log.
- At a profession trainer, the recipe you picked stays picked when you skill up (the stock window
  jumps back to the first one you can learn).
- The windows are stock Blizzard frames (dialog frame, buttons, checkboxes, scroll bars). With
  [DragonUI](https://github.com/NeticSoul/DragonUI) installed they wear DragonUI's retail skin:
  the metal frame with the round portrait, red buttons and gold category bars. The profession
  window goes further when DragonUI has its own professions window: it takes that window's art,
  so it looks like DragonUI's professions overview (the profession's coloured skill bar, the
  list's category bars and skill-up arrows, the recipe on a parchment card with the profession's
  drawing, quality-ringed icons and slots, and its side tabs).
- With a DragonUI that hosts other professions addons (its `Professions.Host`, DragonUI 2.7.0+),
  there is only one window: DragonUI's. The recipe list, the recipe card, the craft controls and
  the proc log button go into it; Training and Profit are pages of it; Milling and Prospecting
  are side tabs; tracked recipes go into its objective tracker; and K (or `/prof`) opens its
  Overview. There, `/prof classic` shows DragonUI's own crafting page and `/prof retail` brings
  this one back. If the profession closes behind DragonUI's window (opening a trade or inspect
  window does that), **Create** turns into **Reopen**: click it to open the profession again,
  then craft as usual. In combat it can't, and says to open the profession from your spellbook.
  Without DragonUI, everything above uses this addon's own window.
- With [mod-reagent-bank-account](https://github.com/buildthehomelab/mod-reagent-bank-account)'s
  ReagentBankUI, everything its old profession sidebar did is in this window: the amount,
  crafting from the bank, Deposit leftovers and Add to Shopping List.

**Profession equipment** (after retail's, from Dragonflight on)
- Every profession has a **tool slot and two accessory slots** (Fishing: a rod slot and a lure
  slot), at the top of its window. Each accessory slot takes one kind of accessory (Alchemy:
  gloves and an apron; Cooking: a hat and an apron), so two of a kind never count together, and
  an item can't go in two slots. The slots are **shared by the whole account**
  (`RetailProfessions.Gear.AccountWide`), except for characters running a challenge that keeps
  gear to the character (Hardcore, Iron Man, Self-Found, Self-Crafted by default). Gear only
  counts for a character with the skill (and level) it asks for. Soulbound items go in too, like heirlooms: a character that takes one off gets it bound to them. The **Equipment** tab shows every profession's slots
  as cards, gathering professions and Fishing included, with what each set gives; the
  professions book (K) has them too. Drag an item
  from your bags onto a slot, or right-click a gear item in your bags; right-click a slot to take
  it off. What's slotted leaves your bags.
- **Gear items** give skill and retail's stats in percentage points: Multicraft, Resourcefulness
  and crafting speed on top of the crafting perks, or for Herbalism, Mining and Skinning
  **Finesse** (a chance of an extra herb, ore or hide), **Perception** (better odds on the rare
  things a node or corpse gives) and **Deftness** (faster gathering). Their tooltips say what
  they give, and the recipe odds count them.
- 73 gear items (a tool and two accessories per profession, green from skill 75 and blue from
  225) are **crafted by other professions**: Blacksmiths make hammers and picks, Engineers
  spanners and loupes, Leatherworkers gloves and aprons, Tailors hats and robes. Their recipes
  come by themselves when the crafter's skill gets there.
- **Enchanting's rods** come in three steps, one per rod its recipes ask for: Enchanter's Runed
  Rod (learned at 150, counts as a Runed Golden Rod), Truesilver Enchanter's Rod (200, Runed
  Truesilver Rod) and Grand Enchanter's Rod (275, Runed Arcanite Rod). Enchanters make them
  from a Blacksmith's plain rod, and none of them uses up the rod before it, so there's no need
  to work through the stock runed rods.
- **Recipe tools count from the slots**: a Blacksmith Hammer, Arclight Spanner, Gyromatic
  Micro-Adjustor, Jeweler's Kit, Virtuoso Inking Set or runed rod in one of its profession's
  slots counts as carried, and so do the stat tools that stand in for them. A recipe that needs
  two tools takes the second from an accessory slot or from the bags. Tools in the bags still
  count as before. The Engineering stat tools are multitools (a Gnomish Army Knife), so one slot
  covers the spanner, micro-adjustor and hammer.
- **Gathering tools**: Mining and Skinning need their tool, as they do in stock, but a Mining Pick
  or Skinning Knife in a Mining or Skinning slot counts, so it needs no bag space. One in the bags
  still works too.
- **Fishing rod**, as retail has it: a rod in the Fishing slot fishes without being equipped, so
  the weapon stays on; the rod shows in the hands while the line is out. Lures and fishing lines
  go on it (no rod to click: using one applies it), its fishing skill and its lure's count, and
  the lure runs out as usual. A rod in the main hand still works and comes first. Put a stack of
  lures in the **lure slot** and a cast of Fishing with no lure on the rod puts one on by itself. Druids' Salmon
  Run (mod-druid-swipe-fishing) is its own thing and doesn't change.
- Gear needs the skill it lists (without bonuses), so individual progression's era skill cap
  gates it like everything else. Unlearn a profession and its gear comes back to your bags.

## Individual progression

With [mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression):
- Unlearned recipes are listed up to skill **300** before Outland opens for the player and
  **375** before Northrend, by skill tier and never by profession.
- Trainers, vendors and drops on a continent (or in a dungeon of an expansion) the player hasn't
  reached are left out.
- So are sources one of its `npc_ipp_*` / `gobject_ipp_*` scripts hides at the player's
  progression, like the Cenarion Hold vendors before Blackwing Lair or Alurmi before Outland, and
  quests from a giver it hides. The addon asks again after each loading screen.

## How it works

The addon reads learned recipes from the client, as the old window does. The module adds what the
client can't know. At startup it indexes every recipe of every profession from
`SkillLineAbility.dbc`, with:
- its skill thresholds;
- trainers (`trainer_spell`);
- recipe items and who sells them, quest rewards and loot tables (with references, collapsing
  shared world-drop tables);
- `skill_discovery_template`;
- and the zones of the spawns involved.

The addon asks through addon whispers to itself (prefix `RPR`, like
[mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah)'s `RAH`). It caches a
profession's list per data version, so the list travels once.

Without the module the window still works, minus unlearned recipes, exact odds, sources and the
Milling and Prospecting tabs.

For Milling and Prospecting the module reads `milling_loot_template`, `prospecting_loot_template`
and the reference tables they point to at startup and works out each result's chance (groups,
references and the drop rates included), which is what the window shows. A Mill All is a job on
the server: every cast time it checks what the spell checks (spell known, skill, five in the
bags), takes five, rolls the core's own loot table (`Loot::FillLoot`) and stores the result.

The crafting perks hang on the core's own hooks. Multicraft and Resourcefulness roll when a
craft creates its item (`OnPlayerCreateItem`), from the recipe's yellow and grey skill in
`SkillLineAbility.dbc` and the player's skill. The core has no hook for a cast time, so the
speed is applied right after `Spell::prepare`: the cast is shortened and its start is sent to
the client again. Which recipes loop is worked out at startup from every recipe's reagents and
product.

The same hook fixes a core gap, with the perks on or off. About 1,860 recipes (most Classic
and TBC gear) get quicker as your skill rises: `SpellCastTimes.dbc` has a base time, a step per
level and a floor, and for a recipe the level is your skill / 5. The client shows that time,
but the core only loads the base, so Ruby Pendant of Fire said 8 seconds at 258 Jewelcrafting
and took 25. The module casts at the time the client shows; the speed perk comes off that.

Profession equipment lives on the server. A slotted item keeps its `item_instance` row; a
`mod_retail_professions_gear_slot` row replaces its `character_inventory` row, the way mail holds
items. Slots are read at login. The skill bonus is a hidden Mod Skill aura per profession
(spells 90800-90812), and the stats feed the perks above and three gathering hooks: Deftness
shortens herb, ore and skinning casts after `Spell::prepare`, Finesse adds an item when a
primary herb, ore or hide is looted (`OnPlayerLootItem`), Perception raises the other items'
chances while a node's or skinned corpse's loot is rolled (`OnItemRoll`). The client checks a
recipe's tools itself, so at startup the module takes the tools out of every trade skill spell,
the client patch does the same in `Spell.dbc` (`tools/build_gear_patch.py`), and the module
checks them before each cast: bags, worn or slots. A missing tool gets the client's own
"Requires ..." message.

The Fishing slot works the same way: the client patch and the module take the main-hand rod out
of Fishing and of every lure and fishing line (and the lure's item target, so the client casts it
without asking for a rod), and the module checks for a rod in the main hand or the slot. The core's
Enchant Item effects need an item target, so on the server lures and lines become a Dummy and
the module puts each on the rod after the cast (`OnSpellCast`): the one used on, the main hand's,
or the slotted one; its time left is kept
on the item and counted down while the player is online. During the Fishing channel the hands
show the slotted rod; mod-transmog-plus leaves the hands alone while someone fishes without a rod
in the main hand.

The profit view asks mod-retail-ah's server for prices under that module's `RAH` prefix (its `K`
request, which needs no auctioneer). Without it, or with `RetailAH.CraftPrices = 0`, the view
says there are no auction prices on the realm.

## Requirements

- An [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) WotLK (master) server.
- A WoW 3.3.5a (12340) client with the `RetailProfessions` addon installed.
- Optional: [mod-individual-progression](https://github.com/ZhengPeiRu21/mod-individual-progression)
  (era skill caps and locked continents), [mod-retail-ah](https://github.com/buildthehomelab/wow-mod-retail-ah)
  (craft-for-profit prices), [mod-reagent-bank-account](https://github.com/buildthehomelab/mod-reagent-bank-account)
  with its ReagentBankUI, and [DragonUI](https://github.com/NeticSoul/DragonUI) (skin).

## Install

Server:
```
cd azerothcore-wotlk/modules
git clone https://github.com/buildthehomelab/wow-mod-retail-professions.git mod-retail-professions
```
Re-run CMake, rebuild, and copy `conf/mod_retail_professions.conf.dist` next to your
`worldserver.conf`. The SQL under `data/sql` (the profession equipment tables, skill auras, gear
items and their recipes) is applied by the core's database updater.

Profession equipment needs the client patch: `tools/build_gear_patch.py --from-mpq <your
spells-and-items patch> --out <new patch>` takes the tools out of every trade skill spell in
`Spell.dbc`, the rod requirement out of Fishing, lures and lines, and adds the gear items
(`Item.dbc`) and their recipes (`Spell.dbc`, `SkillLineAbility.dbc`). Without it everything
works except tools counting from the slots and fishing or luring with the slotted rod, and the
new items show question-mark icons and their recipes don't show in the window.
To remove the module, run `data/sql/uninstall/` by hand: the characters script mails slotted
gear back to its owners first.

Client: copy `addon/RetailProfessions` into `Interface/AddOns`. On realms using Portalkeeper,
`sql/portalkeeper_addon.sql` (run by hand against `acore_world`) makes it a required addon.

The first start works out zones for the trainers, vendors and drops it needs and, with
`RetailProfessions.SaveZoneData = 1`, saves them to `creature`/`gameobject`, so later starts are
quicker.

## Configuration

See `conf/mod_retail_professions.conf.dist`: master switch, the era skill cap, hiding locked
continents, how many sources per kind, the world-drop threshold, saving zones, Milling and
Prospecting from the window (`RetailProfessions.Refine.Enable`, `RetailProfessions.Refine.CastTime`),
and the crafting perks (`RetailProfessions.Perks.Enable` and a `Min` / `Max` percent each for
`Perks.Multicraft`, `Perks.Resourcefulness` (plus `Refund`) and `Perks.Speed`), and profession
equipment (`RetailProfessions.Gear.Enable`).

## Development

`lua tools/addon_smoke_test.lua addon/RetailProfessions` loads the addon against a stubbed
3.3.5a API and a fake server and walks through opening a profession, filters, crafting, where to
learn a recipe, tracking, the book, combat, the profit view (with a fake mod-retail-ah price
server), the Training and Profit tabs (next steps, the leveling guide, the most profitable crafts,
a line opening another profession), shopping for an unlearned recipe, the
crafting perks, milling (its tab, Mill All, Stop, the reagent bank) and the classic switch.

## Troubleshooting

- **The window shows no unlearned recipes or skill-up odds**: the server module isn't running.
  Check that the folder is named `mod-retail-professions`, that CMake was re-run and the server
  rebuilt, and that `RetailProfessions.Enable = 1` in `mod_retail_professions.conf`. Without the
  module the addon only shows what the client knows.
- **The profit view says there are no auction prices**: it needs mod-retail-ah on the same
  server, and `RetailAH.CraftPrices` must not be `0`.
- **K does nothing**: the addon only binds K if it was free. Set a key under Key Bindings >
  Retail Professions, or type `/prof`.
- **You want the old window back**: `/prof classic` switches to it, `/prof retail` returns.
- **A window ended up off screen**: `/prof reset` puts the windows back.

## Credits

Author: [buildthehomelab](https://github.com/buildthehomelab)

## License

MIT, see [LICENSE](LICENSE).

## Shared prices and profitable crafts

The profit and training views request RetailAH's additive KC service, backed by the
AH bot's own stable seller quote cache. This avoids walking current auctions for every
batch and keeps both faction references aligned with the configured bot pricing model.
Each request is bounded to the addon-message size limit and only one batch is in flight;
queued batches start after completion, avoiding the old startup request burst. Prices
are reused for three minutes across recipe details, Training and Most profitable crafts.

Material cost uses the cheaper vendor or bot reference. Estimated output proceeds deduct
the effective house cut; vendor sales and the existing modeled buyer offer remain alternatives.
Labels distinguish bot reference estimates from live lowest-buyout prices. References do
not establish stock availability or guarantee a player sale; craft options may share the
same materials. Locked and soulbound items retain their restrictions. An older RetailAH
or missing/disabled provider falls back to the original K live-market service.

Deploy the matching mod-ah-bot-plus and RetailAH server builds and distribute this addon
update together. Enable AuctionHouseBot.Seller.StablePrices in the server override. No SQL
or client DBC/MPQ changes are required. Existing auctions are not repriced by the catalog.

Validation: `tools/profit_catalog_test.lua` runs under Lua 5.1 and checks queued batches,
size limits, fallback, timeout recovery, gates, vendor costs and multi-output craft estimates.
The full addon smoke test also exercises an older server's K fallback.

## BiS crafts priced against the buyer offer

For items marked by RetailAH's authoritative BiS-buyer flag, output value and profit ranking
use the actual bot buying offer after the effective auction cut. Material costs still use
full seller references/vendor prices. This avoids advertising a retail seller reference as
what the bot will pay: a 212g gross reference at 90% yields a 190.8g gross buyer offer, or
181.26g net at a 5% cut. Those numbers are an example, not a verified live Heartseeker quote.
An unavailable targeted offer falls back to vendor proceeds, not the higher retail quote.

Other items retain the existing valuation behavior. Tooltips identify bot-buyer valuation
and explain that purchase timing follows buyer cycles. Requires the matched bot/RetailAH
server changes and this updated addon.

Authoritative KC rows also carry the server's exact net buyer proceeds. This preserves
core fee-rounding order even with custom auction-cut rates; older responses use gross
minus truncated effective fee as a compatibility fallback. Vendor-fallback tooltip text
identifies vendor valuation instead of claiming a bot offer was selected.
