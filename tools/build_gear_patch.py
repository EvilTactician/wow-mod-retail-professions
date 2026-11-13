#!/usr/bin/env python3
"""
mod-retail-professions: client patch rows and world SQL for profession equipment, from
tools/gear_data.py.

The 3.3.5a (12340) client needs the gear items and their recipes in its own DBCs (an item's icon
comes from its Item.dbc row; a recipe has to be in Spell.dbc and SkillLineAbility.dbc to show and
cast), and it checks recipe tools itself. A patch MPQ replaces whole files, so start from the
realm patch that already ships Spell.dbc, SkillLineAbility.dbc and Item.dbc (patch-z80 on
Evermore) to keep its other changes:

    python3 build_gear_patch.py --from-mpq patch-z80-spells-and-items.MPQ --out new/patch-z80-spells-and-items.MPQ
    python3 build_gear_patch.py --sql --from-mpq patch-z80-spells-and-items.MPQ

What --out changes (every other file in the MPQ is copied unchanged):

- Spell.dbc: clears Totem (fields 50, 51) and TotemCategory (222, 223) on every trade skill spell
  (Attributes & 0x20, SPELL_ATTR0_IS_TRADESKILL) that has any of them set, and on the spells that
  need a Mining Pick or Skinning Knife, which aren't marked as trade skills. The server records
  and clears the same fields on the same spells at startup and checks the tools itself, so tools
  in profession equipment slots count. Then appends the recipe spells (copies of a stock recipe
  of the crafter, see RECIPE_TEMPLATES in gear_data.py).
  The rod in the Fishing slot: Fishing (spells needing exactly a fishing pole, with a Trans Door
  effect) loses its rod requirement (fields 68-70), so it casts without one in the main hand;
  lures and lines (the same requirement, an item target and an Enchant Item effect) lose it as
  well as the item target: Targets (16) 0, and effect 0 a Dummy (3) on the caster (implicit
  target 1), so the client casts them at once instead of asking for a rod to click. The server
  (Gear::Build) takes the same rod requirement out of SpellInfo, makes the lures' effect a Dummy
  there too, checks for a rod itself and puts the lure on the rod in the main hand or the slot.
- SkillLineAbility.dbc: appends the recipes' rows (learned automatically at the recipe's level).
- Item.dbc: appends a row per gear item, with the displayId (icon) of an existing item.

Rows are appended in id order after the file's own rows, which keep their order: never re-sort a
client DBC (an id-sorted SkillRaceClassInfo.dbc and Achievement.dbc broke the client before).
The builder checks that the other rows come out as an in-order prefix of the new file. Run on
its own output, or on a patch built on top of it, it replaces its rows where they are instead of
adding them twice, so the gear rows keep their place before rows added later.

--sql writes data/sql/db-world/updates/mod_retail_professions_2026_10_30_01.sql (item_template,
item_dbc, spell_dbc, skilllineability_dbc, mod_retail_professions_gear) and
data/sql/uninstall/mod_retail_professions_uninstall_world.sql. It reads the recipe templates and
the icon items from the same DBCs, so give it the patch you build from.

Packing needs StormLib (libstorm). Point STORMLIB at it if it isn't /usr/local/lib/libstorm.dylib.

Released under the MIT License.
"""

import argparse
import collections
import ctypes
import importlib.util
import os
import shutil
import struct
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SQL_PATH = os.path.join(ROOT, "data", "sql", "db-world", "updates", "mod_retail_professions_2026_10_30_01.sql")
UNINSTALL_PATH = os.path.join(ROOT, "data", "sql", "uninstall", "mod_retail_professions_uninstall_world.sql")


