#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <cstrike>
#include <hitmarkers>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#tryinclude <TopDefenders>
#tryinclude <hitsounds>
#define REQUIRE_PLUGIN

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin forwards
//----------------------------------------------------------------------------------------------------
GlobalForward g_hForward_StatusOK;
GlobalForward g_hForward_StatusNotOK;

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin convars
//----------------------------------------------------------------------------------------------------
ConVar g_cvChannel;
ConVar g_cvShowDamage;

//----------------------------------------------------------------------------------------------------
// Purpose: Cookie handles
//----------------------------------------------------------------------------------------------------
Cookie g_cShowDamage;
Cookie g_cShowHitmarker;
Cookie g_cDisplayType;
Cookie g_cHitmarkerStyle;
Cookie g_cShowHealth;
Cookie g_cHeadshotColor;
Cookie g_cBodyshotColor;

//----------------------------------------------------------------------------------------------------
// Purpose: Global variables
//----------------------------------------------------------------------------------------------------
bool g_bShowDamage = true;
bool g_bPlugin_DynamicChannels = false;
bool g_bDynamicNative = false;
bool g_bPlugin_TopDefenders = false;
bool g_bTopDefsNative = false;
bool g_bPlugin_HitSounds = false;
bool g_bHitSoundsNative = false;

#define g_iHitmarkerStyle 6 // g_sHitStyles size - 1
int g_iHUDChannel = 4;
enum struct PlayerData
{
	int damage;
	int enable;
	int health;
	int type;
	int style;
	int headColor[3];
	int bodyColor[3];

	int lastTick;

	void Reset()
	{
		this.damage = 1;
		this.enable = 2;
		this.health = 1;
		this.type = view_as<int>(DISPLAY_CENTER);
		this.style = g_iHitmarkerStyle;
		this.headColor[0] = 255;
		this.headColor[1] = 45;
		this.headColor[2] = 45;
		this.bodyColor[0] = 255;
		this.bodyColor[1] = 165;
		this.bodyColor[2] = 0;
		this.lastTick = -1;
	}
}

PlayerData g_playerData[MAXPLAYERS+1];

enum DisplayType
{
	DISPLAY_CENTER = 0,
	DISPLAY_GAME = 1,
	DISPLAY_HINT = 2
}

Handle g_hHudSync = INVALID_HANDLE;

//----------------------------------------------------------------------------------------------------
// Purpose: Hitmarker styles
//----------------------------------------------------------------------------------------------------
char g_sHitStyles[7][32] =
{
	"∷",
	"◞ ◟\n◝ ◜",
	"◜◝\n◟◞",
	"╳",
	"╲ ╱\n╱ ╲",
	"⊕",
	"⊗",
};

public Plugin myinfo =
{
	name = "Hitmarkers",
	author = "koen, .Rushaway",
	description = "Generates hitmarkers when you hit a player or an entity",
	version = HitMarker_VERSION,
	url = "https://github.com/srcdslab/sm-plugin-HitMarker"
};

public void OnPluginStart()
{
	// LoadTranslations("plugin.hitmarkers.phrases");

	// Plugin settings
	g_cvChannel = CreateConVar("sm_hitmarker_channel", "4", "Channel for hitmarkers to be displayed on");
	g_cvChannel.AddChangeHook(OnConVarChange);
	g_iHUDChannel = g_cvChannel.IntValue;

	g_cvShowDamage = CreateConVar("sm_hitmarker_showdamage", "1", "Show damage under hitmarker");
	g_cvShowDamage.AddChangeHook(OnConVarChange);
	g_bShowDamage = g_cvShowDamage.BoolValue;
	AutoExecConfig(true, "Hitmarkers");

	// Plugin commands
	RegConsoleCmd("sm_hm", Command_Hitmarkers, "Open hitmarkers settings");
	RegConsoleCmd("sm_hitmarker", Command_Hitmarkers, "Open hitmarker settings");
	RegConsoleCmd("sm_hitmarkers", Command_Hitmarkers, "Open hitmarker settings");
	RegConsoleCmd("sm_sd", Command_Hitmarkers, "Open hitmarkers settings");
	RegConsoleCmd("sm_showdamage", Command_Hitmarkers, "Open hitmarkers settings");

	RegConsoleCmd("sm_headhitcolor", Command_HeadColor, "Change your zombie hitmarker color.");
	RegConsoleCmd("sm_headhitcolour", Command_HeadColor, "Change your zombie hitmarker color.");

	RegConsoleCmd("sm_bodyhitcolor", Command_BodyColor, "Change your zombie hitmarker color.");
	RegConsoleCmd("sm_bodyhitcolour", Command_BodyColor, "Change your zombie hitmarker color.");

	// Event hooks
	HookEvent("player_hurt", Event_PlayerHurt);
	HookEvent("round_end", Event_OnRoundEnd, EventHookMode_PostNoCopy);

	// Hook onto entities so plugin detects when we hit a boss (or a breakable)
	HookEntityOutput("func_physbox", "OnHealthChanged", Hook_EntityOnDamage);
	HookEntityOutput("func_physbox_multiplayer", "OnHealthChanged", Hook_EntityOnDamage);
	HookEntityOutput("func_breakable", "OnHealthChanged", Hook_EntityOnDamage);
	HookEntityOutput("math_counter", "OutValue", Hook_EntityOnDamage);

	CleanupAndInit();

	// Client cookies
	SetCookieMenuItem(SettingsMenuHandler, 0, "Hitmarker Settings");

	g_cShowDamage = new Cookie("Hitmarker_Damage", "Show damage under hitmarker", CookieAccess_Private);
	g_cShowHitmarker = new Cookie("hitmarker_enable", "Show hitmarkers", CookieAccess_Private);
	g_cDisplayType = new Cookie("hitmarker_display", "Hitmarker display type", CookieAccess_Private);
	g_cHitmarkerStyle = new Cookie("hitmarker_style", "Hitmarker style", CookieAccess_Private);
	g_cHeadshotColor = new Cookie("hitmarker_head_color", "Headshot hitmarker color", CookieAccess_Private);
	g_cBodyshotColor = new Cookie("hitmarker_body_color", "Bodyshot hitmarker color", CookieAccess_Private);
	g_cShowHealth = new Cookie("hitmarker_health", "Show health under hitmarker", CookieAccess_Private);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && AreClientCookiesCached(client))
			OnClientCookiesCached(client);
	}
}

