# Copilot Instructions for HitMarker SourceMod Plugin

## Repository Overview

This repository contains a **SourcePawn plugin** for **SourceMod**, providing hitmarkers and hitsounds functionality for Source engine games (primarily CS:GO/CS2). The plugin displays visual and audio feedback when players hit targets, with extensive customization options.

### Key Features
- Visual hitmarkers with customizable styles and colors
- Multiple hitsound types (normal, headshot, bodyshot, killshot)
- Client preference system with persistent cookies
- Multi-language support
- Boss/entity hit detection
- Integration with other plugins (TopDefenders, DynamicChannels)

## Technical Environment

- **Language**: SourcePawn (C-like syntax specific to SourceMod)
- **Platform**: SourceMod 1.11+ framework for Source engine games
- **Build System**: SourceKnight for dependency management and compilation
- **Compiler**: SourcePawn compiler (spcomp)

## Project Structure

```
/
├── addons/sourcemod/
│   ├── scripting/
│   │   ├── HitMarker.sp              # Main plugin source
│   │   └── include/
│   │       └── hitmarkers.inc        # Native API definitions
│   └── translations/
│       └── HitMarker.phrases.txt     # Multi-language strings
├── common/sound/hitmarker/           # Sound assets
├── sourceknight.yaml                # Build configuration
└── .github/workflows/ci.yml         # CI/CD pipeline
```

## Architecture Patterns

### Plugin Structure
```sourcepawn
public Plugin myinfo = { ... };      // Plugin metadata
public void OnPluginStart() { ... }  // Initialization
public void OnPluginEnd() { ... }    // Cleanup (rarely needed)
public APLRes AskPluginLoad2() { ... } // Native registration
```

### Memory Management
- **Always use `delete`** for Handle cleanup (no null checks needed)
- **Avoid `Clear()`** on StringMap/ArrayList (causes memory leaks)
- Use `CleanupAndInit()` pattern for Handle recreation
- Proper cleanup in `OnMapEnd()` and round end events

### Client Data Management
```sourcepawn
enum struct PlayerData {
    // Struct members for player settings
    void Reset() { /* Reset to defaults */ }
}
PlayerData g_PlayerData[MAXPLAYERS + 1];
```

### Cookie System (Client Preferences)
- Combined cookie storage: `"value1|value2|value3"`
- Load/Save functions for each cookie type
- Default values when cookies are empty
- Validation and clamping of loaded values

## Code Style & Standards

### Naming Conventions
- **Global variables**: `g_` prefix (e.g., `g_cvEnable`)
- **Functions**: PascalCase (e.g., `LoadHitmarkerSettings`)
- **Local variables**: camelCase (e.g., `clientIndex`)
- **Constants**: UPPER_CASE (e.g., `DEFAULT_VOLUME`)

### SourcePawn Specifics
```sourcepawn
#pragma semicolon 1
#pragma newdecls required

// Use methodmaps for cleaner code
enum struct MyData {
    int value;
    void Reset() { this.value = 0; }
}

// Proper event handling
HookEvent("player_hurt", Event_PlayerHurt);

// String operations
char buffer[256];
Format(buffer, sizeof(buffer), "Text %d", value);
```

### Error Handling
- Check client validity: `1 <= client <= MaxClients`
- Validate `IsClientInGame(client)` before operations
- Use `GetGameTickCount()` to prevent duplicate operations per tick

## Dependencies & Integration

### SourceKnight Dependencies
- **sourcemod**: Core SourceMod framework
- **multicolors**: Colored chat messages
- **spectate**: Spectator functionality
- **TopDefenders**: Player ranking (optional)
- **dynamicchannels**: Dynamic HUD channels (optional)

### Optional Plugin Integration
```sourcepawn
#undef REQUIRE_PLUGIN
#tryinclude <OptionalPlugin>
#define REQUIRE_PLUGIN

// Runtime availability checks
bool g_bPlugin_Available = false;
g_bPlugin_Available = LibraryExists("PluginName");
```

## Build & Development Process

### Local Development
1. Install SourceKnight: Follow SourceKnight documentation
2. Build: `sourceknight build` (or use CI/CD)
3. Test: Load plugin on development server

### File Modifications
- **Main Logic**: Edit `HitMarker.sp`
- **API Changes**: Update `hitmarkers.inc` native definitions
- **New Translations**: Add to `HitMarker.phrases.txt`
- **Dependencies**: Modify `sourceknight.yaml`

