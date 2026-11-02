/*
 * mod-retail-professions: bosses stay skinnable in bot groups.
 *
 * A corpse can only be skinned once nothing is left on it, and that includes loot the players
 * can't see. Bots pass on quest items (Head of Onyxia), leave their own copy of the per-player ones
 * (Mature Black Dragon Sinew), and can win a unique item they already carry, which the core then
 * keeps on the corpse for them. So the boss never counted as looted. Once the players have taken
 * everything they can, what is left is thrown away and the corpse becomes skinnable
 * (RetailProfessions.BossSkinning.DiscardBotLoot). A unique item a player already carries doesn't
 * count as theirs either: they can't loot a second one.
 *
 * Released under the MIT License.
 */

#include "RetailProfessions.h"
#include "Creature.h"
#include "DataMap.h"
#include "GameTime.h"
#include "Group.h"
#include "Log.h"
#include "LootMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "StringFormat.h"
#include "WorldSession.h"

#include <algorithm>
#include <string>
#include <type_traits>
#include <vector>

namespace
{
    // How often a boss's corpse is checked for loot only bots could still take.
    constexpr uint32 CORPSE_CHECK_INTERVAL = 1000;

    // What keeps a boss from being skinned is logged when it changes, and again after this long.
    constexpr time_t CORPSE_LOG_INTERVAL = 5 * MINUTE;

    struct CorpseCheck : public DataMap::Base
    {
        uint32 timer = 0;
        std::string loggedReason;
        time_t loggedAt = 0;
    };

    // Bot sessions: IsHeadless() on current playerbots cores, IsBot() on older ones.
    template <typename Session, typename = void>
    struct HasIsHeadless : std::false_type { };

    template <typename Session>
    struct HasIsHeadless<Session, std::void_t<decltype(std::declval<Session&>().IsHeadless())>> : std::true_type { };

    template <typename Session, typename = void>
    struct HasIsBot : std::false_type { };

    template <typename Session>
    struct HasIsBot<Session, std::void_t<decltype(std::declval<Session&>().IsBot())>> : std::true_type { };

    template <typename Session>
    bool IsBotSession(Session* session)
    {
        if constexpr (HasIsHeadless<Session>::value)
            return session->IsHeadless();
        else if constexpr (HasIsBot<Session>::value)
            return session->IsBot();
        else
            return false;
    }

    bool IsBot(Player const* player)
    {
        WorldSession* session = player->GetSession();
        return session && IsBotSession(session);
    }

