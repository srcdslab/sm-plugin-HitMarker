#if defined _hitmarkers_included
	#endinput
#endif
#define _hitmarkers_included

#define HitMarker_V_MAJOR   2
#define HitMarker_V_MINOR   0
#define HitMarker_V_PATCH   0

#define HitMarker_VERSION   "2.0.0"

enum HitmarkerType
{
	Hitmarker_Damage,
	Hitmarker_Rank,
	Hitmarker_Enable,
};

enum MenuType
{
	Menu_Hitmarker,
	Menu_HeadColor,
	Menu_BodyColor,
};

/**
 * Called when the plugin becomes available.
 * 
 * @noreturn
 */
forward void HitMarker_OnPluginOK();

/**
 * Called when the plugin becomes unavailable.
 * This can happen when the plugin is reloaded or unloaded.
 * 
 * @noreturn
 */
forward void HitMarker_OnPluginNotOK();

/**
 * Gets the current status of a hitmarker setting for a client.
 *
 * @param client    Client index
 * @param type      Type of setting to query
 * @return          Current value of the setting
 * @error          Invalid client index or client not in game
 */
native bool GetHitmarkerStatus(int client, HitmarkerType type);

/**
 * Toggles a hitmarker setting for a client.
 *
 * @param client    Client index
 * @param type      Type of setting to toggle
 * @noreturn
 * @error          Invalid client index or client not in game
 */
native void ToggleHitmarker(int client, HitmarkerType type);

/**
 * Opens a hitmarker settings menu for a client.
 *
 * @param client    Client index
 * @param type      Type of menu to open
 * @noreturn
 * @error          Invalid client index or client not in game
 */
native void OpenHitmarkerMenu(int client, MenuType type);

public SharedPlugin __pl_hitmarkers =
{
	name = "hitmarkers",
	file = "hitmarkers.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_hitmarkers_SetNTVOptional()
{
	MarkNativeAsOptional("GetHitmarkerStatus");
	MarkNativeAsOptional("ToggleHitmarker");
	MarkNativeAsOptional("OpenHitmarkerMenu");
}
#endif