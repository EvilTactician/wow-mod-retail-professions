# Profession equipment (build spec)

Retail-style profession gear for mod-retail-professions: every profession gets a tool slot and
accessory slots, filled from the profession window. Items in the slots live server-side (they
leave the bags), give skill and crafting/gathering stats, and the tools that recipes require
(Blacksmith Hammer, Arclight Spanner, Jeweler's Kit, rods, ...) count from the slots.

## Slots

| Skill line | Slots |
|---|---|
| Alchemy 171, Blacksmithing 164, Enchanting 333, Engineering 202, Herbalism 182, Inscription 773, Jewelcrafting 755, Leatherworking 165, Mining 186, Skinning 393, Tailoring 197, Cooking 185 | 0 = tool, 1 and 2 = accessories, one kind each |
| Fishing 356 | 0 = rod, 1 = lures (a stack) |

Enchanting's tool comes in three tiers, one per stock rod its recipes ask for: Runed Golden (green,
learned at 150), Runed Truesilver (expert, 200, usable at 150) and Runed Arcanite (blue, 275).

Each accessory slot takes one kind of accessory, the same in both tiers (green 75, blue 225), so
two of a kind (two pairs of gloves, a green and a blue apron) never count together:

| Profession | Slot 1 | Slot 2 |
|---|---|---|
| Alchemy | Gloves | Apron |
| Blacksmithing | Whetstone Kit | Apron |
| Enchanting | Hood | Focusing Lens |
| Engineering | Headgear (goggles, helmet) | Gloves |
| Herbalism | Gloves | Satchel |
| Inscription | Scroll Case | Robe |
| Jewelcrafting | Loupe | Gem Pouch |
| Leatherworking | Mallet | Gloves |
| Mining | Headlamp | Satchel |
| Skinning | Gloves | Pack |
| Tailoring | Needles | Apron / Robe |
| Cooking | Hat | Apron |

What may go in a slot of skill S:
- a **gear item** (row in `mod_retail_professions_gear` with `skill = S`): only in the slot its
  `kind` names (0 the tool, 1 or 2 the accessory slot of its kind);
- a **plain tool** of S: an item that meets one of S's recipe tool requirements (the recipe's
  exact Totem item, or an item whose TotemCategory is compatible with the recipe's category).
  Any slot of S. That is how a recipe needing two tools (Engineering: spanner + hammer or
  micro-adjustor) gets its second one: from an accessory slot, or from the bags as before. The
  Engineering stat tools need neither: their TotemCategory is 161 Gnomish Army Knife (mask 63),
  which covers the spanner, micro-adjustor and hammer (and, like the stock knife, the pick,
  knife and flint).
  Also plain tools: a **gathering tool** of Mining (TotemCategory compatible with 165 Mining Pick)
  or Skinning (166 Skinning Knife), and for Fishing a **fishing pole** (weapon subclass 20), in
  slot 0 only.
- in Fishing's slot 1, a **stack of lures**: items whose use spell (charges -1, used up) puts a
  temporary enchantment on a rod (the lure spells below; not the fishing hats, which keep theirs).
  A stack of the same lure on top of it fills the slot's stack; the rest stays in the bags. When
  a cast of Fishing starts and the rod it uses (main hand, else the slot) has no lure, the module
  puts one from the slot on that rod and uses it up.

At login (`PlaceOnLoad`) an item keeps its slot while it still fits there, else moves to the slot
of its kind (rows saved before each accessory had its slot), else goes back to the bags (by mail
when full), as does a second copy of an item in one profession's slots.

Rules: the player must know the profession. The item's `RequiredSkill`/`RequiredSkillRank`
must be met (pure skill, without gear bonuses). This is how gear is gated by era: IP caps skill
at 300/375. The same entry can't sit in two slots of one profession. No equip or unequip
in combat, while casting, while trading, or for bots.

## Tables

