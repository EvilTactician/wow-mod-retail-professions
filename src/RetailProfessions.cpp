/*
 * mod-retail-professions: configuration, the addon transport, request dispatch and script
 * registration.
 *
 * Wire format, both directions: "<COMMAND>:<request id>:<field>:<field>..." after the addon
 * prefix and a tab. Rows inside a field are separated by ';' and their values by ','. List
 * answers come as "<X>R" (meta), any number of "<X>D" (rows) and "<X>E" (end).
 *
 *   HELLO:<req>:<protocol>   -> HELLO:<req>:<version>:<flags>:<stamp>:<skill cap>:<orange %>:<grey %>:<points>
 *                               :<multicraft min>:<max>:<resourcefulness min>:<max>:<refund>:<speed min>:<max>
 *   L:<req>:<skill line>     -> LR:<req>:<skill>:<count>:<gm>, LD rows, LE   (RetailProfessionsIndex.cpp)
 *   W:<req>:<spell>          -> WR:<req>:<spell>:<recipe item>, WD rows, WE
 *   M:<req>:<T|V>:<entry>    -> M:<req>:ok:<where>   or ERR:<req>:none
 *   Y:<req>:<M|P>            -> YR:<req>:<kind>:<count>, YD rows, YE        (RetailProfessionsRefine.cpp)
 *   X:<req>:<M|P>:<item>:<n> -> X:<req>:ok:<n>:<cast ms>, then XP per cast and XE at the end
 *   XS:<req>                 -> XS:<req>:ok
 *   (unasked)                   PK:0:<spell>:<M|R>:<item*n/...>   a craft proc      (RetailProfessionsPerks.cpp)
 *   GC, G, GQ, GU, GT           profession equipment                                 (RetailProfessionsGear.cpp)
 *
 * Addon messages arrive as CMSG_MESSAGECHAT on the world thread, so requests are answered
 * straight from the hook.
 */

#include "RetailProfessions.h"
#include "Chat.h"
#include "Config.h"
#include "Player.h"
#include "QuestDef.h"
#include "ScriptMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>
#include <charconv>
#include <unordered_map>

namespace RetailProfessions
{
    namespace
    {
        Config sConfig;

        // Each request but HELLO walks an index on the world thread, and addon whispers are
        // never muted by the chat flood check, so each character gets a small budget.
        constexpr float REQUEST_BURST = 12.0f;
        constexpr float REQUEST_RATE = 4.0f;

        struct SessionState
        {
            float tokens = REQUEST_BURST;
            uint32 lastRefill = 0;
        };

        std::unordered_map<ObjectGuid::LowType, SessionState> sSessions;

        constexpr uint32 IP_PROGRESSION_QUEST_BASE = 66000;
        constexpr uint8 IP_STATE_MAX = 18;
        constexpr uint8 IP_STATE_TBC = 8;
        constexpr uint8 IP_STATE_WOTLK = 13;
    }

    Config& GetConfig()
    {
        return sConfig;
    }

