/*
 * mod-retail-professions: profession equipment, after retail's (Dragonflight on).
 *
 * Each profession has a tool slot and two accessory slots, filled from the profession window.
 * Each accessory slot takes one kind of accessory (Cooking: hat, apron), as mod_retail_professions_gear's
 * kind (the slot) says, so two of a kind (two pairs of gloves, a green and a blue apron) never
 * count together, and no item goes in two slots of a profession. What goes in a slot leaves the
 * bags: like mail, the item keeps its item_instance row and a mod_retail_professions_gear_slot row
 * stands in for its character_inventory row. Slotted items are read at login and live in the
 * player's CustomData until logout.
 *
 * The slots belong to the account (RetailProfessions.Gear.AccountWide): each of its characters
 * logs in to the same slotted items. Their rows have owner_guid 0 and the account, and their
 * item_instance rows owner_guid 0 too (as guild bank items have), so deleting the character that
 * last held them doesn't delete them. A character running a challenge of
 * RetailProfessions.Gear.PersonalChallenges (mod-challenges: Iron Man, Self-Found, Self-Crafted)
 * has slots of its own instead: rows with its guid and account 0. A character that turns
 * account-wide (a challenge ended) has its own rows moved to the account's slots at login, where
 * they are free. Bots never read the slots, so an alt played by a bot can't hold them twice.
 * Soulbound items go in the account's slots too, as heirlooms would: the best rods, the runed
 * enchanting rods and the alchemist's stones all bind on pickup. A character that takes one off
 * gets it bound to itself.
 *
 * What a slot gives:
 *   - gear items (mod_retail_professions_gear) give skill, through a hidden aura per profession,
 *     and percentage points of Multicraft, Resourcefulness and crafting speed on top of what the
 *     Perks code works out from recipe mastery, or of Finesse, Perception and Deftness when
 *     gathering;
 *   - any item a recipe needs as a tool (Blacksmith Hammer, Arclight Spanner, Jeweler's Kit, a
 *     runed rod...) counts as carried while it sits in one of that profession's slots.
 *
 * The client checks a recipe's tools itself and never sends the cast without them, so the
 * client patch clears them from Spell.dbc, and the server clears them from SpellInfo at
 * startup and checks them itself (bags, worn, or slots) before each cast. Both clear the same
 * spells: every trade skill spell with a tool, and Mining and Skinning, which aren't marked as
 * trade skills. A player without the patch still has the client's own check, which only looks in
 * the bags: nothing breaks, the slots just don't count.
 *
 * Gathering tools and fishing rods (HELLO_GEAR_GATHER):
 *   - Mining and Skinning need their tool, as they do in stock. A Mining Pick or Skinning Knife
 *     (anything with a compatible tool category) counts from the bags, or from a slot of its
 *     profession as a plain tool, where it takes no bag space;
 *   - Fishing has a rod slot and a lure slot. Fishing works with the rod there instead of
 *     in the main hand, and lures and fishing lines go on it: the client patch takes the rod
 *     requirement (and the lure's item target) out of Spell.dbc, the server takes the rod
 *     requirement out of SpellInfo and checks it itself. A rod in the main hand still comes first.
 *     The slotted rod's fishing skill (its own and its lure's or line's) comes through the
 *     Fishing skill aura; the module counts its lure down itself. The lure slot holds a stack of
 *     lures (HELLO_GEAR_TYPED): a cast of Fishing with no lure on the rod it uses (main hand or
 *     slot) puts one from there on that rod, using it up as using it by hand would.
 *
 * Gear is gated by skill alone: an item's RequiredSkill/RequiredSkillRank must be met, without
 * bonuses. Individual progression caps skill per era, so that is the era gate as well.
 *
 * Messages (see RetailProfessions.cpp for the wire format):
 *   GC:<req>                         -> GCD:<req>:<rows>..., GCE:<req>:<count>   the gear items
 *   G:<req>                          -> GD:<req>:<rows>..., GE:<req>:<count>     what is slotted (skill,slot,entry,guid,count)
 *   GQ:<req>:<bag>:<slot>:<skill>:<s> -> GQ:<req>:ok:<skill>:<s>                 slot an item from the bags
 *   GU:<req>:<skill>:<s>             -> GU:<req>:ok                             take one off
 *   GT:<req>:<skill>                 -> GTD:<req>:<rows>..., GTE:<req>:<count>   recipe tools
 *   (unasked)                           GD:0 + GE:0 after any change, PG:0:<skill>:F:<item>*<n> on a Finesse proc
 */

#include "RetailProfessions.h"
#include "Bag.h"
#include "Chat.h"
#include "Creature.h"
#include "DBCStores.h"
#include "DataMap.h"
#include "DatabaseEnv.h"
#include "GameObject.h"
#include "Item.h"
#include "ItemTemplate.h"
#include "Log.h"
#include "LootMgr.h"
#include "Mail.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Opcodes.h"
#include "Player.h"
#include "Random.h"
#include "SharedDefines.h"
#include "Spell.h"
#include "SpellAuraEffects.h"
#include "SpellAuras.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>
#include <array>
#include <map>
#include <set>
#include <unordered_map>

#if __has_include("ChallengesApi.h")
#include "ChallengesApi.h"
#endif

namespace RetailProfessions::Gear
{
    namespace
    {
        struct Layout
        {
            uint32 skill;
            uint8 slots;
            uint32 aura; // server-only Mod Skill aura carrying the skill bonus
        };

        constexpr std::array<Layout, 13> LAYOUTS = {{
            { SKILL_ALCHEMY,        3, 90800 },
            { SKILL_BLACKSMITHING,  3, 90801 },
            { SKILL_ENCHANTING,     3, 90802 },
            { SKILL_ENGINEERING,    3, 90803 },
            { SKILL_HERBALISM,      3, 90804 },
            { SKILL_INSCRIPTION,    3, 90805 },
            { SKILL_JEWELCRAFTING,  3, 90806 },
            { SKILL_LEATHERWORKING, 3, 90807 },
            { SKILL_MINING,         3, 90808 },
            { SKILL_SKINNING,       3, 90809 },
            { SKILL_TAILORING,      3, 90810 },
            { SKILL_COOKING,        3, 90811 },
            { SKILL_FISHING,        2, 90812 },
        }};

        constexpr uint8 MAX_SLOTS = 3;
        constexpr uint8 TOOL_SLOT = 0;
        constexpr uint8 LURE_SLOT = 1; // Fishing's second slot: a stack of lures, not gear
        constexpr uint8 ANY_SLOT = 9;          // GQ: the first slot that fits
        constexpr uint32 MAX_TOOL_ENTRIES = 30; // items listed per tool in GT
        constexpr uint32 CHECK_INTERVAL = 5000;
        constexpr char const* DATA_KEY = "RetailProfessionsGear";

        // The tools gathering needs. No other spell asks for these two categories.
        struct GatherTool
        {
            uint32 skill;
            uint32 category; // TotemCategory
        };

        constexpr std::array<GatherTool, 2> GATHER_TOOLS = {{
            { SKILL_MINING,   165 }, // Mining Pick
            { SKILL_SKINNING, 166 }, // Skinning Knife
        }};

        constexpr uint32 FISHING_POLE_MASK = 1 << ITEM_SUBCLASS_WEAPON_FISHING_POLE;

        struct GearRow
        {
            uint32 skill = 0;
            uint8 slot = TOOL_SLOT; // the column kind: 0 the tool, 1 or 2 the accessory slot it goes in
            uint16 skillBonus = 0;
            std::array<uint8, STAT_COUNT> stats{};
            uint32 countsAs = 0;
        };

        std::unordered_map<uint32, GearRow> sGear; // by item entry

        // A recipe's tools as the spell had them before they were cleared.
        struct Need
        {
            std::array<uint32, 2> totem{};
            std::array<uint32, 2> category{};
            uint32 skill = 0; // 0 when no profession teaches it: then any profession's slots count
        };

        std::unordered_map<uint32, Need> sNeeds; // by spell

        // What a profession's recipes need, for slotting plain tools and for GT.
        struct SkillTools
        {
            std::set<uint32> items;      // exact Totem items
            std::set<uint32> categories; // TotemCategory ids
            std::vector<std::string> rows;
        };

        std::unordered_map<uint32, SkillTools> sTools; // by skill

        // Skill values at which a profession has recipes learned on reaching them (AcquireMethod 1:
        // the gear recipes). The core only looks for those when a skill crosses a rank (75, 150...).
        std::unordered_map<uint32, std::set<uint32>> sLearnLevels; // by skill

        // Whether the spells' tools were taken out at startup (a config reload doesn't change it).
        bool sToolsCleared = false;

        // Spells that need a rod in the main hand: Fishing (casts), and lures and lines (put on
        // the rod). Their rod requirement is taken out at startup when sPoleCleared, and a lure's
        // or line's effect becomes a Dummy: the core's Enchant Item needs an item target, which a
        // rod in the Fishing slot can't be, so the module puts every lure and line on itself.
        struct PoleEnchant
        {
            bool temporary = false; // Enchant Item Temporary (lures), else Enchant Item (lines)
            uint32 enchant = 0;
        };

        std::set<uint32> sPoleCasts;
        std::map<uint32, PoleEnchant> sPoleEnchants; // by spell
        bool sPoleCleared = false;

        // Lures for the lure slot: items used up putting a lure (a temporary one) on the rod, with
        // that spell. Not the fishing hats' lure, which the hat keeps.
        std::unordered_map<uint32, uint32> sLureItems; // item entry -> lure spell

