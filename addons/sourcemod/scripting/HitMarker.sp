#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <multicolors>
#include <clientprefs>

#include "utilshelper.inc"

#undef REQUIRE_PLUGIN
#include <Spectate>

#pragma newdecls required
#pragma semicolon 1

#define	HIT_OVERLAY_INTERVAL			0.15
#define	HIT_SOUND_INTERVAL				1.0

#define SND_PATH_HIT_PRECACHE			"hitmarker/hitmarker.mp3"
#define MATERIAL_PATH_HIT 				"overlays/hitmarker/hitmarker"
#define	MATERIAL_PATH_HIT_VTF_PRECACHE	"overlays/hitmarker/hitmarker.vtf"
#define	MATERIAL_PATH_HIT_VMT_PRECACHE	"overlays/hitmarker/hitmarker.vmt"

Handle g_hShowZombie = INVALID_HANDLE, g_hShowBoss = INVALID_HANDLE, g_hHearSound = INVALID_HANDLE;

ConVar g_cHitIntervalDisplay, g_cHitVolumeSound, g_cHitSpectator;
float g_fHitIntervalDisplay, g_fHitVolumeSound;
bool g_bHitSpectator;

bool g_bShowZombie[MAXPLAYERS + 1], g_bShowBoss[MAXPLAYERS + 1], g_bHearSound[MAXPLAYERS + 1], g_bShowing[MAXPLAYERS + 1] = { false, ... };

bool g_bLate = false;

bool g_bLibrarySpectate = false;

public Plugin myinfo = 
{
	name = "HitMarker",
	author = "Nano, maxime1907",
	description = "Displays a hitmarker when you deal damage",
	version = "1.0",
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if (LibraryExists("Spectate"))
		g_bLibrarySpectate = true;
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "Spectate", false))
		g_bLibrarySpectate = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "Spectate", false))
		g_bLibrarySpectate = false;
}

public void OnPluginStart()
{
	g_cHitIntervalDisplay = CreateConVar("sm_hitmarker_interval_display", "0.1", "How much time between every hit", 0, true, 0.0, true, 1.0);
	g_cHitVolumeSound = CreateConVar("sm_hitmarker_volume_sound", "1.0", "Volume of the hit effect", 0, true, 0.0, true, 1.0);
	g_cHitSpectator = CreateConVar("sm_hitmarkers_spectate", "1", "Enable hitmarker for spectators", 0, true, 0.0, true, 1.0);

	g_cHitIntervalDisplay.AddChangeHook(OnConVarChanged);
	g_cHitVolumeSound.AddChangeHook(OnConVarChanged);
	g_cHitSpectator.AddChangeHook(OnConVarChanged);

	g_hShowZombie = RegClientCookie("hitmaker_zombie", "Enable/Disable hitmarker against zombies", CookieAccess_Private);
	g_hShowBoss = RegClientCookie("hitmarker_boss", "Enable/Disable hitmarker against bosses", CookieAccess_Private);
	g_hHearSound = RegClientCookie("hitmarker_sound", "Enable/Disable hitmarker sound effect", CookieAccess_Private);

	SetCookieMenuItem(CookieMenu_HitMarker, INVALID_HANDLE, "HitMarker Settings");

	HookEntityOutput("func_physbox", "OnHealthChanged", Hook_EntityOnDamage);
	HookEntityOutput("func_physbox_multiplayer", "OnHealthChanged", Hook_EntityOnDamage);
	HookEntityOutput("func_breakable", "OnHealthChanged", Hook_EntityOnDamage);
	HookEntityOutput("math_counter", "OutValue", Hook_EntityOnDamage);

	HookEvent("player_hurt", Hook_EventOnDamage);

	RegConsoleCmd("sm_hitmarker", Command_HitMarker);
	RegConsoleCmd("sm_hm", Command_HitMarker);

	AutoExecConfig(true);
	GetConVars();

	// Late load
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnPluginEnd()
{
	// Late unload
	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(IsClientConnected(i))
			{
				OnClientDisconnect(i);
			}
		}
	}

	Cleanup(true);
}

public void OnMapStart()
{
	PrecacheSound(SND_PATH_HIT_PRECACHE);
	PrecacheModel(MATERIAL_PATH_HIT_VTF_PRECACHE);
	PrecacheModel(MATERIAL_PATH_HIT_VMT_PRECACHE);

	AddFilesToDownloadsTable("hitmarker_downloadlist.ini");
}

public void OnClientPutInServer(int client)
{
	if (AreClientCookiesCached(client))
		ReadClientCookies(client);
}