    // Whether the player could still take this item off the corpse. Not when it is reserved for
    // the winner of its roll (the core keeps it for a winner who couldn't carry it), and not when
    // it is a unique item the player already carries.
    bool CanStillLoot(Player const* player, LootItem const& item, ObjectGuid source)
    {
        if (!item.AllowedForPlayer(player, source))
            return false;

        if (item.rollWinnerGUID && item.rollWinnerGUID != player->GetGUID())
            return false;

        ItemPosCountVec dest;
        return player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest, item.itemid, item.count) != EQUIP_ERR_CANT_CARRY_MORE_OF_THIS;
    }

    std::string ItemName(uint32 itemId)
    {
        ItemTemplate const* proto = sObjectMgr->GetItemTemplate(itemId);
        return Acore::StringFormat("{} ({})", proto ? proto->Name1 : "unknown item", itemId);
    }

    // Whether this character may still loot the corpse at all. Someone who has left the group
    // since the kill may not, so what was theirs is nobody's.
    bool HasLootRights(Creature const* creature, Group const* group, ObjectGuid guid)
    {
        return group ? group->IsMember(guid) : creature->GetLootRecipientGUID() == guid;
    }

    // One of the loot's per-player lists (quest items, each player's own copy of a shared item,
    // items that drop on a condition). False when an entry has to stay on the corpse: a player
    // could still take it, or it belongs to someone who is offline and might be a player.
    // `reason` then says which, for the log.
    bool OnlyBotItemsLeft(Creature const* creature, Group const* group, QuestItemMap const& lists,
        std::vector<LootItem> const& items, std::string& reason)
    {
        for (auto const& [guid, list] : lists)
        {
            if (!HasLootRights(creature, group, guid))
                continue;

            Player* owner = ObjectAccessor::FindConnectedPlayer(guid);
            if (owner && IsBot(owner))
                continue;

            for (QuestItem const& entry : *list)
            {
                if (entry.index >= items.size())
                    continue;

                LootItem const& item = items[entry.index];
                if (entry.is_looted || item.is_looted)
                    continue;

                // The master looter is listed for quest items they have no quest for.
                if (owner && owner->IsInMap(creature) && !CanStillLoot(owner, item, creature->loot.sourceWorldObjectGUID))
                    continue;

                reason = owner ? Acore::StringFormat("{} can still loot {}", owner->GetName(), ItemName(item.itemid))
                    : Acore::StringFormat("{} is kept for a character who is offline", ItemName(item.itemid));
                return false;
            }
        }

        return true;
    }

    // Whether all that is left on the corpse is loot no player of the group could take. When it
    // isn't, `reason` says what is in the way, for the log; it stays empty for a group of bots.
    bool OnlyBotLootLeft(Creature const* creature, std::string& reason)
    {
        Loot const& loot = creature->loot;
        Group const* group = creature->GetLootRecipientGroup();

        // The players who can loot this corpse. Bot groups are left alone, and nothing is thrown
        // away while a player is out of the instance: they could come back for it.
        std::vector<Player*> players;
        auto addLooter = [&](Player* looter)
        {
            if (!looter || IsBot(looter))
                return true;

            if (!looter->IsInMap(creature))
            {
                reason = Acore::StringFormat("{} is outside the instance", looter->GetName());
                return false;
            }

            players.push_back(looter);
            return true;
        };

        if (group)
        {
            for (GroupReference const* itr = group->GetFirstMember(); itr != nullptr; itr = itr->next())
                if (!addLooter(itr->GetSource()))
                    return false;
        }
        else if (!addLooter(creature->GetLootRecipient()))
            return false;

        if (players.empty())
            return false;

        // Gold is for everyone, so the players haven't finished looting while it is there.
        if (loot.gold)
        {
            reason = "the gold is still on the corpse";
            return false;
        }

        // Nothing is thrown away while the group still rolls for something on this corpse. The
        // rolls themselves are asked, not the items' "blocked" mark: with Group Loot the core
        // sets that mark on an item everyone is passed on automatically and never takes it off
        // again. One faction's Head of Onyxia is such an item on every kill by the other faction.
        // Rolls only run while the corpse's roll timer does; the group's list of them belongs to
        // every map its members are on, so it isn't read when there is no need.
        if (group && creature->m_groupLootTimer)
        {
            for (Roll const* roll : group->GetRolls())
            {
                if (roll->getTarget() != &loot)
                    continue;

                reason = Acore::StringFormat("the group is still rolling for {}", ItemName(roll->itemid));
                return false;
            }
        }

        // With a master looter, rolled items stay blocked until they are handed out.
        bool const masterLoot = group && group->GetLootMethod() == MASTER_LOOT;

        for (LootItem const& item : loot.items)
        {
            // Shared items are in the per-player lists below.
            if (item.is_looted || item.freeforall)
                continue;

            // No roll is running, so this is an item the core left blocked after a roll nobody
            // could join. It lets nobody loot a blocked item.
            if (item.is_blocked && !masterLoot)
                continue;

            for (Player* player : players)
            {
                if (!CanStillLoot(player, item, loot.sourceWorldObjectGUID))
                    continue;

                reason = Acore::StringFormat("{} can still loot {}", player->GetName(), ItemName(item.itemid));
                return false;
            }

            // Who could loot it when the boss died, for the ones who aren't here to ask now.
            for (ObjectGuid const& guid : item.GetAllowedLooters())
            {
                if (!HasLootRights(creature, group, guid))
                    continue;

                Player* looter = ObjectAccessor::FindConnectedPlayer(guid);
                if (looter && IsBot(looter))
                    continue;

                if (std::find(players.begin(), players.end(), looter) != players.end())
                    continue;

                reason = Acore::StringFormat("{} is kept for a character who is offline", ItemName(item.itemid));
                return false;
            }
        }

        return OnlyBotItemsLeft(creature, group, loot.GetPlayerQuestItems(), loot.quest_items, reason)
            && OnlyBotItemsLeft(creature, group, loot.GetPlayerFFAItems(), loot.items, reason)
            && OnlyBotItemsLeft(creature, group, loot.GetPlayerNonQuestNonFFAConditionalItems(), loot.items, reason);
    }
}