public void OnAllPluginsLoaded()
{
	SendForward_Available();

	g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");
	g_bPlugin_TopDefenders = LibraryExists("TopDefenders");
	g_bPlugin_HitSounds = LibraryExists("hitsounds");
	VerifyNatives();
}

public void OnPluginPauseChange(bool pause)
{
	if (pause)
		SendForward_NotAvailable();
	else
		SendForward_Available();
}

public void OnPluginEnd()
{
	SendForward_NotAvailable();
}


public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
	{
		g_bPlugin_DynamicChannels = true;
		VerifyNative_DynamicChannel();
	}
	if (strcmp(name, "TopDefenders", false) == 0)
	{
		g_bPlugin_TopDefenders = true;
		VerifyNative_TopDefenders();
	}
	if (strcmp(name, "hitsounds", false) == 0)
	{
		g_bPlugin_HitSounds = true;
		VerifyNative_HitSounds();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
	{
		g_bPlugin_DynamicChannels = false;
		VerifyNative_DynamicChannel();
	}
	if (strcmp(name, "TopDefenders", false) == 0)
	{
		g_bPlugin_TopDefenders = false;
		VerifyNative_TopDefenders();
	}
	if (strcmp(name, "hitsounds", false) == 0)
	{
		g_bPlugin_HitSounds = false;
		VerifyNative_HitSounds();
	}
}

public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	g_iHUDChannel = g_cvChannel.IntValue;
	g_bShowDamage = g_cvShowDamage.BoolValue;
}

stock void VerifyNatives()
{
	VerifyNative_DynamicChannel();
	VerifyNative_TopDefenders();
	VerifyNative_HitSounds();
}

stock void VerifyNative_DynamicChannel()
{
	g_bDynamicNative = g_bPlugin_DynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;
}

stock void VerifyNative_TopDefenders()
{
	g_bTopDefsNative = g_bPlugin_TopDefenders && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "TopDefenders_GetClientRank") == FeatureStatus_Available;
}

stock void VerifyNative_HitSounds()
{
	g_bHitSoundsNative = g_bPlugin_HitSounds && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "OpenHitsoundMenu") == FeatureStatus_Available;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Natives
//----------------------------------------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("hitmarkers");

	// Get client settings native
	CreateNative("GetHitmarkerStatus", Native_GetHitmarkerStatus);

	// Change client settings native
	CreateNative("ToggleHitmarker", Native_ToggleHitmarker);

	// Menu native
	CreateNative("OpenHitmarkerMenu", Native_OpenHitmarkerMenu);

	// Plugin forwards
	g_hForward_StatusOK = CreateGlobalForward("HitMarker_OnPluginOK", ET_Ignore);
	g_hForward_StatusNotOK = CreateGlobalForward("HitMarker_OnPluginNotOK", ET_Ignore);

	return APLRes_Success;
}