def load_gear_data():
    spec = importlib.util.spec_from_file_location("gear_data", os.path.join(HERE, "gear_data.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


GD = load_gear_data()

# --- DBC layouts (3.3.5a, build 12340) --------------------------------------------------------

SPELL_FIELDS = 234
F_ID = 0
F_ATTRIBUTES = 4
F_TOTEM = (50, 51)
F_REAGENT = 52            # 8 items, then 8 counts
F_REAGENT_COUNT = 60
F_EFFECT = 71             # 3
F_EFFECT_BASE_POINTS = 80
F_EFFECT_ITEM_TYPE = 107
F_NAME = 136              # 16 locales + flags (152)
F_RANK = 153              # 16 + flags (169)
F_SPELL_ICON = 133
F_DESCRIPTION = 170       # 16 + flags (186)
F_TOOLTIP = 187           # 16 + flags (203)
F_TOTEM_CATEGORY = (222, 223)
TOOL_FIELDS = F_TOTEM + F_TOTEM_CATEGORY
GATHER_TOOL_CATEGORIES = (165, 166)  # Mining Pick, Skinning Knife
F_TARGETS = 16
F_EQUIPPED_ITEM = (68, 69, 70)  # EquippedItemClass, SubClassMask, InventoryTypeMask
F_IMPLICIT_TARGET_A = 86        # 3
POLE_FIELDS = (F_TARGETS,) + F_EQUIPPED_ITEM + (F_EFFECT, F_IMPLICIT_TARGET_A)
ITEM_CLASS_WEAPON = 2
FISHING_POLE_MASK = 1 << 20     # ITEM_SUBCLASS_WEAPON_FISHING_POLE
TARGET_FLAG_ITEM = 0x10
SPELL_EFFECT_DUMMY = 3
SPELL_EFFECT_TRANS_DOOR = 50
SPELL_EFFECT_ENCHANT_ITEM = 53
SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY = 54
TARGET_UNIT_CASTER = 1
SPELL_ATTR0_IS_TRADESKILL = 0x20
SPELL_EFFECT_CREATE_ITEM = 24

SPELL_STRINGS = set(range(F_NAME, F_NAME + 16)) | set(range(F_RANK, F_RANK + 16)) \
    | set(range(F_DESCRIPTION, F_DESCRIPTION + 16)) | set(range(F_TOOLTIP, F_TOOLTIP + 16))
# AzerothCore's spell_dbc column types (data/sql/base/db_world/spell_dbc.sql): floats, signed
# ints; everything else is unsigned.
SPELL_FLOATS = {47, 77, 78, 79, 101, 102, 103, 119, 120, 121, 216, 217, 218, 229, 230, 231}
SPELL_SIGNED = {0, 13, 15, 41, *range(52, 71), 74, 75, 76, 80, 81, 82, *range(110, 116), 224, 228}

SLA_FIELDS = 14           # ID, SkillLine, Spell, RaceMask, ClassMask, ExcludeRace, ExcludeClass,
                          # MinSkillLineRank, SupercededBySpell, AcquireMethod,
                          # TrivialSkillLineRankHigh, TrivialSkillLineRankLow, CharacterPoints[2]
SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE = 1

ITEM_FIELDS = 8           # ID, ClassID, SubclassID, Sound_Override_Subclassid, Material,
                          # DisplayInfoID, InventoryType, SheatheType
ITEM_CLASS_MISC, ITEM_SUBCLASS_MISC_OTHER = 15, 4  # not equippable: the items live in profession slots
INVTYPE_NON_EQUIP = 0


class Dbc:
    """A WDBC file kept in its own row order."""

    def __init__(self, path, fields, name):
        with open(path, "rb") as f:
            data = f.read()
        magic, count, nfields, size, strsize = struct.unpack_from("<4s4I", data, 0)
        if magic != b"WDBC" or nfields != fields or size != fields * 4:
            sys.exit("%s: not a 3.3.5a %s (%d fields, expected %d)" % (path, name, nfields, fields))
        self.name, self.fields = name, fields
        self.rows = [list(struct.unpack_from("<%dI" % fields, data, 20 + i * size)) for i in range(count)]
        self.strings = bytearray(data[20 + count * size:20 + count * size + strsize])

    def write(self, path):
        with open(path, "wb") as f:
            f.write(struct.pack("<4s4I", b"WDBC", len(self.rows), self.fields, self.fields * 4, len(self.strings)))
            for row in self.rows:
                f.write(struct.pack("<%dI" % self.fields, *row))
            f.write(self.strings)

    def string(self, at):
        return self.strings[at:self.strings.index(b"\0", at)].decode("utf-8")

    def add_string(self, text):
        """Offset of text in the string block, appended unless it's already there as a whole string."""
        if not text:
            return 0
        raw = text.encode("utf-8") + b"\0"
        at = self.strings.find(b"\0" + raw)
        if at >= 0:
            return at + 1
        at = len(self.strings)
        self.strings.extend(raw)
        return at

    def find(self, row_id, what):
        row = next((r for r in self.rows if r[0] == row_id), None)
        if row is None:
            sys.exit("%s row %d (%s) is missing" % (self.name, row_id, what))
        return row


def u32(value):
    return value & 0xFFFFFFFF


def s32(value):
    return struct.unpack("<i", struct.pack("<I", value))[0]


# --- Building the rows ------------------------------------------------------------------------------

def our_ids():
    return ({i["spell"] for i in GD.ITEMS}, {i["entry"] for i in GD.ITEMS})


def place_ours(dbc, ids, new_rows):
    """Puts our rows in: a row this builder made before (a re-run on its own output, or on a
    patch built later on top of it) is replaced where it is, the others are appended. Ids in our
    ranges that aren't ours are refused: something else took them. Returns how many replaced."""
    first, last = (GD.SPELL_FIRST, GD.SPELL_LAST) if dbc.name != "Item.dbc" else (GD.ITEM_FIRST, GD.ITEM_LAST)
    stray = [r[0] for r in dbc.rows if first <= r[0] <= last and r[0] not in ids]
    if stray:
        sys.exit("%s: rows %s are in our id range %d-%d but aren't ours" % (dbc.name, stray, first, last))
    by_id = {r[0]: r for r in new_rows}
    replaced = 0
    for n, row in enumerate(dbc.rows):
        if row[0] in by_id:
            dbc.rows[n] = by_id.pop(row[0])
            replaced += 1
    dbc.rows += [r for r in new_rows if r[0] in by_id]
    return replaced


def clear_tools(spell, abilities):
    """Clears Totem/TotemCategory on every trade skill spell that has any, loot crafting (Darkmoon
    cards, tarots) included, and on Mining and Skinning; the same spells the server clears
    (Gear::Build, which takes the loot crafting recipes' placeholder out instead so they still
    roll their loot).
    Returns (spells cleared, {skill line or 0 for none: count})."""
    skills = collections.defaultdict(set)
    for a in abilities.rows:
        skills[a[2]].add(a[1])
    total, counts = 0, collections.Counter()
    for row in spell.rows:
        gather = row[F_TOTEM_CATEGORY[0]] in GATHER_TOOL_CATEGORIES
        if (gather or row[F_ATTRIBUTES] & SPELL_ATTR0_IS_TRADESKILL) and any(row[f] for f in TOOL_FIELDS):
            for f in TOOL_FIELDS:
                row[f] = 0
            total += 1
            for skill in sorted(skills.get(row[F_ID], {0})):
                counts[skill] += 1
    return total, counts


def free_fishing_pole(spell):
    """Takes the main-hand rod out of Fishing, lures and lines (see the module docstring); the
    same spells Gear::Build picks. Returns (casts, lures) changed: none on the builder's own
    output, whose rows are rod-free already."""
    casts = lures = 0
    for row in spell.rows:
        stock = s32(row[F_EQUIPPED_ITEM[0]]) == ITEM_CLASS_WEAPON and row[F_EQUIPPED_ITEM[1]] == FISHING_POLE_MASK
        if stock and SPELL_EFFECT_TRANS_DOOR in row[F_EFFECT:F_EFFECT + 3]:
            casts += 1
        elif stock and row[F_TARGETS] & TARGET_FLAG_ITEM and row[F_EFFECT] in (SPELL_EFFECT_ENCHANT_ITEM, SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY):
            row[F_TARGETS] = 0
            row[F_EFFECT] = SPELL_EFFECT_DUMMY
            row[F_IMPLICIT_TARGET_A] = TARGET_UNIT_CASTER
            lures += 1
        else:
            continue
        row[F_EQUIPPED_ITEM[0]] = u32(-1)
        row[F_EQUIPPED_ITEM[1]] = 0
        row[F_EQUIPPED_ITEM[2]] = 0
    return casts, lures


def recipe_row(spell, item):
    row = list(spell.find(item["template"], "recipe template for %s" % item["name"]))
    if row[F_EFFECT] != SPELL_EFFECT_CREATE_ITEM or row[F_EFFECT + 1] or row[F_EFFECT + 2]:
        sys.exit("Spell.dbc %d isn't a plain Create Item recipe" % item["template"])
    row[F_ID] = item["spell"]
    for f in TOOL_FIELDS:
        row[f] = 0
    reagents = item["reagents"] + [(0, 0)] * (8 - len(item["reagents"]))
    for n, (entry, count) in enumerate(reagents):
        row[F_REAGENT + n] = entry
        row[F_REAGENT_COUNT + n] = count
    row[F_EFFECT_BASE_POINTS] = 0  # one item (base points + die sides 1)
    row[F_EFFECT_ITEM_TYPE] = item["entry"]
    for f in SPELL_STRINGS:
        row[f] = 0
    row[F_NAME] = spell.add_string(item["name"])
    return row


def ability_row(item):
    return [item["spell"], item["crafter"], item["spell"], 0, 0, 0, 0, item["learn"], 0,
            SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE, item["grey"], item["yellow"], 0, 0]


def item_row(items_dbc, item):
    look = items_dbc.find(item["look"], "icon of %s" % item["name"])
    return [item["entry"], ITEM_CLASS_MISC, ITEM_SUBCLASS_MISC_OTHER, u32(-1), look[4], look[5],
            INVTYPE_NON_EQUIP, 0]


def check_prefix(name, old_rows, new_rows, old_strings, new_strings, allowed=()):
    """The old rows must come out as an in-order prefix of the new file, equal except for the
    fields in allowed; the old string block must be a prefix of the new one."""
    if len(new_rows) < len(old_rows):
        sys.exit("%s: lost rows" % name)
    for n, (old, new) in enumerate(zip(old_rows, new_rows)):
        if old != new and any(o != w for f, (o, w) in enumerate(zip(old, new)) if f not in allowed):
            sys.exit("%s: row %d (id %d) changed or moved" % (name, n, old[0]))
    if new_strings[:len(old_strings)] != old_strings:
        sys.exit("%s: string block changed" % name)


def build(folder):
    """Edits the three DBCs in folder (DBFilesClient files). Returns what the SQL needs."""
    spell = Dbc(os.path.join(folder, "Spell.dbc"), SPELL_FIELDS, "Spell.dbc")
    abilities = Dbc(os.path.join(folder, "SkillLineAbility.dbc"), SLA_FIELDS, "SkillLineAbility.dbc")
    items = Dbc(os.path.join(folder, "Item.dbc"), ITEM_FIELDS, "Item.dbc")
    spells, entries = our_ids()

    old = {d.name: ([list(r) for r in d.rows], bytes(d.strings)) for d in (spell, abilities, items)}

    total, cleared = clear_tools(spell, abilities)
    casts, lures = free_fishing_pole(spell)

    new_spells = [recipe_row(spell, i) for i in GD.ITEMS]
    new_abilities = [ability_row(i) for i in GD.ITEMS]
    new_items = [item_row(items, i) for i in GD.ITEMS]
    replaced = {d.name: place_ours(d, ids, rows) for d, ids, rows in
                ((spell, spells, new_spells), (abilities, spells, new_abilities), (items, entries, new_items))}

    # Everyone else's rows keep their order and content (ours are in place by construction).
    for d, ids, allowed in ((spell, spells, TOOL_FIELDS + POLE_FIELDS), (abilities, spells, ()), (items, entries, ())):
        old_rows, old_strings = old[d.name]
        check_prefix(d.name, [r for r in old_rows if r[0] not in ids], [r for r in d.rows if r[0] not in ids],
                     old_strings, d.strings, allowed)
        d.write(os.path.join(folder, d.name))

    per_skill = ", ".join("%s %d" % (GD.SKILL_NAMES.get(k, "skill %d" % k) if k else "no skill line", v)
                          for k, v in sorted(cleared.items(), key=lambda kv: -kv[1]))
    print("Spell.dbc: tools cleared on %d trade skill spells%s; %d recipes (%d replaced in place)"
          % (total, " (%s)" % per_skill if per_skill else "", len(new_spells), replaced["Spell.dbc"]))
    if casts or lures:
        print("Spell.dbc: rod requirement taken out of %d Fishing and %d lure/line spells" % (casts, lures))
    print("SkillLineAbility.dbc: %d rows (%d replaced in place)" % (len(new_abilities), replaced["SkillLineAbility.dbc"]))
    print("Item.dbc: %d rows (%d replaced in place)" % (len(new_items), replaced["Item.dbc"]))
    return dict(spells=new_spells, abilities=new_abilities, items=new_items, cleared=(total, cleared))


# --- SQL -------------------------------------------------------------------------------------------

def sql_str(text):
    return "'" + text.replace("\\", "\\\\").replace("'", "''") + "'"


def spell_sql_values(row, name):
    out = []
    for f, v in enumerate(row):
        if f == F_NAME:
            out.append(sql_str(name))
        elif f in SPELL_STRINGS:
            out.append("''")
        elif f in SPELL_FLOATS:
            out.append(repr(round(struct.unpack("<f", struct.pack("<I", v))[0], 6)))
        elif f in SPELL_SIGNED:
            out.append(str(s32(v)))
        else:
            out.append(str(v))
    return "(" + ", ".join(out) + ")"


# item_template columns (data/sql/base/db_world/item_template.sql), in order, with the values
# every gear item shares; per-item values are filled in below.
ITEM_TEMPLATE_COLUMNS = [
    ("entry", None), ("class", ITEM_CLASS_MISC), ("subclass", ITEM_SUBCLASS_MISC_OTHER),
    ("SoundOverrideSubclass", -1), ("name", None), ("displayid", None), ("Quality", None),
    ("Flags", 0), ("FlagsExtra", 0), ("BuyCount", 1), ("BuyPrice", None), ("SellPrice", None),
    ("InventoryType", INVTYPE_NON_EQUIP), ("AllowableClass", -1), ("AllowableRace", -1),
    ("ItemLevel", None), ("RequiredLevel", 0), ("RequiredSkill", None), ("RequiredSkillRank", None),
    ("requiredspell", 0), ("requiredhonorrank", 0), ("RequiredCityRank", 0),
    ("RequiredReputationFaction", 0), ("RequiredReputationRank", 0), ("maxcount", 0),
    ("stackable", 1), ("ContainerSlots", 0),
] + [(c % n, 0) for n in range(1, 11) for c in ("stat_type%d", "stat_value%d")] + [
    ("ScalingStatDistribution", 0), ("ScalingStatValue", 0),
    ("dmg_min1", 0), ("dmg_max1", 0), ("dmg_type1", 0), ("dmg_min2", 0), ("dmg_max2", 0), ("dmg_type2", 0),
    ("armor", 0), ("holy_res", 0), ("fire_res", 0), ("nature_res", 0), ("frost_res", 0),
    ("shadow_res", 0), ("arcane_res", 0), ("delay", 0), ("ammo_type", 0), ("RangedModRange", 0),
] + [(c % n, d) for n in range(1, 6) for c, d in (("spellid_%d", 0), ("spelltrigger_%d", 0),
                                                   ("spellcharges_%d", 0), ("spellppmRate_%d", 0),
                                                   ("spellcooldown_%d", -1), ("spellcategory_%d", 0),
                                                   ("spellcategorycooldown_%d", -1))] + [
    ("bonding", 0),  # no binding: crafters sell and trade them (Bind on Equip means nothing for non-equip items)
    ("description", None), ("PageText", 0), ("LanguageID", 0), ("PageMaterial", 0),
    ("startquest", 0), ("lockid", 0), ("Material", None), ("sheath", 0), ("RandomProperty", 0),
    ("RandomSuffix", 0), ("block", 0), ("itemset", 0), ("MaxDurability", 0), ("area", 0), ("Map", 0),
    ("BagFamily", 0), ("TotemCategory", None),
    ("socketColor_1", 0), ("socketContent_1", 0), ("socketColor_2", 0), ("socketContent_2", 0),
    ("socketColor_3", 0), ("socketContent_3", 0), ("socketBonus", 0), ("GemProperties", 0),
    ("RequiredDisenchantSkill", -1), ("ArmorDamageModifier", 0), ("duration", 0),
    ("ItemLimitCategory", 0), ("HolidayId", 0), ("ScriptName", ""), ("DisenchantID", 0),
    ("FoodType", 0), ("minMoneyLoot", 0), ("maxMoneyLoot", 0), ("flagsCustom", 0), ("VerifiedBuild", 0),
]
assert len(ITEM_TEMPLATE_COLUMNS) == 138


def item_template_values(item, dbc_row):
    own = {"entry": item["entry"], "name": item["name"], "displayid": dbc_row[5],
           "Quality": item["quality"], "BuyPrice": item["sell_price"] * 4, "SellPrice": item["sell_price"],
           "ItemLevel": item["item_level"], "RequiredSkill": item["skill"],
           "RequiredSkillRank": item["required_rank"], "description": item["description"],
           "Material": s32(dbc_row[4]), "TotemCategory": item["totem_category"]}
    out = []
    for column, default in ITEM_TEMPLATE_COLUMNS:
        value = own[column] if default is None else default
        out.append(sql_str(value) if isinstance(value, str) else str(value))
    return "(" + ", ".join(out) + ")"


def between(column, first, last):
    return "`%s` BETWEEN %d AND %d" % (column, first, last)


def write_sql(built):
    items = GD.ITEMS
    first_item, last_item = GD.ITEM_FIRST, GD.ITEM_LAST
    first_spell, last_spell = GD.SPELL_FIRST, GD.SPELL_LAST
    out = [
        "-- mod-retail-professions: profession equipment items and their recipes (classic tier).",
        "--",
        "-- GENERATED by tools/build_gear_patch.py from tools/gear_data.py: change gear_data.py and run",
        "-- the tool again (python3 tools/build_gear_patch.py --sql --from-mpq <the realm's z80 patch>),",
        "-- don't edit this file. The client patch (patch-z80) gets the same Spell.dbc,",
        "-- SkillLineAbility.dbc and Item.dbc rows.",
        "--",
        "-- - item_template + item_dbc %d-%d: %d gear items for the profession equipment slots. Not"
        % (items[0]["entry"], items[-1]["entry"], len(items)),
        "--   equippable (class 15/4, no inventory type), not bound, RequiredSkill/RequiredSkillRank =",
        "--   the profession they serve at 75 (green), 150 (Enchanting's expert rod) or 225 (blue). Stat",
        "--   tools carry the TotemCategory of the recipe tool they stand in for (Blacksmith Hammer,",
        "--   Arclight Spanner, runed rods, ...).",
        "-- - spell_dbc + skilllineability_dbc %d-%d: the recipes, crafted by Blacksmithing,"
        % (items[0]["spell"], items[-1]["spell"]),
        "--   Leatherworking, Tailoring, Engineering and Enchanting. AcquireMethod 1: learned when the",
        "--   crafter's skill is at least the recipe level (Player::learnSkillRewardedSpells runs at login,",
        "--   when a rank is trained, and the module adds the moment a skill-up reaches a recipe level).",
        "-- - mod_retail_professions_gear: what each item gives in a slot (table from _00.sql); kind is",
        "--   the slot it goes in: 0 the tool, 1 or 2 the accessory slot of its kind.",
        "--",
        "-- Idempotent: deletes the whole id ranges first.",
        "",
        "DELETE FROM `item_template` WHERE %s;" % between("entry", first_item, last_item),
        "INSERT INTO `item_template` (%s) VALUES" % ", ".join("`%s`" % c for c, _ in ITEM_TEMPLATE_COLUMNS),
        ",\n".join(item_template_values(i, r) for i, r in zip(items, built["items"])) + ";",
        "",
        "DELETE FROM `item_dbc` WHERE %s;" % between("ID", first_item, last_item),
        "INSERT INTO `item_dbc` VALUES",
        ",\n".join("(" + ", ".join(str(s32(v)) for v in r) + ")" for r in built["items"]) + ";",
        "",
        "DELETE FROM `spell_dbc` WHERE %s;" % between("ID", first_spell, last_spell),
        "INSERT INTO `spell_dbc` VALUES",
        ",\n".join(spell_sql_values(r, i["name"]) for i, r in zip(items, built["spells"])) + ";",
        "",
        "DELETE FROM `skilllineability_dbc` WHERE %s;" % between("ID", first_spell, last_spell),
        "INSERT INTO `skilllineability_dbc` VALUES",
        ",\n".join("(" + ", ".join(str(s32(v)) for v in r) + ")" for r in built["abilities"]) + ";",
        "",
        "DELETE FROM `mod_retail_professions_gear` WHERE %s;" % between("entry", first_item, last_item),
        "INSERT INTO `mod_retail_professions_gear` (`entry`, `skill`, `kind`, `skill_bonus`, %s, `counts_as`) VALUES"
        % ", ".join("`%s`" % c for c in GD.STAT_COLUMNS),
        ",\n".join("(%d, %d, %d, %d, %s, %d)" % (i["entry"], i["skill"], i["slot"], i["skill_bonus"],
                                                 ", ".join(str(i["stats"][c]) for c in GD.STAT_COLUMNS),
                                                 i["counts_as"]) for i in items) + ";",
        "",
    ]
    os.makedirs(os.path.dirname(SQL_PATH), exist_ok=True)
    with open(SQL_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))
    print("wrote", os.path.relpath(SQL_PATH, ROOT))

    uninstall = [
        "-- mod-retail-professions: undo the module's world database changes. Run it by hand on the",
        "-- world database after removing the module; AzerothCore doesn't run it automatically.",
        "--",
        "-- Removes the profession equipment items, their recipes, the skill bonus auras and the gear",
        "-- table. Run mod_retail_professions_uninstall_characters.sql first, so slotted gear goes back",
        "-- to its owners' mail; without item_template rows the server then deletes the gear items",
        "-- characters still hold at their next login (Player::_LoadInventory, unknown item). The client",
        "-- patch rows (patch-z80) stay until that patch is rebuilt without them. Generated by",
        "-- tools/build_gear_patch.py --sql. Idempotent: safe to run again.",
        "",
        "DELETE FROM `item_template` WHERE %s;" % between("entry", first_item, last_item),
        "DELETE FROM `item_dbc` WHERE %s;" % between("ID", first_item, last_item),
        "DELETE FROM `spell_dbc` WHERE %s;" % between("ID", first_spell, last_spell),
        "DELETE FROM `skilllineability_dbc` WHERE %s;" % between("ID", first_spell, last_spell),
        "DELETE FROM `spell_dbc` WHERE %s;" % between("ID", GD.AURA_FIRST, GD.AURA_LAST),
        "DROP TABLE IF EXISTS `mod_retail_professions_gear`;",
        "",
    ]
    os.makedirs(os.path.dirname(UNINSTALL_PATH), exist_ok=True)
    with open(UNINSTALL_PATH, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(uninstall))
    print("wrote", os.path.relpath(UNINSTALL_PATH, ROOT))


# --- MPQ (same StormLib calls and flags as the module's other patch builders) ----------------------

def stormlib():
    lib = ctypes.CDLL(os.environ.get("STORMLIB", "/usr/local/lib/libstorm.dylib"))
    handle = ctypes.c_void_p
    lib.SFileOpenArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(handle)]
    lib.SFileCreateArchive.argtypes = [ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.POINTER(handle)]
    lib.SFileExtractFile.argtypes = [handle, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    lib.SFileAddFileEx.argtypes = [handle, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint, ctypes.c_uint, ctypes.c_uint]
    lib.SFileCloseArchive.argtypes = [handle]

    class FindData(ctypes.Structure):
        _fields_ = [("cFileName", ctypes.c_char * 1024), ("szPlainName", ctypes.c_char_p),
                    ("dwHashIndex", ctypes.c_uint), ("dwBlockIndex", ctypes.c_uint),
                    ("dwFileSize", ctypes.c_uint), ("dwFileFlags", ctypes.c_uint),
                    ("dwCompSize", ctypes.c_uint), ("dwFileTimeLo", ctypes.c_uint),
                    ("dwFileTimeHi", ctypes.c_uint), ("lcLocale", ctypes.c_uint)]

    lib.SFileFindFirstFile.argtypes = [handle, ctypes.c_char_p, ctypes.POINTER(FindData), ctypes.c_char_p]
    lib.SFileFindFirstFile.restype = handle
    lib.SFileFindNextFile.argtypes = [handle, ctypes.POINTER(FindData)]
    lib.SFileFindClose.argtypes = [handle]
    # They return a C++ bool, one byte: read as ctypes' default int, the rest of the register can
    # make false read true, and the file search never ends (100% CPU, then killed for memory).
    for name in ("SFileOpenArchive", "SFileCreateArchive", "SFileExtractFile", "SFileAddFileEx",
                 "SFileCloseArchive", "SFileFindNextFile", "SFileFindClose"):
        getattr(lib, name).restype = ctypes.c_bool
    return lib, handle, FindData


def extract_all(mpq, folder):
    lib, handle, FindData = stormlib()
    h = handle()
    if not lib.SFileOpenArchive(mpq.encode(), 0, 0x100, ctypes.byref(h)):
        sys.exit("can't open %s" % mpq)

    names = []
    found = FindData()
    search = lib.SFileFindFirstFile(h, b"*", ctypes.byref(found), None)
    while search:
        name = found.cFileName.decode()
        if name in names:  # the search came round again: stop rather than loop
            break
        names.append(name)
        if not lib.SFileFindNextFile(search, ctypes.byref(found)):
            break
    if search:
        lib.SFileFindClose(search)

    files = []
    for name in names:
        if name in ("(listfile)", "(attributes)", "(signature)"):
            continue
        dst = os.path.join(folder, *name.split("\\"))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not lib.SFileExtractFile(h, name.encode(), dst.encode(), 0):
            sys.exit("can't extract %s" % name)
        files.append((dst, name))
    lib.SFileCloseArchive(h)
    return files


def pack(out, files):
    lib, handle, _ = stormlib()
    if os.path.exists(out):
        os.remove(out)
    h = handle()
    # MPQ v1 with a listfile and attributes; each file zlib-compressed, like the realm's patches.
    if not lib.SFileCreateArchive(out.encode(), 0x00300000, max(16, len(files) * 2), ctypes.byref(h)):
        sys.exit("can't create %s" % out)
    for src, name in files:
        if not lib.SFileAddFileEx(h, src.encode(), name.encode(), 0x80000200, 0x02, 0x02):
            sys.exit("can't add %s" % name)
    lib.SFileCloseArchive(h)


NEEDED = ("Spell.dbc", "SkillLineAbility.dbc", "Item.dbc")


def dbc_folder(files):
    """The DBFilesClient folder of an extracted patch, after checking it has the three files."""
    have = {name.lower(): src for src, name in files}
    paths = []
    for dbc in NEEDED:
        src = have.get(("DBFilesClient\\" + dbc).lower())
        if src is None:
            sys.exit("the patch has no DBFilesClient\\%s; build from the realm patch that ships it" % dbc)
        paths.append(src)
    folder = os.path.dirname(paths[0])
    if any(os.path.dirname(p) != folder or os.path.basename(p) != d for p, d in zip(paths, NEEDED)):
        sys.exit("unexpected DBFilesClient file names in the patch: %s" % paths)
    return folder


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from-mpq", help="realm patch MPQ with Spell.dbc, SkillLineAbility.dbc and Item.dbc")
    parser.add_argument("--dbc-dir", help="instead of --from-mpq: a folder with those three DBCs (edited in place unless only --sql)")
    parser.add_argument("--out", help="with --from-mpq: the new MPQ (every file of the old one, three DBCs changed)")
    parser.add_argument("--sql", action="store_true", help="write the world SQL and the uninstall SQL")
    args = parser.parse_args()
    if bool(args.from_mpq) == bool(args.dbc_dir):
        parser.error("give --from-mpq or --dbc-dir")
    if not args.out and not args.sql:
        parser.error("nothing to do: give --out and/or --sql")
    if args.out and not args.from_mpq:
        parser.error("--out needs --from-mpq")

    work = tempfile.mkdtemp(prefix="profession-gear-")
    try:
        if args.from_mpq:
            files = extract_all(args.from_mpq, os.path.join(work, "mpq"))
            folder = dbc_folder(files)
        else:
            folder = args.dbc_dir
            if args.sql and not args.out:  # don't touch the caller's files just for SQL
                copy = os.path.join(work, "dbc")
                os.makedirs(copy)
                for dbc in NEEDED:
                    shutil.copy(os.path.join(folder, dbc), copy)
                folder = copy
        built = build(folder)
        if args.sql:
            write_sql(built)
        if args.out:
            os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
            pack(args.out, files)
            print("%s: %d files" % (args.out, len(files)))
    finally:
        shutil.rmtree(work)


if __name__ == "__main__":
    main()
