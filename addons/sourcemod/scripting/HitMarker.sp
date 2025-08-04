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
#define REQUIRE_PLUGIN

#define DEFAULT_VOLUME 0.8
#define DEFAULT_VOLUME_INT 80

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin convars
//----------------------------------------------------------------------------------------------------
ConVar g_cvEnable;
ConVar g_cvChannel;
ConVar g_cvShowDamage;
ConVar g_cvHitsound;
ConVar g_cvHitsoundHead;
ConVar g_cvHitsoundBody;
ConVar g_cvHitsoundKill;

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
Cookie g_cVolume;
Cookie g_cEnable;
Cookie g_cBoss;
Cookie g_cDetailed;

//----------------------------------------------------------------------------------------------------
// Purpose: Global variables
//----------------------------------------------------------------------------------------------------
bool g_bEnable = true;
bool g_bShowDamage = true;
bool g_bPlugin_DynamicChannels = false;
bool g_bDynamicNative = false;
bool g_bPlugin_TopDefenders = false;
bool g_bTopDefsNative = false;

char g_sHitsoundPath[PLATFORM_MAX_PATH];
char g_sHitsoundHeadPath[PLATFORM_MAX_PATH];
char g_sHitsoundBodyPath[PLATFORM_MAX_PATH];
char g_sHitsoundKillPath[PLATFORM_MAX_PATH];

#define g_iHitmarkerStyle 6 // g_sHitStyles size - 1
int g_iHUDChannel = 4;
int g_iLastTick[MAXPLAYERS + 1] = {-1, ...};
enum struct HM_PlayerData
{
	int damage;
	int enable;
	int health;
	int type;
	int style;
	int headColor[3];
	int bodyColor[3];

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
	}
}

enum struct HS_PlayerData
{
	int volume;
	float fVolume;
	bool boss;
	bool enable;
	bool detailed;

	void Reset()
	{
		this.volume = DEFAULT_VOLUME_INT;
		this.fVolume = DEFAULT_VOLUME;
		this.boss = true;
		this.enable = true;
		this.detailed = false;
	}
}

HM_PlayerData g_HM_pData[MAXPLAYERS + 1];
HS_PlayerData g_HS_pData[MAXPLAYERS + 1];

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

	// HitMarker convars
	g_cvEnable = CreateConVar("sm_hitmarker_enable", "1", "Enable hitmarkers");
	g_cvEnable.AddChangeHook(OnConVarChange);
	g_bEnable = g_cvEnable.BoolValue;

	g_cvChannel = CreateConVar("sm_hitmarker_channel", "4", "Channel for hitmarkers to be displayed on");
	g_cvChannel.AddChangeHook(OnConVarChange);
	g_iHUDChannel = g_cvChannel.IntValue;

	g_cvShowDamage = CreateConVar("sm_hitmarker_showdamage", "1", "Show damage under hitmarker");
	g_cvShowDamage.AddChangeHook(OnConVarChange);
	g_bShowDamage = g_cvShowDamage.BoolValue;

	// Hitsound convars
	g_cvHitsound = CreateConVar("sm_hitsound_path", "hitmarker/hitmarker.mp3", "File location of normal hitsound relative to sound folder.");
	g_cvHitsoundHead = CreateConVar("sm_hitsound_head_path", "hitmarker/headshot.mp3", "File location of head hitsound relative to sound folder.");
	g_cvHitsoundBody = CreateConVar("sm_hitsound_body_path", "hitmarker/bodyshot.mp3", "File location of body hitsound relative to sound folder.");
	g_cvHitsoundKill = CreateConVar("sm_hitsound_kill_path", "hitmarker/killshot.mp3", "File location of kill hitsound relative to sound folder.");
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

	RegConsoleCmd("sm_hits", Command_Hitsound, "Bring up hitsounds settings menu");
	RegConsoleCmd("sm_hitsound", Command_Hitsound, "Bring up hitsounds settings menu");
	RegConsoleCmd("sm_hitsounds", Command_Hitsound, "Bring up hitsounds settings menu");

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
	SetCookieMenuItem(SettingsMenuHandler, INVALID_HANDLE, "Hitmarker Settings");
	SetCookieMenuItem(CookieMenu_HitMarker, INVALID_HANDLE, "Hit Sound Settings");
	

	g_cShowDamage = new Cookie("hitmarker_damage", "Show damage under hitmarker", CookieAccess_Private);
	g_cShowHitmarker = new Cookie("hitmarker_enable", "Show hitmarkers", CookieAccess_Private);
	g_cDisplayType = new Cookie("hitmarker_display", "Hitmarker display type", CookieAccess_Private);
	g_cHitmarkerStyle = new Cookie("hitmarker_style", "Hitmarker style", CookieAccess_Private);
	g_cHeadshotColor = new Cookie("hitmarker_head_color", "Headshot hitmarker color", CookieAccess_Private);
	g_cBodyshotColor = new Cookie("hitmarker_body_color", "Bodyshot hitmarker color", CookieAccess_Private);
	g_cShowHealth = new Cookie("hitmarker_health", "Show health under hitmarker", CookieAccess_Private);

	g_cEnable = new Cookie("hitsound_enable", "Toggle hitsounds", CookieAccess_Private);
	g_cVolume = new Cookie("hitsound_volume", "Hitsound volume", CookieAccess_Private);
	g_cBoss = new Cookie("hitsound_boss", "Toggle boss hitsounds", CookieAccess_Private);
	g_cDetailed = new Cookie("hitsound_detailed", "Toggle detailed hitsounds", CookieAccess_Private);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && AreClientCookiesCached(client))
			OnClientCookiesCached(client);
	}
}