        Layout const* LayoutOf(uint32 skill)
        {
            for (Layout const& layout : LAYOUTS)
                if (layout.skill == skill)
                    return &layout;
            return nullptr;
        }

        GatherTool const* GatherToolOf(uint32 skill)
        {
            for (GatherTool const& tool : GATHER_TOOLS)
                if (tool.skill == skill)
                    return &tool;
            return nullptr;
        }

        GatherTool const* GatherToolOfCategory(uint32 category)
        {
            for (GatherTool const& tool : GATHER_TOOLS)
                if (tool.category == category)
                    return &tool;
            return nullptr;
        }

        bool IsFishingPole(ItemTemplate const* proto)
        {
            return proto->Class == ITEM_CLASS_WEAPON && proto->SubClass == ITEM_SUBCLASS_WEAPON_FISHING_POLE;
        }

        uint32 LureSpellOf(uint32 entry)
        {
            auto itr = sLureItems.find(entry);
            return itr != sLureItems.end() ? itr->second : 0;
        }

        GearRow const* GearOf(uint32 entry)
        {
            auto itr = sGear.find(entry);
            return itr != sGear.end() ? &itr->second : nullptr;
        }

        // What an item gives in a slot of `skill`: its gear row when it is that profession's
        // gear. Another profession's gear tool slotted as a plain tool gives nothing.
        GearRow const* GearFor(uint32 entry, uint32 skill)
        {
            GearRow const* row = GearOf(entry);
            return row && row->skill == skill ? row : nullptr;
        }

        // ---- per player -------------------------------------------------------------------------

        using Slots = std::array<Item*, MAX_SLOTS>;

        struct Data : public DataMap::Base
        {
            bool loaded = false;
            uint32 checkTimer = CHECK_INTERVAL;
            uint32 sinceCheck = 0;
            bool lureTicked = false; // a slotted rod's lure time went down since it was saved
            bool rodShown = false;   // the hands show the slotted rod for a cast of Fishing
            bool shared = false;     // the slots are the account's, not the character's own
            uint32 account = 0;
            std::map<uint32, Slots> skills; // by skill line

            ~Data() override
            {
                for (auto& [skill, slots] : skills)
                    for (Item* item : slots)
                        delete item;
            }
        };

        Data* DataOf(Player* player)
        {
            return player->CustomData.Get<Data>(DATA_KEY);
        }

        // The slotted gear of a player whose slots are read, else nullptr.
        Data* LoadedDataOf(Player* player)
        {
            Data* data = DataOf(player);
            return data && data->loaded ? data : nullptr;
        }

        bool IsBot(Player const* player)
        {
            return !player->GetSession() || player->GetSession()->IsHeadless();
        }

        // Whether the character runs a challenge that keeps its gear to itself (with an older
        // mod-challenges, Self-Found).
        bool KeepsOwnSlots(Player const* player)
        {
#if defined(CHALLENGES_API_HAS_RUNNING)
            return (Challenges::Running(player->GetGUID().GetCounter()) & GetConfig().gearPersonalChallenges) != 0;
#elif __has_include("ChallengesApi.h")
            return Challenges::IsSelfFound(player->GetGUID().GetCounter());
#else
            return false;
#endif
        }

        // Whether the character gets the account's slots.
        bool UsesAccountSlots(Player const* player)
        {
            return GetConfig().gearAccountWide && !KeepsOwnSlots(player);
        }

        // Whether the character may use a slotted item: the account's slots hold what another
        // character put in, so the item's skill (pure) and level requirements count for whoever
        // uses it. One it can't use stays slotted and gives nothing, as for an unlearned profession.
        bool Usable(Player const* player, Item const* item)
        {
            ItemTemplate const* proto = item->GetTemplate();
            if (proto->RequiredSkill && player->GetPureSkillValue(proto->RequiredSkill) < proto->RequiredSkillRank)
                return false;
            return player->GetLevel() >= proto->RequiredLevel;
        }

        // The slot row's owner columns: (0, account) for the account's, (guid, 0) for the character's.
        std::string SlotOwner(Player const* player, Data const* data)
        {
            return data->shared ? Acore::StringFormat("0, {}", data->account) : Acore::StringFormat("{}, 0", player->GetGUID().GetCounter());
        }

        // Whether an item sitting in one of a profession's slots meets a tool requirement.
        bool MeetsTotem(Item const* item, uint32 totem)
        {
            if (item->GetEntry() == totem)
                return true;
            GearRow const* row = GearOf(item->GetEntry());
            return row && row->countsAs == totem;
        }

        // Gear standing in for an exact tool item (counts_as), in the bags or worn: it counts
        // there too, as a stat tool with the tool's category does.
        bool CarriesStandIn(Player const* player, uint32 totem)
        {
            for (auto const& [entry, row] : sGear)
                if (row.countsAs == totem && player->HasItemCount(entry))
                    return true;
            return false;
        }

        bool MeetsCategory(Player const* player, Item const* item, uint32 category)
        {
            return player->IsTotemCategoryCompatiableWith(item->GetTemplate(), category);
        }

        // Every slotted item of the profession that teaches a recipe (all professions when none does).
        template <typename Pred>
        bool AnySlotted(Player* player, uint32 skill, Pred pred)
        {
            Data* data = LoadedDataOf(player);
            if (!data)
                return false;
            for (auto const& [slotSkill, slots] : data->skills)
            {
                if (skill && slotSkill != skill)
                    continue;
                for (Item const* item : slots)
                    if (item && Usable(player, item) && pred(item))
                        return true;
            }
            return false;
        }

        void Notify(Player* player, std::string const& text)
        {
            ChatHandler(player->GetSession()).SendSysMessage("|cffffd200Profession equipment:|r " + text);
        }

        // ---- the rod ------------------------------------------------------------------------------

        Item* MainHandPole(Player* player)
        {
            Item* item = player->GetItemByPos(INVENTORY_SLOT_BAG_0, EQUIPMENT_SLOT_MAINHAND);
            return item && IsFishingPole(item->GetTemplate()) && !item->IsBroken() ? item : nullptr;
        }

        // The rod in the Fishing slot when it's the one fishing uses: one in the main hand goes first.
        Item* SlottedPole(Player* player)
        {
            if (MainHandPole(player))
                return nullptr;
            Data* data = LoadedDataOf(player);
            if (!data)
                return nullptr;
            auto itr = data->skills.find(SKILL_FISHING);
            if (itr == data->skills.end())
                return nullptr;
            for (Item* item : itr->second)
                if (item && IsFishingPole(item->GetTemplate()) && !item->IsBroken() && Usable(player, item))
                    return item;
            return nullptr;
        }

        // The Fishing skill a rod gives when worn: its equip spells and those of its line (permanent
        // enchantment) and lure (temporary).
        int32 PoleSkill(Item const* pole)
        {
            int32 total = 0;
            auto add = [&total](uint32 spellId)
            {
                if (SpellInfo const* info = sSpellMgr->GetSpellInfo(spellId))
                    for (SpellEffectInfo const& effect : info->GetEffects())
                        if ((effect.IsAura(SPELL_AURA_MOD_SKILL) || effect.IsAura(SPELL_AURA_MOD_SKILL_TALENT)) && effect.MiscValue == SKILL_FISHING)
                            total += effect.CalcValue();
            };
            for (_Spell const& spell : pole->GetTemplate()->Spells)
                if (spell.SpellId > 0 && spell.SpellTrigger == ITEM_SPELLTRIGGER_ON_EQUIP)
                    add(spell.SpellId);
            for (EnchantmentSlot slot : { PERM_ENCHANTMENT_SLOT, TEMP_ENCHANTMENT_SLOT })
                if (SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(pole->GetEnchantmentId(slot)))
                    for (uint8 i = 0; i < MAX_SPELL_ITEM_ENCHANTMENT_EFFECTS; ++i)
                        if (enchant->type[i] == ITEM_ENCHANTMENT_TYPE_EQUIP_SPELL && enchant->spellid[i])
                            add(enchant->spellid[i]);
            return total;
        }

        // Sets an enchantment on a slotted item. Not Item::SetEnchantment: that queues the item
        // for its owner's inventory save, which drops items it can't find in the bags.
        void SetSlottedEnchantment(Item* item, EnchantmentSlot slot, uint32 id, uint32 duration, uint32 charges)
        {
            uint16 field = ITEM_FIELD_ENCHANTMENT_1_1 + slot * MAX_ENCHANTMENT_OFFSET;
            item->SetUInt32Value(field + ENCHANTMENT_ID_OFFSET, id);
            item->SetUInt32Value(field + ENCHANTMENT_DURATION_OFFSET, duration);
            item->SetUInt32Value(field + ENCHANTMENT_CHARGES_OFFSET, charges);
        }

        // While fishing with the slotted rod the hands show it (and its lure's glow) instead of
        // what is equipped; the weapons stay equipped. mod-transmog-plus leaves the hands alone
        // then (FishingWithoutRodInHand).
        void ShowRod(Player* player, Data* data, Item const* rod)
        {
            uint16 mainHand = PLAYER_VISIBLE_ITEM_1_ENTRYID + EQUIPMENT_SLOT_MAINHAND * 2;
            uint16 offHand = PLAYER_VISIBLE_ITEM_1_ENTRYID + EQUIPMENT_SLOT_OFFHAND * 2;
            player->SetUInt32Value(mainHand, rod->GetEntry());
            player->SetUInt16Value(mainHand + 1, 0, rod->GetEnchantmentId(PERM_ENCHANTMENT_SLOT));
            player->SetUInt16Value(mainHand + 1, 1, rod->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT));
            player->SetUInt32Value(offHand, 0);
            player->SetUInt32Value(offHand + 1, 0);
            data->rodShown = true;
        }