public int Native_GetHitmarkerStatus(Handle plugin, int numParams)
{
	HitmarkerType type = view_as<HitmarkerType>(GetNativeCell(2));
	switch (type)
	{
		case Hitmarker_Damage:
		{
			return g_playerData[GetNativeCell(1)].damage;
		}
		case Hitmarker_Enable:
		{
			return g_playerData[GetNativeCell(1)].enable;
		}
		case Hitmarker_Rank:
		{
			return g_playerData[GetNativeCell(1)].health;
		}
	}
	return 1;
}

public int Native_ToggleHitmarker(Handle plugin, int numParams)
{
	HitmarkerType type = view_as<HitmarkerType>(GetNativeCell(2));
	switch (type)
	{
		case Hitmarker_Damage:
		{
			InternalToggleDamage(GetNativeCell(1));
		}
		case Hitmarker_Enable:
		{
			InternalToggleHitmarker(GetNativeCell(1));
		}
		case Hitmarker_Rank:
		{
			InternalToggleShowHealth(GetNativeCell(1));
		}
	}
	return 1;
}

public int Native_OpenHitmarkerMenu(Handle plugin, int numParams)
{
	MenuType type = view_as<MenuType>(GetNativeCell(2));
	switch (type)
	{
		case Menu_Hitmarker:
		{
			HitmarkerMenu(GetNativeCell(1));
		}
		case Menu_HeadColor:
		{
			HeadColor(GetNativeCell(1));
		}
		case Menu_BodyColor:
		{
			BodyColor(GetNativeCell(1));
		}
	}
	return 1;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Client connect & disconnect
//----------------------------------------------------------------------------------------------------
public void OnClientPutInServer(int client)
{
	if (!AreClientCookiesCached(client))
	{
		g_playerData[client].damage = 1;
		g_playerData[client].enable = 2;
		g_playerData[client].health = 1;
		g_playerData[client].type = view_as<int>(DISPLAY_CENTER);
		g_playerData[client].style = g_iHitmarkerStyle;
		g_playerData[client].headColor[0] = 255;
		g_playerData[client].headColor[1] = 45;
		g_playerData[client].headColor[2] = 45;
		g_playerData[client].bodyColor[0] = 255;
		g_playerData[client].bodyColor[1] = 165;
		g_playerData[client].bodyColor[2] = 0;
	}
}

public void OnClientDisconnect(int client)
{
	g_playerData[client].Reset();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Cookie functions
//----------------------------------------------------------------------------------------------------
public void OnClientCookiesCached(int client)
{
	char buffer[32];
	g_cShowHitmarker.Get(client, buffer, sizeof(buffer));

	if (buffer[0] == '\0' && !IsFakeClient(client))
	{
		g_cShowHitmarker.Set(client, "2");
		g_cShowDamage.Set(client, "1");
		g_cShowHealth.Set(client, "1");

		// Default display type is game center bcs players are used to it
		// Dont wanna make karen start crying a river..
		IntToString(view_as<int>(DISPLAY_CENTER), buffer, sizeof(buffer));
		g_cDisplayType.Set(client, buffer);
		IntToString(g_iHitmarkerStyle, buffer, sizeof(buffer));
		g_cHitmarkerStyle.Set(client, buffer);
		g_cHeadshotColor.Set(client, "255 45 45");
		g_cBodyshotColor.Set(client, "255 165 0");
		return;
	}

	g_cShowHitmarker.Get(client, buffer, sizeof(buffer));
	g_playerData[client].enable = StringToInt(buffer);

	g_cShowDamage.Get(client, buffer, sizeof(buffer));
	g_playerData[client].damage = StringToInt(buffer);

	g_cDisplayType.Get(client, buffer, sizeof(buffer));
	g_playerData[client].type = StringToInt(buffer);

	g_cShowHealth.Get(client, buffer, sizeof(buffer));
	g_playerData[client].health = strcmp(buffer, "1", false) == 0;

	g_cHitmarkerStyle.Get(client, buffer, sizeof(buffer));
	g_playerData[client].style = StringToInt(buffer);

	char buffer2[3][8];
	int val;

	g_cHeadshotColor.Get(client, buffer, sizeof(buffer));
	ExplodeString(buffer, " ", buffer2, sizeof(buffer2), sizeof(buffer2[]), true);

	val = StringToInt(buffer2[0]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_playerData[client].headColor[0] = val;

	val = StringToInt(buffer2[1]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_playerData[client].headColor[1] = val;

	val = StringToInt(buffer2[2]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_playerData[client].headColor[2] = val;

	g_cBodyshotColor.Get(client, buffer, sizeof(buffer));
	ExplodeString(buffer, " ", buffer2, sizeof(buffer2), sizeof(buffer2[]), true);

	val = StringToInt(buffer2[0]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_playerData[client].bodyColor[0] = val;

	val = StringToInt(buffer2[1]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_playerData[client].bodyColor[1] = val;

	val = StringToInt(buffer2[2]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_playerData[client].bodyColor[2] = val;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Console command callbacks
//----------------------------------------------------------------------------------------------------
public Action Command_Hitmarkers(int client, int args)
{
	HitmarkerMenu(client);
	return Plugin_Handled;
}

public Action Command_HeadColor(int client, int args)
{
	if (args != 3)
	{
		HeadColor(client);
		return Plugin_Handled;
	}

	char buffer[32];
	int r, g, b;

	GetCmdArg(1, buffer, sizeof(buffer));
	r = StringToInt(buffer);
	GetCmdArg(2, buffer, sizeof(buffer));
	g = StringToInt(buffer);
	GetCmdArg(3, buffer, sizeof(buffer));
	b = StringToInt(buffer);

	if (r > 255) r = 255;
	else if (r < 0) r = 0;

	if (g > 255) g = 255;
	else if (g < 0) g = 0;

	if (b > 255) b = 255;
	else if (b < 0) b = 0;

	g_playerData[client].headColor[0] = r;
	g_playerData[client].headColor[1] = g;
	g_playerData[client].headColor[2] = b;

	Format(buffer, sizeof(buffer), "%d %d %d", r, g, b);
	g_cHeadshotColor.Set(client, buffer);

	CReplyToCommand(client, "{green}[HitMarker]{default} You have set your headshot hitmarker color to {red}%d {green}%d {blue}%d", r, g, b);
	return Plugin_Handled;
}

public Action Command_BodyColor(int client, int args)
{
	if (args != 3)
	{
		BodyColor(client);
		return Plugin_Handled;
	}

	char buffer[32];
	int r, g, b;

	GetCmdArg(1, buffer, sizeof(buffer));
	r = StringToInt(buffer);
	GetCmdArg(2, buffer, sizeof(buffer));
	g = StringToInt(buffer);
	GetCmdArg(3, buffer, sizeof(buffer));
	b = StringToInt(buffer);

	if (r > 255) r = 255;
	else if (r < 0) r = 0;

	if (g > 255) g = 255;
	else if (g < 0) g = 0;

	if (b > 255) b = 255;
	else if (b < 0) b = 0;

	g_playerData[client].bodyColor[0] = r;
	g_playerData[client].bodyColor[1] = g;
	g_playerData[client].bodyColor[2] = b;

	Format(buffer, sizeof(buffer), "%d %d %d", r, g, b);
	g_cBodyshotColor.Set(client, buffer);

	CReplyToCommand(client, "{green}[HitMarker]{default} You have set your headshot hitmarker color to {red}%d {green}%d {blue}%d", r, g, b);
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Toggle setting functions
//----------------------------------------------------------------------------------------------------
void InternalToggleHitmarker(int client)
{
	g_playerData[client].enable++;
	if (g_playerData[client].enable > 2)
		g_playerData[client].enable = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_playerData[client].enable);
	g_cShowHitmarker.Set(client, buffer);
	switch (g_playerData[client].enable)
	{
		case 0:
			CPrintToChat(client, "{green}[HitMarker]{default} Hitmarkers are now {red}disabled");
		case 1:
			CPrintToChat(client, "{green}[HitMarker]{default} Hitmarkers are now {green}enabled");
		case 2:
			CPrintToChat(client, "{green}[HitMarker]{default} Hitmarkers are now {green}enabled (Players + Bosses)");
	}
}

void InternalToggleDamage(int client)
{
	g_playerData[client].damage++;
	if (g_playerData[client].damage > 2)
		g_playerData[client].damage = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_playerData[client].damage);
	g_cShowDamage.Set(client, buffer);
	switch (g_playerData[client].damage)
	{
		case 0:
			CPrintToChat(client, "{green}[HitMarker]{default} Damage display under hitmarkers is now {red}disabled");
		case 1:
			CPrintToChat(client, "{green}[HitMarker]{default} Damage display under hitmarkers is now {green}enabled");
		case 2:
			CPrintToChat(client, "{green}[HitMarker]{default} Damage display under hitmarkers is now {green}enabled (+Rank)");
	}
}

void InternalToggleDisplayType(int client)
{
	g_playerData[client].type++;
	if (g_playerData[client].type > 2)
		g_playerData[client].type = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_playerData[client].type);
	g_cDisplayType.Set(client, buffer);
	switch (g_playerData[client].type)
	{
		case 0:
			CPrintToChat(client, "{green}[HitMarker]{default} Hitmarker display type is now using {green}Game Center");
		case 1:
			CPrintToChat(client, "{green}[HitMarker]{default} Hitmarker display type is now using {green}Game_text");
		case 2:
			CPrintToChat(client, "{green}[HitMarker]{default} Hitmarker display type is now using {green}Hint");
	}
}

void InternalToggleShowHealth(int client)
{
	g_playerData[client].health++;
	if (g_playerData[client].health > 2)
		g_playerData[client].health = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_playerData[client].health);
	g_cShowHealth.Set(client, buffer);
	switch (g_playerData[client].health)
	{
		case 0:
			CPrintToChat(client, "{green}[HitMarker]{default} Health display under hitmarkers is now {red}disabled");
		case 1:
			CPrintToChat(client, "{green}[HitMarker]{default} Health display under hitmarkers is now {green}enabled");
		case 2:
			CPrintToChat(client, "{green}[HitMarker]{default} Health display under hitmarkers is now {green}enabled (+Victim name)");
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Player hurt event hook
//----------------------------------------------------------------------------------------------------
public void Event_PlayerHurt(Handle event, const char[] name, bool broadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (!(1 <= attacker <= MaxClients) || !IsClientInGame(attacker))
		return;

	if (!IsPlayerAlive(attacker) || GetClientTeam(attacker) != CS_TEAM_CT)
		return;

	// Only show 1 hitmarker per tick
	int tick = GetGameTickCount();
	if (tick == g_playerData[attacker].lastTick)
		return;

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsClientInGame(victim) || GetClientTeam(victim) == CS_TEAM_CT || attacker == victim)
		return;

	if (g_playerData[attacker].style > g_iHitmarkerStyle)
		g_playerData[attacker].style = 0;

	int damage = GetEventInt(event, "dmg_health");
	int hitgroup = GetEventInt(event, "hitgroup");
	int hp = GetEventInt(event, "health") + damage;

	char sRank[32], buffer[128], sHP[128] = "Dead";

#if defined _TopDefenders_included
	if (g_bShowDamage && g_bTopDefsNative && g_playerData[attacker].damage == 2)
		Format(sRank, sizeof(sRank), "(#%d)", TopDefenders_GetClientRank(attacker));
#endif

	if (g_bShowDamage && g_playerData[attacker].health != 0 && hp > 0)
	{
		if (g_playerData[attacker].health == 2)
			Format(sHP, sizeof(sHP), "%N: %d HP", victim, hp);
		else
			Format(sHP, sizeof(sHP), "%d HP", hp);
	}

	// Format our hitmarker
	if (g_playerData[attacker].type != view_as<int>(DISPLAY_GAME)) // DISPLAY_CENTER or DISPLAY_HINT
	{
		if (g_bShowDamage && g_playerData[attacker].damage != 0)
		{
			Format(buffer, sizeof(buffer), "-%d %s", damage, g_playerData[attacker].damage == 2 ? sRank : "");
			if (g_playerData[attacker].health)
				Format(buffer, sizeof(buffer), "%s \n%s", buffer, sHP);

			SendHudMsg(attacker, buffer, view_as<DisplayType>(g_playerData[attacker].type));
		}
		else if (g_bShowDamage && g_playerData[attacker].health)
		{
			Format(buffer, sizeof(buffer), "%s %s", buffer, sHP);
			SendHudMsg(attacker, buffer, view_as<DisplayType>(g_playerData[attacker].type));
		}
		if (g_playerData[attacker].enable)
		{
			Format(buffer, sizeof(buffer), "%s", g_sHitStyles[g_playerData[attacker].style]);
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
	}
	else if (g_playerData[attacker].type == view_as<int>(DISPLAY_GAME))
	{
		// The Hitmarker is not enabled but we still need to Format for damage or/and health
		if (!g_playerData[attacker].enable)
			Format(buffer, sizeof(buffer), "\n\n\n\n\n\n\n\n");
	
		// For this display we need to always set the new line at the end of the string
		// This is because we re-use the buffer for each line
		if (g_bShowDamage && g_playerData[attacker].damage != 0)
		{
			Format(buffer, sizeof(buffer), "%s-%d %s\n", buffer, damage, g_playerData[attacker].damage == 2 ? sRank : "");
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
		else
			Format(buffer, sizeof(buffer), "%s\n", buffer);

		if (g_bShowDamage && g_playerData[attacker].health)
		{
			Format(buffer, sizeof(buffer), "%s%s\n", buffer, sHP);
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
		else
			Format(buffer, sizeof(buffer), "%s\n", buffer);

		if (g_playerData[attacker].enable)
		{
			Format(buffer, sizeof(buffer), "\n\n\n\n%s\n\n%s", g_sHitStyles[g_playerData[attacker].style], buffer);
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
	}

	g_playerData[attacker].lastTick = tick;
}

public void Hook_EntityOnDamage(const char[] output, int caller, int activator, float delay)
{
	if (!(1 <= activator <= MaxClients) || !IsClientInGame(activator))
		return;
	
	if (g_playerData[activator].enable != 2)
		return;

	if (!IsPlayerAlive(activator))
		return;

	// Only show 1 hitmarker per tick
	int tick = GetGameTickCount();
	if (tick == g_playerData[activator].lastTick)
		return;

	if (g_playerData[activator].style > g_iHitmarkerStyle)
		g_playerData[activator].style = 0;

	char buffer[128];
	Format(buffer, sizeof(buffer), "\n\n\n\n%s\n\n\n\n", g_sHitStyles[g_playerData[activator].style]);
	SendHudMsg(activator, buffer, DISPLAY_GAME);
}

void SendHudMsg(int client, char[] szMessage, DisplayType type = DISPLAY_HINT, int hitgroup = 0)
{	
	if (type == DISPLAY_HINT && IsVoteInProgress())
		type = DISPLAY_GAME;

	if (type == DISPLAY_HINT)
	{
		PrintHintText(client, "%s", szMessage);
		return;
	}

	if (type == DISPLAY_CENTER)
	{
		PrintCenterText(client, "%s", szMessage);
		return;
	}

	if (g_hHudSync != INVALID_HANDLE)
	{
		if (type == DISPLAY_GAME)
		{
			if (hitgroup == 1)
				SetHudTextParams(-1.0, -1.0, 0.1, g_playerData[client].headColor[0], g_playerData[client].headColor[1], g_playerData[client].headColor[2], 255, 0, 0.0, 0.0, 0.1);
			else
				SetHudTextParams(-1.0, -1.0, 0.1, g_playerData[client].bodyColor[0], g_playerData[client].bodyColor[1], g_playerData[client].bodyColor[2], 255, 0, 0.0, 0.0, 0.1);
		}

		int iHUDChannel = -1;
		if (g_iHUDChannel < 0 || g_iHUDChannel > 5)
			g_iHUDChannel = 4;

	#if defined _DynamicChannels_included_
		if (g_bDynamicNative)
			iHUDChannel = GetDynamicChannel(g_iHUDChannel);
	#endif

		if (g_bDynamicNative)
			ShowHudText(client, iHUDChannel, "%s", szMessage);
		else
		{
			ClearSyncHud(client, g_hHudSync);
			ShowSyncHudText(client, g_hHudSync, "%s", szMessage);
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Management of Handles and prevent memory leaks
//----------------------------------------------------------------------------------------------------
public void CleanupAndInit()
{
	Cleanup();
	Init();
}

void Cleanup(bool bPluginEnd = false)
{
	delete g_hHudSync;

	if (bPluginEnd)
		delete g_cvChannel;
}

public void Init()
{
	g_hHudSync = CreateHudSynchronizer();
}

public void OnMapStart()
{
	CleanupAndInit();
}

public void OnMapEnd()
{
	Cleanup();
}

public void Event_OnRoundEnd(Event event, const char[] name, bool dontBroadcast) 
{ 
	CleanupAndInit();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Main cookie settings menu
//----------------------------------------------------------------------------------------------------
public void SettingsMenuHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch (action)
	{
		case CookieMenuAction_SelectOption:
		{
			HitmarkerMenu(client);
		}
	}
}

public void HitmarkerMenu(int client)
{
	if (!client)
		return;

	Menu menu = CreateMenu(HitmarkerMenuHandler);
	menu.ExitBackButton = true;
	menu.ExitButton = true;

	char buffer[128];

	if (g_playerData[client].enable == 0)
	{
		menu.SetTitle("Hitmarker Settings\n ");
		
		switch(g_playerData[client].enable)
		{
			case 0:
				Format(buffer, sizeof(buffer), "Disabled");
			case 1:
				Format(buffer, sizeof(buffer), "Enabled");
			case 2:
				Format(buffer, sizeof(buffer), "Enabled (Players + Bosses)");
		}
		Format(buffer, sizeof(buffer), "Hitmarkers: %s", buffer);
		menu.AddItem("toggle", buffer);
	}
	else
	{
		menu.SetTitle("Hitmarkers\n \nCurrent Style (%d/%d):\n%s", g_playerData[client].style + 1, sizeof(g_sHitStyles), g_sHitStyles[g_playerData[client].style]);
		switch(g_playerData[client].enable)
		{
			case 0:
				Format(buffer, sizeof(buffer), "Disabled");
			case 1:
				Format(buffer, sizeof(buffer), "Enabled");
			case 2:
				Format(buffer, sizeof(buffer), "Enabled (Players + Bosses)");
		}
		Format(buffer, sizeof(buffer), "Hitmarkers: %s\n \nCustomize Hitmarker:", buffer);
		menu.AddItem("toggle", buffer);
		// menu.AddItem("toggle", "Disable Hitmarkers\n \nCustomize Hitmarker:");
		menu.AddItem("style", "Change Style");

		Format(buffer, sizeof(buffer), "Headshot Color: %d %d %d", g_playerData[client].headColor[0], g_playerData[client].headColor[1], g_playerData[client].headColor[2]);
		menu.AddItem("headcolor", buffer);

		Format(buffer, sizeof(buffer), "Bodyshot Color: %d %d %d\n ", g_playerData[client].bodyColor[0], g_playerData[client].bodyColor[1], g_playerData[client].bodyColor[2]);
		menu.AddItem("bodycolor", buffer);
	}

	switch(g_playerData[client].type)
	{
		case 0:
			Format(buffer, sizeof(buffer), "Game Center");
		case 1:
			Format(buffer, sizeof(buffer), "Game Text");
		case 2:
			Format(buffer, sizeof(buffer), "Hint");
	}
	Format(buffer, sizeof(buffer), "Display Type: %s", buffer);
	menu.AddItem("display", buffer);

	switch(g_playerData[client].damage)
	{
		case 0:
			Format(buffer, sizeof(buffer), "Off");
		case 1:
			Format(buffer, sizeof(buffer), "On");
		case 2:
			Format(buffer, sizeof(buffer), "On (+Rank)");
	}
	Format(buffer, sizeof(buffer), "Show Damage: %s", buffer);
	menu.AddItem("showdamage", buffer);

	switch(g_playerData[client].health)
	{
		case 0:
			Format(buffer, sizeof(buffer), "Off");
		case 1:
			Format(buffer, sizeof(buffer), "On");
		case 2:
			Format(buffer, sizeof(buffer), "On (+Victim name)");
	}
	Format(buffer, sizeof(buffer), "Show Health: %s", buffer);
	menu.AddItem("showhealth", buffer);

	if (g_bHitSoundsNative)
		menu.AddItem("hitsounds", "Hit Sounds Settings");

	menu.Display(client, MENU_TIME_FOREVER);
}

public int HitmarkerMenuHandler(Handle menu, MenuAction action, int client, int selection)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char info[32];
			GetMenuItem(menu, selection, info, sizeof(info));

			if (strcmp(info, "toggle", false) == 0)
			{
				InternalToggleHitmarker(client);
				HitmarkerMenu(client);
			}
			else if (strcmp(info, "style", false) == 0)
			{
				g_playerData[client].style++;
				if (g_playerData[client].style > g_iHitmarkerStyle)
					g_playerData[client].style = 0;

				Format(info, sizeof(info), "%d", g_playerData[client].style);
				g_cHitmarkerStyle.Set(client, info);

				HitmarkerMenu(client);
			}
			else if (strcmp(info, "headcolor", false) == 0)
			{
				HeadColor(client);
			}
			else if (strcmp(info, "bodycolor", false) == 0)
			{
				BodyColor(client);
			}
			else if (strcmp(info, "showdamage", false) == 0)
			{
				InternalToggleDamage(client);
				HitmarkerMenu(client);
			}
			else if (strcmp(info, "display", false) == 0)
			{
				InternalToggleDisplayType(client);
				HitmarkerMenu(client);
			}
			else if (strcmp(info, "showhealth", false) == 0)
			{
				InternalToggleShowHealth(client);
				HitmarkerMenu(client);
			}
		#if defined _hitsounds_included
			else if (g_bHitSoundsNative && strcmp(info, "hitsounds", false) == 0)
			{
				OpenHitsoundMenu(client);
			}
		#endif
		}
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack)
				ShowCookieMenu(client);
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
	return 0;
}

public void HeadColor(int client)
{
	Menu menu = CreateMenu(HeadColorHandler);
	menu.ExitBackButton = true;
	menu.ExitButton = true;

	char buffer[256];
	Format(buffer, 256, "Headshot Hitmarker Colors:\n \nUse \"!headhitcolor <r> <g> <b>\"\nOr choose a color below\n \n");

	Format(buffer, 256, "%sCurrent color: %d %d %d\n", buffer, g_playerData[client].headColor[0], g_playerData[client].headColor[1], g_playerData[client].headColor[2]);
	menu.SetTitle(buffer);

	menu.AddItem("re", "Red");
	menu.AddItem("or", "Orange");
	menu.AddItem("gr", "Green");
	menu.AddItem("bl", "Light Blue");
	menu.AddItem("yl", "Yellow");
	menu.AddItem("wh", "White");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int HeadColorHandler(Handle menu, MenuAction action, int client, int selection)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char buffer[32];
			GetMenuItem(menu, selection, buffer, 32);
			if (strcmp(buffer, "re", false) == 0)
			{
				g_playerData[client].headColor[0] = 255;
				g_playerData[client].headColor[1] = 45;
				g_playerData[client].headColor[2] = 45;
			}
			else if (strcmp(buffer, "or", false) == 0)
			{
				g_playerData[client].headColor[0] = 255;
				g_playerData[client].headColor[1] = 165;
				g_playerData[client].headColor[2] = 0;
			}
			else if (strcmp(buffer, "gr", false) == 0)
			{
				g_playerData[client].headColor[0] = 45;
				g_playerData[client].headColor[1] = 255;
				g_playerData[client].headColor[2] = 45;
			}
			else if (strcmp(buffer, "bl", false) == 0)
			{
				g_playerData[client].headColor[0] = 45;
				g_playerData[client].headColor[1] = 220;
				g_playerData[client].headColor[2] = 255;
			}
			else if (strcmp(buffer, "yl", false) == 0)
			{
				g_playerData[client].headColor[0] = 255;
				g_playerData[client].headColor[1] = 234;
				g_playerData[client].headColor[2] = 0;
			}
			else if (strcmp(buffer, "wh", false) == 0)
			{
				g_playerData[client].headColor[0] = 200;
				g_playerData[client].headColor[1] = 200;
				g_playerData[client].headColor[2] = 200;
			}

			Format(buffer, sizeof(buffer), "%d %d %d", g_playerData[client].headColor[0], g_playerData[client].headColor[1], g_playerData[client].headColor[2]);
			g_cHeadshotColor.Set(client, buffer);

			HeadColor(client);
		}
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack)
				HitmarkerMenu(client);
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
	return 0;
}

public void BodyColor(int client)
{
	Menu menu = CreateMenu(BodyColorHandler);
	menu.ExitBackButton = true;
	menu.ExitButton = true;

	char buffer[256];
	Format(buffer, 256, "Bodyshot Hitmarker Colors:\n \nUse \"!bodyhitcolor <r> <g> <b>\"\nOr choose a color below\n \n");

	Format(buffer, 256, "%sCurrent color: %d %d %d\n", buffer, g_playerData[client].bodyColor[0], g_playerData[client].bodyColor[1], g_playerData[client].bodyColor[2]);
	menu.SetTitle(buffer);

	menu.AddItem("re", "Red");
	menu.AddItem("or", "Orange");
	menu.AddItem("gr", "Green");
	menu.AddItem("bl", "Light Blue");
	menu.AddItem("yl", "Yellow");
	menu.AddItem("wh", "White");
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BodyColorHandler(Handle menu, MenuAction action, int client, int selection)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char buffer[32];
			GetMenuItem(menu, selection, buffer, 32);
			if (strcmp(buffer, "re", false) == 0)
			{
				g_playerData[client].bodyColor[0] = 255;
				g_playerData[client].bodyColor[1] = 45;
				g_playerData[client].bodyColor[2] = 45;
			}
			else if (strcmp(buffer, "or", false) == 0)
			{
				g_playerData[client].bodyColor[0] = 255;
				g_playerData[client].bodyColor[1] = 165;
				g_playerData[client].bodyColor[2] = 0;
			}
			else if (strcmp(buffer, "gr", false) == 0)
			{
				g_playerData[client].bodyColor[0] = 45;
				g_playerData[client].bodyColor[1] = 255;
				g_playerData[client].bodyColor[2] = 45;
			}
			else if (strcmp(buffer, "bl", false) == 0)
			{
				g_playerData[client].bodyColor[0] = 45;
				g_playerData[client].bodyColor[1] = 220;
				g_playerData[client].bodyColor[2] = 255;
			}
			else if (strcmp(buffer, "yl", false) == 0)
			{
				g_playerData[client].bodyColor[0] = 255;
				g_playerData[client].bodyColor[1] = 234;
				g_playerData[client].bodyColor[2] = 0;
			}
			else if (strcmp(buffer, "wh", false) == 0)
			{
				g_playerData[client].bodyColor[0] = 200;
				g_playerData[client].bodyColor[1] = 200;
				g_playerData[client].bodyColor[2] = 200;
			}

			Format(buffer, sizeof(buffer), "%d %d %d", g_playerData[client].bodyColor[0], g_playerData[client].bodyColor[1], g_playerData[client].bodyColor[2]);
			g_cBodyshotColor.Set(client, buffer);

			BodyColor(client);
		}
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack)
				HitmarkerMenu(client);
		}
		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
	return 0;
}

stock void SendForward_Available()
{
	Call_StartForward(g_hForward_StatusOK);
	Call_Finish();
}

stock void SendForward_NotAvailable()
{
	Call_StartForward(g_hForward_StatusNotOK);
	Call_Finish();
}