public void OnAllPluginsLoaded()
{
	g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");
	g_bPlugin_TopDefenders = LibraryExists("TopDefenders");
	VerifyNatives();
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
	{
		g_bPlugin_DynamicChannels = true;
		VerifyNative_DynamicChannel();
	}
	else if (strcmp(name, "TopDefenders", false) == 0)
	{
		g_bPlugin_TopDefenders = true;
		VerifyNative_TopDefenders();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
	{
		g_bPlugin_DynamicChannels = false;
		VerifyNative_DynamicChannel();
	}
	else if (strcmp(name, "TopDefenders", false) == 0)
	{
		g_bPlugin_TopDefenders = false;
		VerifyNative_TopDefenders();
	}
}

public void OnConVarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	g_bEnable = g_cvEnable.BoolValue;
	g_iHUDChannel = g_cvChannel.IntValue;
	g_bShowDamage = g_cvShowDamage.BoolValue;
}

public void OnConfigsExecuted()
{
	PrecacheSounds();
	GetConVarString(g_cvHitsound, g_sHitsoundPath, sizeof(g_sHitsoundPath));
	GetConVarString(g_cvHitsoundBody, g_sHitsoundBodyPath, sizeof(g_sHitsoundBodyPath));
	GetConVarString(g_cvHitsoundHead, g_sHitsoundHeadPath, sizeof(g_sHitsoundHeadPath));
	GetConVarString(g_cvHitsoundKill, g_sHitsoundKillPath, sizeof(g_sHitsoundKillPath));
}

stock void VerifyNatives()
{
	VerifyNative_DynamicChannel();
	VerifyNative_TopDefenders();
}

stock void VerifyNative_DynamicChannel()
{
	g_bDynamicNative = g_bPlugin_DynamicChannels && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;
}

stock void VerifyNative_TopDefenders()
{
	g_bTopDefsNative = g_bPlugin_TopDefenders && CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "TopDefenders_GetClientRank") == FeatureStatus_Available;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Natives
//----------------------------------------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("hitmarkers");

	// Get client settings native
	CreateNative("GetHitmarkerStatus", Native_GetHitmarkerStatus);
	CreateNative("GetHitsoundStatus", Native_GetHitsoundStatus);
	CreateNative("GetHitsoundVolume", Native_GetHitsoundVolume);

	// Change client settings native
	CreateNative("ToggleHitmarker", Native_ToggleHitmarker);
	CreateNative("ToggleHitsound", Native_ToggleHitsound);
	CreateNative("SetHitsoundVolume", Native_SetHitsoundVolume);

	// Menu native
	CreateNative("OpenHitmarkerMenu", Native_OpenHitmarkerMenu);
	CreateNative("OpenHitsoundMenu", Native_OpenHitsoundMenu);

	return APLRes_Success;
}