    void Send(Player* player, std::string const& payload)
    {
        if (!player || !player->GetSession())
            return;

        std::string full = std::string(PREFIX) + "\t" + payload;
        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, full);
        player->GetSession()->SendPacket(&data);
    }

    void SendRows(Player* player, std::string const& header, std::vector<std::string> const& rows)
    {
        std::string line;
        std::size_t const budget = MAX_PAYLOAD - header.size() - 1;
        for (std::string const& row : rows)
        {
            if (!line.empty() && line.size() + 1 + row.size() > budget)
            {
                Send(player, header + ":" + line);
                line.clear();
            }
            if (!line.empty())
                line += ';';
            line += row;
        }
        if (!line.empty())
            Send(player, header + ":" + line);
    }

    void SendError(Player* player, std::string const& req, std::string_view what)
    {
        Send(player, "ERR:" + req + ":" + std::string(what));
    }

    bool ParseUInt(std::string_view text, uint32& out)
    {
        if (text.empty())
            return false;
        auto result = std::from_chars(text.data(), text.data() + text.size(), out, 10);
        return result.ec == std::errc{} && result.ptr == text.data() + text.size();
    }

    std::string Escape(std::string_view text)
    {
        if (text.empty())
            return "-";

        static char const* const HEX = "0123456789ABCDEF";
        std::string out;
        out.reserve(text.size());
        for (char c : text)
        {
            if (c == ',' || c == ';' || c == ':' || c == '|' || c == '%' || c == '\n' || c == '\r')
            {
                out += '%';
                out += HEX[(uint8(c) >> 4) & 0xF];
                out += HEX[uint8(c) & 0xF];
            }
            else
                out += c;
        }
        // A lone "-" would read back as empty.
        return out == "-" ? "%2D" : out;
    }

    uint8 ProgressionState(Player* player)
    {
        if (!sConfig.progressionEnabled || player->IsGameMaster())
            return IP_STATE_MAX;

        uint8 state = 0;
        for (uint8 i = 1; i <= IP_STATE_MAX; ++i)
            if (player->GetQuestStatus(IP_PROGRESSION_QUEST_BASE + i) == QUEST_STATUS_REWARDED)
                state = i;
        return state;
    }

    uint32 SkillCap(Player* player)
    {
        if (!sConfig.skillCapByEra || !sConfig.progressionEnabled)
            return 0;

        uint8 state = ProgressionState(player);
        if (state < IP_STATE_TBC)
            return 300;
        if (state < IP_STATE_WOTLK)
            return 375;
        return 0;
    }

    namespace
    {
        void LoadConfig()
        {
            sConfig.enabled = sConfigMgr->GetOption<bool>("RetailProfessions.Enable", true);
            sConfig.skillCapByEra = sConfigMgr->GetOption<bool>("RetailProfessions.SkillCapByEra", true);
            sConfig.hideLockedContinents = sConfigMgr->GetOption<bool>("RetailProfessions.HideLockedContinents", true);
            sConfig.maxSourcesPerKind = std::clamp<uint32>(sConfigMgr->GetOption<uint32>("RetailProfessions.MaxSourcesPerKind", 6), 1, 20);
            sConfig.worldDropThreshold = std::max<uint32>(sConfigMgr->GetOption<uint32>("RetailProfessions.WorldDropThreshold", 25), 5);
            sConfig.saveZoneData = sConfigMgr->GetOption<bool>("RetailProfessions.SaveZoneData", true);
            sConfig.refine = sConfigMgr->GetOption<bool>("RetailProfessions.Refine.Enable", true);
            sConfig.refineCastTime = std::min<uint32>(sConfigMgr->GetOption<uint32>("RetailProfessions.Refine.CastTime", 0), 60000);
            sConfig.perks = sConfigMgr->GetOption<bool>("RetailProfessions.Perks.Enable", true);
            auto percent = [](char const* key, uint32 fallback, uint32 most)
            {
                return std::min<uint32>(sConfigMgr->GetOption<uint32>(key, fallback), most);
            };
            sConfig.multicraftMax = percent("RetailProfessions.Perks.Multicraft.Max", 25, 100);
            sConfig.multicraftMin = percent("RetailProfessions.Perks.Multicraft.Min", 0, sConfig.multicraftMax);
            sConfig.resourcefulMax = percent("RetailProfessions.Perks.Resourcefulness.Max", 20, 100);
            sConfig.resourcefulMin = percent("RetailProfessions.Perks.Resourcefulness.Min", 0, sConfig.resourcefulMax);
            sConfig.resourcefulRefund = percent("RetailProfessions.Perks.Resourcefulness.Refund", 30, 100);
            sConfig.speedMax = percent("RetailProfessions.Perks.Speed.Max", 50, 90);
            sConfig.speedMin = percent("RetailProfessions.Perks.Speed.Min", 0, sConfig.speedMax);
            sConfig.gear = sConfigMgr->GetOption<bool>("RetailProfessions.Gear.Enable", true);
            sConfig.gearAccountWide = sConfigMgr->GetOption<bool>("RetailProfessions.Gear.AccountWide", true);
            sConfig.gearPersonalChallenges = sConfigMgr->GetOption<uint32>("RetailProfessions.Gear.PersonalChallenges", 15);
            sConfig.bossSkinningDiscard = sConfigMgr->GetOption<bool>("RetailProfessions.BossSkinning.DiscardBotLoot", true);
            sConfig.progressionEnabled = sConfigMgr->GetOption<bool>("IndividualProgression.Enable", false, false);
            sConfig.progressionLimit = sConfigMgr->GetOption<uint8>("IndividualProgression.ProgressionLimit", 0, false);
            sConfig.zulGurubState = sConfigMgr->GetOption<uint8>("IndividualProgression.RequiredZulGurubProgression", 3, false);
            sConfig.zulAmanState = sConfigMgr->GetOption<uint8>("IndividualProgression.RequiredZulAmanProgression", 12, false);
        }

        bool TakeToken(SessionState& state, float cost)
        {
            uint32 now = getMSTime();
            if (state.lastRefill)
                state.tokens = std::min(REQUEST_BURST, state.tokens + getMSTimeDiff(state.lastRefill, now) * REQUEST_RATE / 1000.0f);
            state.lastRefill = now;
            if (state.tokens < cost)
                return false;
            state.tokens -= cost;
            return true;
        }

        void HandleHello(Player* player, std::string const& req)
        {
            uint32 orange = sWorld->getIntConfig(CONFIG_SKILL_CHANCE_ORANGE);
            uint32 grey = sWorld->getIntConfig(CONFIG_SKILL_CHANCE_GREY);
            uint32 gain = sWorld->getIntConfig(CONFIG_SKILL_GAIN_CRAFTING);
            uint32 flags = HELLO_RECIPES | HELLO_MAP_PINS | HELLO_GUIDE | HELLO_RANKS | (sConfig.refine ? HELLO_REFINE : 0)
                | (sConfig.perks ? HELLO_PERKS : 0) | (sConfig.gear ? HELLO_GEAR | HELLO_GEAR_GATHER | HELLO_GEAR_TYPED : 0)
                | (sConfig.gear && Gear::AccountWide(player) ? HELLO_GEAR_ACCOUNT : 0);
            Send(player, "HELLO:" + req + ":" + std::to_string(PROTOCOL_VERSION) + ":"
                + std::to_string(flags) + ":" + std::to_string(Index::Stamp())
                + ":" + std::to_string(SkillCap(player)) + ":" + std::to_string(orange) + ":" + std::to_string(grey)
                + ":" + std::to_string(gain)
                + Acore::StringFormat(":{}:{}:{}:{}:{}:{}:{}", sConfig.multicraftMin, sConfig.multicraftMax,
                    sConfig.resourcefulMin, sConfig.resourcefulMax, sConfig.resourcefulRefund, sConfig.speedMin, sConfig.speedMax));
        }

        std::vector<std::string_view> Split(std::string_view text, char sep)
        {
            std::vector<std::string_view> parts;
            std::size_t start = 0;
            while (true)
            {
                std::size_t pos = text.find(sep, start);
                if (pos == std::string_view::npos)
                {
                    parts.push_back(text.substr(start));
                    break;
                }
                parts.push_back(text.substr(start, pos - start));
                start = pos + 1;
            }
            return parts;
        }

        void Dispatch(Player* player, std::string_view message)
        {
            std::vector<std::string_view> args = Split(message, ':');
            if (args.size() < 2 || args.size() > 8)
                return;

            std::string_view command = args[0];
            std::string req(args[1].substr(0, 12));

            if (command == "HELLO")
            {
                HandleHello(player, req);
                return;
            }

            // A recipe list is a hundred-odd messages; the addon caches it, so it's rare. What
            // herbs and ore give is a few dozen, asked once per login.
            if (!TakeToken(sSessions[player->GetGUID().GetCounter()], command == "L" || command == "Y" || command == "GT" ? 4.0f : 1.0f))
            {
                SendError(player, req, "busy");
                return;
            }

            if (command == "L")
                Index::HandleList(player, req, args);
            else if (command == "W")
                Index::HandleWhere(player, req, args);
            else if (command == "K")
                Index::HandleRank(player, req, args);
            else if (command == "M")
                Index::HandleMapPin(player, req, args);
            else if (!sConfig.gear && (command == "GC" || command == "G" || command == "GQ" || command == "GU" || command == "GT"))
                SendError(player, req, "off");
            else if (command == "GC")
                Gear::HandleCatalog(player, req);
            else if (command == "G")
                Gear::HandleState(player, req);
            else if (command == "GQ")
                Gear::HandleEquip(player, req, args);
            else if (command == "GU")
                Gear::HandleUnequip(player, req, args);
            else if (command == "GT")
                Gear::HandleTools(player, req, args);
            else if (!sConfig.refine && (command == "Y" || command == "X" || command == "XS"))
                SendError(player, req, "off");
            else if (command == "Y")
                Refine::HandleYields(player, req, args);
            else if (command == "X")
                Refine::HandleStart(player, req, args);
            else if (command == "XS")
                Refine::HandleStop(player, req);
            else
                SendError(player, req, "unknown");
        }
    }
}

