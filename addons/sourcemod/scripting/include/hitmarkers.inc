#if defined _hitmarkers_included
	#endinput
#endif
#define _hitmarkers_included

#define HitMarker_V_MAJOR   "2"
#define HitMarker_V_MINOR   "0"
#define HitMarker_V_PATCH   "0"

#define HitMarker_VERSION   HitMarker_V_MAJOR..."."...HitMarker_V_MINOR..."."...HitMarker_V_PATCH

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

enum SoundType
{
	Sound_Boss,
	Sound_Zombie,
	Sound_Detailed,
}

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
 * Gets the current status of a hit sound type for a client.
 *
 * @param client    Client index
 * @param type      Type of sound to query
 * @return          True if enabled, false otherwise
 * @error          Invalid client index or client not in game
 */
native bool GetHitsoundStatus(int client, SoundType type);

/**
 * Gets the current volume setting for a client's hit sounds.
 *
 * @param client    Client index
 * @return          Volume value between 0.0 and 1.0
 * @error          Invalid client index or client not in game
 */
native float GetHitsoundVolume(int client);

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
 * Toggles a hit sound type for a client.
 *
 * @param client    Client index
 * @param type      Type of sound to toggle
 * @noreturn
 * @error          Invalid client index or client not in game
 */
native void ToggleHitsound(int client, SoundType type);

/**
 * Sets the volume for a client's hit sounds.
 *
 * @param client    Client index
 * @param volume    New volume value between 0.0 and 1.0
 * @noreturn
 * @error          Invalid client index or client not in game
 */
native void SetHitsoundVolume(int client, float volume);

/**
 * Opens a hitmarker settings menu for a client.
 *
 * @param client    Client index
 * @param type      Type of menu to open
 * @noreturn
 * @error          Invalid client index or client not in game
 */
native void OpenHitmarkerMenu(int client, MenuType type);

/**
 * Opens the hit sounds settings menu for a client.
 *
 * @param client    Client index
 * @noreturn
 * @error          Invalid client index or client not in game
 */
native void OpenHitsoundMenu(int client);

public SharedPlugin __pl_hitmarkers =
{
	name = "hitmarkers",
	file = "HitMarkers.smx",
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
	MarkNativeAsOptional("GetHitsoundStatus");
	MarkNativeAsOptional("GetHitsoundVolume");
	MarkNativeAsOptional("ToggleHitmarker");
	MarkNativeAsOptional("ToggleHitsound");
	MarkNativeAsOptional("SetHitsoundVolume");
	MarkNativeAsOptional("OpenHitmarkerMenu");
	MarkNativeAsOptional("OpenHitsoundMenu");
}
#endif