World, `mod_retail_professions_gear` (created by the module's world SQL; the content SQL fills it):

| column | type | meaning |
|---|---|---|
| entry | INT UNSIGNED PK | item_template entry |
| skill | SMALLINT UNSIGNED | skill line it serves |
| kind | TINYINT UNSIGNED | the slot it goes in: 0 tool, 1 or 2 the accessory slot of its kind |
| skill_bonus | SMALLINT UNSIGNED | + skill while slotted |
| multicraft, resourcefulness, speed | TINYINT UNSIGNED | crafting stats, percentage points |
| finesse, perception, deftness | TINYINT UNSIGNED | gathering stats, percentage points |
| counts_as | INT UNSIGNED | an item entry this one stands in for as an exact Totem requirement (Jeweler's Kit 20815, Simple Grinder 20824), 0 = none |

Characters, `mod_retail_professions_gear_slot`: `owner_guid, account, skill, slot, item_guid (PK)`,
unique `(owner_guid, account, skill, slot)`. The item keeps its `item_instance` row; this row replaces its
`character_inventory` row (mail-style, as mod-gear-vault does).

## Account-wide slots

`RetailProfessions.Gear.AccountWide` (default 1): the slots belong to the account. Its rows have
`owner_guid 0, account <id>`, and the slotted items' `item_instance.owner_guid` is 0 too (as guild
bank items have), because the core deletes `item_instance` rows by owner before the module's
delete hook runs: deleting a character must not take the account's gear with it. In memory the
logged-in character owns them; every save of a slotted item writes `owner_guid 0` back.

A character running a challenge of `RetailProfessions.Gear.PersonalChallenges` (mod-challenges
bits, default 15: Hardcore 1, Iron Man 2, Self-Found 4, Self-Crafted 8; read with `Challenges::Running`, or
`IsSelfFound` from an older mod-challenges) has slots of its own: rows `owner_guid <guid>,
account 0`, as all rows were before. When it reads the account's slots (the challenge ended, or
AccountWide was just turned on), its own rows move there where the slot is free; the rest go to
its bags. The account's slots never go back to the bags for a profession the character doesn't
know (another character may): they just give nothing there. Each item counts only for a character
that meets its RequiredSkill/RequiredSkillRank (pure skill) and RequiredLevel (`Usable`: skill
aura, stats, recipe tools, the rod, the lure slot), so the account's slots don't get around the
skill gate or individual progression's era caps. Soulbound items go in the account's slots too, as
heirlooms (the good rods, runed enchanting rods and alchemist's stones bind on pickup); a character
that takes one off gets it bound to itself. A
challenge taken after login (they start at level 1, in game) is noticed within 5 s, or at the
next change: the slots are read again, the character's own ones. With AccountWide off, the first
character of the account to log in takes the account's rows as its own.

One set, never two: an account has one player session at a time, and bots (an alt played by a
bot) never read the slots. A character logging in right after another of the account logged out
reads the slots after that one's last writes as long as the characters database runs one async
worker (`CharacterDatabase.WorkerThreads 1`, the default); a row whose item is also in an
inventory or mailbox is dropped at login either way. An account deleted with gear in its slots
leaves its rows behind (the core has no account-delete hook); nothing reads them.

## Stats

- Skill bonus: a server-only passive aura per profession (spells 90800-90811, Mod Skill), amount = sum of slots.
- Multicraft / Resourcefulness / Speed: added (percentage points) to the chances the Perks code
  already rolls from recipe mastery. Capped at 100 (speed at 90, SPEED_CAP).
- Finesse: chance of one extra copy when looting a primary gathered item (Trade Goods herb 9,
  metal & stone 7, leather 6) from a herb/ore node or a skinned corpse.
- Perception: other (rare) items of a gathered node's or skinned corpse's loot roll at
  chance × (100 + perception)%.
- Deftness: gathering casts (herb/mining open-lock, skinning) are deftness% shorter.
- A slotted pick or knife meets Mining's or Skinning's tool requirement, from a slot of any
  profession, since a multitool can be both. The plain item gives no stats.
- The Fishing aura (90812) adds the slotted rod's fishing skill: Mod Skill 356 from its equip
  spells and from the equip spells of its permanent (line) and temporary (lure) enchantments.
  Only while no rod is in the main hand (that one counts by itself, as worn). Recomputed on
  every change and every 5 s (CHECK_INTERVAL), which also follows rods and picks moving in and
  out of the hands and bags.

## Fishing with the slotted rod

At startup the server records the spells that need exactly a fishing pole
(`EquippedItemClass` 2, `EquippedItemSubClassMask` 1 << 20): **casts** (a Trans Door effect:
Fishing 7620, 7731, 7732, 18248, 33095, 51294) and **enchants** (`Targets` has
TARGET_FLAG_ITEM and effect 0 is Enchant Item or Enchant Item Temporary: the 9 lures and 2
fishing lines). It clears their rod requirement in `SpellInfo`. The client patch clears fields
68-70 on the same rows, and on the enchants also `Targets` (16), and makes effect 0 a Dummy (71)
on the caster (86): the client then casts a lure at once instead of asking for an item. The
server makes the enchants' effect 0 a Dummy in `SpellInfo` too (the core's Enchant Item effects
fail without an item target, `Spell::CheckItems`), and the module puts every lure and line on a
rod itself, after the cast (`OnSpellCast`): the cast bar and the used-up lure stay the core's.

