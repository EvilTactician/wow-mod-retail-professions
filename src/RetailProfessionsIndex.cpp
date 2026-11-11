/*
 * mod-retail-professions: every recipe of every profession, and where each one is learned.
 *
 * Built once at startup from data the core already has in memory (SkillLineAbility.dbc, spells,
 * trainers, vendors, quests, item templates and spawns) plus world DB tables the core doesn't
 * keep in a readable form (the loot tables, skill_discovery_template, the SmartAI casts that
 * teach a recipe and the creatures that only spawn for a holiday).
 *
 * The answer to W is meant to read like a guide: what a vendor wants in tokens, which holiday
 * a vendor comes with, which raid's trash a "world drop" really drops in, where the bag or
 * lockbox holding a recipe comes from, who gives a quest and where.
 *
 * Who sees what:
 *   - L lists recipes the player's race and class can learn and that something teaches to
 *     their faction; the addon hides those past the skill cap HELLO sends.
 *   - W lists sources the player could use: friendly trainers and vendors, quests for their
 *     race, and nothing on a continent mod-individual-progression hasn't opened for them
 *     or that one of its npc_ipp_* / gobject_ipp_* scripts hides at their progression.
 */

#include "RetailProfessions.h"
#include "Chat.h"
#include "CreatureData.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "GameEventMgr.h"
#include "GameObjectData.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "MapMgr.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QuestDef.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "Trainer.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <string_view>
#include <unordered_map>
#include <unordered_set>

namespace RetailProfessions::Index
{
    namespace
    {
        // Skill lines with a trade skill window.
        constexpr std::array<uint32, 12> PROFESSIONS = {
            171, // Alchemy
            164, // Blacksmithing
            333, // Enchanting
            202, // Engineering
            773, // Inscription
            755, // Jewelcrafting
            165, // Leatherworking
            197, // Tailoring
            186, // Mining (Smelting)
            185, // Cooking
            129, // First Aid
            776, // Runeforging
        };

        // Professions with ranks to train but no trade skill window: their ranks are indexed too.
        constexpr std::array<uint32, 3> GATHERING = {
            182, // Herbalism
            393, // Skinning
            356, // Fishing
        };

        constexpr uint32 RACEMASK_ALLIANCE = 1101; // human, dwarf, night elf, gnome, draenei
        constexpr uint32 RACEMASK_HORDE = 690;     // orc, undead, tauren, troll, blood elf

        constexpr uint8 TEAMBIT_ALLIANCE = 1;
        constexpr uint8 TEAMBIT_HORDE = 2;
        constexpr uint8 TEAMBIT_BOTH = TEAMBIT_ALLIANCE | TEAMBIT_HORDE;

        // Spawns kept per trainer or vendor (enough to find a near one) and per drop source.
        constexpr std::size_t MAX_SPAWNS = 8;
        constexpr std::size_t MAX_DROP_SPAWNS = 3;

        constexpr uint32 MAP_OUTLAND = 530;
        constexpr uint32 MAP_NORTHREND = 571;
        constexpr uint32 MAP_EBON_HOLD = 609;
        constexpr uint32 ZONE_ISLE_OF_QUEL_DANAS = 4080;
        constexpr std::array<uint32, 6> ZONES_OPEN_ON_OUTLAND_MAP = {
            3430, // Eversong Woods
            3433, // Ghostlands
            3487, // Silvermoon City
            3524, // Azuremyst Isle
            3525, // Bloodmyst Isle
            3557, // The Exodar
        };
        constexpr uint8 IP_STATE_TBC = 8;
        constexpr uint8 IP_STATE_QUEL_DANAS = 12;
        constexpr uint8 IP_STATE_WOTLK = 13;
        constexpr uint8 IP_STATE_NEVER = 255;

        // When mod-individual-progression's visibility scripts (IndividualProgressionAwareness.cpp)
        // show a creature or object: from progression state `from` and before state `before`
        // (0 = no bound). `passedBefore`: the bound is a !hasPassedProgression() check, which
        // IndividualProgression.ProgressionLimit can lift; the pre_* scripts use isBeforeProgression().
        // npc_ipp_zg and npc_ipp_za take their state from the config. Not modelled: npc_ipp_naxx40
        // also shows to IP's excluded accounts, npc_ipp_ds2 to all with AllowEarlyDungeonSet2
        // (neither sells recipes), and IndividualProgressionPvP.cpp's PvP vendors.
        struct ProgressionGate
        {
            std::string_view script;
            uint8 from;
            uint8 before;
            bool passedBefore;
        };
        constexpr std::array<ProgressionGate, 26> PROGRESSION_GATES = {{
            { "gobject_ipp_preaq",    3,  0, false },
            { "gobject_ipp_aqwar",    4,  5, true },
            { "gobject_ipp_si",       6,  7, true },
            { "gobject_ipp_naxx40",   6,  0, false },
            { "gobject_ipp_pre_tbc",  0,  8, false },
            { "gobject_ipp_tbc",      8,  0, false },
            { "gobject_ipp_tbc_t4",   12, 0, false },
            { "gobject_ipp_wotlk",    13, 0, false },
            { "npc_ipp_preaq",        3,  0, false },
            { "npc_ipp_we",           3,  4, true },
            { "npc_ipp_aq",           5,  0, false },
            { "npc_ipp_aqwewar",      3,  5, true },
            { "npc_ipp_aqwar",        4,  5, true },
            { "npc_ipp_si",           6,  7, true },
            { "npc_ipp_pre_naxx40",   0,  6, false },
            { "npc_ipp_naxx40",       6,  0, false },
            { "npc_ipp_pre_tbc",      0,  8, false },
            { "npc_ipp_tbc",          8,  0, false },
            { "npc_ipp_tbc_pre_t3",   0,  10, true },
            { "npc_ipp_tbc_t3",       10, 0, false },
            { "npc_ipp_pre_wotlk",    0,  13, false },
            { "npc_ipp_wotlk",        13, 0, false },
            { "npc_ipp_wotlk_ulduar", 14, 0, false },
            { "npc_ipp_wotlk_totc",   15, 0, false },
            { "npc_ipp_wotlk_icc",    16, 0, false },
            { "npc_ipp_ds2",          3,  0, false },
        }};

        // What the map marker looks like: the red flag city guards use.
        constexpr uint32 POI_FLAGS = 99;
        constexpr uint32 POI_ICON_RED_FLAG = 7;

        struct TrainerSource
        {
            uint32 creature = 0;
            uint32 cost = 0;
            uint32 reqSkill = 0;
            uint32 reqLevel = 0;
            std::array<uint32, 3> reqAbility = {}; // e.g. a specialization: Goblin Engineer, Armorsmith
        };

        // Someone or something that teaches a recipe through a script: a gossip option, a book.
        // What the option asks for comes from its conditions (the first alternative of them).
        struct Teacher
        {
            uint32 id = 0;
            bool object = false;
            uint32 gossipMenu = 0;
            uint32 gossipOption = 0;
            uint32 reqSkill = 0;
            uint32 reqSkillValue = 0;
            std::vector<uint32> reqSpells; // e.g. Goblin Engineer
            std::vector<uint32> reqItems;
            std::vector<uint32> reqQuests; // rewarded before
        };

        // The L row's slot for an enchant that goes on any weapon, one- or two-handed; the client's
        // inventory types end at MAX_INVTYPE - 1.
        constexpr uint32 SLOT_ANY_WEAPON = MAX_INVTYPE;

        // A SkillLineAbility row that teaches the recipe by itself, for the races and classes in it.
        struct AutoRow
        {
            uint32 raceMask = 0;
            uint32 classMask = 0;
            uint32 skill = 0;    // learned on reaching it (AcquireMethod 1); 0 = with the profession
        };

        struct DiscoverySource
        {
            uint32 fromSpell = 0; // 0 = any craft of the profession
            uint32 reqSkill = 0;
            uint32 chance = 0;    // percent x100
        };

        struct Recipe
        {
            uint32 spell = 0;
            uint32 skill = 0;
            uint32 reqSkill = 0;
            uint32 yellow = 0;
            uint32 grey = 0;
            uint32 raceMask = 0;
            uint32 classMask = 0;
            uint32 item = 0;
            uint32 madeMin = 1;
            uint32 madeMax = 1;
            uint32 invType = 0;
            uint32 quality = 1;
            std::string reagents = "-";
            bool targetsItem = false; // cast on an item: enchants, sockets, buckles, linings, embroidery
            uint8 sources = 0;
            uint8 teams = 0;
            std::vector<AutoRow> autoRows;
            std::vector<TrainerSource> trainers;
            std::vector<Teacher> teachers;
            std::vector<uint32> recipeItems;
            std::vector<uint32> quests;
            std::vector<DiscoverySource> discoveries;
            uint8 rank = 0; // a profession's rank (2 = Journeyman ... 6 = Grand Master), not a craft
        };

        struct Drop
        {
            uint32 id = 0;
            uint32 chance = 0; // percent x100, 0 = unknown (a share of a loot group)
        };

        struct Vendor
        {
            uint32 creature = 0;
            uint32 maxcount = 0;
            uint32 extendedCost = 0;
            bool gold = true;
            uint32 event = 0;      // sold only while this game event runs (game_event_npc_vendor)
        };

        // Where an item comes from: a recipe item, or a bag or lockbox a recipe item is found in.
        struct ItemSources
        {
            std::vector<Vendor> vendors;
            std::vector<Drop> creatures;
            std::vector<Drop> pickpocket;
            std::vector<Drop> skinning;
            std::vector<Drop> objects;
            std::vector<Drop> containers;
            std::vector<Drop> fishing; // id = zone or area
            std::vector<uint32> quests;
            bool mail = false;         // comes in the mail (mail_loot_template)
            uint32 worldDropCreatures = 0;
            uint32 worldMinLevel = 0;
            uint32 worldMaxLevel = 0;
            std::vector<uint32> worldMaps; // where most of a world drop's creatures are, most first
            bool worldInstances = false;   // ... and they are dungeons or raids
            uint8 teams = 0;
        };

        struct Spawn
        {
            uint32 map = 0;
            uint32 zone = 0;
            uint32 area = 0;
            float x = 0.0f;
            float y = 0.0f;
            uint32 phaseMask = 1;
            // Shown only from / before these progression states (PROGRESSION_GATES); 0 = no bound.
            uint8 ipFrom = 0;
            uint8 ipBefore = 0;
        };

        struct Data
        {
            std::unordered_map<uint32, Recipe> recipes;
            std::unordered_map<uint32, std::vector<uint32>> bySkill;
            std::unordered_map<uint32, std::vector<uint32>> ranks; // skill * 8 + rank -> the spells that teach it
            std::unordered_map<uint32, ItemSources> items;
            std::unordered_map<uint32, std::vector<Spawn>> creatureSpawns;
            std::unordered_map<uint32, std::vector<Spawn>> objectSpawns;
            std::unordered_set<uint32> spawnedCreatures; // every creature entry with a spawn
            std::unordered_map<uint32, uint32> creatureMap; // creature entry -> map of its first spawn
            std::unordered_map<uint32, uint32> eventOnly;   // creature entry -> the game event all its spawns need
            std::unordered_map<uint32, uint32> questGivers; // quest -> creature entry
            std::unordered_map<uint32, uint32> questObjects; // quest -> gameobject entry
            uint32 stamp = 0;
        };

        Data sData;

        // ---- small helpers ---------------------------------------------------------------------

        char const* DbcString(char const* const (&names)[16])
        {
            char const* name = names[sWorld->GetDefaultDbcLocale()];
            return name && *name ? name : names[LOCALE_enUS];
        }

        char const* DbcString(std::array<char const*, 16> const& names)
        {
            char const* name = names[sWorld->GetDefaultDbcLocale()];
            return name && *name ? name : names[LOCALE_enUS];
        }

        std::string AreaName(uint32 areaId)
        {
            if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(areaId))
                return DbcString(area->area_name);
            return "";
        }

        std::string MapName(uint32 mapId)
        {
            if (MapEntry const* map = sMapStore.LookupEntry(mapId))
                return DbcString(map->name);
            return "";
        }

        // Where a spawn is, in words: "Stormwind City" or "Scholomance".
        std::string PlaceName(Spawn const& spawn)
        {
            if (spawn.zone)
                return AreaName(spawn.zone);
            return MapName(spawn.map);
        }