using namespace RetailProfessions;

class RetailProfessionsPlayerScript : public PlayerScript
{
public:
    RetailProfessionsPlayerScript() : PlayerScript("RetailProfessionsPlayerScript",
        {
            PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT,
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_DELETE_FROM_DB,
            PLAYERHOOK_ON_UPDATE,
            PLAYERHOOK_ON_CREATE_ITEM,
            PLAYERHOOK_ON_LOOT_ITEM,
            PLAYERHOOK_ON_UPDATE_SKILL
        }) { }

    // The addon whispers itself; swallow those messages so they never show up as chat.
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 lang, std::string& msg, Player* receiver) override
    {
        if (lang != LANG_ADDON || !receiver || receiver != player)
            return true;

        std::string const prefixTab = std::string(PREFIX) + "\t";
        if (msg.compare(0, prefixTab.size(), prefixTab) != 0)
            return true;

        if (!GetConfig().enabled)
        {
            Send(player, "OFF:0");
            return false;
        }

        Dispatch(player, std::string_view(msg).substr(prefixTab.size()));
        return false;
    }

    void OnPlayerLogin(Player* player) override
    {
        Gear::OnLogin(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        sSessions.erase(player->GetGUID().GetCounter());
        Refine::Forget(player);
        Gear::OnLogout(player);
    }

    // Only a real delete (CharDeleteMethod 0) gets here; an unlinked character keeps its gear.
    void OnPlayerDeleteFromDB(CharacterDatabaseTransaction trans, uint32 guid) override
    {
        Gear::OnDelete(trans, guid);
    }

    void OnPlayerUpdate(Player* player, uint32 diff) override
    {
        Refine::Update(player, diff);
        Gear::Update(player, diff);
    }

    void OnPlayerCreateItem(Player* player, Item* item, uint32 count) override
    {
        Perks::OnCreateItem(player, item, count);
    }

    void OnPlayerLootItem(Player* player, Item* item, uint32 count, ObjectGuid lootguid) override
    {
        Gear::OnLootItem(player, item, count, lootguid);
    }

    void OnPlayerUpdateSkill(Player* player, uint32 skillId, uint32 value, uint32 /*max*/, uint32 /*step*/, uint32 newValue) override
    {
        Gear::OnUpdateSkill(player, skillId, value, newValue);
    }
};