// A boss's corpse becomes skinnable once the players have looted what they can, even if loot only
// bots could take is still on it. The core only counts a corpse as looted when nothing at all is
// left, and bots leave quest items and unique items they already carry behind.
class RetailProfessionsBossSkinningScript : public AllCreatureScript
{
public:
    RetailProfessionsBossSkinningScript() : AllCreatureScript("RetailProfessionsBossSkinningScript") { }

    void OnAllCreatureUpdate(Creature* creature, uint32 diff) override
    {
        if (!RetailProfessions::GetConfig().bossSkinningDiscard || creature->getDeathState() != DeathState::Corpse)
            return;

        if (!creature->IsDungeonBoss() && !creature->isWorldBoss())
            return;

        if (creature->HasUnitFlag(UNIT_FLAG_SKINNABLE) || !creature->HasDynamicFlag(UNIT_DYNFLAG_LOOTABLE))
            return;

        Loot& loot = creature->loot;
        if (loot.loot_type == LOOT_SKINNING || loot.loot_type == LOOT_PICKPOCKETING)
            return;

        uint32 const skinLoot = creature->GetCreatureTemplate()->SkinLootId;
        if (!skinLoot || !LootTemplates_Skinning.HaveLootFor(skinLoot))
            return;

        CorpseCheck* state = creature->CustomData.GetDefault<CorpseCheck>("mod-retail-professions-boss-skinning");
        state->timer += diff;
        if (state->timer < CORPSE_CHECK_INTERVAL)
            return;

        state->timer = 0;

        // The last item can also leave the corpse through a roll, when its winner gets it. The
        // core only notices an empty corpse when someone closes its loot window, and by then
        // nobody has a reason to open it: the corpse would stay lootable and unskinnable.
        std::string reason;
        if (!loot.isLooted() && !OnlyBotLootLeft(creature, reason))
        {
            // So a boss that stays unskinnable can be explained from Server.log.
            time_t const now = GameTime::GetGameTime().count();
            if (!reason.empty() && (reason != state->loggedReason || now >= state->loggedAt + CORPSE_LOG_INTERVAL))
            {
                LOG_INFO("module", "mod-retail-professions: {} can't be skinned yet: {}", creature->GetName(), reason);
                state->loggedReason = reason;
                state->loggedAt = now;
            }

            return;
        }

        if (loot.isLooted())
            LOG_DEBUG("module", "mod-retail-professions: {} can be skinned now, its last loot went to a roll winner", creature->GetName());
        else
            LOG_INFO("module", "mod-retail-professions: {} can be skinned now, what only bots could loot was thrown away",
                creature->GetName());

        state->loggedReason.clear();

        // What the core does when the last item is looted.
        creature->AllLootRemovedFromCorpse();
        creature->RemoveDynamicFlag(UNIT_DYNFLAG_LOOTABLE);
        loot.clear();
    }
};

void AddRetailProfessionsBossSkinningScripts()
{
    new RetailProfessionsBossSkinningScript();
}