        // A spell that teaches another (a trainer's or quest's "learning" spell) -> the spell it
        // teaches; anything else -> itself.
        uint32 TaughtSpell(uint32 spellId)
        {
            SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId);
            if (!info)
                return spellId;
            for (SpellEffectInfo const& effect : info->GetEffects())
                if (effect.Effect == SPELL_EFFECT_LEARN_SPELL && effect.TriggerSpell)
                    return effect.TriggerSpell;
            return spellId;
        }

        // The slot a spell cast on an item goes on (an enchant, a socket, an embroidery), as an
        // inventory type, from the equipment the spell asks for. Chest enchants name chest and
        // robe, weapon enchants name only weapon subclasses.
        uint32 TargetSlot(SpellInfo const* info)
        {
            if (info->EquippedItemClass != ITEM_CLASS_WEAPON && info->EquippedItemClass != ITEM_CLASS_ARMOR)
                return 0;

            uint32 slots = uint32(info->EquippedItemInventoryTypeMask);
            for (uint32 type = 1; slots && type < MAX_INVTYPE; ++type)
                if (slots & (1u << type))
                    return type;

            uint32 subclasses = uint32(info->EquippedItemSubClassMask);
            if (info->EquippedItemClass == ITEM_CLASS_ARMOR)
                return subclasses == (1u << ITEM_SUBCLASS_ARMOR_SHIELD) ? uint32(INVTYPE_SHIELD) : 0;

            constexpr uint32 TWO_HANDED = (1u << ITEM_SUBCLASS_WEAPON_AXE2) | (1u << ITEM_SUBCLASS_WEAPON_MACE2)
                | (1u << ITEM_SUBCLASS_WEAPON_POLEARM) | (1u << ITEM_SUBCLASS_WEAPON_SWORD2) | (1u << ITEM_SUBCLASS_WEAPON_STAFF)
                | (1u << ITEM_SUBCLASS_WEAPON_EXOTIC2) | (1u << ITEM_SUBCLASS_WEAPON_SPEAR) | (1u << ITEM_SUBCLASS_WEAPON_FISHING_POLE);
            if (subclasses && !(subclasses & ~TWO_HANDED))
                return INVTYPE_2HWEAPON;
            return subclasses & TWO_HANDED ? SLOT_ANY_WEAPON : uint32(INVTYPE_WEAPON);
        }

        uint8 TeamsOfRaceMask(uint32 raceMask)
        {
            if (!raceMask)
                return TEAMBIT_BOTH;
            uint8 teams = 0;
            if (raceMask & RACEMASK_ALLIANCE)
                teams |= TEAMBIT_ALLIANCE;
            if (raceMask & RACEMASK_HORDE)
                teams |= TEAMBIT_HORDE;
            return teams;
        }

        uint8 TeamsOfFaction(uint32 factionTemplate)
        {
            FactionTemplateEntry const* faction = sFactionTemplateStore.LookupEntry(factionTemplate);
            if (!faction)
                return TEAMBIT_BOTH;
            uint8 teams = 0;
            if (!faction->IsHostileToAlliancePlayers())
                teams |= TEAMBIT_ALLIANCE;
            if (!faction->IsHostileToHordePlayers())
                teams |= TEAMBIT_HORDE;
            return teams;
        }

        uint8 TeamOf(Player* player)
        {
            return player->GetTeamId() == TEAM_ALLIANCE ? TEAMBIT_ALLIANCE : TEAMBIT_HORDE;
        }

        std::string JoinIds(std::vector<uint32> const& ids, std::size_t from, std::size_t count)
        {
            std::string out;
            for (std::size_t i = from; i < ids.size() && i < from + count; ++i)
            {
                if (!out.empty())
                    out += ',';
                out += std::to_string(ids[i]);
            }
            return out;
        }

        // Runs `sql` (with one {} for an id list) over ids in chunks.
        template <typename Fn>
        void QueryByIds(std::string_view sql, std::vector<uint32> const& ids, Fn&& onRow)
        {
            constexpr std::size_t CHUNK = 400;
            for (std::size_t from = 0; from < ids.size(); from += CHUNK)
            {
                std::string query = Acore::StringFormat(sql, JoinIds(ids, from, CHUNK));
                if (QueryResult result = WorldDatabase.Query(query))
                    do
                    {
                        onRow(result->Fetch());
                    } while (result->NextRow());
            }
        }

        template <typename T>
        std::vector<uint32> Keys(std::unordered_set<T> const& set)
        {
            std::vector<uint32> out(set.begin(), set.end());
            std::sort(out.begin(), out.end());
            return out;
        }

        // ---- building --------------------------------------------------------------------------

        void ReadRecipes()
        {
            for (uint32 skill : PROFESSIONS)
            {
                for (SkillLineAbilityEntry const* ability : GetSkillLineAbilitiesBySkillLine(skill))
                {
                    SpellInfo const* info = sSpellMgr->GetSpellInfo(ability->Spell);
                    if (!info || !info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL))
                        continue;

                    auto [itr, isNew] = sData.recipes.try_emplace(ability->Spell);
                    Recipe& recipe = itr->second;
                    // Faction- or class-specific rows may teach the recipe by themselves (First Aid
                    // for death knights), so every such row is kept.
                    if (ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE
                        || ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_LEARN)
                        recipe.autoRows.push_back({ ability->RaceMask, ability->ClassMask,
                            ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE ? std::max<uint32>(1, ability->MinSkillLineRank) : 0 });
                    if (!isNew)
                    {
                        // Race-specific rows of the same recipe: any unrestricted row wins.
                        recipe.raceMask = (recipe.raceMask && ability->RaceMask) ? (recipe.raceMask | ability->RaceMask) : 0;
                        recipe.classMask = (recipe.classMask && ability->ClassMask) ? (recipe.classMask | ability->ClassMask) : 0;
                        continue;
                    }

                    recipe.spell = ability->Spell;
                    recipe.skill = skill;
                    recipe.reqSkill = ability->MinSkillLineRank;
                    recipe.yellow = ability->TrivialSkillLineRankLow;
                    recipe.grey = ability->TrivialSkillLineRankHigh;
                    recipe.raceMask = ability->RaceMask;
                    recipe.classMask = ability->ClassMask;

                    for (SpellEffectInfo const& effect : info->GetEffects())
                        if (effect.Effect == SPELL_EFFECT_ENCHANT_ITEM || effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY
                            || effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_PRISMATIC || effect.Effect == SPELL_EFFECT_ENCHANT_HELD_ITEM)
                            recipe.targetsItem = true;

                    for (SpellEffectInfo const& effect : info->GetEffects())
                    {
                        if ((effect.Effect == SPELL_EFFECT_CREATE_ITEM || effect.Effect == SPELL_EFFECT_CREATE_ITEM_2) && effect.ItemType)
                        {
                            recipe.item = effect.ItemType;
                            int32 low = effect.BasePoints + (effect.DieSides > 0 ? 1 : 0);
                            int32 high = effect.BasePoints + effect.DieSides;
                            recipe.madeMin = uint32(std::max(1, low));
                            recipe.madeMax = uint32(std::max(low, high));
                            recipe.madeMax = std::max(recipe.madeMax, recipe.madeMin);
                            break;
                        }
                    }

                    if (recipe.item)
                        if (ItemTemplate const* product = sObjectMgr->GetItemTemplate(recipe.item))
                        {
                            recipe.invType = product->InventoryType;
                            recipe.quality = product->Quality;
                        }
                    if (!recipe.item && recipe.targetsItem)
                        recipe.invType = TargetSlot(info);

                    std::string reagents;
                    for (std::size_t i = 0; i < info->Reagent.size(); ++i)
                    {
                        if (info->Reagent[i] <= 0 || !info->ReagentCount[i])
                            continue;
                        if (!reagents.empty())
                            reagents += '/';
                        reagents += std::to_string(info->Reagent[i]) + "*" + std::to_string(info->ReagentCount[i]);
                    }
                    recipe.reagents = reagents.empty() ? "-" : reagents;

                    sData.bySkill[skill].push_back(recipe.spell);
                }
            }
        }

        // Profession ranks: the spells whose Skill effect sets a profession's cap (rank x 75). They
        // go in with the recipes so the readers below find their trainers, books and quests, but
        // not in bySkill: the L lists and the stamp leave them out. K says where one is taught.
        void ReadRanks()
        {
            auto ranked = [](uint32 skill)
            {
                return std::find(PROFESSIONS.begin(), PROFESSIONS.end(), skill) != PROFESSIONS.end()
                    || std::find(GATHERING.begin(), GATHERING.end(), skill) != GATHERING.end();
            };
            for (uint32 id = 0; id < sSpellMgr->GetSpellInfoStoreSize(); ++id)
            {
                SpellInfo const* info = sSpellMgr->GetSpellInfo(id);
                if (!info)
                    continue;
                for (SpellEffectInfo const& effect : info->GetEffects())
                {
                    if (effect.Effect != SPELL_EFFECT_SKILL || effect.MiscValue <= 0 || !ranked(uint32(effect.MiscValue)))
                        continue;
                    int32 rank = effect.CalcValue();
                    if (rank < 1 || rank > 7)
                        break;
                    uint32 skill = uint32(effect.MiscValue);
                    sData.ranks[skill * 8 + uint32(rank)].push_back(id);
                    auto [itr, isNew] = sData.recipes.try_emplace(id);
                    if (isNew)
                    {
                        itr->second.spell = id;
                        itr->second.skill = skill;
                        itr->second.rank = uint8(rank);
                    }
                    break;
                }
            }
        }

        void ReadTrainers(std::unordered_set<uint32>& creatures)
        {
            for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
            {
                Trainer::Trainer* trainer = sObjectMgr->GetTrainer(entry);
                // Class trainers too: death knights learn their runes from one.
                if (!trainer || (trainer->GetTrainerType() != Trainer::Type::Tradeskill && trainer->GetTrainerType() != Trainer::Type::Class))
                    continue;

                for (Trainer::Spell const& spell : trainer->GetSpells())
                {
                    auto itr = sData.recipes.find(TaughtSpell(spell.SpellId));
                    if (itr == sData.recipes.end())
                        continue;
                    itr->second.trainers.push_back({ entry, spell.MoneyCost, spell.ReqSkillRank, spell.ReqLevel, spell.ReqAbility });
                    creatures.insert(entry);
                }
            }
        }

        // NPCs and objects whose script teaches a recipe: SmartAI casts of a spell that teaches one
        // (Henry Stern's tea, Knot Thimblejack's ogre suit, the teleporter engineers, the books
        // in Blackrock Depths), plus the ones scripted in the core.
        void ReadTeachers(std::unordered_set<uint32>& creatures, std::unordered_set<uint32>& objects)
        {
            struct CoreTeacher
            {
                uint32 creature, spell, gossipMenu, gossipOption;
            };
            // The gossip option whose conditions say what it asks for.
            static constexpr std::array<CoreTeacher, 1> CORE_TEACHERS = { {
                { 9037, 14894, 1945, 0 }, // Gloom'rel: Smelt Dark Iron (boss_tomb_of_seven.cpp)
            } };

            std::unordered_map<uint32, std::vector<std::pair<uint32, std::size_t>>> byMenu; // menu -> recipe, teacher index
            auto add = [&](uint32 spell, uint32 id, bool object, uint32 menu, uint32 option)
            {
                auto itr = sData.recipes.find(TaughtSpell(spell));
                if (itr == sData.recipes.end() || !id)
                    return;
                std::vector<Teacher>& teachers = itr->second.teachers;
                if (std::any_of(teachers.begin(), teachers.end(), [&](Teacher const& t) { return t.id == id && t.object == object; }))
                    return;
                Teacher teacher;
                teacher.id = id;
                teacher.object = object;
                teacher.gossipMenu = menu;
                teacher.gossipOption = option;
                teachers.push_back(teacher);
                if (menu)
                    byMenu[menu].emplace_back(itr->first, teachers.size() - 1);
                (object ? objects : creatures).insert(id);
            };

            constexpr uint32 SMART_EVENT_GOSSIP_SELECT = 62;
            if (QueryResult result = WorldDatabase.Query("SELECT CAST(entryorguid AS SIGNED), CAST(source_type AS UNSIGNED), "
                "CAST(event_type AS UNSIGNED), CAST(event_param1 AS UNSIGNED), CAST(event_param2 AS UNSIGNED), "
                "CAST(action_param1 AS UNSIGNED) FROM smart_scripts WHERE source_type IN (0, 1) AND action_type IN (11, 85, 86, 134)"))
                do
                {
                    Field* f = result->Fetch();
                    uint32 spell = uint32(f[5].Get<uint64>());
                    if (!sData.recipes.count(TaughtSpell(spell)))
                        continue;
                    int64 entryOrGuid = f[0].Get<int64>();
                    bool object = f[1].Get<uint64>() == 1;
                    uint32 id = 0;
                    if (entryOrGuid > 0)
                        id = uint32(entryOrGuid);
                    else if (!object)
                    {
                        if (CreatureData const* data = sObjectMgr->GetCreatureData(uint32(-entryOrGuid)))
                            id = data->id;
                    }
                    else if (GameObjectData const* data = sObjectMgr->GetGameObjectData(uint32(-entryOrGuid)))
                        id = data->id;
                    bool gossip = f[2].Get<uint64>() == SMART_EVENT_GOSSIP_SELECT;
                    add(spell, id, object, gossip ? uint32(f[3].Get<uint64>()) : 0, gossip ? uint32(f[4].Get<uint64>()) : 0);
                } while (result->NextRow());

            for (CoreTeacher const& t : CORE_TEACHERS)
                if (sObjectMgr->GetCreatureTemplate(t.creature))
                    add(t.spell, t.creature, false, t.gossipMenu, t.gossipOption);

            // What each gossip option asks for: skill, spells known (a specialization), items, quests done.
            if (byMenu.empty())
                return;
            std::vector<uint32> menus;
            for (auto const& [menu, list] : byMenu)
                menus.push_back(menu);
            constexpr uint32 SOURCE_GOSSIP_OPTION = 15;
            constexpr uint32 COND_ITEM = 2, COND_SKILL = 7, COND_QUESTREWARDED = 8, COND_SPELL = 25;
            QueryByIds(Acore::StringFormat("SELECT CAST(SourceGroup AS UNSIGNED), CAST(SourceEntry AS UNSIGNED), "
                "CAST(ConditionTypeOrReference AS UNSIGNED), CAST(ConditionValue1 AS UNSIGNED), CAST(ConditionValue2 AS UNSIGNED) "
                "FROM conditions WHERE SourceTypeOrReferenceId = {} AND ElseGroup = 0 AND NegativeCondition = 0 "
                "AND SourceGroup IN ({{}})", SOURCE_GOSSIP_OPTION), menus,
                [&](Field* f)
                {
                    uint32 menu = uint32(f[0].Get<uint64>());
                    uint32 option = uint32(f[1].Get<uint64>());
                    uint32 type = uint32(f[2].Get<uint64>());
                    uint32 value1 = uint32(f[3].Get<uint64>());
                    uint32 value2 = uint32(f[4].Get<uint64>());
                    for (auto const& [spell, index] : byMenu[menu])
                    {
                        Teacher& t = sData.recipes[spell].teachers[index];
                        if (t.gossipOption != option)
                            continue;
                        if (type == COND_SKILL)
                        {
                            t.reqSkill = value1;
                            t.reqSkillValue = value2;
                        }
                        else if (type == COND_SPELL)
                            t.reqSpells.push_back(value1);
                        else if (type == COND_ITEM)
                            t.reqItems.push_back(value1);
                        else if (type == COND_QUESTREWARDED)
                            t.reqQuests.push_back(value1);
                    }
                });
        }

        // Recipe items: the "Pattern: ..." that teaches a spell when used.
        void ReadRecipeItems(std::unordered_set<uint32>& recipeItems)
        {
            for (auto const& [entry, item] : *sObjectMgr->GetItemTemplateStore())
            {
                if (item.Class != ITEM_CLASS_RECIPE)
                    continue;

                for (auto const& spell : item.Spells)
                {
                    if (spell.SpellId <= 0)
                        continue;
                    uint32 taught = spell.SpellTrigger == ITEM_SPELLTRIGGER_LEARN_SPELL_ID ? uint32(spell.SpellId) : TaughtSpell(spell.SpellId);
                    auto itr = sData.recipes.find(taught);
                    if (itr == sData.recipes.end())
                        continue;
                    if (std::find(itr->second.recipeItems.begin(), itr->second.recipeItems.end(), entry) == itr->second.recipeItems.end())
                        itr->second.recipeItems.push_back(entry);
                    recipeItems.insert(entry);
                }
            }
        }

        void ReadVendors(std::unordered_set<uint32> const& wanted, std::unordered_set<uint32>& creatures)
        {
            for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
            {
                VendorItemData const* vendor = sObjectMgr->GetNpcVendorItemList(entry);
                if (!vendor || vendor->Empty())
                    continue;

                for (VendorItem const* item : vendor->m_items)
                {
                    if (!item || !wanted.count(item->item))
                        continue;
                    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item->item);
                    sData.items[item->item].vendors.push_back({ entry, item->maxcount, item->ExtendedCost,
                        !proto || item->IsGoldRequired(proto), 0 });
                    creatures.insert(entry);
                }
            }

            // Items a vendor only sells during a holiday; the core adds them when it starts.
            if (QueryResult result = WorldDatabase.Query("SELECT CAST(eventEntry AS UNSIGNED), CAST(guid AS UNSIGNED), "
                "CAST(item AS UNSIGNED), CAST(maxcount AS UNSIGNED), CAST(ExtendedCost AS UNSIGNED) FROM game_event_npc_vendor"))
                do
                {
                    Field* f = result->Fetch();
                    uint32 item = uint32(f[2].Get<uint64>());
                    CreatureData const* data = wanted.count(item) ? sObjectMgr->GetCreatureData(uint32(f[1].Get<uint64>())) : nullptr;
                    if (!data)
                        continue;
                    std::vector<Vendor>& vendors = sData.items[item].vendors;
                    auto itr = std::find_if(vendors.begin(), vendors.end(), [&](Vendor const& v) { return v.creature == data->id; });
                    uint32 event = uint32(f[0].Get<uint64>());
                    if (itr != vendors.end())
                    {
                        itr->event = event; // the event was on at startup
                        continue;
                    }
                    ItemTemplate const* proto = sObjectMgr->GetItemTemplate(item);
                    uint32 extendedCost = uint32(f[4].Get<uint64>());
                    bool gold = !proto || proto->HasFlag2(ITEM_FLAG2_DONT_IGNORE_BUY_PRICE) || !extendedCost;
                    vendors.push_back({ data->id, uint32(f[3].Get<uint64>()), extendedCost, gold, event });
                    creatures.insert(data->id);
                } while (result->NextRow());
        }

        // Quests rewarding one of `wanted`; with `spells`, also the quests that teach a recipe.
        void ReadQuests(std::unordered_set<uint32> const& wanted, bool spells)
        {
            for (auto const& [id, quest] : sObjectMgr->GetQuestTemplates())
            {
                for (uint32 item : quest->RewardItemId)
                    if (item && wanted.count(item))
                        sData.items[item].quests.push_back(id);
                for (uint32 item : quest->RewardChoiceItemId)
                    if (item && wanted.count(item))
                        sData.items[item].quests.push_back(id);

                if (!spells)
                    continue;
                std::array<uint32, 2> rewardSpells = { uint32(std::max(0, quest->GetRewSpellCast())), quest->GetRewSpell() };
                for (uint32 spell : rewardSpells)
                {
                    if (!spell)
                        continue;
                    auto itr = sData.recipes.find(TaughtSpell(spell));
                    if (itr != sData.recipes.end()
                        && std::find(itr->second.quests.begin(), itr->second.quests.end(), id) == itr->second.quests.end())
                        itr->second.quests.push_back(id);
                }
            }
        }

        // Who gives each quest that matters here, for its place and a map pin: a spawned NPC
        // if there is one, else an object.
        void ReadQuestGivers(std::unordered_set<uint32>& creatures, std::unordered_set<uint32>& objects)
        {
            std::unordered_set<uint32> quests;
            for (auto const& [spell, recipe] : sData.recipes)
                quests.insert(recipe.quests.begin(), recipe.quests.end());
            for (auto const& [item, sources] : sData.items)
                quests.insert(sources.quests.begin(), sources.quests.end());

            for (auto const& [creature, quest] : *sObjectMgr->GetCreatureQuestRelationMap())
            {
                if (!quests.count(quest) || !sData.spawnedCreatures.count(creature))
                    continue;
                if (sData.questGivers.emplace(quest, creature).second)
                    creatures.insert(creature);
            }
            for (auto const& [object, quest] : *sObjectMgr->GetGOQuestRelationMap())
            {
                if (!quests.count(quest) || sData.questGivers.count(quest))
                    continue;
                if (sData.questObjects.emplace(quest, object).second)
                    objects.insert(object);
            }
        }

        struct LootRow
        {
            uint32 entry = 0;
            uint32 item = 0;
            uint32 chance = 0; // percent x100
            uint32 group = 0;
            uint32 reference = 0;
            uint32 rolls = 1;  // a reference row is processed MaxCount times
        };

        // Rows of a loot table that name one of `items`, or (with `refs`) point at one of those
        // reference tables. A row without a chance of its own gets its share of its group: what
        // the group's explicit chances leave, split evenly between the rows that have none. Grouped
        // references are members of their group like items (LootTemplate::AddEntry).
        std::vector<LootRow> ReadLootRows(std::string const& table, std::vector<uint32> const& items, std::vector<uint32> const& refs)
        {
            std::vector<LootRow> rows;
            auto read = [&](std::string const& where, std::vector<uint32> const& ids)
            {
                QueryByIds(Acore::StringFormat("SELECT CAST(Entry AS UNSIGNED), CAST(Item AS UNSIGNED), "
                    "CAST(ROUND(ABS(Chance) * 100) AS UNSIGNED), CAST(GroupId AS UNSIGNED), CAST(Reference AS UNSIGNED), "
                    "CAST(MaxCount AS UNSIGNED) FROM {} WHERE {} IN ({{}})", table, where), ids,
                    [&](Field* f)
                    {
                        uint32 reference = uint32(f[4].Get<uint64>());
                        rows.push_back({ uint32(f[0].Get<uint64>()), uint32(f[1].Get<uint64>()), uint32(f[2].Get<uint64>()),
                            uint32(f[3].Get<uint64>()), reference, reference ? std::clamp<uint32>(uint32(f[5].Get<uint64>()), 1, 10) : 1 });
                    });
            };
            if (!items.empty())
                read("Reference = 0 AND Item", items);
            if (!refs.empty())
                read("Reference", refs);

            std::vector<uint32> grouped;
            for (LootRow const& row : rows)
                if (!row.chance && row.group)
                    grouped.push_back(row.entry);
            if (grouped.empty())
                return rows;
            std::sort(grouped.begin(), grouped.end());
            grouped.erase(std::unique(grouped.begin(), grouped.end()), grouped.end());

            std::unordered_map<uint64, uint32> shares; // entry << 8 | group -> chance x100
            QueryByIds(Acore::StringFormat("SELECT CAST(Entry AS UNSIGNED), CAST(GroupId AS UNSIGNED), "
                "CAST(SUM(Chance = 0) AS UNSIGNED), CAST(ROUND(SUM(ABS(Chance)) * 100) AS UNSIGNED) FROM {} "
                "WHERE GroupId > 0 AND Entry IN ({{}}) GROUP BY Entry, GroupId", table), grouped,
                [&](Field* f)
                {
                    uint32 unset = uint32(f[2].Get<uint64>());
                    uint32 used = uint32(f[3].Get<uint64>());
                    if (unset)
                        shares[(f[0].Get<uint64>() << 8) | f[1].Get<uint64>()] = (used < 10000 ? 10000 - used : 0) / unset;
                });
            for (LootRow& row : rows)
                if (!row.chance && row.group)
                {
                    auto itr = shares.find((uint64(row.entry) << 8) | row.group);
                    if (itr != shares.end())
                        row.chance = itr->second;
                }
            return rows;
        }

        // An item at chance `a` (x100) inside a reference rolled at chance `b`, `rolls` times:
        // the chance of at least one.
        uint32 Combine(uint32 a, uint32 b, uint32 rolls = 1)
        {
            if (!a || !b)
                return 0;
            double once = std::min(1.0, double(a) * double(b) / 1e8);
            double any = 1.0 - std::pow(1.0 - once, double(std::max<uint32>(1, rolls)));
            return std::max<uint32>(1, uint32(std::lround(any * 10000.0)));
        }

        // The loot tables: which creatures (killed, pickpocketed, skinned), chests, containers,
        // fishing spots and mails can hold one of `wanted`, directly or through reference tables.
        // A reference shared by many creatures is a world drop.
        void ReadLoot(std::unordered_set<uint32> const& wanted, std::unordered_set<uint32>& creatures,
            std::unordered_set<uint32>& objects)
        {
            std::vector<uint32> items = Keys(wanted);
            if (items.empty())
                return;

            // Loot ids -> what uses them.
            std::unordered_map<uint32, std::vector<uint32>> creaturesByLoot, creaturesByPickpocket, creaturesBySkinning;
            for (auto const& [entry, creature] : *sObjectMgr->GetCreatureTemplates())
            {
                if (creature.lootid)
                    creaturesByLoot[creature.lootid].push_back(entry);
                if (creature.pickpocketLootId)
                    creaturesByPickpocket[creature.pickpocketLootId].push_back(entry);
                if (creature.SkinLootId)
                    creaturesBySkinning[creature.SkinLootId].push_back(entry);
            }

            std::unordered_map<uint32, std::vector<uint32>> objectsByLoot;
            for (auto const& [entry, object] : *sObjectMgr->GetGameObjectTemplates())
                if (uint32 loot = object.GetLootId())
                    objectsByLoot[loot].push_back(entry);

            // reference id -> (item, chance) it can roll, following nested references.
            std::unordered_map<uint32, std::vector<Drop>> refItems;
            for (LootRow const& row : ReadLootRows("reference_loot_template", items, {}))
                refItems[row.entry].push_back({ row.item, row.chance });

            std::vector<uint32> frontier;
            for (auto const& [ref, drops] : refItems)
                frontier.push_back(ref);
            for (int depth = 0; depth < 4 && !frontier.empty(); ++depth)
            {
                std::vector<LootRow> parents = ReadLootRows("reference_loot_template", {}, frontier);
                frontier.clear();
                for (LootRow const& parent : parents)
                {
                    std::vector<Drop> childDrops = refItems[parent.reference];
                    bool isNew = !refItems.count(parent.entry);
                    std::vector<Drop>& into = refItems[parent.entry];
                    for (Drop const& drop : childDrops)
                        into.push_back({ drop.id, Combine(drop.chance, parent.chance, parent.rolls) });
                    if (isNew)
                        frontier.push_back(parent.entry);
                }
            }

            std::vector<uint32> refs;
            for (auto const& [ref, drops] : refItems)
                refs.push_back(ref);

            // Per item: source id -> best chance, and for creatures, the ones reached via references.
            using Best = std::unordered_map<uint32, std::unordered_map<uint32, uint32>>;
            Best creatureDrops, pickpocketDrops, skinningDrops, objectDrops, containerDrops, fishingDrops;
            std::unordered_map<uint32, std::unordered_map<uint32, uint32>> refCreatures; // item -> creature -> chance

            auto addDrop = [](Best& into, uint32 item, uint32 id, uint32 chance)
            {
                uint32& best = into[item][id];
                best = std::max(best, chance);
            };

            auto readTable = [&](char const* table, auto&& onDrop)
            {
                for (LootRow const& row : ReadLootRows(table, items, refs))
                {
                    if (!row.reference)
                    {
                        onDrop(row.entry, row.item, row.chance, false);
                        continue;
                    }
                    auto itr = refItems.find(row.reference);
                    if (itr != refItems.end())
                        for (Drop const& drop : itr->second)
                            onDrop(row.entry, drop.id, Combine(drop.chance, row.chance, row.rolls), true);
                }
            };

            readTable("creature_loot_template", [&](uint32 loot, uint32 item, uint32 chance, bool viaRef)
            {
                auto itr = creaturesByLoot.find(loot);
                if (itr == creaturesByLoot.end())
                    return;
                for (uint32 creature : itr->second)
                {
                    if (viaRef)
                    {
                        uint32& best = refCreatures[item][creature];
                        best = std::max(best, chance);
                    }
                    else
                        addDrop(creatureDrops, item, creature, chance);
                }
            });

            auto byOwners = [&](std::unordered_map<uint32, std::vector<uint32>> const& owners, Best& into)
            {
                return [&owners, &into, &addDrop](uint32 loot, uint32 item, uint32 chance, bool)
                {
                    auto itr = owners.find(loot);
                    if (itr != owners.end())
                        for (uint32 owner : itr->second)
                            addDrop(into, item, owner, chance);
                };
            };
            readTable("pickpocketing_loot_template", byOwners(creaturesByPickpocket, pickpocketDrops));
            readTable("skinning_loot_template", byOwners(creaturesBySkinning, skinningDrops));
            readTable("gameobject_loot_template", byOwners(objectsByLoot, objectDrops));

            readTable("item_loot_template", [&](uint32 container, uint32 item, uint32 chance, bool)
            {
                if (container != item)
                    addDrop(containerDrops, item, container, chance);
            });
            readTable("fishing_loot_template", [&](uint32 area, uint32 item, uint32 chance, bool)
            {
                addDrop(fishingDrops, item, area, chance);
            });
            readTable("mail_loot_template", [&](uint32, uint32 item, uint32, bool)
            {
                sData.items[item].mail = true;
            });

            // Shared tables reach many templates that never spawn (event, test and unused ones);
            // only spawned creatures count, for the size of a world drop, its level range and
            // where it drops.
            for (auto& [item, all] : refCreatures)
            {
                std::vector<uint32> list;
                for (auto const& [entry, chance] : all)
                    if (sData.spawnedCreatures.count(entry))
                        list.push_back(entry);
                ItemSources& sources = sData.items[item];
                if (list.size() > GetConfig().worldDropThreshold)
                {
                    sources.worldDropCreatures = uint32(list.size());
                    sources.worldMinLevel = 255;
                    std::unordered_map<uint32, uint32> perMap;
                    uint32 inInstances = 0;
                    for (uint32 entry : list)
                    {
                        if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(entry))
                        {
                            sources.worldMinLevel = std::min<uint32>(sources.worldMinLevel, creature->minlevel);
                            sources.worldMaxLevel = std::max<uint32>(sources.worldMaxLevel, creature->maxlevel);
                        }
                        auto map = sData.creatureMap.find(entry);
                        if (map == sData.creatureMap.end())
                            continue;
                        ++perMap[map->second];
                        MapEntry const* mapEntry = sMapStore.LookupEntry(map->second);
                        if (mapEntry && mapEntry->Instanceable())
                            ++inInstances;
                    }
                    // Mostly in dungeons or raids (a raid's trash shares one table): name them.
                    // Otherwise the continents (not transports), leaving out a few strays.
                    sources.worldInstances = inInstances * 2 > list.size();
                    std::vector<std::pair<uint32, uint32>> ranked; // count, map
                    for (auto const& [map, count] : perMap)
                    {
                        MapEntry const* mapEntry = sMapStore.LookupEntry(map);
                        if (mapEntry && (sources.worldInstances ? mapEntry->Instanceable() : mapEntry->IsContinent()))
                            ranked.emplace_back(count, map);
                    }
                    std::sort(ranked.begin(), ranked.end(), [](auto const& a, auto const& b)
                        { return a.first != b.first ? a.first > b.first : a.second < b.second; });
                    for (std::size_t i = 0; i < ranked.size() && i < 3 && ranked[i].first * 4 >= ranked.front().first; ++i)
                        sources.worldMaps.push_back(ranked[i].second);
                }
                else if (!list.empty())
                    for (uint32 entry : list)
                        addDrop(creatureDrops, item, entry, all[entry]);
                else
                    for (auto const& [entry, chance] : all)
                        addDrop(creatureDrops, item, entry, chance);
            }

            // A big shared pickpocket or skinning table (lockboxes) isn't worth a spawn lookup each:
            // those are summed up rather than listed.
            auto store = [](Best const& from, std::vector<Drop> ItemSources::*member, std::unordered_set<uint32>* interesting,
                std::size_t listedUpTo)
            {
                for (auto const& [item, byId] : from)
                {
                    std::vector<Drop>& into = sData.items[item].*member;
                    for (auto const& [id, chance] : byId)
                    {
                        into.push_back({ id, chance });
                        if (interesting && byId.size() <= listedUpTo)
                            interesting->insert(id);
                    }
                    std::sort(into.begin(), into.end(), [](Drop const& a, Drop const& b)
                        { return a.chance != b.chance ? a.chance > b.chance : a.id < b.id; });
                }
            };
            constexpr std::size_t ALL = std::numeric_limits<std::size_t>::max();
            store(creatureDrops, &ItemSources::creatures, &creatures, ALL);
            store(pickpocketDrops, &ItemSources::pickpocket, &creatures, GetConfig().worldDropThreshold);
            store(skinningDrops, &ItemSources::skinning, &creatures, GetConfig().worldDropThreshold);
            store(objectDrops, &ItemSources::objects, &objects, ALL);
            store(containerDrops, &ItemSources::containers, nullptr, ALL);
            store(fishingDrops, &ItemSources::fishing, nullptr, ALL);
        }

        // The bags, boxes and lockboxes recipe items are found in, which aren't recipe items
        // themselves: where those come from is part of the answer.
        std::unordered_set<uint32> ContainersOf(std::unordered_set<uint32> const& items)
        {
            std::unordered_set<uint32> out;
            for (uint32 item : items)
            {
                auto itr = sData.items.find(item);
                if (itr != sData.items.end())
                    for (Drop const& d : itr->second.containers)
                        if (!items.count(d.id))
                            out.insert(d.id);
            }
            return out;
        }

        void ReadDiscoveries()
        {
            QueryResult result = WorldDatabase.Query("SELECT CAST(spellId AS UNSIGNED), CAST(reqSpell AS SIGNED), "
                "CAST(reqSkillValue AS UNSIGNED), CAST(ROUND(chance * 100) AS UNSIGNED) FROM skill_discovery_template");
            if (!result)
                return;
            do
            {
                Field* f = result->Fetch();
                auto itr = sData.recipes.find(uint32(f[0].Get<uint64>()));
                if (itr == sData.recipes.end())
                    continue;
                // The core never rolls a discovery without a chance.
                if (!f[3].Get<uint64>())
                    continue;
                int64 reqSpell = f[1].Get<int64>();
                itr->second.discoveries.push_back({ reqSpell > 0 ? uint32(reqSpell) : 0, uint32(f[2].Get<uint64>()),
                    uint32(f[3].Get<uint64>()) });
            } while (result->NextRow());
        }

        void LoadSavedZones(std::unordered_map<uint32, std::pair<uint32, uint32>>& zones, char const* table)
        {
            if (QueryResult result = WorldDatabase.Query("SELECT CAST(guid AS UNSIGNED), CAST(zoneId AS UNSIGNED), "
                "CAST(areaId AS UNSIGNED) FROM {} WHERE zoneId <> 0", table))
                do
                {
                    Field* fields = result->Fetch();
                    zones[uint32(fields[0].Get<uint64>())] = { uint32(fields[1].Get<uint64>()), uint32(fields[2].Get<uint64>()) };
                } while (result->NextRow());
        }

        void CollectSpawnedCreatures()
        {
            for (auto const& [spawnId, data] : sObjectMgr->GetAllCreatureData())
            {
                sData.spawnedCreatures.insert(data.id);
                sData.creatureMap.emplace(data.id, data.mapid);
            }
        }

        // Creatures that are only out while a game event runs (a holiday's vendors, the
        // Darkmoon Faire): every spawn of them belongs to one.
        void ReadEventOnlyCreatures()
        {
            std::unordered_map<uint32, uint32> spawns;
            for (auto const& [spawnId, data] : sObjectMgr->GetAllCreatureData())
                ++spawns[data.id];

            // entry -> spawns in events (a spawn can be in several), first event
            std::unordered_map<uint32, std::pair<std::unordered_set<uint32>, uint32>> inEvents;
            if (QueryResult result = WorldDatabase.Query("SELECT CAST(guid AS UNSIGNED), CAST(eventEntry AS SIGNED) "
                "FROM game_event_creature WHERE eventEntry > 0"))
                do
                {
                    Field* f = result->Fetch();
                    uint32 guid = uint32(f[0].Get<uint64>());
                    if (CreatureData const* data = sObjectMgr->GetCreatureData(guid))
                    {
                        auto& [guids, event] = inEvents[data->id];
                        if (guids.empty())
                            event = uint32(f[1].Get<int64>());
                        guids.insert(guid);
                    }
                } while (result->NextRow());

            for (auto const& [entry, inEvent] : inEvents)
                if (inEvent.first.size() >= spawns[entry])
                    sData.eventOnly[entry] = inEvent.second;
        }

        // Spawns of each trainer, vendor (MAX_SPAWNS, to find a near one), dropping creature and
        // object (a few, for the zone), with their zones: saved in the database, or worked out
        // from the map files (and saved for next time). Dungeons are named after their map instead.
        // The progression window a spawn's mod-individual-progression script shows it in.
        void SetProgressionGate(Spawn& spawn, uint32 scriptId)
        {
            Config const& config = GetConfig();
            if (!scriptId || !config.progressionEnabled)
                return;

            std::string const& script = sObjectMgr->GetScriptName(scriptId);
            if (script == "npc_ipp_zg" || script == "npc_ipp_za")
            {
                spawn.ipFrom = script == "npc_ipp_zg" ? config.zulGurubState : config.zulAmanState;
                return;
            }

            auto gate = std::find_if(PROGRESSION_GATES.begin(), PROGRESSION_GATES.end(),
                [&](ProgressionGate const& g) { return g.script == script; });
            if (gate == PROGRESSION_GATES.end())
                return;

            // hasPassedProgression() is never true for a state past the limit.
            uint8 limit = config.progressionLimit;
            spawn.ipFrom = limit && gate->from > limit ? IP_STATE_NEVER : gate->from;
            spawn.ipBefore = gate->passedBefore && limit && gate->before > limit ? 0 : gate->before;
        }

        void ReadSpawns(std::unordered_set<uint32> const& service, std::unordered_set<uint32> const& droppers,
            std::unordered_set<uint32> const& objects)
        {
            std::unordered_map<uint32, std::pair<uint32, uint32>> savedCreatures;
            std::unordered_map<uint32, std::pair<uint32, uint32>> savedObjects;
            LoadSavedZones(savedCreatures, "creature");
            LoadSavedZones(savedObjects, "gameobject");

            WorldDatabaseTransaction trans = WorldDatabase.BeginTransaction();
            uint32 computed = 0;

            auto place = [&](SpawnData const& data, std::unordered_map<uint32, std::pair<uint32, uint32>> const& saved,
                char const* table)
            {
                Spawn spawn;
                spawn.map = data.mapid;
                spawn.x = data.posX;
                spawn.y = data.posY;
                spawn.phaseMask = data.phaseMask;
                MapEntry const* map = sMapStore.LookupEntry(data.mapid);
                if (!map || map->Instanceable())
                    return spawn;

                auto itr = saved.find(data.spawnId);
                if (itr != saved.end())
                    std::tie(spawn.zone, spawn.area) = itr->second;
                else
                {
                    sMapMgr->GetZoneAndAreaId(data.phaseMask, spawn.zone, spawn.area, data.mapid, data.posX, data.posY, data.posZ);
                    // A first start may load a lot of terrain here, before the world loop runs:
                    // keep the freeze detector (MaxCoreStuckTime) from taking it for a hang.
                    if (++computed % 200 == 0)
                        ++World::m_worldLoopCounter;
                    if (GetConfig().saveZoneData && spawn.zone)
                        trans->Append("UPDATE {} SET zoneId = {}, areaId = {} WHERE guid = {}", table, spawn.zone, spawn.area, data.spawnId);
                }
                return spawn;
            };

            for (auto const& [spawnId, data] : sObjectMgr->GetAllCreatureData())
            {
                std::size_t keep = service.count(data.id) ? MAX_SPAWNS : droppers.count(data.id) ? MAX_DROP_SPAWNS : 0;
                if (!keep)
                    continue;
                std::vector<Spawn>& spawns = sData.creatureSpawns[data.id];
                if (spawns.size() < keep)
                {
                    spawns.push_back(place(data, savedCreatures, "creature"));
                    CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(data.id);
                    SetProgressionGate(spawns.back(), data.ScriptId ? data.ScriptId : creature ? creature->ScriptID : 0);
                }
            }

            for (auto const& [spawnId, data] : sObjectMgr->GetAllGOData())
            {
                if (!objects.count(data.id))
                    continue;
                std::vector<Spawn>& spawns = sData.objectSpawns[data.id];
                if (spawns.size() < MAX_DROP_SPAWNS)
                {
                    spawns.push_back(place(data, savedObjects, "gameobject"));
                    GameObjectTemplate const* object = sObjectMgr->GetGameObjectTemplate(data.id);
                    SetProgressionGate(spawns.back(), data.ScriptId ? data.ScriptId : object ? object->ScriptId : 0);
                }
            }

            if (trans->GetSize())
                WorldDatabase.CommitTransaction(trans);

            LOG_INFO("server.loading", ">> mod-retail-professions: {} sources spawned; worked out {} zones",
                sData.creatureSpawns.size() + sData.objectSpawns.size(), computed);
        }

        bool Spawned(uint32 creature)
        {
            return sData.creatureSpawns.count(creature) != 0;
        }

        // Drops nobody can reach (templates never spawned), unless nothing else drops the item:
        // a summoned boss is still a source.
        void PruneUnspawned(std::vector<Drop>& drops, std::unordered_map<uint32, std::vector<Spawn>> const& spawns)
        {
            bool anySpawned = std::any_of(drops.begin(), drops.end(), [&](Drop const& d) { return spawns.count(d.id) != 0; });
            if (anySpawned)
                drops.erase(std::remove_if(drops.begin(), drops.end(), [&](Drop const& d) { return !spawns.count(d.id); }), drops.end());
            else if (drops.size() > 3)
                drops.resize(3);
        }

        // The skill a recipe needs. SkillLineAbility's MinSkillLineRank is 1 for nearly every
        // recipe (it only means something for recipes learned on reaching a skill), so the need
        // comes from what teaches it: the trainer's rank, the recipe item's required skill, the
        // discovery's skill. Without any of those, the yellow threshold is the closest guess.
        uint32 RequiredSkill(Recipe const& recipe)
        {
            uint32 need = std::numeric_limits<uint32>::max();
            auto consider = [&](uint32 value) { if (value) need = std::min(need, value); };
            for (TrainerSource const& t : recipe.trainers)
                consider(t.reqSkill);
            for (uint32 entry : recipe.recipeItems)
            {
                auto itr = sData.items.find(entry);
                ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
                if (item && itr != sData.items.end() && itr->second.teams)
                    consider(item->RequiredSkillRank);
            }
            for (DiscoverySource const& d : recipe.discoveries)
                consider(d.reqSkill);
            for (Teacher const& t : recipe.teachers)
                if (t.reqSkill == recipe.skill)
                    consider(t.reqSkillValue);
            // Only rows for everyone: a race's or class's own (death knights get First Aid's
            // bandages with the skill) would otherwise read as "needs 1" for the rest.
            for (AutoRow const& row : recipe.autoRows)
                if (!row.raceMask && !row.classMask)
                    consider(row.skill ? row.skill : 1);
            if (need != std::numeric_limits<uint32>::max())
                return need;
            if (recipe.reqSkill > 1)
                return recipe.reqSkill;
            return std::max<uint32>(1, recipe.yellow);
        }

        // Which factions can get at each item and recipe, now that spawns are known.
        void Finish()
        {
            for (auto& [entry, sources] : sData.items)
            {
                sources.vendors.erase(std::remove_if(sources.vendors.begin(), sources.vendors.end(),
                    [](Vendor const& v) { return !Spawned(v.creature); }), sources.vendors.end());
                PruneUnspawned(sources.creatures, sData.creatureSpawns);
                PruneUnspawned(sources.objects, sData.objectSpawns);
                for (std::vector<Drop>* list : { &sources.pickpocket, &sources.skinning })
                    list->erase(std::remove_if(list->begin(), list->end(),
                        [](Drop const& d) { return !sData.spawnedCreatures.count(d.id); }), list->end());

                ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
                uint8 itemTeams = item ? TeamsOfRaceMask(item->AllowableRace == uint32(-1) ? 0 : item->AllowableRace) : TEAMBIT_BOTH;

                uint8 reach = 0;
                for (Vendor const& vendor : sources.vendors)
                    if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(vendor.creature))
                        reach |= TeamsOfFaction(creature->faction);
                if (!sources.creatures.empty() || !sources.pickpocket.empty() || !sources.skinning.empty() || !sources.objects.empty()
                    || !sources.containers.empty() || !sources.fishing.empty() || sources.mail || sources.worldDropCreatures)
                    reach |= TEAMBIT_BOTH;
                for (uint32 questId : sources.quests)
                    if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                        reach |= TeamsOfRaceMask(quest->GetAllowableRaces());

                sources.teams = itemTeams & reach;
            }

            for (auto& [spell, recipe] : sData.recipes)
            {
                recipe.trainers.erase(std::remove_if(recipe.trainers.begin(), recipe.trainers.end(),
                    [](TrainerSource const& t) { return !Spawned(t.creature); }), recipe.trainers.end());

                recipe.teachers.erase(std::remove_if(recipe.teachers.begin(), recipe.teachers.end(),
                    [](Teacher const& t) { return t.object ? !sData.objectSpawns.count(t.id) : !Spawned(t.id); }), recipe.teachers.end());

                uint8 teams = 0;
                if (!recipe.teachers.empty())
                {
                    recipe.sources |= SRC_NPC;
                    for (Teacher const& t : recipe.teachers)
                    {
                        CreatureTemplate const* creature = t.object ? nullptr : sObjectMgr->GetCreatureTemplate(t.id);
                        teams |= creature ? TeamsOfFaction(creature->faction) : TEAMBIT_BOTH;
                    }
                }
                if (!recipe.trainers.empty())
                {
                    recipe.sources |= SRC_TRAINER;
                    for (TrainerSource const& t : recipe.trainers)
                        if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.creature))
                            teams |= TeamsOfFaction(creature->faction);
                }
                for (uint32 entry : recipe.recipeItems)
                {
                    auto itr = sData.items.find(entry);
                    if (itr != sData.items.end() && itr->second.teams)
                    {
                        recipe.sources |= SRC_ITEM;
                        teams |= itr->second.teams;
                    }
                }
                for (uint32 questId : recipe.quests)
                    if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    {
                        recipe.sources |= SRC_QUEST;
                        teams |= TeamsOfRaceMask(quest->GetAllowableRaces());
                    }
                if (!recipe.discoveries.empty())
                {
                    recipe.sources |= SRC_DISCOVERY;
                    teams |= TEAMBIT_BOTH;
                }
                if (!recipe.autoRows.empty())
                {
                    recipe.sources |= SRC_AUTO;
                    for (AutoRow const& row : recipe.autoRows)
                        teams |= TeamsOfRaceMask(row.raceMask);
                }
                recipe.teams = teams & TeamsOfRaceMask(recipe.raceMask);
                recipe.reqSkill = RequiredSkill(recipe);
            }

            for (auto& [skill, spells] : sData.bySkill)
                std::sort(spells.begin(), spells.end(), [](uint32 a, uint32 b)
                {
                    Recipe const& ra = sData.recipes.at(a);
                    Recipe const& rb = sData.recipes.at(b);
                    return ra.reqSkill != rb.reqSkill ? ra.reqSkill < rb.reqSkill : a < b;
                });
        }

        std::string ListRow(Recipe const& recipe, uint32 recipeItem)
        {
            return Acore::StringFormat("{},{},{},{},{},{},{},{},{},{},{},{},{},{}", recipe.spell, recipe.reqSkill, recipe.yellow,
                recipe.grey, recipe.item, recipe.madeMin, recipe.madeMax, uint32(recipe.sources), recipe.reagents,
                recipe.invType, recipe.quality, recipeItem, recipe.targetsItem ? 1 : 0, uint32(Perks::Flags(recipe.spell)));
        }

        // FNV-1a over everything an L row can carry, so the addon's cache follows the data.
        void ComputeStamp()
        {
            uint32 hash = 2166136261u;
            auto mix = [&](std::string const& text)
            {
                for (unsigned char c : text)
                {
                    hash ^= c;
                    hash *= 16777619u;
                }
            };
            mix(std::to_string(PROTOCOL_VERSION));
            for (uint32 skill : PROFESSIONS)
            {
                auto itr = sData.bySkill.find(skill);
                if (itr == sData.bySkill.end())
                    continue;
                for (uint32 spell : itr->second)
                {
                    Recipe const& recipe = sData.recipes[spell];
                    mix(ListRow(recipe, recipe.recipeItems.empty() ? 0 : recipe.recipeItems.front()));
                    mix(std::to_string(recipe.teams) + ":" + std::to_string(recipe.raceMask) + ":" + std::to_string(recipe.classMask));
                }
            }
            sData.stamp = hash ? hash : 1;
        }

        // ---- who sees what ---------------------------------------------------------------------

        struct Viewer
        {
            Player* player = nullptr;
            FactionTemplateEntry const* faction = nullptr;
            uint8 progression = 18;
            uint8 team = TEAMBIT_BOTH;
            bool everything = false;
        };

        Viewer MakeViewer(Player* player)
        {
            Viewer viewer;
            viewer.player = player;
            viewer.faction = player->GetFactionTemplateEntry();
            viewer.team = TeamOf(player);
            viewer.everything = player->IsGameMaster();
            viewer.progression = ProgressionState(player);
            return viewer;
        }

        // The progression state that opens the continent or expansion a spawn is in; 0 = always open.
        uint8 RegionState(Spawn const& spawn)
        {
            if (spawn.map == MAP_OUTLAND)
            {
                if (std::find(ZONES_OPEN_ON_OUTLAND_MAP.begin(), ZONES_OPEN_ON_OUTLAND_MAP.end(), spawn.zone) != ZONES_OPEN_ON_OUTLAND_MAP.end())
                    return 0;
                return spawn.zone == ZONE_ISLE_OF_QUEL_DANAS ? IP_STATE_QUEL_DANAS : IP_STATE_TBC;
            }

            // Dungeons and Northrend by the expansion their map belongs to.
            MapEntry const* map = sMapStore.LookupEntry(spawn.map);
            uint32 expansion = map ? map->Expansion() : 0;
            if (expansion >= 2)
                return IP_STATE_WOTLK;
            if (expansion == 1)
                return IP_STATE_TBC;
            return 0;
        }

        // Whether the continent or expansion a spawn is in is open to the player.
        bool RegionOpen(Viewer const& viewer, Spawn const& spawn)
        {
            if (viewer.everything || !GetConfig().hideLockedContinents)
                return true;
            if (spawn.map == MAP_EBON_HOLD)
                return viewer.player->getClass() == CLASS_DEATH_KNIGHT;
            return viewer.progression >= RegionState(spawn);
        }

        // Whether a mod-individual-progression script lets the player see the spawn.
        bool ProgressionShows(Viewer const& viewer, Spawn const& spawn)
        {
            if (viewer.everything || !GetConfig().progressionEnabled)
                return true;
            return viewer.progression >= spawn.ipFrom && (!spawn.ipBefore || viewer.progression < spawn.ipBefore);
        }

        // A spawn the player can see and get to: its region is open and no progression script hides it.
        bool IsOpen(Viewer const& viewer, Spawn const& spawn)
        {
            return ProgressionShows(viewer, spawn) && RegionOpen(viewer, spawn);
        }

        bool IsFriendly(Viewer const& viewer, uint32 factionTemplate)
        {
            if (viewer.everything || !viewer.faction)
                return true;
            FactionTemplateEntry const* faction = sFactionTemplateStore.LookupEntry(factionTemplate);
            if (!faction)
                return true;
            if (faction->IsHostileTo(*viewer.faction))
                return false;
            return viewer.player->GetReputationRank(faction->faction) > REP_HOSTILE;
        }

        bool InPhase(Viewer const& viewer, Spawn const& spawn)
        {
            return (spawn.phaseMask & (PHASEMASK_NORMAL | viewer.player->GetPhaseMask())) != 0;
        }

        // The spawn a player would go to: the nearest on their map, else the first one open to them.
        Spawn const* BestSpawn(Viewer const& viewer, std::vector<Spawn> const* spawns, bool needPhase)
        {
            if (!spawns)
                return nullptr;
            Spawn const* best = nullptr;
            float bestDist = 0.0f;
            for (Spawn const& spawn : *spawns)
            {
                if (!IsOpen(viewer, spawn) || (needPhase && !InPhase(viewer, spawn)))
                    continue;
                float dist = spawn.map == viewer.player->GetMapId()
                    ? viewer.player->GetExactDist2d(spawn.x, spawn.y) : 1e9f;
                if (!best || dist < bestDist)
                {
                    best = &spawn;
                    bestDist = dist;
                }
            }
            return best;
        }

        // Where a creature or object is that nothing open to this player has yet: the region the
        // first spawn is in, for a "more once it opens" note; empty when it isn't locked away.
        std::string LockedRegion(Viewer const& viewer, std::vector<Spawn> const* spawns)
        {
            if (!spawns || spawns->empty() || viewer.everything || !GetConfig().hideLockedContinents)
                return "";
            for (Spawn const& spawn : *spawns)
                if (IsOpen(viewer, spawn))
                    return "";
            Spawn const& spawn = spawns->front();
            if (spawn.map == MAP_EBON_HOLD || RegionOpen(viewer, spawn))
                return "";
            // Not when a progression script still hides it once the region opens.
            uint8 opens = RegionState(spawn);
            if (GetConfig().progressionEnabled && (spawn.ipFrom > opens || (spawn.ipBefore && spawn.ipBefore <= opens)))
                return "";
            if (spawn.map == MAP_OUTLAND)
                return spawn.zone == ZONE_ISLE_OF_QUEL_DANAS ? AreaName(ZONE_ISLE_OF_QUEL_DANAS) : MapName(MAP_OUTLAND);
            return opens == IP_STATE_TBC ? MapName(MAP_OUTLAND) : MapName(MAP_NORTHREND);
        }

        // A friendly creature the player can walk up to: its nearest open spawn. When it's only
        // somewhere they can't go yet, `locked` (if given) gets the region.
        bool CanUseCreature(Viewer const& viewer, uint32 entry, Spawn const** where, std::string* locked = nullptr)
        {
            CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(entry);
            if (!creature || !IsFriendly(viewer, creature->faction))
                return false;
            auto itr = sData.creatureSpawns.find(entry);
            std::vector<Spawn> const* spawns = itr != sData.creatureSpawns.end() ? &itr->second : nullptr;
            *where = BestSpawn(viewer, spawns, true);
            if (!*where && locked)
                *locked = LockedRegion(viewer, spawns);
            return *where != nullptr;
        }

        // A drop source is shown unless every spawn of it is somewhere the player can't go yet.
        bool DropOpen(Viewer const& viewer, std::unordered_map<uint32, std::vector<Spawn>> const& all, uint32 id, Spawn const** where,
            std::string* locked = nullptr)
        {
            auto itr = all.find(id);
            if (itr == all.end())
            {
                *where = nullptr;
                return true;
            }
            *where = BestSpawn(viewer, &itr->second, false);
            if (!*where && locked)
                *locked = LockedRegion(viewer, &itr->second);
            return *where != nullptr;
        }

        bool MatchesMasks(Player* player, uint32 raceMask, uint32 classMask)
        {
            return (!raceMask || (raceMask & player->getRaceMask())) && (!classMask || (classMask & player->getClassMask()));
        }

        // A recipe item this player could use: their race, their faction's sources, and the
        // specialization it needs (Gnomish/Goblin Engineer, Armorsmith ...).
        bool PlayerMayUseItem(Player* player, uint32 entry)
        {
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
            if (!item)
                return false;
            if (item->AllowableRace && item->AllowableRace != uint32(-1) && !(item->AllowableRace & player->getRaceMask()))
                return false;
            if (item->AllowableClass && item->AllowableClass != uint32(-1) && !(item->AllowableClass & player->getClassMask()))
                return false;
            if (item->RequiredSpell && !player->HasSpell(item->RequiredSpell))
                return false;
            return true;
        }

        uint32 RecipeItemFor(Player* player, Recipe const& recipe)
        {
            uint8 team = TeamOf(player);
            for (uint32 entry : recipe.recipeItems)
            {
                auto itr = sData.items.find(entry);
                if (itr != sData.items.end() && (itr->second.teams & team) && PlayerMayUseItem(player, entry))
                    return entry;
            }
            return 0;
        }

        bool TrainerTeaches(Player* player, TrainerSource const& t)
        {
            for (uint32 ability : t.reqAbility)
                if (ability && !player->HasSpell(ability))
                    return false;
            return true;
        }

        // A scripted teacher's option shows only to those who know the spells it asks for.
        bool TeacherTeaches(Player* player, Teacher const& t)
        {
            for (uint32 spell : t.reqSpells)
                if (!player->HasSpell(spell))
                    return false;
            return true;
        }

        bool QuestOpen(Player* player, Quest const* quest)
        {
            return !quest->GetAllowableRaces() || (quest->GetAllowableRaces() & player->getRaceMask());
        }

        AutoRow const* AutoRowFor(Player* player, Recipe const& recipe)
        {
            for (AutoRow const& row : recipe.autoRows)
                if (MatchesMasks(player, row.raceMask, row.classMask))
                    return &row;
            return nullptr;
        }

        // Whether anything teaches this player the recipe (by faction, race, class and
        // specialization). Where it is, and whether the player can get there yet, is W's business.
        bool Learnable(Player* player, Recipe const& recipe)
        {
            uint8 team = TeamOf(player);
            if (!(recipe.teams & team) || !MatchesMasks(player, recipe.raceMask, recipe.classMask))
                return false;
            if (AutoRowFor(player, recipe) || !recipe.discoveries.empty() || RecipeItemFor(player, recipe))
                return true;
            for (TrainerSource const& t : recipe.trainers)
                if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.creature))
                    if ((TeamsOfFaction(creature->faction) & team) && TrainerTeaches(player, t))
                        return true;
            for (Teacher const& t : recipe.teachers)
            {
                CreatureTemplate const* creature = t.object ? nullptr : sObjectMgr->GetCreatureTemplate(t.id);
                if ((!creature || (TeamsOfFaction(creature->faction) & team)) && TeacherTeaches(player, t))
                    return true;
            }
            for (uint32 questId : recipe.quests)
                if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    if (QuestOpen(player, quest))
                        return true;
            return false;
        }

        // "Honored with Thorium Brotherhood", or empty.
        std::string ReputationText(ItemTemplate const* item)
        {
            if (!item || !item->RequiredReputationFaction)
                return "";
            FactionEntry const* faction = sFactionStore.LookupEntry(item->RequiredReputationFaction);
            if (!faction)
                return "";
            static char const* const RANKS[] = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" };
            uint32 rank = std::min<uint32>(item->RequiredReputationRank, 7);
            return std::string(RANKS[rank]) + " with " + DbcString(faction->name);
        }

        std::string QuestZone(Quest const* quest)
        {
            return quest->GetZoneOrSort() > 0 ? AreaName(uint32(quest->GetZoneOrSort())) : "";
        }

        // ---- words for the guide ---------------------------------------------------------------

        std::string Join(std::vector<std::string> const& parts, std::string_view sep)
        {
            std::string out;
            for (std::string const& part : parts)
            {
                if (part.empty())
                    continue;
                if (!out.empty())
                    out += sep;
                out += part;
            }
            return out;
        }

        std::string ItemName(uint32 entry)
        {
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
            return item ? item->Name1 : "";
        }

        std::string SpellName(uint32 spell)
        {
            SpellInfo const* info = sSpellMgr->GetSpellInfo(spell);
            return info ? DbcString(info->SpellName) : "";
        }

        std::string SkillName(uint32 skill)
        {
            SkillLineEntry const* line = sSkillLineStore.LookupEntry(skill);
            return line ? DbcString(line->name) : "";
        }

        std::string QuestTitle(uint32 questId)
        {
            Quest const* quest = sObjectMgr->GetQuestTemplate(questId);
            return quest ? quest->GetTitle() : "";
        }

        // A game event's name ("Winter Veil", "Darkmoon Faire (Elwynn Forest)").
        std::string EventName(uint32 event)
        {
            GameEventMgr::GameEventDataMap const& events = sGameEventMgr->GetEventMap();
            return event < events.size() ? events[event].Description : "";
        }

        std::string EventOnly(uint32 creature)
        {
            auto itr = sData.eventOnly.find(creature);
            if (itr == sData.eventOnly.end())
                return "";
            std::string name = EventName(itr->second);
            return name.empty() ? "during an event" : name + " only";
        }

        // What a vendor wants besides gold: "3 Dalaran Cooking Award", "40 Badge of Justice".
        std::string CostText(uint32 extendedCost)
        {
            ItemExtendedCostEntry const* cost = sItemExtendedCostStore.LookupEntry(extendedCost);
            if (!cost)
                return "";
            std::vector<std::string> parts;
            for (uint32 i = 0; i < MAX_ITEM_EXTENDED_COST_REQUIREMENTS; ++i)
                if (cost->reqitem[i] && cost->reqitemcount[i])
                    parts.push_back(Acore::StringFormat("{} {}", cost->reqitemcount[i], ItemName(cost->reqitem[i])));
            if (cost->reqhonorpoints)
                parts.push_back(Acore::StringFormat("{} honor", cost->reqhonorpoints));
            if (cost->reqarenapoints)
                parts.push_back(Acore::StringFormat("{} arena points", cost->reqarenapoints));
            if (cost->reqpersonalarenarating)
                parts.push_back(Acore::StringFormat("{} personal arena rating", cost->reqpersonalarenarating));
            return Join(parts, ", ");
        }

        // Rare spawns and bosses, worth a word next to their name.
        std::string RankTag(CreatureTemplate const* creature)
        {
            if (creature->rank == CREATURE_ELITE_RARE || creature->rank == CREATURE_ELITE_RAREELITE)
                return "rare";
            if (creature->rank == CREATURE_ELITE_WORLDBOSS || (creature->flags_extra & CREATURE_FLAG_EXTRA_DUNGEON_BOSS))
                return "boss";
            return "";
        }

        std::string Levels(CreatureTemplate const* creature)
        {
            return creature->minlevel == creature->maxlevel ? std::to_string(creature->minlevel)
                : Acore::StringFormat("{}-{}", creature->minlevel, creature->maxlevel);
        }

        std::string Percent(uint32 x100)
        {
            if (!x100)
                return "";
            return x100 >= 1000 ? Acore::StringFormat("{}%", x100 / 100) : Acore::StringFormat("{:.1f}%", x100 / 100.0f);
        }

        // Several creatures summed up: "12 kinds of creatures, level 20-35".
        std::string CreatureSpread(std::vector<Drop> const& drops)
        {
            uint32 low = 255, high = 0;
            for (Drop const& d : drops)
                if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(d.id))
                {
                    low = std::min<uint32>(low, creature->minlevel);
                    high = std::max<uint32>(high, creature->maxlevel);
                }
            if (high < low)
                return Acore::StringFormat("{} kinds of creatures", drops.size());
            return Acore::StringFormat("{} kinds of creatures, level {}", drops.size(),
                low == high ? std::to_string(low) : Acore::StringFormat("{}-{}", low, high));
        }

        std::string WorldPlaces(ItemSources const& sources)
        {
            std::vector<std::string> names;
            for (uint32 map : sources.worldMaps)
                names.push_back(MapName(map));
            return Join(names, ", ");
        }

        // Where a quest is picked up: its giver and their place (the quest's own zone when it
        // has one; profession quests are filed under the profession instead).
        void QuestGiver(Viewer const& viewer, Quest const* quest, std::string& name, std::string& place)
        {
            name.clear();
            place = QuestZone(quest);
            auto giver = sData.questGivers.find(quest->GetQuestId());
            if (giver != sData.questGivers.end())
            {
                if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(giver->second))
                {
                    name = creature->Name;
                    auto itr = sData.creatureSpawns.find(giver->second);
                    if (Spawn const* where = BestSpawn(viewer, itr != sData.creatureSpawns.end() ? &itr->second : nullptr, false))
                        place = PlaceName(*where);
                }
                return;
            }
            auto object = sData.questObjects.find(quest->GetQuestId());
            if (object != sData.questObjects.end())
                if (GameObjectTemplate const* go = sObjectMgr->GetGameObjectTemplate(object->second))
                {
                    name = go->name;
                    auto itr = sData.objectSpawns.find(object->second);
                    if (Spawn const* where = BestSpawn(viewer, itr != sData.objectSpawns.end() ? &itr->second : nullptr, false))
                        place = PlaceName(*where);
                }
        }

        // A quest whose giver a mod-individual-progression script hides from the player at every spawn.
        bool QuestGiverHidden(Viewer const& viewer, Quest const* quest)
        {
            auto giver = sData.questGivers.find(quest->GetQuestId());
            if (giver == sData.questGivers.end())
                return false;
            auto itr = sData.creatureSpawns.find(giver->second);
            if (itr == sData.creatureSpawns.end() || itr->second.empty())
                return false;
            return std::none_of(itr->second.begin(), itr->second.end(), [&](Spawn const& spawn) { return ProgressionShows(viewer, spawn); });
        }

        std::string QuestRepeat(Quest const* quest)
        {
            if (quest->IsDaily())
                return "daily";
            if (quest->IsWeekly())
                return "weekly";
            if (quest->IsRepeatable())
                return "repeatable";
            return "";
        }

        // Tooltip lines about a quest: who gives it, what it needs first.
        std::vector<std::string> QuestDetails(Viewer const& viewer, Quest const* quest)
        {
            std::vector<std::string> lines;
            std::string giver, place;
            QuestGiver(viewer, quest, giver, place);
            if (!giver.empty())
                lines.push_back("Quest giver: " + giver + (place.empty() ? "" : " - " + place));
            if (quest->GetQuestLevel() > 0)
                lines.push_back(Acore::StringFormat("Level {} quest, from level {}", quest->GetQuestLevel(), quest->GetMinLevel()));
            else
                lines.push_back(Acore::StringFormat("From level {}; it scales to your level", quest->GetMinLevel()));
            if (quest->GetRequiredSkill() && quest->GetRequiredSkillValue())
                lines.push_back(Acore::StringFormat("Needs {} {}", SkillName(quest->GetRequiredSkill()), quest->GetRequiredSkillValue()));
            if (quest->GetPrevQuestId() > 0)
                lines.push_back("After the quest " + QuestTitle(uint32(quest->GetPrevQuestId())));
            std::string repeat = QuestRepeat(quest);
            if (!repeat.empty())
                lines.push_back("A " + repeat + " quest");
            return lines;
        }

        // How to get hold of a bag, box or lockbox a recipe item is found in: short, then in full.
        std::vector<std::string> ItemOrigin(Viewer const& viewer, uint32 entry)
        {
            std::vector<std::string> lines;
            auto itr = sData.items.find(entry);
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(entry);
            if (itr == sData.items.end())
                return lines;
            ItemSources const& sources = itr->second;
            uint32 const limit = 3;

            std::vector<uint32> quests;
            for (uint32 questId : sources.quests)
                if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    if ((QuestOpen(viewer.player, quest) || viewer.everything) && !QuestGiverHidden(viewer, quest))
                        quests.push_back(questId);
            for (std::size_t i = 0; i < quests.size() && i < limit; ++i)
            {
                Quest const* quest = sObjectMgr->GetQuestTemplate(quests[i]);
                std::string giver, place;
                QuestGiver(viewer, quest, giver, place);
                std::string repeat = QuestRepeat(quest);
                lines.push_back("Reward from the " + (repeat.empty() ? "" : repeat + " ") + "quest " + quest->GetTitle()
                    + (place.empty() ? "" : " (" + place + ")"));
            }
            if (quests.size() > limit)
                lines.push_back(Acore::StringFormat("... and {} more quests", quests.size() - limit));

            for (Vendor const& v : sources.vendors)
            {
                Spawn const* where = nullptr;
                if (!CanUseCreature(viewer, v.creature, &where))
                    continue;
                std::string cost = CostText(v.extendedCost);
                lines.push_back("Sold by " + sObjectMgr->GetCreatureTemplate(v.creature)->Name + " (" + PlaceName(*where) + ")"
                    + (cost.empty() ? "" : " for " + cost));
                break;
            }

            if (!sources.creatures.empty())
            {
                if (sources.creatures.size() <= limit)
                    for (Drop const& d : sources.creatures)
                    {
                        CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(d.id);
                        Spawn const* where = nullptr;
                        if (creature && DropOpen(viewer, sData.creatureSpawns, d.id, &where))
                            lines.push_back("Dropped by " + creature->Name + (where ? " (" + PlaceName(*where) + ")" : ""));
                    }
                else
                    lines.push_back("Dropped by " + CreatureSpread(sources.creatures));
            }
            if (sources.worldDropCreatures)
            {
                std::string places = WorldPlaces(sources);
                lines.push_back(Acore::StringFormat("World drop, level {}-{}", sources.worldMinLevel, sources.worldMaxLevel)
                    + (places.empty() ? "" : " (" + places + ")"));
            }
            if (!sources.pickpocket.empty())
                lines.push_back("Pickpocketed from " + (sources.pickpocket.size() == 1
                    ? sObjectMgr->GetCreatureTemplate(sources.pickpocket.front().id)->Name : CreatureSpread(sources.pickpocket)));
            if (!sources.skinning.empty())
                lines.push_back("Skinned from " + (sources.skinning.size() == 1
                    ? sObjectMgr->GetCreatureTemplate(sources.skinning.front().id)->Name : CreatureSpread(sources.skinning)));
            for (std::size_t i = 0; i < sources.objects.size() && i < limit; ++i)
                if (GameObjectTemplate const* object = sObjectMgr->GetGameObjectTemplate(sources.objects[i].id))
                {
                    Spawn const* where = nullptr;
                    DropOpen(viewer, sData.objectSpawns, sources.objects[i].id, &where);
                    lines.push_back("Found in " + object->name + (where ? " (" + PlaceName(*where) + ")" : ""));
                }
            if (!sources.fishing.empty())
            {
                std::vector<std::string> areas;
                for (std::size_t i = 0; i < sources.fishing.size() && i < limit; ++i)
                    areas.push_back(AreaName(sources.fishing[i].id));
                lines.push_back("Fished up in " + Join(areas, ", "));
            }
            if (sources.mail)
                lines.push_back("Arrives in the mail");
            for (std::size_t i = 0; i < sources.containers.size() && i < limit; ++i)
                lines.push_back("Inside " + ItemName(sources.containers[i].id));
            if (item && item->LockID)
                lines.push_back("Locked: open it with Lockpicking, or ask a rogue");
            return lines;
        }

        // A few words for a container's line; ItemOrigin has the rest.
        std::string ItemOriginNote(ItemSources const& sources, ItemTemplate const* item)
        {
            std::string note;
            bool daily = std::any_of(sources.quests.begin(), sources.quests.end(), [](uint32 id)
            {
                Quest const* quest = sObjectMgr->GetQuestTemplate(id);
                return quest && quest->IsDailyOrWeekly();
            });
            if (!sources.quests.empty())
                note = daily ? "daily quest reward" : "quest reward";
            else if (!sources.vendors.empty())
                note = "sold by a vendor";
            else if (!sources.creatures.empty() || sources.worldDropCreatures)
                note = "dropped by creatures";
            else if (!sources.pickpocket.empty())
                note = "pickpocketed";
            else if (!sources.objects.empty())
                note = "found in chests";
            else if (!sources.fishing.empty())
                note = "fished up";
            else if (sources.mail)
                note = "comes in the mail";
            else if (!sources.containers.empty())
                note = "inside another container";
            if (item && item->LockID)
                note += note.empty() ? "locked" : ", locked";
            return note;
        }

        // A W row out of its first seven fields (already escaped and joined) plus the note and
        // tooltip lines, cut to fit one addon message: detail lines go from the end first, then
        // the note gets shorter. SendRows never splits a row.
        std::string FitRow(std::string const& head, std::string note, std::vector<std::string> details, std::size_t budget)
        {
            auto build = [&]() { return head + "," + Escape(note) + "," + Escape(Join(details, "\n")); };
            std::string out = build();
            while (out.size() > budget && !details.empty())
            {
                details.pop_back();
                out = build();
            }
            while (out.size() > budget && !note.empty())
            {
                note.resize(note.size() > 8 ? note.size() - 8 : 0);
                out = build();
            }
            return out;
        }
    }

    void Build()
    {
        uint32 oldMSTime = getMSTime();
        sData = Data();

        std::unordered_set<uint32> recipeItems;
        std::unordered_set<uint32> service;  // trainers, vendors, teachers and quest givers
        std::unordered_set<uint32> droppers;
        std::unordered_set<uint32> objects;

        CollectSpawnedCreatures();
        ReadEventOnlyCreatures();
        ReadRecipes();
        ReadRanks();
        ReadTrainers(service);
        ReadTeachers(service, objects);
        ReadRecipeItems(recipeItems);
        ReadVendors(recipeItems, service);
        ReadQuests(recipeItems, true);
        ReadLoot(recipeItems, droppers, objects);
        // Then the same for the bags and lockboxes recipe items are found in.
        std::unordered_set<uint32> containers = ContainersOf(recipeItems);
        ReadVendors(containers, service);
        ReadQuests(containers, false);
        ReadLoot(containers, droppers, objects);
        ReadQuestGivers(service, objects);
        ReadDiscoveries();
        ReadSpawns(service, droppers, objects);
        Finish();
        ComputeStamp();

        LOG_INFO("server.loading", ">> mod-retail-professions: indexed {} recipes ({} recipe items, {} containers) in {} ms",
            sData.recipes.size(), recipeItems.size(), containers.size(), GetMSTimeDiffToNow(oldMSTime));
    }

    uint32 Stamp()
    {
        return sData.stamp;
    }

    // L:<req>:<skill> -> every recipe of the profession the player could learn or already knows.
    // Row: spell, required skill, yellow, grey, product item, made min, made max, source bits,
    // reagents ("id*n/id*n" or "-"), product inventory type, product quality, recipe item,
    // 1 when it's cast on an item (an enchant, socket, buckle, lining...), PerkFlags.
    void HandleList(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 skill = 0;
        if (args.size() < 3 || !ParseUInt(args[2], skill))
        {
            SendError(player, req, "bad");
            return;
        }

        // A GM sees everything; the addon doesn't cache that list for the account.
        bool everything = player->IsGameMaster();

        std::vector<std::string> rows;
        auto itr = sData.bySkill.find(skill);
        if (itr != sData.bySkill.end())
            for (uint32 spell : itr->second)
            {
                Recipe const& recipe = sData.recipes.at(spell);
                if (everything || player->HasSpell(spell) || Learnable(player, recipe))
                    rows.push_back(ListRow(recipe, RecipeItemFor(player, recipe)));
            }

        Send(player, "LR:" + req + ":" + std::to_string(skill) + ":" + std::to_string(rows.size()) + ":" + (everything ? "1" : "0"));
        SendRows(player, "LD:" + req, rows);
        Send(player, "LE:" + req);
    }

    // W:<req>:<spell> -> where the player can learn a recipe.
    // Rows: kind, id, name, zone, a, b, c, note, details. The note is a few words that go on the
    // line (a vendor's token price, the holiday it comes with, "rare"); details are tooltip lines
    // separated by '\n'. Kinds:
    //   A  learned automatically             a = skill (0 = with the profession)
    //   T  trainer   id = creature           a = cost (copper), b = skill, c = level (0 = any)
    //   N  taught by someone when asked (a script)  id = creature
    //   G  taught by an object (a book, a tablet)   id = gameobject
    //   V  vendor    id = creature           a = price (copper, 0 = not gold), b = limited stock, c = reputation
    //   D  drop      id = creature           a = chance x100 (0 = unknown), b = "min-max" level
    //   P  pickpocket, K skinning: as D; id 0 = summed up, name = "12 kinds of creatures, level 20-35"
    //   X  world drop                        a = how many creatures, b = "min-max" level, c = where (instances
    //                                        when it's dungeon or raid trash, else continents)
    //   O  object    id = gameobject         a = chance x100
    //   C  container id = item               a = chance x100; note/details = where the container comes from
    //   Q  quest     id = quest              a = quest level, b = min level, c = quest giver
    //   R  quest reward of the recipe item, same fields as Q
    //   S  discovery id = spell crafted (0 = any)   a = chance x100, b = skill
    //   L  more sources where the player can't go yet: name = the region, a = how many
    void HandleWhere(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 spell = 0;
        if (args.size() < 3 || !ParseUInt(args[2], spell))
        {
            SendError(player, req, "bad");
            return;
        }

        auto ritr = sData.recipes.find(spell);
        if (ritr == sData.recipes.end())
        {
            SendError(player, req, "none");
            return;
        }
        Recipe const& recipe = ritr->second;
        Viewer viewer = MakeViewer(player);
        uint32 const limit = GetConfig().maxSourcesPerKind;
        std::vector<std::string> rows;
        std::vector<std::pair<std::string, uint32>> locked; // region, sources there
        std::size_t const budget = MAX_PAYLOAD - std::string("WD:" + req).size() - 1;

        auto row = [&](char kind, uint32 id, std::string const& name, std::string const& zone, std::string const& a,
            std::string const& b = "0", std::string const& c = "-", std::string const& note = "",
            std::vector<std::string> const& details = {})
        {
            rows.push_back(FitRow(Acore::StringFormat("{},{},{},{},{},{},{}", kind, id, Escape(name), Escape(zone), a, b, c),
                note, details, budget));
        };
        auto lockedAt = [&](std::string const& region)
        {
            if (region.empty())
                return;
            auto itr = std::find_if(locked.begin(), locked.end(), [&](auto const& l) { return l.first == region; });
            if (itr == locked.end())
                locked.emplace_back(region, 1);
            else
                ++itr->second;
        };
        auto distance = [&](Spawn const* where)
        {
            return where->map == player->GetMapId() ? player->GetExactDist2d(where->x, where->y) : 1e9f;
        };

        if (AutoRow const* autoRow = AutoRowFor(player, recipe))
            row('A', 0, "", "", std::to_string(autoRow->skill));

        // Trainers: near ones first.
        {
            std::vector<std::pair<float, std::string>> found;
            for (TrainerSource const& t : recipe.trainers)
            {
                Spawn const* where = nullptr;
                std::string region;
                if (!TrainerTeaches(player, t))
                    continue;
                if (!CanUseCreature(viewer, t.creature, &where, &region))
                {
                    lockedAt(region);
                    continue;
                }
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.creature);
                std::vector<std::string> details;
                if (!creature->SubName.empty())
                    details.push_back(creature->SubName);
                if (t.reqSkill)
                    details.push_back(Acore::StringFormat("Teaches it from {} {}", SkillName(recipe.skill), t.reqSkill));
                if (t.reqLevel > 1)
                    details.push_back(Acore::StringFormat("Needs level {}", t.reqLevel));
                for (uint32 ability : t.reqAbility)
                    if (ability)
                        details.push_back("Needs " + SpellName(ability));
                std::string event = EventOnly(t.creature);
                if (!event.empty())
                    details.push_back(event);
                found.emplace_back(distance(where), FitRow(Acore::StringFormat("T,{},{},{},{},{},{}", t.creature,
                    Escape(creature->Name), Escape(PlaceName(*where)), t.cost, t.reqSkill, t.reqLevel), event, details, budget));
            }
            std::sort(found.begin(), found.end(), [](auto const& a, auto const& b) { return a.first < b.first; });
            for (std::size_t i = 0; i < found.size() && i < limit; ++i)
                rows.push_back(found[i].second);
        }

        // Teachers with a script: a gossip option, a book to read.
        for (Teacher const& t : recipe.teachers)
        {
            if (!TeacherTeaches(player, t))
                continue;
            std::vector<std::string> details;
            std::string note;
            if (t.reqSkill && t.reqSkillValue)
                details.push_back(Acore::StringFormat("Needs {} {}", SkillName(t.reqSkill), t.reqSkillValue));
            for (uint32 spellId : t.reqSpells)
                details.push_back("Needs " + SpellName(spellId));
            for (uint32 item : t.reqItems)
            {
                details.push_back("Needs " + ItemName(item) + " in your bags");
                if (note.empty())
                    note = "bring " + ItemName(item);
            }
            for (uint32 questId : t.reqQuests)
            {
                details.push_back("After the quest " + QuestTitle(questId));
                if (note.empty())
                    note = "after " + QuestTitle(questId);
            }
            Spawn const* where = nullptr;
            std::string region;
            if (t.object)
            {
                GameObjectTemplate const* object = sObjectMgr->GetGameObjectTemplate(t.id);
                if (!object || !DropOpen(viewer, sData.objectSpawns, t.id, &where, &region))
                {
                    lockedAt(region);
                    continue;
                }
                details.insert(details.begin(), "Use it to learn the recipe");
                row('G', t.id, object->name, where ? PlaceName(*where) : "", "0", "0", "-", note, details);
            }
            else
            {
                if (!CanUseCreature(viewer, t.id, &where, &region))
                {
                    lockedAt(region);
                    continue;
                }
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(t.id);
                details.insert(details.begin(), "Talk to them to learn the recipe");
                std::string event = EventOnly(t.id);
                if (!event.empty())
                    details.push_back(event);
                row('N', t.id, creature->Name, PlaceName(*where), "0", "0", "-", note.empty() ? event : note, details);
            }
        }

        auto questRow = [&](char kind, Quest const* quest)
        {
            if (QuestGiverHidden(viewer, quest))
                return;
            std::string giver, place;
            QuestGiver(viewer, quest, giver, place);
            row(kind, quest->GetQuestId(), quest->GetTitle(), place,
                std::to_string(quest->GetQuestLevel() > 0 ? uint32(quest->GetQuestLevel()) : std::max<uint32>(1, quest->GetMinLevel())),
                std::to_string(quest->GetMinLevel()), Escape(giver), QuestRepeat(quest), QuestDetails(viewer, quest));
        };

        for (uint32 questId : recipe.quests)
            if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                if (QuestOpen(player, quest))
                    questRow('Q', quest);

        for (DiscoverySource const& d : recipe.discoveries)
        {
            SpellInfo const* from = d.fromSpell ? sSpellMgr->GetSpellInfo(d.fromSpell) : nullptr;
            row('S', d.fromSpell, from ? DbcString(from->SpellName) : "", "", std::to_string(d.chance), std::to_string(d.reqSkill));
        }

        uint32 recipeItem = RecipeItemFor(player, recipe);
        auto iitr = recipeItem ? sData.items.find(recipeItem) : sData.items.end();
        if (iitr != sData.items.end())
        {
            ItemSources const& sources = iitr->second;
            ItemTemplate const* item = sObjectMgr->GetItemTemplate(recipeItem);

            std::vector<std::pair<float, std::string>> vendors;
            for (Vendor const& v : sources.vendors)
            {
                Spawn const* where = nullptr;
                std::string region;
                if (!CanUseCreature(viewer, v.creature, &where, &region))
                {
                    lockedAt(region);
                    continue;
                }
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(v.creature);
                std::string cost = CostText(v.extendedCost);
                std::string event = v.event ? EventName(v.event) : "";
                event = event.empty() ? EventOnly(v.creature) : event + " only";
                std::vector<std::string> details;
                if (!creature->SubName.empty())
                    details.push_back(creature->SubName);
                if (!cost.empty())
                    details.push_back("Costs " + cost + (v.gold && item && item->BuyPrice > 0 ? " and gold" : ""));
                std::string reputation = ReputationText(item);
                if (!reputation.empty())
                    details.push_back("Needs " + reputation);
                if (v.maxcount)
                    details.push_back(Acore::StringFormat("Limited stock ({} at a time), restocks over time", v.maxcount));
                if (!event.empty())
                    details.push_back(event);
                vendors.emplace_back(distance(where), FitRow(Acore::StringFormat("V,{},{},{},{},{},{}", v.creature,
                    Escape(creature->Name), Escape(PlaceName(*where)), v.gold && item ? std::max(0, item->BuyPrice) : 0,
                    v.maxcount ? 1 : 0, Escape(reputation)), Join({ cost, event }, ", "), details, budget));
            }
            std::sort(vendors.begin(), vendors.end(), [](auto const& a, auto const& b) { return a.first < b.first; });
            for (std::size_t i = 0; i < vendors.size() && i < limit; ++i)
                rows.push_back(vendors[i].second);

            for (uint32 questId : sources.quests)
                if (Quest const* quest = sObjectMgr->GetQuestTemplate(questId))
                    if (QuestOpen(player, quest))
                        questRow('R', quest);

            uint32 shown = 0;
            for (Drop const& d : sources.creatures)
            {
                if (shown >= limit)
                    break;
                Spawn const* where = nullptr;
                std::string region;
                CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(d.id);
                if (!creature)
                    continue;
                if (!DropOpen(viewer, sData.creatureSpawns, d.id, &where, &region))
                {
                    lockedAt(region);
                    continue;
                }
                std::string tag = RankTag(creature);
                std::string event = EventOnly(d.id);
                std::vector<std::string> details = { "Level " + Levels(creature) };
                if (d.chance)
                    details.push_back("Drops it " + Percent(d.chance) + " of the time");
                if (tag == "rare")
                    details.push_back("A rare spawn: it isn't always there");
                if (!event.empty())
                    details.push_back(event);
                row('D', d.id, creature->Name, where ? PlaceName(*where) : "", std::to_string(d.chance),
                    std::to_string(creature->minlevel) + "-" + std::to_string(creature->maxlevel), "-", Join({ tag, event }, ", "), details);
                ++shown;
            }

            if (sources.worldDropCreatures)
            {
                std::string places = WorldPlaces(sources);
                std::vector<std::string> details = { Acore::StringFormat("From {} kinds of creatures, level {}-{}",
                    sources.worldDropCreatures, sources.worldMinLevel, sources.worldMaxLevel) };
                if (!places.empty())
                    details.push_back((sources.worldInstances ? "Mostly in " : "Mostly on ") + places);
                if (item && item->Bonding != BIND_WHEN_PICKED_UP)
                    details.push_back("It binds when equipped, so it also turns up on the auction house");
                row('X', 0, "", "", std::to_string(sources.worldDropCreatures),
                    std::to_string(sources.worldMinLevel) + "-" + std::to_string(sources.worldMaxLevel), Escape(places),
                    sources.worldInstances ? "trash" : "", details);
            }

            // Pickpocketing and skinning: name a few, or sum up a big shared table.
            auto creatureList = [&](char kind, std::vector<Drop> const& drops, char const* verb)
            {
                if (drops.empty())
                    return;
                if (drops.size() > limit)
                {
                    row(kind, 0, CreatureSpread(drops), "", "0", "0", "-", "", { std::string(verb) + " " + CreatureSpread(drops) });
                    return;
                }
                for (Drop const& d : drops)
                    if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(d.id))
                    {
                        Spawn const* where = nullptr;
                        std::string region;
                        if (!DropOpen(viewer, sData.creatureSpawns, d.id, &where, &region))
                        {
                            lockedAt(region);
                            continue;
                        }
                        std::vector<std::string> details = { "Level " + Levels(creature) };
                        if (d.chance)
                            details.push_back(Percent(d.chance) + " of the time");
                        row(kind, d.id, creature->Name, where ? PlaceName(*where) : "", std::to_string(d.chance),
                            std::to_string(creature->minlevel) + "-" + std::to_string(creature->maxlevel), "-", RankTag(creature), details);
                    }
            };
            creatureList('P', sources.pickpocket, "Pickpocketed from");
            creatureList('K', sources.skinning, "Skinned from");

            shown = 0;
            for (Drop const& d : sources.objects)
            {
                if (shown >= limit)
                    break;
                Spawn const* where = nullptr;
                std::string region;
                GameObjectTemplate const* object = sObjectMgr->GetGameObjectTemplate(d.id);
                if (!object)
                    continue;
                if (!DropOpen(viewer, sData.objectSpawns, d.id, &where, &region))
                {
                    lockedAt(region);
                    continue;
                }
                std::vector<std::string> details;
                if (d.chance)
                    details.push_back("In " + Percent(d.chance) + " of them");
                row('O', d.id, object->name, where ? PlaceName(*where) : "", std::to_string(d.chance), "0", "-", "", details);
                ++shown;
            }

            shown = 0;
            for (Drop const& d : sources.containers)
            {
                if (shown >= limit)
                    break;
                if (ItemTemplate const* container = sObjectMgr->GetItemTemplate(d.id))
                {
                    std::vector<std::string> origin = ItemOrigin(viewer, d.id);
                    if (d.chance)
                        origin.insert(origin.begin(), "Holds it " + Percent(d.chance) + " of the time");
                    auto citr = sData.items.find(d.id);
                    std::string note = citr != sData.items.end() ? ItemOriginNote(citr->second, container) : "";
                    row('C', d.id, container->Name1, "", std::to_string(d.chance), "0", "-", note, origin);
                    ++shown;
                }
            }
        }

        for (auto const& [region, count] : locked)
            row('L', 0, region, "", std::to_string(count));

        Send(player, "WR:" + req + ":" + std::to_string(spell) + ":" + std::to_string(recipeItem));
        SendRows(player, "WD:" + req, rows);
        Send(player, "WE:" + req);
    }

    // K:<req>:<skill>:<rank> -> where the player learns a profession's rank (2 = Journeyman ...
    // 6 = Grand Master), answered as W is. Of the spells that set that rank, the one with the most
    // sources for the player's faction: a trainer's, a book's or a quest's.
    void HandleRank(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 skill = 0;
        uint32 rank = 0;
        if (args.size() < 4 || !ParseUInt(args[2], skill) || !ParseUInt(args[3], rank) || rank > 7)
        {
            SendError(player, req, "bad");
            return;
        }

        uint8 team = TeamOf(player);
        uint32 best = 0;
        std::size_t bestSources = 0;
        auto itr = sData.ranks.find(skill * 8 + rank);
        if (itr != sData.ranks.end())
            for (uint32 spell : itr->second)
            {
                Recipe const& recipe = sData.recipes.at(spell);
                if (!(recipe.teams & team))
                    continue;
                std::size_t sources = recipe.trainers.size() + recipe.teachers.size() + recipe.quests.size()
                    + (RecipeItemFor(player, recipe) ? 1 : 0);
                if (sources > bestSources || (sources == bestSources && spell < best))
                {
                    best = spell;
                    bestSources = sources;
                }
            }
        if (!best)
        {
            SendError(player, req, "none");
            return;
        }

        std::string spell = std::to_string(best);
        HandleWhere(player, req, { args[0], args[1], spell });
    }

    // M:<req>:<kind>:<id> -> flags the nearest spawn on the map (when it's on the player's
    // continent) and answers where it is. Kinds as in W: T, V, N (a friendly creature), D, P, K
    // (any creature), O, G (an object), Q, R (id = quest: its giver).
    void HandleMapPin(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 id = 0;
        if (args.size() < 4 || args[2].empty() || !ParseUInt(args[3], id))
        {
            SendError(player, req, "bad");
            return;
        }

        Viewer viewer = MakeViewer(player);
        char kind = args[2][0];
        bool object = kind == 'O' || kind == 'G';
        bool friendly = kind == 'T' || kind == 'V' || kind == 'N';
        if (kind == 'Q' || kind == 'R')
        {
            auto giver = sData.questGivers.find(id);
            auto go = sData.questObjects.find(id);
            if (giver != sData.questGivers.end())
                id = giver->second;
            else if (go != sData.questObjects.end())
            {
                id = go->second;
                object = true;
            }
            else
                id = 0;
        }

        Spawn const* where = nullptr;
        std::string name;
        if (object)
        {
            if (GameObjectTemplate const* go = sObjectMgr->GetGameObjectTemplate(id))
            {
                DropOpen(viewer, sData.objectSpawns, id, &where);
                name = go->name;
            }
        }
        else if (CreatureTemplate const* creature = sObjectMgr->GetCreatureTemplate(id))
        {
            if (friendly)
                CanUseCreature(viewer, id, &where);
            else
                DropOpen(viewer, sData.creatureSpawns, id, &where);
            name = creature->Name;
        }
        if (!where)
        {
            SendError(player, req, "none");
            return;
        }

        std::string text = PlaceName(*where);
        float x = where->x;
        float y = where->y;
        if (where->zone)
        {
            Map2ZoneCoordinates(x, y, where->zone);
            if (x >= 0.0f && x <= 100.0f && y >= 0.0f && y <= 100.0f && !(x == where->x && y == where->y))
                text += Acore::StringFormat(" ({:.0f}, {:.0f})", x, y);
        }

        if (where->map == player->GetMapId())
        {
            WorldPacket data(SMSG_GOSSIP_POI, 4 + 4 + 4 + 4 + 4 + name.size() + 1);
            data << uint32(POI_FLAGS);
            data << float(where->x);
            data << float(where->y);
            data << uint32(POI_ICON_RED_FLAG);
            data << uint32(0);
            data << name;
            player->SendDirectMessage(&data);
            text += Acore::StringFormat(", {} yards away", uint32(player->GetExactDist2d(where->x, where->y)));
        }
        else
            text += " - " + MapName(where->map);

        Send(player, "M:" + req + ":ok:" + Escape(text));
    }
}