public void OnClientDisconnect(int client)
{
	SetClientCookies(client);
}

public void OnClientCookiesCached(int client)
{
	ReadClientCookies(client);
}

public void OnConVarChanged(ConVar convar, char[] oldValue, char[] newValue)
{
	GetConVars();
}

//   .d8888b.   .d88888b.  888b     d888 888b     d888        d8888 888b    888 8888888b.   .d8888b.
//  d88P  Y88b d88P" "Y88b 8888b   d8888 8888b   d8888       d88888 8888b   888 888  "Y88b d88P  Y88b
//  888    888 888     888 88888b.d88888 88888b.d88888      d88P888 88888b  888 888    888 Y88b.
//  888        888     888 888Y88888P888 888Y88888P888     d88P 888 888Y88b 888 888    888  "Y888b.
//  888        888     888 888 Y888P 888 888 Y888P 888    d88P  888 888 Y88b888 888    888     "Y88b.
//  888    888 888     888 888  Y8P  888 888  Y8P  888   d88P   888 888  Y88888 888    888       "888
//  Y88b  d88P Y88b. .d88P 888   "   888 888   "   888  d8888888888 888   Y8888 888  .d88P Y88b  d88P
//   "Y8888P"   "Y88888P"  888       888 888       888 d88P     888 888    Y888 8888888P"   "Y8888P"

public Action Command_HitMarker(int client, int args)
{	
	DisplayCookieMenu(client);
	return Plugin_Handled;
}

//  888b     d888 8888888888 888b    888 888     888
//  8888b   d8888 888        8888b   888 888     888
//  88888b.d88888 888        88888b  888 888     888
//  888Y88888P888 8888888    888Y88b 888 888     888
//  888 Y888P 888 888        888 Y88b888 888     888
//  888  Y8P  888 888        888  Y88888 888     888
//  888   "   888 888        888   Y8888 Y88b. .d88P
//  888       888 8888888888 888    Y888  "Y88888P"

public void CookieMenu_HitMarker(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch(action)
	{
		case CookieMenuAction_SelectOption:
		{
			DisplayCookieMenu(client);
		}
	}
}

public void DisplayCookieMenu(int client)
{
	Menu menu = new Menu(MenuHandler_HitMarker, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	menu.ExitBackButton = true;
	menu.ExitButton = true;
	SetMenuTitle(menu, "HitMarker Settings");
	AddMenuItem(menu, NULL_STRING, "Show against zombies");
	AddMenuItem(menu, NULL_STRING, "Show against bosses");
	AddMenuItem(menu, NULL_STRING, "Hear a sound effect");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public int MenuHandler_HitMarker(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			if(param1 != MenuEnd_Selected)
				delete menu;
		}
		case MenuAction_Cancel:
		{
			if(param2 == MenuCancel_ExitBack)
				ShowCookieMenu(param1);
		}
		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0:
				{
					g_bShowZombie[param1] = !g_bShowZombie[param1];
				}
				case 1:
				{
					g_bShowBoss[param1] = !g_bShowBoss[param1];
				}
				case 2:
				{
					g_bHearSound[param1] = !g_bHearSound[param1];
				}
				default: return 0;
			}
			DisplayMenu(menu, param1, MENU_TIME_FOREVER);
		}
		case MenuAction_DisplayItem:
		{
			char sBuffer[32];
			switch(param2)
			{
				case 0:
				{
					Format(sBuffer, sizeof(sBuffer), "Show against zombies: %s", g_bShowZombie[param1] ? "Enabled" : "Disabled");
				}
				case 1:
				{
					Format(sBuffer, sizeof(sBuffer), "Show against bosses: %s", g_bShowBoss[param1] ? "Enabled" : "Disabled");
				}
				case 2:
				{
					Format(sBuffer, sizeof(sBuffer), "Hear a sound effect: %s", g_bHearSound[param1] ? "Enabled" : "Disabled");
				}
			}
			return RedrawMenuItem(sBuffer);
		}
	}
	return 0;
}

// ##     ##  #######   #######  ##    ##  ######  
// ##     ## ##     ## ##     ## ##   ##  ##    ## 
// ##     ## ##     ## ##     ## ##  ##   ##       
// ######### ##     ## ##     ## #####     ######  
// ##     ## ##     ## ##     ## ##  ##         ## 
// ##     ## ##     ## ##     ## ##   ##  ##    ## 
// ##     ##  #######   #######  ##    ##  ######  

public void Hook_EntityOnDamage(const char[] output, int caller, int activator, float delay)
{
	HandleHit(activator, true);
}