public int Native_GetHitmarkerStatus(Handle plugin, int numParams)
{
	HitmarkerType type = view_as<HitmarkerType>(GetNativeCell(2));
	switch (type)
	{
		case Hitmarker_Damage:
		{
			return g_HM_pData[GetNativeCell(1)].damage;
		}
		case Hitmarker_Enable:
		{
			return g_HM_pData[GetNativeCell(1)].enable;
		}
		case Hitmarker_Rank:
		{
			return g_HM_pData[GetNativeCell(1)].health;
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

public int Native_GetHitsoundStatus(Handle plugin, int numParams)
{
	SoundType type = view_as<SoundType>(GetNativeCell(2));
	switch (type)
	{
		case Sound_Zombie:
			return g_HS_pData[GetNativeCell(1)].enable;
		case Sound_Boss:
			return g_HS_pData[GetNativeCell(1)].boss;
		case Sound_Detailed:
			return g_HS_pData[GetNativeCell(1)].detailed;
	}
	return 1;
}

public any Native_GetHitsoundVolume(Handle plugin, int numParams)
{
	return g_HS_pData[GetNativeCell(1)].volume;
}

public int Native_ToggleHitsound(Handle plugin, int numParams)
{
	SoundType type = view_as<SoundType>(GetNativeCell(2));
	switch (type)
	{
		case Sound_Zombie:
			ToggleZombieHitsound(GetNativeCell(1));
		case Sound_Boss:
			ToggleBossHitsound(GetNativeCell(1));
		case Sound_Detailed:
			ToggleDetailedHitsound(GetNativeCell(1));
	}
	return 1;
}

public int Native_SetHitsoundVolume(Handle plugin, int numParams)
{
	char buffer[4];
	Format(buffer, sizeof(buffer), "%.2f", GetNativeCell(2) / 100.0);
	g_HS_pData[GetNativeCell(1)].volume = GetNativeCell(2);
	g_HS_pData[GetNativeCell(1)].fVolume = StringToFloat(buffer);
	g_cVolume.Set(GetNativeCell(1), buffer);
	return 1;
}

public int Native_OpenHitsoundMenu(Handle plugin, int numParams)
{
	DisplayCookieMenu(GetNativeCell(1));
	return 1;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Client connect & disconnect
//----------------------------------------------------------------------------------------------------
public void OnClientPutInServer(int client)
{
	if (!AreClientCookiesCached(client))
	{
		g_HM_pData[client].damage = 1;
		g_HM_pData[client].enable = 2;
		g_HM_pData[client].health = 1;
		g_HM_pData[client].type = view_as<int>(DISPLAY_CENTER);
		g_HM_pData[client].style = g_iHitmarkerStyle;
		g_HM_pData[client].headColor[0] = 255;
		g_HM_pData[client].headColor[1] = 45;
		g_HM_pData[client].headColor[2] = 45;
		g_HM_pData[client].bodyColor[0] = 255;
		g_HM_pData[client].bodyColor[1] = 165;
		g_HM_pData[client].bodyColor[2] = 0;
	}
}

public void OnClientDisconnect(int client)
{
	g_HM_pData[client].Reset();
	g_HS_pData[client].Reset();
	g_iLastTick[client] = -1;
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
	g_HM_pData[client].enable = StringToInt(buffer);

	g_cShowDamage.Get(client, buffer, sizeof(buffer));
	g_HM_pData[client].damage = StringToInt(buffer);

	g_cDisplayType.Get(client, buffer, sizeof(buffer));
	g_HM_pData[client].type = StringToInt(buffer);

	g_cShowHealth.Get(client, buffer, sizeof(buffer));
	g_HM_pData[client].health = strcmp(buffer, "1", false) == 0;

	g_cHitmarkerStyle.Get(client, buffer, sizeof(buffer));
	g_HM_pData[client].style = StringToInt(buffer);

	char buffer2[3][8];
	int val;

	g_cHeadshotColor.Get(client, buffer, sizeof(buffer));
	ExplodeString(buffer, " ", buffer2, sizeof(buffer2), sizeof(buffer2[]), true);

	val = StringToInt(buffer2[0]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_HM_pData[client].headColor[0] = val;

	val = StringToInt(buffer2[1]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_HM_pData[client].headColor[1] = val;

	val = StringToInt(buffer2[2]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_HM_pData[client].headColor[2] = val;

	g_cBodyshotColor.Get(client, buffer, sizeof(buffer));
	ExplodeString(buffer, " ", buffer2, sizeof(buffer2), sizeof(buffer2[]), true);

	val = StringToInt(buffer2[0]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_HM_pData[client].bodyColor[0] = val;

	val = StringToInt(buffer2[1]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_HM_pData[client].bodyColor[1] = val;

	val = StringToInt(buffer2[2]);
	if (val > 255) val = 255;
	else if (val < 0) val = 0;
	g_HM_pData[client].bodyColor[2] = val;

	g_cEnable.Get(client, buffer, sizeof(buffer));

	if (buffer[0] == '\0')
	{
		g_cEnable.Set(client, "1");
		g_cBoss.Set(client, "1");
		g_cDetailed.Set(client, "1");
		g_cVolume.Set(client, "0.80");
	}

	g_HS_pData[client].enable = strcmp(buffer, "1", false) == 0;

	g_cBoss.Get(client, buffer, sizeof(buffer));
	g_HS_pData[client].boss = strcmp(buffer, "1", false) == 0;

	g_cDetailed.Get(client, buffer, sizeof(buffer));
	g_HS_pData[client].detailed = strcmp(buffer, "1", false) == 0;

	g_cVolume.Get(client, buffer, sizeof(buffer));
	g_HS_pData[client].fVolume = StringToFloat(buffer);
	g_HS_pData[client].volume = RoundToNearest(g_HS_pData[client].fVolume * 100);
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

	g_HM_pData[client].headColor[0] = r;
	g_HM_pData[client].headColor[1] = g;
	g_HM_pData[client].headColor[2] = b;

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

	g_HM_pData[client].bodyColor[0] = r;
	g_HM_pData[client].bodyColor[1] = g;
	g_HM_pData[client].bodyColor[2] = b;

	Format(buffer, sizeof(buffer), "%d %d %d", r, g, b);
	g_cBodyshotColor.Set(client, buffer);

	CReplyToCommand(client, "{green}[HitMarker]{default} You have set your headshot hitmarker color to {red}%d {green}%d {blue}%d", r, g, b);
	return Plugin_Handled;
}

public Action Command_Hitsound(int client, int args)
{
	char buffer[8];
	int len = GetCmdArg(1, buffer, sizeof(buffer));

	if (strcmp(buffer, "off", false) == 0)
	{
		if (g_HS_pData[client].enable)
		{
			g_HS_pData[client].enable = false;
			g_cEnable.Set(client, "0");
			CPrintToChat(client, "{green}[HitSound]{default} Hitsounds have been {red}disabled!");
		}
		else
			CPrintToChat(client, "{green}[HitSound]{default} Hitsounds are already {red}disabled!");
	}
	else if (strcmp(buffer, "on", false) == 0)
	{
		if (g_HS_pData[client].enable)
			CPrintToChat(client, "{green}[HitSound]{default} Hitsounds are already {green}enabled!");
		else
		{
			g_HS_pData[client].enable = true;
			g_cEnable.Set(client, "1");
			CPrintToChat(client, "{green}[HitSound]{default} Hitsounds have been {green}enabled!");
		}
	}
	else
	{
		int input;
		if (len != 0 && StringToIntEx(buffer, input) == len)
		{
			float fVolume = input / 100.0;
			char recalc[8];
			Format(recalc, sizeof(recalc), "%.2f", fVolume);

			g_HS_pData[client].volume = input;
			g_HS_pData[client].fVolume = fVolume;
			CPrintToChat(client, "{green}[HitSound]{default} Hitsound volume has been changed to {green}%d", input);
			g_cVolume.Set(client, recalc);
		}
		else
			DisplayCookieMenu(client);
	}
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Toggle setting functions
//----------------------------------------------------------------------------------------------------
void InternalToggleHitmarker(int client)
{
	g_HM_pData[client].enable++;
	if (g_HM_pData[client].enable > 2)
		g_HM_pData[client].enable = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_HM_pData[client].enable);
	g_cShowHitmarker.Set(client, buffer);
	switch (g_HM_pData[client].enable)
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
	g_HM_pData[client].damage++;
	if (g_HM_pData[client].damage > 2)
		g_HM_pData[client].damage = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_HM_pData[client].damage);
	g_cShowDamage.Set(client, buffer);
	switch (g_HM_pData[client].damage)
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
	g_HM_pData[client].type++;
	if (g_HM_pData[client].type > 2)
		g_HM_pData[client].type = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_HM_pData[client].type);
	g_cDisplayType.Set(client, buffer);
	switch (g_HM_pData[client].type)
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
	g_HM_pData[client].health++;
	if (g_HM_pData[client].health > 2)
		g_HM_pData[client].health = 0;
	
	char buffer[32];
	Format(buffer, sizeof(buffer), "%d", g_HM_pData[client].health);
	g_cShowHealth.Set(client, buffer);
	switch (g_HM_pData[client].health)
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

	if (!IsPlayerAlive(attacker))
		return;

	// Only perform 1 hitmarker/hitsound per tick
	int tick = GetGameTickCount();
	if (tick == g_iLastTick[attacker])
		return;

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!IsClientInGame(victim) || attacker == victim)
		return;

	int hitgroup = GetEventInt(event, "hitgroup");
	int hp = GetEventInt(event, "health");

	// Play hitsound
	if (g_HS_pData[attacker].detailed)
	{
		if (hp == 0)
			EmitSoundToClient(attacker, g_sHitsoundKillPath, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_HS_pData[attacker].fVolume);
		else if (hitgroup == 1)
			EmitSoundToClient(attacker, g_sHitsoundHeadPath, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_HS_pData[attacker].fVolume);
		else
			EmitSoundToClient(attacker, g_sHitsoundBodyPath, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_HS_pData[attacker].fVolume);
	}
	else
		EmitSoundToClient(attacker, g_sHitsoundPath, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_HS_pData[attacker].fVolume);

	g_iLastTick[attacker] = tick;

	// Only display hitmarkers if enabled
	if (!g_bEnable)
		return;

	if (g_HM_pData[attacker].style > g_iHitmarkerStyle)
		g_HM_pData[attacker].style = 0;

	int damage = GetEventInt(event, "dmg_health");
	int previousHealth = hp + damage;

	// Build our hitmarker
	char sRank[32], buffer[128], sHP[128] = "Dead";

#if defined _TopDefenders_included
	if (g_bShowDamage && g_bTopDefsNative && g_HM_pData[attacker].damage == 2)
		Format(sRank, sizeof(sRank), "(#%d)", TopDefenders_GetClientRank(attacker));
#endif

	if (g_bShowDamage && g_HM_pData[attacker].health != 0 && previousHealth > 0)
	{
		if (g_HM_pData[attacker].health == 2)
			Format(sHP, sizeof(sHP), "%N: %d HP", victim, previousHealth);
		else
			Format(sHP, sizeof(sHP), "%d HP", previousHealth);
	}

	// Format our hitmarker
	if (g_HM_pData[attacker].type != view_as<int>(DISPLAY_GAME)) // DISPLAY_CENTER or DISPLAY_HINT
	{
		if (g_bShowDamage && g_HM_pData[attacker].damage != 0)
		{
			Format(buffer, sizeof(buffer), "-%d %s", damage, g_HM_pData[attacker].damage == 2 ? sRank : "");
			if (g_HM_pData[attacker].health)
				Format(buffer, sizeof(buffer), "%s \n%s", buffer, sHP);

			SendHudMsg(attacker, buffer, view_as<DisplayType>(g_HM_pData[attacker].type));
		}
		else if (g_bShowDamage && g_HM_pData[attacker].health)
		{
			Format(buffer, sizeof(buffer), "%s %s", buffer, sHP);
			SendHudMsg(attacker, buffer, view_as<DisplayType>(g_HM_pData[attacker].type));
		}
		if (g_HM_pData[attacker].enable)
		{
			Format(buffer, sizeof(buffer), "%s", g_sHitStyles[g_HM_pData[attacker].style]);
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
	}
	else if (g_HM_pData[attacker].type == view_as<int>(DISPLAY_GAME))
	{
		// The Hitmarker is not enabled but we still need to Format for damage or/and health
		if (!g_HM_pData[attacker].enable)
			Format(buffer, sizeof(buffer), "\n\n\n\n\n\n\n\n");
	
		// For this display we need to always set the new line at the end of the string
		// This is because we re-use the buffer for each line
		if (g_bShowDamage && g_HM_pData[attacker].damage != 0)
		{
			Format(buffer, sizeof(buffer), "%s-%d %s\n", buffer, damage, g_HM_pData[attacker].damage == 2 ? sRank : "");
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
		else
			Format(buffer, sizeof(buffer), "%s\n", buffer);

		if (g_bShowDamage && g_HM_pData[attacker].health)
		{
			Format(buffer, sizeof(buffer), "%s%s\n", buffer, sHP);
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
		else
			Format(buffer, sizeof(buffer), "%s\n", buffer);

		if (g_HM_pData[attacker].enable)
		{
			Format(buffer, sizeof(buffer), "\n\n\n\n%s\n\n%s", g_sHitStyles[g_HM_pData[attacker].style], buffer);
			SendHudMsg(attacker, buffer, DISPLAY_GAME, hitgroup);
		}
	}
}

public void Hook_EntityOnDamage(const char[] output, int caller, int activator, float delay)
{
	if (!(1 <= activator <= MaxClients) || !IsClientInGame(activator))
		return;

	if (!IsPlayerAlive(activator))
		return;

	// Only perform 1 hitmarker/hitsound per tick
	int tick = GetGameTickCount();
	if (tick == g_iLastTick[activator])
		return;

	if (g_HS_pData[activator].fVolume != 0.0)
		EmitSoundToClient(activator, g_sHitsoundPath, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_HS_pData[activator].fVolume);

	g_iLastTick[activator] = tick;

	// Only display hitmarkers if enabled
	if (!g_bEnable)
		return;

	if (g_HM_pData[activator].enable == 2)
	{
		if (g_HM_pData[activator].style > g_iHitmarkerStyle)
			g_HM_pData[activator].style = 0;

		char buffer[128];
		Format(buffer, sizeof(buffer), "\n\n\n\n%s\n\n\n\n", g_sHitStyles[g_HM_pData[activator].style]);
		SendHudMsg(activator, buffer, DISPLAY_GAME);
	}

	if (!g_HS_pData[activator].enable || !g_HS_pData[activator].boss)
		return;

	int iTeam = GetClientTeam(activator);
	if (iTeam == CS_TEAM_NONE || iTeam == CS_TEAM_SPECTATOR)
		return;

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
				SetHudTextParams(-1.0, -1.0, 0.1, g_HM_pData[client].headColor[0], g_HM_pData[client].headColor[1], g_HM_pData[client].headColor[2], 255, 0, 0.0, 0.0, 0.1);
			else
				SetHudTextParams(-1.0, -1.0, 0.1, g_HM_pData[client].bodyColor[0], g_HM_pData[client].bodyColor[1], g_HM_pData[client].bodyColor[2], 255, 0, 0.0, 0.0, 0.1);
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

	if (g_HM_pData[client].enable == 0)
	{
		menu.SetTitle("Hitmarker Settings\n ");
		
		switch(g_HM_pData[client].enable)
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
		menu.SetTitle("Hitmarkers\n \nCurrent Style (%d/%d):\n%s", g_HM_pData[client].style + 1, sizeof(g_sHitStyles), g_sHitStyles[g_HM_pData[client].style]);
		switch(g_HM_pData[client].enable)
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

		Format(buffer, sizeof(buffer), "Headshot Color: %d %d %d", g_HM_pData[client].headColor[0], g_HM_pData[client].headColor[1], g_HM_pData[client].headColor[2]);
		menu.AddItem("headcolor", buffer);

		Format(buffer, sizeof(buffer), "Bodyshot Color: %d %d %d\n ", g_HM_pData[client].bodyColor[0], g_HM_pData[client].bodyColor[1], g_HM_pData[client].bodyColor[2]);
		menu.AddItem("bodycolor", buffer);
	}

	switch(g_HM_pData[client].type)
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

	switch(g_HM_pData[client].damage)
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

	switch(g_HM_pData[client].health)
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
				g_HM_pData[client].style++;
				if (g_HM_pData[client].style > g_iHitmarkerStyle)
					g_HM_pData[client].style = 0;

				Format(info, sizeof(info), "%d", g_HM_pData[client].style);
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
			else if (strcmp(info, "hitsounds", false) == 0)
			{
				OpenHitsoundMenu(client);
			}
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

	Format(buffer, 256, "%sCurrent color: %d %d %d\n", buffer, g_HM_pData[client].headColor[0], g_HM_pData[client].headColor[1], g_HM_pData[client].headColor[2]);
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
				g_HM_pData[client].headColor[0] = 255;
				g_HM_pData[client].headColor[1] = 45;
				g_HM_pData[client].headColor[2] = 45;
			}
			else if (strcmp(buffer, "or", false) == 0)
			{
				g_HM_pData[client].headColor[0] = 255;
				g_HM_pData[client].headColor[1] = 165;
				g_HM_pData[client].headColor[2] = 0;
			}
			else if (strcmp(buffer, "gr", false) == 0)
			{
				g_HM_pData[client].headColor[0] = 45;
				g_HM_pData[client].headColor[1] = 255;
				g_HM_pData[client].headColor[2] = 45;
			}
			else if (strcmp(buffer, "bl", false) == 0)
			{
				g_HM_pData[client].headColor[0] = 45;
				g_HM_pData[client].headColor[1] = 220;
				g_HM_pData[client].headColor[2] = 255;
			}
			else if (strcmp(buffer, "yl", false) == 0)
			{
				g_HM_pData[client].headColor[0] = 255;
				g_HM_pData[client].headColor[1] = 234;
				g_HM_pData[client].headColor[2] = 0;
			}
			else if (strcmp(buffer, "wh", false) == 0)
			{
				g_HM_pData[client].headColor[0] = 200;
				g_HM_pData[client].headColor[1] = 200;
				g_HM_pData[client].headColor[2] = 200;
			}

			Format(buffer, sizeof(buffer), "%d %d %d", g_HM_pData[client].headColor[0], g_HM_pData[client].headColor[1], g_HM_pData[client].headColor[2]);
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

	Format(buffer, 256, "%sCurrent color: %d %d %d\n", buffer, g_HM_pData[client].bodyColor[0], g_HM_pData[client].bodyColor[1], g_HM_pData[client].bodyColor[2]);
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
				g_HM_pData[client].bodyColor[0] = 255;
				g_HM_pData[client].bodyColor[1] = 45;
				g_HM_pData[client].bodyColor[2] = 45;
			}
			else if (strcmp(buffer, "or", false) == 0)
			{
				g_HM_pData[client].bodyColor[0] = 255;
				g_HM_pData[client].bodyColor[1] = 165;
				g_HM_pData[client].bodyColor[2] = 0;
			}
			else if (strcmp(buffer, "gr", false) == 0)
			{
				g_HM_pData[client].bodyColor[0] = 45;
				g_HM_pData[client].bodyColor[1] = 255;
				g_HM_pData[client].bodyColor[2] = 45;
			}
			else if (strcmp(buffer, "bl", false) == 0)
			{
				g_HM_pData[client].bodyColor[0] = 45;
				g_HM_pData[client].bodyColor[1] = 220;
				g_HM_pData[client].bodyColor[2] = 255;
			}
			else if (strcmp(buffer, "yl", false) == 0)
			{
				g_HM_pData[client].bodyColor[0] = 255;
				g_HM_pData[client].bodyColor[1] = 234;
				g_HM_pData[client].bodyColor[2] = 0;
			}
			else if (strcmp(buffer, "wh", false) == 0)
			{
				g_HM_pData[client].bodyColor[0] = 200;
				g_HM_pData[client].bodyColor[1] = 200;
				g_HM_pData[client].bodyColor[2] = 200;
			}

			Format(buffer, sizeof(buffer), "%d %d %d", g_HM_pData[client].bodyColor[0], g_HM_pData[client].bodyColor[1], g_HM_pData[client].bodyColor[2]);
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

public void CookieMenu_HitMarker(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch (action)
	{
		case CookieMenuAction_SelectOption:
			DisplayCookieMenu(client);
	}
}

public void DisplayCookieMenu(int client)
{
	Menu menu = new Menu(MenuHandler_HitMarker, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	SetMenuTitle(menu, "Hitsounds:\n \n");

	char buffer[128];
	Format(buffer, sizeof(buffer), "Hitsounds: %s\n ", g_HS_pData[client].enable ? "On" : "Off");
	AddMenuItem(menu, "zombie", buffer);

	Format(buffer, sizeof(buffer), "Boss hitsounds: %s\n ", g_HS_pData[client].boss ? "On" : "Off");
	AddMenuItem(menu, "boss", buffer);

	Format(buffer, sizeof(buffer), "Detailed hitsounds: %s\n \nUse \"!hitsound [0-100]\" to set volume", g_HS_pData[client].detailed ? "On" : "Off");
	AddMenuItem(menu, "detailed", buffer);

	Format(buffer, sizeof(buffer), "Volume: %d", g_HS_pData[client].volume);
	AddMenuItem(menu, "vol", buffer);
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_HitMarker(Menu menu, MenuAction action, int client, int selection)
{
	switch (action)
	{
		case MenuAction_End:
		{
			if (client != MenuEnd_Selected)
				delete menu;
		}
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack)
				ShowCookieMenu(client);
		}
		case MenuAction_Select:
		{
			switch (selection)
			{
				case 0:
					ToggleZombieHitsound(client);
				case 1:
					ToggleBossHitsound(client);
				case 2:
					ToggleDetailedHitsound(client);
				case 3:
				{
					g_HS_pData[client].fVolume = g_HS_pData[client].fVolume - 0.1;
					if (g_HS_pData[client].fVolume <= 0.0) g_HS_pData[client].fVolume = 1.0;

					g_HS_pData[client].volume = g_HS_pData[client].volume - 10;
					if (g_HS_pData[client].volume <= 0) g_HS_pData[client].volume = 100;

					char buffer[8];
					Format(buffer, sizeof(buffer), "%.2f", g_HS_pData[client].fVolume);
					g_cVolume.Set(client, buffer);

					CPrintToChat(client, "{green}[HitSound]{default} Hitsound volume has been changed to {green}%d", g_HS_pData[client].volume);
				}
			}
			DisplayCookieMenu(client);
		}
	}
	return 0;
}

public void ToggleZombieHitsound(int client)
{
	g_HS_pData[client].enable = !g_HS_pData[client].enable;
	CPrintToChat(client, "{green}[HitSound]{default} Zombie hitsounds are now %s", g_HS_pData[client].enable ? "{green}enabled" : "{red}disabled");
	g_HS_pData[client].enable ? g_cEnable.Set(client, "1") : g_cEnable.Set(client, "0");
}

public void ToggleBossHitsound(int client)
{
	g_HS_pData[client].boss = !g_HS_pData[client].boss;
	CPrintToChat(client, "{green}[HitSound]{default} Boss hitsounds are now %s", g_HS_pData[client].boss ? "{green}enabled" : "{red}disabled");
	g_HS_pData[client].boss ? g_cBoss.Set(client, "1") : g_cBoss.Set(client, "0");
}

public void ToggleDetailedHitsound(int client)
{
	g_HS_pData[client].detailed = !g_HS_pData[client].detailed;
	CPrintToChat(client, "{green}[HitSound]{default} Detailed hitsounds are now %s", g_HS_pData[client].detailed ? "{green}enabled" : "{red}disabled");
	g_HS_pData[client].detailed ? g_cDetailed.Set(client, "1") : g_cDetailed.Set(client, "0");
}

stock void PrecacheSounds()
{
	char sBuffer[PLATFORM_MAX_PATH];

	// Boss Hitmarker Sound
	GetConVarString(g_cvHitsound, g_sHitsoundPath, sizeof(g_sHitsoundPath));
	PrecacheSound(g_sHitsoundPath, true);
	Format(sBuffer, sizeof(sBuffer), "sound/%s", g_sHitsoundPath);
	AddFileToDownloadsTable(sBuffer);

	// Body Shot Sound
	GetConVarString(g_cvHitsoundBody, g_sHitsoundHeadPath, sizeof(g_sHitsoundHeadPath));
	PrecacheSound(g_sHitsoundHeadPath, true);
	Format(sBuffer, sizeof(sBuffer), "sound/%s", g_sHitsoundHeadPath);
	AddFileToDownloadsTable(sBuffer);

	// Head Shot Sound
	GetConVarString(g_cvHitsoundHead, g_sHitsoundBodyPath, sizeof(g_sHitsoundBodyPath));
	PrecacheSound(g_sHitsoundBodyPath, true);
	Format(sBuffer, sizeof(sBuffer), "sound/%s", g_sHitsoundBodyPath);
	AddFileToDownloadsTable(sBuffer);

	// Kill Shot Sound
	GetConVarString(g_cvHitsoundKill, g_sHitsoundKillPath, sizeof(g_sHitsoundKillPath));
	PrecacheSound(g_sHitsoundKillPath, true);
	Format(sBuffer, sizeof(sBuffer), "sound/%s", g_sHitsoundKillPath);
	AddFileToDownloadsTable(sBuffer);
}