class RetailProfessionsSpellScript : public AllSpellScript
{
public:
    RetailProfessionsSpellScript() : AllSpellScript("RetailProfessionsSpellScript",
        { ALLSPELLHOOK_ON_PREPARE, ALLSPELLHOOK_ON_SPELL_CHECK_CAST, ALLSPELLHOOK_ON_CAST }) { }

    void OnSpellPrepare(Spell* spell, Unit* caster, SpellInfo const* spellInfo) override
    {
        Perks::OnPrepare(spell, caster, spellInfo);
        Gear::OnPrepare(spell, caster, spellInfo);
    }

    void OnSpellCheckCast(Spell* spell, bool /*strict*/, SpellCastResult& res) override
    {
        Gear::OnCheckCast(spell, res);
    }

    void OnSpellCast(Spell* spell, Unit* caster, SpellInfo const* spellInfo, bool /*skipCheck*/) override
    {
        Gear::OnCast(spell, caster, spellInfo);
    }
};

class RetailProfessionsGlobalScript : public GlobalScript
{
public:
    RetailProfessionsGlobalScript() : GlobalScript("RetailProfessionsGlobalScript", { GLOBALHOOK_ON_ITEM_ROLL }) { }

    bool OnItemRoll(Player const* player, LootStoreItem const* storeItem, float& chance, Loot& loot, LootStore const& store) override
    {
        Gear::OnItemRoll(player, storeItem, chance, loot, store);
        return true;
    }
};

class RetailProfessionsWorldScript : public WorldScript
{
public:
    RetailProfessionsWorldScript() : WorldScript("RetailProfessionsWorldScript",
        { WORLDHOOK_ON_AFTER_CONFIG_LOAD, WORLDHOOK_ON_STARTUP }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        LoadConfig();
    }

    // After every spawn is loaded and before the maps update: the index reads zones from the
    // map files.
    void OnStartup() override
    {
        if (GetConfig().enabled)
        {
            // First: the recipe lists say which recipes get a perk.
            if (GetConfig().perks)
                Perks::Build();
            // Before the index: it lists recipes as the client sees them, tools taken out.
            Gear::Build();
            Index::Build();
            if (GetConfig().refine)
                Refine::Build();
        }
    }
};

void AddRetailProfessionsBossSkinningScripts();

void AddRetailProfessionsScripts()
{
    AddRetailProfessionsBossSkinningScripts();
    new RetailProfessionsPlayerScript();
    new RetailProfessionsSpellScript();
    new RetailProfessionsGlobalScript();
    new RetailProfessionsWorldScript();
}