public void Hook_EventOnDamage(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	HandleHit(attacker, false);
}

public Action Timer_NoOverlay(Handle timer, int client)
{
	if (!IsValidClient(client) || !IsClientInGame(client))
		return Plugin_Handled;

	g_bShowing[client] = false;
	ShowOverlayToClient(client, "");
	return Plugin_Handled;
}

// ######## ##     ## ##    ##  ######  ######## ####  #######  ##    ##  ######  
// ##       ##     ## ###   ## ##    ##    ##     ##  ##     ## ###   ## ##    ## 
// ##       ##     ## ####  ## ##          ##     ##  ##     ## ####  ## ##       
// ######   ##     ## ## ## ## ##          ##     ##  ##     ## ## ## ##  ######  
// ##       ##     ## ##  #### ##          ##     ##  ##     ## ##  ####       ## 
// ##       ##     ## ##   ### ##    ##    ##     ##  ##     ## ##   ### ##    ## 
// ##        #######  ##    ##  ######     ##    ####  #######  ##    ##  ######

stock void HandleHit(int client, bool bBoss)
{
	HandleHitClient(client, bBoss);

	if (g_bHitSpectator && g_bLibrarySpectate)
		HandleHitSpectators(client, bBoss);
}

stock void HandleHitClient(int client, bool bBoss)
{
	if (!IsValidClient(client))
		return;

	if (((bBoss && g_bShowBoss[client]) || (!bBoss && g_bShowZombie[client])) && !g_bShowing[client])
	{
		g_bShowing[client] = true;
		ShowOverlayToClient(client, MATERIAL_PATH_HIT);

		CreateTimer(g_fHitIntervalDisplay, Timer_NoOverlay, client);
	}

	if (g_bHearSound[client])
	{
		EmitSoundToClient(client, SND_PATH_HIT_PRECACHE, SOUND_FROM_PLAYER, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, g_fHitVolumeSound);
	}
}

stock void HandleHitSpectators(int client, bool bBoss)
{
	int iSpectators[MAXPLAYERS+1];
	int iSize;

	Spectate_GetClientSpectators(client, iSpectators, iSize);

	for (int i = 0; i < iSize; i++)
		HandleHitClient(iSpectators[i], bBoss);
}

stock void ShowOverlayToClient(int client, const char[] overlaypath)
{
	ClientCommand(client, "r_screenoverlay \"%s\"", overlaypath);
}

void Cleanup(bool bPluginEnd = false)
{
	if (bPluginEnd)
	{
		if (g_hShowZombie != INVALID_HANDLE)
			CloseHandle(g_hShowZombie);
		if (g_hShowBoss != INVALID_HANDLE)
			CloseHandle(g_hShowBoss);
		if (g_hHearSound != INVALID_HANDLE)
			CloseHandle(g_hHearSound);

		delete g_cHitIntervalDisplay;
		delete g_cHitVolumeSound;
		delete g_cHitSpectator;
	}
}

public void GetConVars()
{
	g_fHitIntervalDisplay = g_cHitIntervalDisplay.FloatValue;
	g_fHitVolumeSound = g_cHitVolumeSound.FloatValue;
	g_bHitSpectator = g_cHitSpectator.BoolValue;
}

public void ReadClientCookies(int client)
{
	char sValue[8];

	GetClientCookie(client, g_hShowZombie, sValue, sizeof(sValue));
	g_bShowZombie[client] = (sValue[0] == '\0' ? true : StringToInt(sValue) == 1);

	GetClientCookie(client, g_hShowBoss, sValue, sizeof(sValue));
	g_bShowBoss[client] = (sValue[0] == '\0' ? true : StringToInt(sValue) == 1);

	GetClientCookie(client, g_hHearSound, sValue, sizeof(sValue));
	g_bHearSound[client] = (sValue[0] == '\0' ? true : StringToInt(sValue) == 1);
}

public void SetClientCookies(int client)
{
	char sValue[8];

	Format(sValue, sizeof(sValue), "%i", g_bShowZombie[client]);
	SetClientCookie(client, g_hShowZombie, sValue);

	Format(sValue, sizeof(sValue), "%i", g_bShowBoss[client]);
	SetClientCookie(client, g_hShowBoss, sValue);

	Format(sValue, sizeof(sValue), "%i", g_bHearSound[client]);
	SetClientCookie(client, g_hHearSound, sValue);
}

bool IsValidClient(int client, bool nobots = true)
{
	if (client <= 0 || client > MaxClients || !IsClientConnected(client) || (nobots && IsFakeClient(client)))
	{
		return false;
	}
	return IsClientInGame(client);
}