- Fishing needs a rod in the main hand or the Fishing slot, else the client's own "Requires
  Fishing Pole" (SMSG_CAST_FAILED, EQUIPPED_ITEM_CLASS 2 / 1 << 20).
- A lure or line with an item target (an unpatched client, which still asks) must target a rod,
  and goes on it. Without one it goes on the rod in the main hand, else on the slotted rod. On a
  rod in the inventory (or a trade window) the module does what `Spell::EffectEnchantItemTmp` /
  `EffectEnchantItemPerm` do (`ApplyEnchantment` off, `SetEnchantment`, `ApplyEnchantment` on).
  On the slotted rod it writes the enchantment fields itself (not `Item::SetEnchantment`, which
  queues the item for its owner's inventory save), saves the item, and says so in chat. Lure durations as
  `Spell::EffectEnchantItemTmp`: 600 s for the 8 classic lures, else 3600 s.
- With the patched client a lure no longer asks for a rod, so a rod in the bags can't take one
  (as retail: the lure goes on the rod you fish with). The Dummy skips the core's per-effect
  item checks (`Spell::CheckItems`); the one that matters, no soulbound enchantment on a trade
  partner's rod, the module repeats.
- The slotted rod's lure counts down every 5 s while the player is online, saved when it runs
  out and at logout.
- While Fishing is channeled with the slotted rod, the main-hand visible item is the rod (with
  its enchant visuals) and the off hand is empty; the next update after the channel ends puts
  `SetVisibleItemSlot` back for both (and at logout). mod-transmog-plus's outgoing-packet patch
  skips the hand fields while the player channels a spell that summons a fishing bobber with no
  rod in the main hand.
- Druids' Salmon Run (mod-druid-swipe-fishing) uses its own spell and isn't touched.

## Tool requirements

At startup the server records every trade skill spell's `Totem[2]` and `TotemCategory[2]`, and
those of the 13 Mining and Skinning spells (TotemCategory 165 or 166, not marked as trade skills),
and clears them in `SpellInfo`. The client patch clears the same fields (Spell.dbc 50, 51, 222, 223)
on the same spells: those 13 and every row with `Attributes & 0x20` (SPELL_ATTR0_IS_TRADESKILL)
that has any of them set, loot crafting included (effect 0 is Create Item 2 with an item, and
TotemCategory 0 is set, or Totem 0 with icon 1: Darkmoon cards, tarots, Prismatic Black Diamond).
Their tool is what makes the core roll spell_loot_template instead of creating the placeholder, so
once the index has read what they make, the server also clears effect 0's item in `SpellInfo`: with
no item the core rolls the loot all the same. The client keeps the item, to show what they make.
Before each cast the server checks the recorded tools itself, skipping casts from an item with
no reagent cost (enchanting scrolls), as the core does: a tool counts in the bags (or worn), or
in any slot of the recipe's profession; a gear item with counts_as counts in the bags too.
Another profession's gear can sit in a slot as a plain tool but gives no stats there. A missing tool fails the cast with the client's own
"Requires X" message (an SMSG_CAST_FAILED carrying the recorded ids still missing: the client names the first it gets), then SPELL_FAILED_DONT_REPORT.

## Addon messages (RPR transport, HELLO flag 0x20 = HELLO_GEAR; 0x40 = HELLO_GEAR_GATHER: the Fishing rod slot and gathering tools; 0x80 = HELLO_GEAR_TYPED: one kind per accessory slot, GC's kind is the slot, Cooking 3 slots, Fishing a lure slot; 0x100 = HELLO_GEAR_ACCOUNT: this character's slots are the account's)

Wire format as in RetailProfessions.cpp: `<CMD>:<req>:<fields>`; list answers come as rows
`;`-separated, values `,`-separated, names `Escape()`d.

| request | answer |
|---|---|
| `GC:<req>` gear catalog | `GCD:<req>:<rows>` (any number), then `GCE:<req>:<count>`. Row: `entry,skill,kind,skillBonus,multicraft,resourcefulness,speed,finesse,perception,deftness,reqSkill,reqRank` |
| `G:<req>` slotted gear | `GD:<req>:<rows>` (any number), then `GE:<req>:<count>`. Row: `skill,slot,entry,itemGuid,count` |
| `GQ:<req>:<bag>:<bagSlot>:<skill>:<slot>` equip | `GQ:<req>:ok:<skill>:<slot>` or `ERR:<req>:<code>`. bag 0 = backpack, 1-4 = bags; bagSlot counts from 1 (as GetContainerItemInfo). skill 0 = the item's own profession; slot 9 = first free fitting slot (tool slot for a tool/plain tool, else an empty accessory slot; a full set swaps the tool slot or the first accessory slot) |
| `GU:<req>:<skill>:<slot>` unequip to bags | `GU:<req>:ok` or `ERR:<req>:<code>` |
| `GT:<req>:<skill>` tool requirements (none for Herbalism and Fishing) | `GTD:<req>:<rows>`, then `GTE:<req>:<count>`. Rows `T,<key>,<name>,<entry>/<entry>/...` define a tool: key `c<category>` or `i<item>`, name escaped, entries = items that meet it (gear items with counts_as included), at most 30. Rows `S,<spell>,<key>[/<key>]` give a recipe's tools. All T rows come before the S rows that use them |

Unasked, after any change (equip, unequip, a profession unlearned, login): `GD:0:...` rows then
`GE:0:<count>`. On a Finesse proc: `PG:0:<skill>:F:<item>*<n>`.

Error codes: `off` (gear disabled), `loading` (slots not read yet), `combat`, `casting`,
`trade`, `bot`, `noitem` (nothing at that bag slot), `notgear` (not gear or a tool of that
profession), `unlearned`, `rank` (skill too low), `slot` (wrong slot for this item),
`dup` (already in another slot of this profession), `full` (the lure slot's stack of that lure is full), `soulbound` (older servers only: soulbound, and the slots are the account's), `bags` (no room to take an item off),
`empty` (nothing in that slot), `busy` (rate limit, retried by the addon).

## IDs (checked free on the live z80 and in every module, 2026-10-30)

- spell_dbc 90800-90811: server-only skill auras (one per profession, in the order of the table above);
  90812 the Fishing aura (SQL _02, checked free on the boaring z80 4b68c47a and in every module, 2026-10-30)
- items 90800-90879: gear items (item_template + Item.dbc via z80); 90870-90871 Cooking's second
  accessories (2026-10-30, z80 rebuilt on 1c57cff3); 90872 Enchanting's expert Truesilver rod,
  recipe 90892 (2026-10-31, z80 rebuilt on b6e4c4ec)
- spells + SkillLineAbility 90820-90899: the recipes that craft them (Spell.dbc via z80 + spell_dbc + skilllineability_dbc)