        void HideRod(Player* player, Data* data)
        {
            for (uint8 slot : { EQUIPMENT_SLOT_MAINHAND, EQUIPMENT_SLOT_OFFHAND })
                player->SetVisibleItemSlot(slot, player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));
            data->rodShown = false;
        }

        bool Fishing(Player const* player)
        {
            Spell const* spell = player->GetCurrentSpell(CURRENT_CHANNELED_SPELL);
            return spell && sPoleCasts.count(spell->GetSpellInfo()->Id);
        }

        // The account's items have no owner in item_instance, as guild bank items have: deleting
        // the character holding them then leaves them be. In memory the player owns them.
        void KeepOwnerless(Data const* data, Item const* item, CharacterDatabaseTransaction trans)
        {
            if (data->shared)
                trans->Append("UPDATE item_instance SET owner_guid = 0 WHERE guid = {}", item->GetGUID().GetCounter());
        }

        // A slotted item's owner in item_instance: none for the account's, else the character.
        void SetDbOwner(Player const* player, Data const* data, Item const* item, CharacterDatabaseTransaction trans)
        {
            trans->Append("UPDATE item_instance SET owner_guid = {} WHERE guid = {}", data->shared ? 0 : player->GetGUID().GetCounter(),
                item->GetGUID().GetCounter());
        }

        void SaveSlotted(Data const* data, Item* item, CharacterDatabaseTransaction trans)
        {
            if (item->GetState() == ITEM_UNCHANGED)
                item->FSetState(ITEM_CHANGED);
            item->SaveToDB(trans);
            KeepOwnerless(data, item, trans);
        }

        // ---- the skill auras --------------------------------------------------------------------

        void UpdateAura(Player* player, Layout const& layout, Slots const* slots)
        {
            int32 bonus = 0;
            if (slots && player->HasSkill(layout.skill))
            {
                for (Item const* item : *slots)
                    if (item && Usable(player, item))
                        if (GearRow const* row = GearFor(item->GetEntry(), layout.skill))
                            bonus += row->skillBonus;
                if (layout.skill == SKILL_FISHING)
                {
                    if (Item const* pole = SlottedPole(player))
                        bonus += PoleSkill(pole);
                }
            }

            Aura* aura = player->GetAura(layout.aura);
            if (!bonus)
            {
                if (aura)
                    player->RemoveAurasDueToSpell(layout.aura);
                return;
            }
            if (!aura)
                aura = player->AddAura(layout.aura, player);
            if (aura)
                if (AuraEffect* effect = aura->GetEffect(EFFECT_0))
                    if (effect->GetAmount() != bonus)
                        effect->ChangeAmount(bonus);
        }

        void UpdateSkillAura(Player* player, uint32 skill)
        {
            Layout const* layout = LayoutOf(skill);
            Data* data = LoadedDataOf(player);
            if (!layout || !data)
                return;
            auto itr = data->skills.find(skill);
            UpdateAura(player, *layout, itr != data->skills.end() ? &itr->second : nullptr);
        }

        void UpdateAuras(Player* player)
        {
            Data* data = LoadedDataOf(player);
            for (Layout const& layout : LAYOUTS)
            {
                Slots const* slots = nullptr;
                if (data)
                {
                    auto itr = data->skills.find(layout.skill);
                    if (itr != data->skills.end())
                        slots = &itr->second;
                }
                UpdateAura(player, layout, slots);
            }
        }

        // ---- telling the addon ------------------------------------------------------------------

        void SendState(Player* player, std::string const& req)
        {
            std::vector<std::string> rows;
            if (Data* data = LoadedDataOf(player))
                for (auto const& [skill, slots] : data->skills)
                    for (uint8 slot = 0; slot < MAX_SLOTS; ++slot)
                        if (Item const* item = slots[slot])
                            rows.push_back(Acore::StringFormat("{},{},{},{},{}", skill, slot, item->GetEntry(), item->GetGUID().GetCounter(), item->GetCount()));
            SendRows(player, "GD:" + req, rows);
            Send(player, Acore::StringFormat("GE:{}:{}", req, rows.size()));
        }

        // ---- moving items in and out ------------------------------------------------------------

        // Puts a taken-off item in the bags, or in the mail when `mail` and the bags are full.
        // False when it fits nowhere (it stays where it is).
        bool Return(Player* player, Item* item, CharacterDatabaseTransaction trans, bool mail)
        {
            ItemPosCountVec dest;
            if (player->CanStoreItem(NULL_BAG, NULL_SLOT, dest, item, false) == EQUIP_ERR_OK)
            {
                player->MoveItemToInventory(dest, item, true);
                return true;
            }
            if (!mail)
                return false;

            item->FSetState(ITEM_CHANGED);
            item->SaveToDB(trans);
            MailDraft("Profession equipment", "Your bags were full, so this came by mail.")
                .AddItem(item)
                .SendMailTo(trans, MailReceiver(player), MailSender(player, MAIL_STATIONERY_GM), MAIL_CHECK_MASK_COPIED);
            return true;
        }

        void DeleteSlotRow(Item const* item, CharacterDatabaseTransaction trans)
        {
            trans->Append("DELETE FROM mod_retail_professions_gear_slot WHERE item_guid = {}", item->GetGUID().GetCounter());
        }

        // Empties every slot of a profession into the bags (the mail when full). The aura follows.
        void ReturnSkill(Player* player, Data* data, uint32 skill, CharacterDatabaseTransaction trans)
        {
            auto itr = data->skills.find(skill);
            if (itr == data->skills.end())
                return;
            for (Item*& item : itr->second)
            {
                if (!item)
                    continue;
                DeleteSlotRow(item, trans);
                Return(player, item, trans, true);
                item = nullptr;
            }
            data->skills.erase(itr);
        }

        // Takes back slotted gear of professions the player no longer knows. Not the account's:
        // another character may know the profession; it just gives nothing here.
        void CheckSkills(Player* player, Data* data)
        {
            if (data->shared)
                return;
            std::vector<uint32> forgotten;
            for (auto const& [skill, slots] : data->skills)
                if (!player->HasSkill(skill) && std::any_of(slots.begin(), slots.end(), [](Item* item) { return item != nullptr; }))
                    forgotten.push_back(skill);
            if (forgotten.empty())
                return;

            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            for (uint32 skill : forgotten)
                ReturnSkill(player, data, skill, trans);
            player->SaveInventoryAndGoldToDB(trans);
            CharacterDatabase.CommitTransaction(trans);

            Notify(player, "the equipment of a profession you no longer know went back to your bags.");
            UpdateAuras(player);
            SendState(player, "0");
        }

        // ---- which slot ---------------------------------------------------------------------------

        // The slots an item may go in: a profession's own gear the slot of its kind (the tool, one
        // accessory slot each), a plain tool any of them. Fishing: a rod the first, lures the second.
        bool Fits(Item const* item, uint32 skill, uint8 slot)
        {
            if (skill == SKILL_FISHING)
                return slot == LURE_SLOT ? LureSpellOf(item->GetEntry()) != 0 : IsFishingPole(item->GetTemplate());
            GearRow const* row = GearFor(item->GetEntry(), skill);
            return !row || row->slot == slot;
        }

        // Where a slotted item goes at login: its own slot while it still fits there, else the
        // slot of its kind (an accessory saved before each kind got its slot), else none (it goes
        // back to the bags). None for a second one of an item, too.
        uint8 PlaceOnLoad(Item const* item, Layout const& layout, Slots const& slots, uint8 saved)
        {
            for (Item const* other : slots)
                if (other && other->GetEntry() == item->GetEntry())
                    return MAX_SLOTS;
            if (saved < layout.slots && !slots[saved] && Fits(item, layout.skill, saved))
                return saved;
            for (uint8 slot = 0; slot < layout.slots; ++slot)
                if (!slots[slot] && Fits(item, layout.skill, slot))
                    return slot;
            return MAX_SLOTS;
        }

        // ---- loading ----------------------------------------------------------------------------

        void Loaded(WorldSession* session, ObjectGuid guid, bool shared, QueryResult result)
        {
            Player* player = session->GetPlayer();
            if (!player || player->GetGUID() != guid)
                return;
            Data* data = player->CustomData.GetDefault<Data>(DATA_KEY);
            if (data->loaded)
                return;
            data->shared = shared;
            data->account = session->GetAccountId();

            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            std::vector<Item*> homeless;
            // Rows written again: in another slot, or the character's own moved to the account's.
            // All are deleted before any is written back, so no two share a slot on the way.
            std::vector<std::pair<Item*, uint32>> moved; // item, skill
            bool changed = false;
            if (result)
                do
                {
                    Field* fields = result->Fetch();
                    ObjectGuid::LowType itemGuid = fields[11].Get<uint32>();

                    // The item is back in the bags or a mailbox: the write that moved it there
                    // won a race with this one, and that copy is the real one.
                    if (fields[15].Get<uint64>())
                    {
                        LOG_ERROR("module", "mod-retail-professions: {}'s slotted item {} is also in an inventory or mailbox; dropped from the slots.",
                            player->GetName(), itemGuid);
                        trans->Append("DELETE FROM mod_retail_professions_gear_slot WHERE item_guid = {}", itemGuid);
                        changed = true;
                        continue;
                    }

                    ItemTemplate const* proto = fields[12].IsNull() ? nullptr : sObjectMgr->GetItemTemplate(fields[12].Get<uint32>());
                    Item* item = proto ? NewItemOrBag(proto) : nullptr;
                    if (!item || !item->LoadFromDB(itemGuid, player->GetGUID(), fields, proto->ItemId))
                    {
                        LOG_ERROR("module", "mod-retail-professions: {}'s slotted item {} no longer exists; dropped from the slots.", player->GetName(), itemGuid);
                        trans->Append("DELETE FROM mod_retail_professions_gear_slot WHERE item_guid = {}", itemGuid);
                        changed = true;
                        delete item;
                        continue;
                    }
                    item->SetState(ITEM_UNCHANGED);

                    uint32 skill = fields[13].Get<uint16>();
                    uint8 saved = fields[14].Get<uint8>();
                    // A row of the other kind (the character's own with the account's slots, or the
                    // account's with AccountWide off) moves over.
                    bool own = fields[16].Get<uint32>() != 0;
                    bool otherOwner = shared == own;
                    Layout const* layout = LayoutOf(skill);
                    uint8 slot = layout ? PlaceOnLoad(item, *layout, data->skills[skill], saved) : MAX_SLOTS;
                    if (slot >= MAX_SLOTS)
                    {
                        homeless.push_back(item);
                        continue;
                    }
                    data->skills[skill][slot] = item;
                    if (slot != saved || otherOwner)
                    {
                        trans->Append("DELETE FROM mod_retail_professions_gear_slot WHERE item_guid = {}", itemGuid);
                        moved.emplace_back(item, skill);
                    }
                } while (result->NextRow());

            // Rows for a slot that no longer exists (or a second copy of an item) give their item
            // back. Their rows go before the moved ones are written back into the slots they held.
            for (Item* item : homeless)
            {
                DeleteSlotRow(item, trans);
                Return(player, item, trans, true);
                changed = true;
            }

            for (auto const& [item, skill] : moved)
            {
                Slots const& slots = data->skills[skill];
                uint8 slot = uint8(std::find(slots.begin(), slots.end(), item) - slots.begin());
                trans->Append("INSERT INTO mod_retail_professions_gear_slot (owner_guid, account, skill, slot, item_guid) VALUES ({}, {}, {}, {})",
                    SlotOwner(player, data), skill, slot, item->GetGUID().GetCounter());
                SetDbOwner(player, data, item, trans);
                changed = true;
            }
            for (auto itr = data->skills.begin(); itr != data->skills.end();)
            {
                bool empty = std::none_of(itr->second.begin(), itr->second.end(), [](Item* item) { return item != nullptr; });
                itr = empty ? data->skills.erase(itr) : std::next(itr);
            }

            data->loaded = true;

            // With the feature off, everything goes back.
            if (!GetConfig().gear)
            {
                std::vector<uint32> skills;
                for (auto const& [skill, slots] : data->skills)
                    skills.push_back(skill);
                for (uint32 skill : skills)
                    ReturnSkill(player, data, skill, trans);
                changed = changed || !skills.empty();
            }

            if (changed)
                player->SaveInventoryAndGoldToDB(trans);
            CharacterDatabase.CommitTransaction(trans);

            CheckSkills(player, data);
            UpdateAuras(player);
            SendState(player, "0");
        }

        // ---- slotting ---------------------------------------------------------------------------

        // Client bag 0 is the backpack, 1-4 the bags on the belt; client slots count from 1.
        Item* ItemAtClientPos(Player* player, uint32 bag, uint32 slot)
        {
            if (slot < 1)
                return nullptr;
            if (bag == 0)
                return slot <= uint32(INVENTORY_SLOT_ITEM_END - INVENTORY_SLOT_ITEM_START)
                    ? player->GetItemByPos(INVENTORY_SLOT_BAG_0, INVENTORY_SLOT_ITEM_START + slot - 1) : nullptr;
            if (bag <= uint32(INVENTORY_SLOT_BAG_END - INVENTORY_SLOT_BAG_START) && slot <= MAX_BAG_SIZE)
                return player->GetItemByPos(INVENTORY_SLOT_BAG_START + bag - 1, slot - 1);
            return nullptr;
        }

        // Whether an item meets one of a profession's recipe tools, is its gathering tool (pick,
        // knife) or, for Fishing, a rod.
        bool IsPlainTool(Player const* player, ItemTemplate const* proto, uint32 skill)
        {
            if (skill == SKILL_FISHING)
                return IsFishingPole(proto);
            if (GatherTool const* tool = GatherToolOf(skill))
                if (proto->TotemCategory && player->IsTotemCategoryCompatiableWith(proto, tool->category))
                    return true;
            auto itr = sTools.find(skill);
            if (itr == sTools.end())
                return false;
            SkillTools const& tools = itr->second;
            if (tools.items.count(proto->ItemId))
                return true;
            if (GearRow const* row = GearOf(proto->ItemId))
                if (row->countsAs && tools.items.count(row->countsAs))
                    return true;
            if (proto->TotemCategory)
                for (uint32 category : tools.categories)
                    if (player->IsTotemCategoryCompatiableWith(proto, category))
                        return true;
            return false;
        }

        // Why an item can't be slotted for a profession (an error code), or nullptr.
        char const* Refusal(Player* player, Item* item, uint32 skill)
        {
            ItemTemplate const* proto = item->GetTemplate();
            GearRow const* row = GearOf(proto->ItemId);
            // Lures go in Fishing's lure slot as a stack.
            bool lure = skill == SKILL_FISHING && LureSpellOf(proto->ItemId);
            if (!(row && row->skill == skill) && !lure && !IsPlainTool(player, proto, skill))
                return "notgear";
            if (!player->HasSkill(skill))
                return "unlearned";
            if (proto->RequiredSkill && player->GetPureSkillValue(proto->RequiredSkill) < proto->RequiredSkillRank)
                return "rank";
            if ((!lure && (item->GetCount() > 1 || proto->GetMaxStackSize() > 1)) || item->IsInTrade() || item->IsRefundable() || item->IsBOPTradable()
                || item->IsWrapped() || proto->Duration || item->GetUInt32Value(ITEM_FIELD_DURATION))
                return "notgear";
            return nullptr;
        }

        uint8 PickSlot(Item const* item, Layout const& layout, Slots const& slots)
        {
            if (GearRow const* row = GearFor(item->GetEntry(), layout.skill))
                return row->slot;
            if (layout.skill == SKILL_FISHING)
                return LureSpellOf(item->GetEntry()) ? LURE_SLOT : TOOL_SLOT;
            for (uint8 slot = 0; slot < layout.slots; ++slot)
                if (!slots[slot])
                    return slot;
            return TOOL_SLOT;
        }

        // A challenge started (or ended) since the slots were read: read the right ones. Every
        // change is written already; the lure time left is saved, then the objects go.
        void Reload(Player* player)
        {
            OnLogout(player);
            UpdateAuras(player);
            SendState(player, "0");
            OnLogin(player);
        }

        bool CanChange(Player* player, std::string const& req)
        {
            char const* why = nullptr;
            Data* data = LoadedDataOf(player);
            if (!GetConfig().gear)
                why = "off";
            else if (IsBot(player))
                why = "bot";
            else if (!data)
                why = "loading";
            else if (data->shared != UsesAccountSlots(player))
            {
                Reload(player);
                why = "loading";
            }
            else if (player->IsInCombat())
                why = "combat";
            else if (player->IsNonMeleeSpellCast(false))
                why = "casting";
            else if (player->GetTradeData())
                why = "trade";
            if (why)
                SendError(player, req, why);
            return !why;
        }
    }

    // ---- startup ------------------------------------------------------------------------------

    void Build()
    {
        uint32 oldMSTime = getMSTime();
        sGear.clear();
        sNeeds.clear();
        sTools.clear();
        sToolsCleared = false;
        sPoleCasts.clear();
        sPoleEnchants.clear();
        sPoleCleared = false;
        sLureItems.clear();
        sLearnLevels.clear();
        for (Layout const& layout : LAYOUTS)
            for (SkillLineAbilityEntry const* ability : GetSkillLineAbilitiesBySkillLine(layout.skill))
                if (ability->AcquireMethod == SKILL_LINE_ABILITY_LEARNED_ON_SKILL_VALUE && ability->MinSkillLineRank > 1)
                    sLearnLevels[layout.skill].insert(ability->MinSkillLineRank);

        //                                                  0      1      2     3            4           5                6      7          8           9          10
        if (QueryResult result = WorldDatabase.Query("SELECT entry, skill, kind, skill_bonus, multicraft, resourcefulness, speed, finesse, perception, deftness, counts_as "
            "FROM mod_retail_professions_gear"))
            do
            {
                Field* fields = result->Fetch();
                uint32 entry = fields[0].Get<uint32>();
                GearRow row;
                row.skill = fields[1].Get<uint16>();
                row.slot = fields[2].Get<uint8>();
                row.skillBonus = fields[3].Get<uint16>();
                for (uint8 stat = 0; stat < STAT_COUNT; ++stat)
                    row.stats[stat] = fields[4 + stat].Get<uint8>();
                row.countsAs = fields[10].Get<uint32>();
                Layout const* layout = LayoutOf(row.skill);
                if (!sObjectMgr->GetItemTemplate(entry) || !layout || row.skill == SKILL_FISHING || row.slot >= layout->slots)
                {
                    LOG_ERROR("sql.sql", "mod-retail-professions: mod_retail_professions_gear row {} has no item, an unsupported skill or a bad kind (slot); skipped.", entry);
                    continue;
                }
                sGear.emplace(entry, row);
            } while (result->NextRow());

        // Every trade skill spell's tools, and Mining's and Skinning's, then cleared: the module
        // checks them itself.
        bool clear = GetConfig().gear;
        for (uint32 id = 0; id < sSpellMgr->GetSpellInfoStoreSize(); ++id)
        {
            SpellInfo* info = const_cast<SpellInfo*>(sSpellMgr->GetSpellInfo(id));
            if (!info)
                continue;
            GatherTool const* gatherTool = GatherToolOfCategory(info->TotemCategory[0]);
            if (!info->HasAttribute(SPELL_ATTR0_IS_TRADESKILL) && !gatherTool)
                continue;
            if (!info->Totem[0] && !info->Totem[1] && !info->TotemCategory[0] && !info->TotemCategory[1])
                continue;
            // Darkmoon cards, tarots, Prismatic Black Diamond: the tool is what makes the core
            // roll spell_loot_template instead of creating the placeholder (IsLootCrafting), so
            // they keep it and the core checks it, in the bags. tools/build_gear_patch.py skips
            // the same spells.
            if (info->Effects[EFFECT_0].Effect == SPELL_EFFECT_CREATE_ITEM_2 && info->Effects[EFFECT_0].ItemType && info->IsLootCrafting())
                continue;

            Need need;
            need.totem = info->Totem;
            need.category = info->TotemCategory;
            SkillLineAbilityMapBounds bounds = sSpellMgr->GetSkillLineAbilityMapBounds(id);
            for (auto itr = bounds.first; itr != bounds.second && !need.skill; ++itr)
                if (LayoutOf(itr->second->SkillLine))
                    need.skill = itr->second->SkillLine;
            // Mining a creature's corpse has no skill line of its own.
            if (gatherTool)
                need.skill = gatherTool->skill;
            sNeeds.emplace(id, need);

            if (clear)
            {
                sToolsCleared = true;
                info->Totem = { 0, 0 };
                info->TotemCategory = { 0, 0 };
            }
        }

        // Fishing and the lures and lines put on the rod: the rod may sit in the Fishing slot
        // instead of the main hand, so its requirement goes and the module checks it.
        // tools/build_gear_patch.py picks the same spells (free_fishing_pole).
        for (uint32 id = 0; id < sSpellMgr->GetSpellInfoStoreSize(); ++id)
        {
            SpellInfo* info = const_cast<SpellInfo*>(sSpellMgr->GetSpellInfo(id));
            if (!info || info->EquippedItemClass != ITEM_CLASS_WEAPON || info->EquippedItemSubClassMask != int32(FISHING_POLE_MASK))
                continue;
            SpellEffectInfo& effect = info->_GetEffects()[EFFECT_0];
            bool cast = info->HasEffect(SPELL_EFFECT_TRANS_DOOR);
            bool enchant = (info->Targets & TARGET_FLAG_ITEM)
                && (effect.Effect == SPELL_EFFECT_ENCHANT_ITEM || effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY);
            if (cast)
                sPoleCasts.insert(id);
            else if (enchant)
                sPoleEnchants[id] = { effect.Effect == SPELL_EFFECT_ENCHANT_ITEM_TEMPORARY, uint32(effect.MiscValue) };
            else
                continue;
            if (clear)
            {
                sPoleCleared = true;
                info->EquippedItemClass = -1;
                info->EquippedItemSubClassMask = 0;
                info->EquippedItemInventoryTypeMask = 0;
                if (enchant)
                    effect.Effect = SPELL_EFFECT_DUMMY;
            }
        }

        // Lures for the lure slot: used up (charges -1) putting a temporary enchantment on the rod.
        for (auto const& [entry, proto] : *sObjectMgr->GetItemTemplateStore())
            for (_Spell const& spell : proto.Spells)
                if (spell.SpellId > 0 && spell.SpellTrigger == ITEM_SPELLTRIGGER_ON_USE && spell.SpellCharges < 0)
                    if (auto lure = sPoleEnchants.find(uint32(spell.SpellId)); lure != sPoleEnchants.end() && lure->second.temporary)
                    {
                        sLureItems.emplace(entry, uint32(spell.SpellId));
                        break;
                    }

        // Each profession's tools, with the items that meet them, for the addon.
        std::map<uint32, std::vector<uint32>> categoryItems; // TotemCategory -> items with it
        for (auto const& [entry, proto] : *sObjectMgr->GetItemTemplateStore())
            if (proto.TotemCategory)
                categoryItems[proto.TotemCategory].push_back(entry);

        std::map<uint32, std::map<std::string, std::vector<uint32>>> recipeKeys; // skill -> keys -> spells
        for (auto const& [spell, need] : sNeeds)
        {
            if (!need.skill)
                continue;
            SkillTools& tools = sTools[need.skill];
            std::string keys;
            for (uint32 totem : need.totem)
                if (totem)
                {
                    tools.items.insert(totem);
                    keys += (keys.empty() ? "" : "/") + Acore::StringFormat("i{}", totem);
                }
            for (uint32 category : need.category)
                if (category)
                {
                    tools.categories.insert(category);
                    keys += (keys.empty() ? "" : "/") + Acore::StringFormat("c{}", category);
                }
            recipeKeys[need.skill][keys].push_back(spell);
        }

        for (auto& [skill, tools] : sTools)
        {
            auto addTool = [&](std::string const& key, std::string const& name, std::vector<uint32> entries)
            {
                for (auto const& [entry, row] : sGear)
                    if (row.countsAs && key == Acore::StringFormat("i{}", row.countsAs))
                        entries.push_back(entry);
                std::sort(entries.begin(), entries.end());
                entries.erase(std::unique(entries.begin(), entries.end()), entries.end());
                if (entries.size() > MAX_TOOL_ENTRIES)
                    entries.resize(MAX_TOOL_ENTRIES);
                std::string list;
                for (uint32 entry : entries)
                    list += (list.empty() ? "" : "/") + std::to_string(entry);
                tools.rows.push_back(Acore::StringFormat("T,{},{},{}", key, Escape(name), list.empty() ? "-" : list));
            };

            for (uint32 totem : tools.items)
            {
                ItemTemplate const* proto = sObjectMgr->GetItemTemplate(totem);
                addTool(Acore::StringFormat("i{}", totem), proto ? proto->Name1 : std::to_string(totem), { totem });
            }

            for (uint32 category : tools.categories)
            {
                TotemCategoryEntry const* required = sTotemCategoryStore.LookupEntry(category);
                std::vector<uint32> entries;
                std::string name;
                uint32 nameEntry = 0;
                for (auto const& [itemCategory, items] : categoryItems)
                {
                    TotemCategoryEntry const* have = sTotemCategoryStore.LookupEntry(itemCategory);
                    if (!required || !have || have->categoryType != required->categoryType
                        || (have->categoryMask & required->categoryMask) != required->categoryMask)
                        continue;
                    entries.insert(entries.end(), items.begin(), items.end());
                    // The server has no TotemCategory names: the tool is named after the first
                    // item of exactly that category ("Blacksmith Hammer").
                    if (itemCategory == category)
                        for (uint32 entry : items)
                            if (!nameEntry || entry < nameEntry)
                                nameEntry = entry;
                }
                if (ItemTemplate const* proto = nameEntry ? sObjectMgr->GetItemTemplate(nameEntry) : nullptr)
                    name = proto->Name1;
                else
                    name = Acore::StringFormat("Tool {}", category);
                addTool(Acore::StringFormat("c{}", category), name, std::move(entries));
            }

            for (auto const& [keys, spells] : recipeKeys[skill])
                for (uint32 spell : spells)
                    tools.rows.push_back(Acore::StringFormat("S,{},{}", spell, keys));
        }

        // About 2,300 recipes have tools in a stock Spell.dbc. Almost none means the server reads a
        // Spell.dbc already cleared (the client patch's): nothing would check tools at all.
        if (sNeeds.size() < 500)
            LOG_ERROR("server.loading", "mod-retail-professions: only {} recipes have tools. Is the server's Spell.dbc the client patch's? "
                "It must be the stock one: the module takes the tools out itself and checks them.", sNeeds.size());

        LOG_INFO("server.loading", ">> mod-retail-professions: {} profession gear items, {} recipes with tools, {} fishing and {} lure spells, {} lures{} in {} ms",
            sGear.size(), sNeeds.size(), sPoleCasts.size(), sPoleEnchants.size(), sLureItems.size(), clear ? " (checked by the module)" : "",
            GetMSTimeDiffToNow(oldMSTime));
    }

    float Bonus(Player* player, uint32 skill, Stat stat)
    {
        if (!GetConfig().gear || stat >= STAT_COUNT)
            return 0.0f;
        Data* data = LoadedDataOf(player);
        if (!data)
            return 0.0f;
        auto itr = data->skills.find(skill);
        if (itr == data->skills.end())
            return 0.0f;
        uint32 total = 0;
        for (Item const* item : itr->second)
            if (item && Usable(player, item))
                if (GearRow const* row = GearFor(item->GetEntry(), skill))
                    total += row->stats[stat];
        return float(total);
    }

    // ---- requests -----------------------------------------------------------------------------

    void HandleCatalog(Player* player, std::string const& req)
    {
        std::vector<std::string> rows;
        rows.reserve(sGear.size());
        for (auto const& [entry, row] : sGear)
        {
            ItemTemplate const* proto = sObjectMgr->GetItemTemplate(entry);
            rows.push_back(Acore::StringFormat("{},{},{},{},{},{},{},{},{},{},{},{}", entry, row.skill, row.slot, row.skillBonus,
                row.stats[STAT_MULTICRAFT], row.stats[STAT_RESOURCEFULNESS], row.stats[STAT_SPEED],
                row.stats[STAT_FINESSE], row.stats[STAT_PERCEPTION], row.stats[STAT_DEFTNESS],
                proto ? proto->RequiredSkill : 0, proto ? proto->RequiredSkillRank : 0));
        }
        SendRows(player, "GCD:" + req, rows);
        Send(player, Acore::StringFormat("GCE:{}:{}", req, rows.size()));
    }

    void HandleState(Player* player, std::string const& req)
    {
        if (!LoadedDataOf(player))
        {
            SendError(player, req, IsBot(player) ? "bot" : "loading");
            return;
        }
        SendState(player, req);
    }

    void HandleTools(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 skill = 0;
        if (args.size() < 3 || !ParseUInt(args[2], skill))
        {
            SendError(player, req, "args");
            return;
        }
        auto itr = sTools.find(skill);
        std::vector<std::string> const empty;
        std::vector<std::string> const& rows = itr != sTools.end() ? itr->second.rows : empty;
        SendRows(player, "GTD:" + req, rows);
        Send(player, Acore::StringFormat("GTE:{}:{}", req, rows.size()));
    }

    void HandleEquip(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 bag = 0, bagSlot = 0, skill = 0, slot = 0;
        if (args.size() < 6 || !ParseUInt(args[2], bag) || !ParseUInt(args[3], bagSlot) || !ParseUInt(args[4], skill) || !ParseUInt(args[5], slot))
        {
            SendError(player, req, "args");
            return;
        }
        if (!CanChange(player, req))
            return;

        Item* item = ItemAtClientPos(player, bag, bagSlot);
        if (!item)
        {
            SendError(player, req, "noitem");
            return;
        }

        // No profession given: the item's own, or the first learned one it is a tool for.
        if (!skill)
        {
            if (GearRow const* row = GearOf(item->GetEntry()))
                skill = row->skill;
            else
                for (Layout const& layout : LAYOUTS)
                    if (player->HasSkill(layout.skill) && IsPlainTool(player, item->GetTemplate(), layout.skill))
                    {
                        skill = layout.skill;
                        break;
                    }
        }
        Layout const* layout = LayoutOf(skill);
        if (!layout)
        {
            SendError(player, req, "notgear");
            return;
        }
        if (char const* why = Refusal(player, item, skill))
        {
            SendError(player, req, why);
            return;
        }

        Data* data = LoadedDataOf(player);
        Slots& slots = data->skills[skill];
        if (slot == ANY_SLOT)
            slot = PickSlot(item, *layout, slots);
        if (slot >= layout->slots || !Fits(item, skill, uint8(slot)))
        {
            SendError(player, req, "slot");
            return;
        }
        for (uint8 other = 0; other < layout->slots; ++other)
            if (other != slot && slots[other] && slots[other]->GetEntry() == item->GetEntry())
            {
                SendError(player, req, "dup");
                return;
            }

        Item* previous = slots[slot];

        // More of the lure already in the slot: the stack grows, what doesn't fit stays in the bags.
        if (previous && previous->GetEntry() == item->GetEntry() && previous->GetMaxStackCount() > 1)
        {
            uint32 move = std::min(previous->GetMaxStackCount() - std::min(previous->GetCount(), previous->GetMaxStackCount()), item->GetCount());
            if (!move)
            {
                SendError(player, req, "full");
                return;
            }
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            previous->SetCount(previous->GetCount() + move);
            SaveSlotted(data, previous, trans);
            player->DestroyItemCount(item, move, true);
            player->SaveInventoryAndGoldToDB(trans);
            CharacterDatabase.CommitTransaction(trans);
            Send(player, Acore::StringFormat("GQ:{}:ok:{}:{}", req, skill, slot));
            SendState(player, "0");
            return;
        }

        // Out of the bags first: whatever the slot held can then take its place there.
        uint8 fromBag = item->GetBagSlot(), fromSlot = item->GetSlot();
        player->MoveItemFromInventory(fromBag, fromSlot, true);

        ItemPosCountVec dest;
        if (previous && player->CanStoreItem(NULL_BAG, NULL_SLOT, dest, previous, false) != EQUIP_ERR_OK)
        {
            // It won't fit (a special bag, say): put the new one back where it was.
            // Its own spot is free again; anywhere else in the bags if not. Should even that fail,
            // its inventory row is still in the database and it is back at the next login.
            ItemPosCountVec back;
            if (player->CanStoreItem(fromBag, fromSlot, back, item, false) == EQUIP_ERR_OK
                || player->CanStoreItem(NULL_BAG, NULL_SLOT, back, item, false) == EQUIP_ERR_OK)
                player->MoveItemToInventory(back, item, true, true);
            else
            {
                LOG_ERROR("module", "mod-retail-professions: {} couldn't take item {} back after a failed swap; it returns at the next login.",
                    player->GetName(), item->GetGUID().GetCounter());
                delete item;
            }
            SendError(player, req, "bags");
            return;
        }

        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        if (previous)
        {
            DeleteSlotRow(previous, trans);
            player->MoveItemToInventory(dest, previous, true);
        }
        item->DeleteFromInventoryDB(trans);
        SaveSlotted(data, item, trans);
        trans->Append("INSERT INTO mod_retail_professions_gear_slot (owner_guid, account, skill, slot, item_guid) VALUES ({}, {}, {}, {})",
            SlotOwner(player, data), skill, slot, item->GetGUID().GetCounter());
        slots[slot] = item;
        player->SaveInventoryAndGoldToDB(trans);
        CharacterDatabase.CommitTransaction(trans);

        UpdateAura(player, *layout, &slots);
        Send(player, Acore::StringFormat("GQ:{}:ok:{}:{}", req, skill, slot));
        SendState(player, "0");
    }

    void HandleUnequip(Player* player, std::string const& req, std::vector<std::string_view> const& args)
    {
        uint32 skill = 0, slot = 0;
        if (args.size() < 4 || !ParseUInt(args[2], skill) || !ParseUInt(args[3], slot))
        {
            SendError(player, req, "args");
            return;
        }
        if (!CanChange(player, req))
            return;

        Data* data = LoadedDataOf(player);
        Layout const* layout = LayoutOf(skill);
        auto itr = data->skills.find(skill);
        if (!layout || slot >= layout->slots || itr == data->skills.end() || !itr->second[slot])
        {
            SendError(player, req, "empty");
            return;
        }

        Item* item = itr->second[slot];
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        if (!Return(player, item, trans, false))
        {
            SendError(player, req, "bags");
            return;
        }
        DeleteSlotRow(item, trans);
        itr->second[slot] = nullptr;
        player->SaveInventoryAndGoldToDB(trans);
        CharacterDatabase.CommitTransaction(trans);

        UpdateAura(player, *layout, &itr->second);
        if (std::none_of(itr->second.begin(), itr->second.end(), [](Item* other) { return other != nullptr; }))
            data->skills.erase(itr);
        Send(player, "GU:" + req + ":ok");
        SendState(player, "0");
    }

    // ---- player life cycle --------------------------------------------------------------------

    void OnLogin(Player* player)
    {
        // Bots never slot anything, and their rows (an alt played by a bot) stay untouched.
        if (IsBot(player))
            return;

        WorldSession* session = player->GetSession();
        ObjectGuid guid = player->GetGUID();
        // The account's rows and the character's own; with the account's slots, its own ones move
        // there (the account's come first, so they keep their slots). With AccountWide off, the
        // first character of the account to log in takes the account's rows as its own, so none
        // are left where nobody reads them. A character keeping slots of its own reads only those.
        bool shared = UsesAccountSlots(player);
        std::string rows = KeepsOwnSlots(player)
            ? Acore::StringFormat("g.owner_guid = {}", guid.GetCounter())
            : Acore::StringFormat("(g.owner_guid = 0 AND g.account = {}) OR g.owner_guid = {}", session->GetAccountId(), guid.GetCounter());
        //                                                                    0               1                    2         3            4           5         6                7                    8              9              10
        session->GetQueryProcessor().AddCallback(CharacterDatabase.AsyncQuery(Acore::StringFormat("SELECT ii.creatorGuid, ii.giftCreatorGuid, ii.count, ii.duration, ii.charges, ii.flags, ii.enchantments, ii.randomPropertyId, ii.durability, ii.playedTime, ii.text, "
            //  11            12            13       14       15                                                                  16
            "g.item_guid, ii.itemEntry, g.skill, g.slot, CAST(ci.item IS NOT NULL OR mi.item_guid IS NOT NULL AS UNSIGNED), g.owner_guid "
            "FROM mod_retail_professions_gear_slot g "
            "LEFT JOIN item_instance ii ON ii.guid = g.item_guid "
            "LEFT JOIN character_inventory ci ON ci.item = g.item_guid "
            "LEFT JOIN mail_items mi ON mi.item_guid = g.item_guid "
            "WHERE {} ORDER BY g.owner_guid, g.skill, g.slot", rows))
            .WithCallback([session, guid, shared](QueryResult result) { Loaded(session, guid, shared, std::move(result)); }));
    }

    bool AccountWide(Player* player)
    {
        if (Data* data = LoadedDataOf(player))
            return data->shared;
        return !IsBot(player) && UsesAccountSlots(player);
    }

    void OnLogout(Player* player)
    {
        Data* data = LoadedDataOf(player);
        if (data && data->rodShown)
            HideRod(player, data);
        // The items are saved, but for the time left on a slotted rod's lure; only the objects go.
        if (data && data->lureTicked)
        {
            auto itr = data->skills.find(SKILL_FISHING);
            if (itr != data->skills.end())
            {
                CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
                for (Item* item : itr->second)
                    if (item && item->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT))
                        SaveSlotted(data, item, trans);
                CharacterDatabase.CommitTransaction(trans);
            }
        }
        player->CustomData.Erase(DATA_KEY);
    }

    void OnDelete(CharacterDatabaseTransaction trans, uint32 guid)
    {
        trans->Append("DELETE ii FROM item_instance ii JOIN mod_retail_professions_gear_slot g ON g.item_guid = ii.guid WHERE g.owner_guid = {}", guid);
        trans->Append("DELETE FROM mod_retail_professions_gear_slot WHERE owner_guid = {}", guid);
    }

    namespace
    {
        // A slotted rod's lure runs out as one on a rod in the bags does: while the player is online.
        void TickLures(Player* player, Data* data, uint32 elapsed)
        {
            auto itr = data->skills.find(SKILL_FISHING);
            if (itr == data->skills.end())
                return;
            for (Item* item : itr->second)
            {
                if (!item || !item->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT) || !item->GetEnchantmentDuration(TEMP_ENCHANTMENT_SLOT))
                    continue;
                uint32 left = item->GetEnchantmentDuration(TEMP_ENCHANTMENT_SLOT);
                if (left > elapsed)
                {
                    item->SetUInt32Value(ITEM_FIELD_ENCHANTMENT_1_1 + TEMP_ENCHANTMENT_SLOT * MAX_ENCHANTMENT_OFFSET + ENCHANTMENT_DURATION_OFFSET, left - elapsed);
                    data->lureTicked = true;
                    continue;
                }
                SetSlottedEnchantment(item, TEMP_ENCHANTMENT_SLOT, 0, 0, 0);
                CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
                SaveSlotted(data, item, trans);
                CharacterDatabase.CommitTransaction(trans);
                Notify(player, Acore::StringFormat("the lure on your {} wore off.", item->GetTemplate()->Name1));
            }
        }
    }

    void Update(Player* player, uint32 diff)
    {
        Data* data = LoadedDataOf(player);
        if (!data)
            return;
        if (data->rodShown && !Fishing(player))
            HideRod(player, data);
        data->sinceCheck += diff;
        if (data->checkTimer > diff)
        {
            data->checkTimer -= diff;
            return;
        }
        data->checkTimer = CHECK_INTERVAL;
        // A challenge taken at the start level, after login: its own slots from now on.
        if (data->shared != UsesAccountSlots(player))
        {
            Reload(player);
            return;
        }
        if (data->skills.empty())
        {
            data->sinceCheck = 0;
            return;
        }
        TickLures(player, data, data->sinceCheck);
        data->sinceCheck = 0;
        if (!player->IsInCombat())
            CheckSkills(player, data);
        // A rod put in the main hand, a pick picked up: what the slots give changes with them.
        UpdateAuras(player);
    }

    void OnUpdateSkill(Player* player, uint32 skill, uint32 value, uint32 newValue)
    {
        auto itr = sLearnLevels.find(skill);
        if (itr == sLearnLevels.end() || newValue <= value)
            return;
        auto next = itr->second.upper_bound(value);
        if (next != itr->second.end() && *next <= newValue)
            player->learnSkillRewardedSpells(skill, newValue);
    }

    // ---- recipe tools -------------------------------------------------------------------------

    namespace
    {
        // The client's own "Requires Fishing Pole".
        void SendNeedsPole(Player* player, Spell const* spell)
        {
            WorldPacket data(SMSG_CAST_FAILED, 1 + 4 + 1 + 4 + 4);
            data << uint8(spell->m_cast_count);
            data << uint32(spell->GetSpellInfo()->Id);
            data << uint8(SPELL_FAILED_EQUIPPED_ITEM_CLASS);
            data << uint32(ITEM_CLASS_WEAPON);
            data << uint32(FISHING_POLE_MASK);
            player->SendDirectMessage(&data);
        }

        // Fishing needs a rod in the main hand or the Fishing slot. A lure or line goes on the rod
        // it was used on (an unpatched client still asks for one; it must be a rod), else on the
        // one in the main hand, else on the slotted one (OnCast).
        void CheckPole(Spell* spell, Player* player, SpellCastResult& res)
        {
            if (auto lure = sPoleEnchants.find(spell->GetSpellInfo()->Id); lure != sPoleEnchants.end())
            {
                if (Item* target = spell->m_targets.GetItemTarget())
                {
                    if (IsFishingPole(target->GetTemplate()))
                    {
                        // As Spell::CheckItems: no soulbound enchantment on a trade partner's item.
                        SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(lure->second.enchant);
                        if (target->GetOwner() != player && (!enchant || (enchant->slot & ENCHANTMENT_CAN_SOULBOUND)))
                            res = SPELL_FAILED_NOT_TRADEABLE;
                        return;
                    }
                }
                else if (MainHandPole(player) || SlottedPole(player))
                    return;
            }
            else if (MainHandPole(player) || SlottedPole(player))
            {
                // A rod just put in the main hand: the slotted one's skill no longer counts.
                UpdateSkillAura(player, SKILL_FISHING);
                return;
            }

            SendNeedsPole(player, spell);
            res = SPELL_FAILED_DONT_REPORT;
        }

        // How long a lure lasts, as Spell::EffectEnchantItemTmp has it.
        uint32 LureSeconds(uint32 spellId)
        {
            switch (spellId)
            {
                case 8087:  // Shiny Bauble
                case 8088:  // Nightcrawlers
                case 8089:  // Aquadynamic Fish Attractor
                case 8090:  // Bright Baubles
                case 8532:  // Aquadynamic Fish Lens
                case 9092:  // Flesh Eating Worm
                case 43699: // Fishing Hat Lure
                case 45731: // Sharpened Fish Hook
                    return 600;
                default:
                    return 3600;
            }
        }

        // Puts a lure or line on a rod: one in the bags, worn or in a trade window as
        // Spell::EffectEnchantItemTmp and EffectEnchantItemPerm do it, the slotted one itself.
        void PutOnRod(Player* player, Item* rod, uint32 spellId, PoleEnchant const& lure, SpellItemEnchantmentEntry const* enchant)
        {
            EnchantmentSlot slot = lure.temporary ? TEMP_ENCHANTMENT_SLOT : PERM_ENCHANTMENT_SLOT;
            uint32 duration = lure.temporary ? LureSeconds(spellId) * IN_MILLISECONDS : 0;
            uint32 charges = lure.temporary ? enchant->charges : 0;

            Data* data = LoadedDataOf(player);
            if (!data || rod != SlottedPole(player))
            {
                Player* owner = rod->GetOwner();
                if (!owner)
                    return;
                owner->ApplyEnchantment(rod, slot, false);
                rod->SetEnchantment(slot, enchant->ID, duration, charges, player->GetGUID());
                owner->ApplyEnchantment(rod, slot, true);
                owner->RemoveTradeableItem(rod);
                rod->ClearSoulboundTradeable(owner);
                return;
            }

            SetSlottedEnchantment(rod, slot, enchant->ID, duration, charges);
            player->GetSession()->SendEnchantmentLog(player->GetGUID(), player->GetGUID(), rod->GetEntry(), enchant->ID);
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            SaveSlotted(data, rod, trans);
            CharacterDatabase.CommitTransaction(trans);
            UpdateSkillAura(player, SKILL_FISHING);
        }

        // A cast of Fishing with no lure on the rod it uses takes one from the lure slot.
        void AutoLure(Player* player)
        {
            Data* data = LoadedDataOf(player);
            if (!data)
                return;
            auto itr = data->skills.find(SKILL_FISHING);
            if (itr == data->skills.end() || !itr->second[LURE_SLOT])
                return;
            Item* rod = MainHandPole(player);
            if (!rod)
                rod = SlottedPole(player);
            if (!rod || rod->GetEnchantmentId(TEMP_ENCHANTMENT_SLOT))
                return;

            Item*& stack = itr->second[LURE_SLOT];
            if (!Usable(player, stack))
                return;
            uint32 spellId = LureSpellOf(stack->GetEntry());
            auto lure = sPoleEnchants.find(spellId);
            SpellItemEnchantmentEntry const* enchant = lure != sPoleEnchants.end() ? sSpellItemEnchantmentStore.LookupEntry(lure->second.enchant) : nullptr;
            if (!enchant)
                return;
            PutOnRod(player, rod, spellId, lure->second, enchant);

            std::string name = stack->GetTemplate()->Name1;
            uint32 left = stack->GetCount() - 1;
            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            if (left)
            {
                stack->SetCount(left);
                SaveSlotted(data, stack, trans);
            }
            else
            {
                DeleteSlotRow(stack, trans);
                stack->DeleteFromDB(trans);
                delete stack;
                stack = nullptr;
            }
            CharacterDatabase.CommitTransaction(trans);
            Notify(player, Acore::StringFormat("{} is on your {} ({} left in the lure slot).", name, rod->GetTemplate()->Name1, left));
            SendState(player, "0");
        }
    }

    void OnCheckCast(Spell* spell, SpellCastResult& res)
    {
        if (res != SPELL_CAST_OK)
            return;
        if (sPoleCleared && (sPoleCasts.count(spell->GetSpellInfo()->Id) || sPoleEnchants.count(spell->GetSpellInfo()->Id)))
        {
            if (Player* player = spell->GetCaster() ? spell->GetCaster()->ToPlayer() : nullptr)
                CheckPole(spell, player, res);
            return;
        }
        // As the core: an item that pays the reagents (an enchanting scroll casting its recipe)
        // needs no tools either.
        if (spell->m_CastItem && spell->m_CastItem->GetTemplate()->HasFlag(ITEM_FLAG_NO_REAGENT_COST))
            return;
        Player* player = spell->GetCaster() ? spell->GetCaster()->ToPlayer() : nullptr;
        if (!player)
            return;
        auto itr = sNeeds.find(spell->GetSpellInfo()->Id);
        if (itr == sNeeds.end())
            return;
        Need const& need = itr->second;

        // The core checks them itself when they weren't taken out.
        if (!sToolsCleared)
            return;

        bool totemsMissing = false;
        for (uint32 totem : need.totem)
            if (totem && !player->HasItemCount(totem) && !CarriesStandIn(player, totem)
                && !AnySlotted(player, need.skill, [totem](Item const* item) { return MeetsTotem(item, totem); }))
                totemsMissing = true;

        bool categoriesMissing = false;
        if (!totemsMissing)
            for (uint32 category : need.category)
                // A pick or knife counts from any profession's slot: a multitool can be both.
                if (category && !player->HasItemTotemCategory(category)
                    && !AnySlotted(player, GatherToolOfCategory(category) ? 0 : need.skill, [player, category](Item const* item) { return MeetsCategory(player, item, category); }))
                    categoriesMissing = true;

        if (!totemsMissing && !categoriesMissing)
            return;

        // The client's own "Requires ..." message, with the tools the spell no longer carries.
        SpellCastResult result = totemsMissing ? SPELL_FAILED_TOTEMS : SPELL_FAILED_TOTEM_CATEGORY;
        std::array<uint32, 2> const& ids = totemsMissing ? need.totem : need.category;
        WorldPacket data(SMSG_CAST_FAILED, 1 + 4 + 1 + 8);
        data << uint8(spell->m_cast_count);
        data << uint32(spell->GetSpellInfo()->Id);
        data << uint8(result);
        for (uint32 id : ids)
            if (id)
                data << uint32(id);
        player->SendDirectMessage(&data);

        res = SPELL_FAILED_DONT_REPORT;
    }

    void OnCast(Spell* spell, Unit* caster, SpellInfo const* info)
    {
        if (!sPoleCleared || !caster || !caster->IsPlayer())
            return;
        Player* player = caster->ToPlayer();
        if (sPoleCasts.count(info->Id))
        {
            if (Item* rod = SlottedPole(player))
                if (Data* data = LoadedDataOf(player))
                    ShowRod(player, data, rod);
            AutoLure(player);
            return;
        }
        auto itr = sPoleEnchants.find(info->Id);
        if (itr == sPoleEnchants.end())
            return;
        SpellItemEnchantmentEntry const* enchant = sSpellItemEnchantmentStore.LookupEntry(itr->second.enchant);
        if (!enchant)
            return;

        // The rod it was used on, else the one in the main hand, else the slotted one.
        Item* rod = spell->m_targets.GetItemTarget();
        if (!rod)
            rod = MainHandPole(player);
        bool slotted = !rod;
        if (!rod)
            rod = SlottedPole(player);
        if (!rod)
            return;
        PutOnRod(player, rod, info->Id, itr->second, enchant);
        if (slotted)
            Notify(player, Acore::StringFormat("{} is on your {}.", info->SpellName[player->GetSession()->GetSessionDbcLocale()], rod->GetTemplate()->Name1));
    }

    // ---- gathering ----------------------------------------------------------------------------

    namespace
    {
        bool IsPrimaryGathered(ItemTemplate const* proto)
        {
            // Herbs, ore, stone, leather and hides; not elementals (motes, essences). Not by exact
            // subclass: the realm has hides under Trade Goods' generic subclass.
            return proto->Class == ITEM_CLASS_TRADE_GOODS && proto->SubClass != ITEM_SUBCLASS_ELEMENTAL;
        }

        uint32 LockSkill(GameObject const* go)
        {
            LockEntry const* lock = sLockStore.LookupEntry(go->GetGOInfo()->GetLockId());
            if (!lock)
                return 0;
            for (uint8 i = 0; i < MAX_LOCK_CASE; ++i)
                if (lock->Type[i] == LOCK_KEY_SKILL)
                {
                    if (lock->Index[i] == LOCKTYPE_HERBALISM)
                        return SKILL_HERBALISM;
                    if (lock->Index[i] == LOCKTYPE_MINING)
                        return SKILL_MINING;
                }
            return 0;
        }

        // The gathering profession behind loot from `source`: a herb or ore node, or a skinned
        // corpse (whose skill may be Herbalism or Mining too). 0 for anything else.
        uint32 GatherSkill(Player const* player, ObjectGuid source, bool skinned)
        {
            if (source.IsGameObject())
            {
                GameObject const* go = ObjectAccessor::GetGameObject(*player, source);
                return go ? LockSkill(go) : 0;
            }
            if (source.IsCreatureOrVehicle() && skinned)
            {
                Creature const* creature = ObjectAccessor::GetCreature(*player, source);
                if (!creature)
                    return 0;
                uint32 skill = creature->GetCreatureTemplate()->GetRequiredLootSkill();
                return skill == SKILL_SKINNING || skill == SKILL_HERBALISM || skill == SKILL_MINING ? skill : 0;
            }
            return 0;
        }

        // Herb gathering, mining and skinning casts.
        uint32 GatherSpellSkill(SpellInfo const* info)
        {
            for (SpellEffectInfo const& effect : info->GetEffects())
            {
                if (effect.Effect == SPELL_EFFECT_SKINNING)
                    return SKILL_SKINNING;
                if (effect.Effect == SPELL_EFFECT_OPEN_LOCK && effect.MiscValue == LOCKTYPE_HERBALISM)
                    return SKILL_HERBALISM;
                if (effect.Effect == SPELL_EFFECT_OPEN_LOCK && effect.MiscValue == LOCKTYPE_MINING)
                    return SKILL_MINING;
            }
            return 0;
        }

        void Give(Player* player, uint32 entry, uint32 count)
        {
            ItemPosCountVec dest;
            if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, entry, count) == EQUIP_ERR_OK)
            {
                if (Item* item = player->StoreNewItem(dest, entry, true))
                    player->SendNewItem(item, count, true, false);
            }
            else
                player->SendItemRetrievalMail(entry, count);
        }
    }

    void OnPrepare(Spell* spell, Unit* caster, SpellInfo const* info)
    {
        if (!caster || !caster->IsPlayer() || spell->getState() != SPELL_STATE_PREPARING)
            return;
        uint32 skill = GatherSpellSkill(info);
        if (!skill)
            return;
        float deftness = std::min(Bonus(caster->ToPlayer(), skill, STAT_DEFTNESS), 90.0f);
        int32 full = spell->GetCastTime();
        if (deftness <= 0.0f || full <= 0)
            return;

        // As the Perks code does it: m_casttime is protected, a derived class may name it.
        struct Access : Spell { using Spell::m_casttime; };
        spell->*(&Access::m_casttime) = std::max<int32>(int32(float(full) * (100.0f - deftness) / 100.0f), 1);
        spell->ReSetTimer();
        spell->SendSpellStart();
    }

    void OnLootItem(Player* player, Item* item, uint32 count, ObjectGuid source)
    {
        if (!item || !count || IsBot(player) || !IsPrimaryGathered(item->GetTemplate()))
            return;

        bool skinned = false;
        if (source.IsCreatureOrVehicle())
            if (Creature const* creature = ObjectAccessor::GetCreature(*player, source))
                skinned = creature->loot.loot_type == LOOT_SKINNING;

        uint32 skill = GatherSkill(player, source, skinned);
        if (!skill)
            return;
        float finesse = Bonus(player, skill, STAT_FINESSE);
        if (finesse <= 0.0f || !roll_chance_f(finesse))
            return;

        Give(player, item->GetEntry(), 1);
        Send(player, Acore::StringFormat("PG:0:{}:F:{}*1", skill, item->GetEntry()));
    }

    void OnItemRoll(Player const* player, LootStoreItem const* storeItem, float& chance, Loot& loot, LootStore const& store)
    {
        if (!player || !storeItem || storeItem->reference || chance >= 100.0f || IsBot(player))
            return;
        bool skinned = &store == &LootTemplates_Skinning;
        if (!skinned && &store != &LootTemplates_Gameobject)
            return;
        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(storeItem->itemid);
        if (!proto || IsPrimaryGathered(proto))
            return;

        uint32 skill = GatherSkill(player, loot.sourceWorldObjectGUID, skinned);
        if (!skill)
            return;
        float perception = Bonus(const_cast<Player*>(player), skill, STAT_PERCEPTION);
        if (perception > 0.0f)
            chance = std::min(chance * (100.0f + perception) / 100.0f, 100.0f);
    }
}