### Testing Strategy
- **No unit tests**: SourcePawn plugins tested by server loading
- **Load plugin**: Use `sm plugins load hitmarker` in server console
- **Check errors**: Monitor server logs for compilation/runtime errors
- **Functional testing**: Join server and test features manually
- **Performance**: Monitor tick rate and memory usage

## Common Development Tasks

### Adding New ConVars
```sourcepawn
ConVar g_cvNewSetting;
g_cvNewSetting = CreateConVar("sm_hitmarker_newsetting", "1", "Description");
g_cvNewSetting.AddChangeHook(OnConVarChange);
AutoExecConfig(true, "Hitmarkers"); // Save to config file
```

### Cookie Management
```sourcepawn
// Define cookie
Cookie g_cNewCookie;
g_cNewCookie = new Cookie("cookie_name", "Description", CookieAccess_Private);

// Save data
char buffer[32];
Format(buffer, sizeof(buffer), "%d|%d", value1, value2);
g_cNewCookie.Set(client, buffer);

// Load data
g_cNewCookie.Get(client, buffer, sizeof(buffer));
char parts[2][8];
ExplodeString(buffer, "|", parts, sizeof(parts), sizeof(parts[]));
```

### Event Handling
```sourcepawn
HookEvent("event_name", Event_Handler);

public void Event_Handler(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    // Handle event
}
```

### Menu Systems
```sourcepawn
Menu menu = CreateMenu(MenuHandler);
menu.SetTitle("Menu Title");
menu.AddItem("item_id", "Display Text");
menu.Display(client, MENU_TIME_FOREVER);
```

## Sound Management

### Precaching and Downloads
```sourcepawn
PrecacheSound(soundPath, true);
Format(buffer, sizeof(buffer), "sound/%s", soundPath);
AddFileToDownloadsTable(buffer);
```

### Playing Sounds
```sourcepawn
EmitSoundToClient(client, soundPath, SOUND_FROM_PLAYER, 
    SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, volume);
```

## Performance Considerations

### Critical Performance Rules
- **Minimize timer usage**: Use events and hooks instead
- **Cache expensive operations**: Store results, don't recalculate
- **Tick rate awareness**: Limit operations per tick using `GetGameTickCount()`
- **String operations**: Minimize in frequently called functions
- **Loop optimization**: Prefer O(1) lookups over O(n) searches

### HUD Display Optimization
```sourcepawn
// Use HUD synchronizers for game text
Handle g_hHudSync = CreateHudSynchronizer();
ShowSyncHudText(client, g_hHudSync, "Text");
```

## Translation System

### Adding New Phrases
```
"Phrase_Key"
{
    "en"    "English text with {1} parameters"
    "zho"   "Traditional Chinese text"
    "chi"   "Simplified Chinese text"  
    "fr"    "French text"
}
```

### Using Translations
```sourcepawn
LoadTranslations("HitMarker.phrases");
CPrintToChat(client, "%t %t", "Prefix_Key", "Message_Key", param1);
```

## Common Pitfalls & Best Practices

### Memory Management
```sourcepawn
// WRONG: Memory leak
arrayList.Clear();

// CORRECT: Proper cleanup
delete arrayList;
arrayList = new ArrayList();
```

### SQL Operations (if added)
- **Always use async**: No synchronous SQL calls
- **Escape strings**: Use proper SQL escaping
- **Use transactions**: For multiple related queries
- **Use methodmaps**: For cleaner SQL handling

### Client Validation
```sourcepawn
// Standard client checks
if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
    return;

// Additional checks as needed
if (IsFakeClient(client) || !IsPlayerAlive(client))
    return;
```

## Debugging Tips

### Common Issues
- **Plugin not loading**: Check compiler errors in console
- **Runtime errors**: Monitor server logs for stack traces
- **Performance issues**: Use SourceMod profiler
- **Memory leaks**: Check Handle usage and cleanup

### Useful Console Commands
```
sm plugins list              // List loaded plugins
sm plugins reload hitmarker  // Reload plugin
sm plugins info hitmarker    // Show plugin info
sm_cookie_menu               // Test cookie menu
```

## Version Control Practices

- **Semantic versioning**: Update version in `hitmarkers.inc`
- **Clear commit messages**: Describe functional changes
- **Test before committing**: Ensure plugin compiles and loads
- **Tag releases**: Use git tags for stable versions

This plugin follows SourceMod best practices and integrates with the broader Source engine modding ecosystem. Always consider compatibility with other plugins and server performance when making modifications.