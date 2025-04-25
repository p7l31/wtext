#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <worldtext>
#include <adminmenu>

#define PLUGIN_VERSION "1.0.0"

public Plugin myinfo = {
    name = "Player Head Text",
    author = "whyhaveyouforsakenme",
    description = "Allows players to display text above their heads",
    version = PLUGIN_VERSION,
    url = "-"
};

// Store the entity indexes for each player
int g_TextEntities[MAXPLAYERS+1] = {INVALID_ENT_REFERENCE, ...};
// Store timer handles for position updates
Handle g_hUpdateTimer[MAXPLAYERS+1];

public void OnPluginStart() {
    // Initialize timer handles array
    for (int i = 1; i <= MaxClients; i++) {
        g_hUpdateTimer[i] = null;
    }

    // Register the command with admin flag "z"
    RegAdminCmd("sm_wtext", Command_WorldText, ADMFLAG_ROOT, "Display text above your head");
    
    // Create a command listener for "/wtext" without the "sm_" prefix
    AddCommandListener(CommandListener_WorldText, "say");
}

public void OnMapStart() {
    // Reset all text entities on map start
    for (int i = 1; i <= MaxClients; i++) {
        if (g_TextEntities[i] != INVALID_ENT_REFERENCE) {
            int entity = EntRefToEntIndex(g_TextEntities[i]);
            if (entity != INVALID_ENT_REFERENCE) {
                AcceptEntityInput(entity, "Kill");
            }
            g_TextEntities[i] = INVALID_ENT_REFERENCE;
        }
        
        if (g_hUpdateTimer[i] != null) {
            KillTimer(g_hUpdateTimer[i]);
            g_hUpdateTimer[i] = null;
        }
    }
}

public void OnClientDisconnect(int client) {
    // Remove text when player disconnects
    RemovePlayerText(client);
}

public Action CommandListener_WorldText(int client, const char[] command, int argc) {
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return Plugin_Continue;
        
    // Check if client has admin flag "z"
    if (!CheckCommandAccess(client, "sm_wtext", ADMFLAG_ROOT))
        return Plugin_Continue;
        
    char message[256];
    GetCmdArgString(message, sizeof(message));
    
    // Remove quotation marks that Source adds
    if (message[0] == '"' && message[strlen(message)-1] == '"') {
        message[strlen(message)-1] = '\0';
        strcopy(message, sizeof(message), message[1]);
    }
    
    // Check if the message starts with "/wtext"
    if (strncmp(message, "/wtext", 6, false) == 0) {
        // Extract the text from the message
        char textToShow[256];
        int startPos = 7; // Position after "/wtext "
        
        if (strlen(message) > startPos) {
            strcopy(textToShow, sizeof(textToShow), message[startPos]);
            ShowWorldText(client, textToShow);
        } else {
            PrintToChat(client, "[SM] Usage: /wtext [text]");
        }
        
        return Plugin_Handled; // Block the chat message
    }
    
    return Plugin_Continue;
}

public Action Command_WorldText(int client, int args) {
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
        return Plugin_Handled;
        
    if (args < 1) {
        ReplyToCommand(client, "[SM] Usage: /wtext [text]");
        return Plugin_Handled;
    }
    
    char textToShow[256];
    GetCmdArgString(textToShow, sizeof(textToShow));
    
    ShowWorldText(client, textToShow);
    
    return Plugin_Handled;
}

void ShowWorldText(int client, const char[] text) {
    // First validate if the text contains prohibited characters
    if (!IsValidText(text)) {
        PrintToChat(client, "[SM] Error: Только символы ASCII разрешены.");
        return;
    }
    
    // Remove any existing text
    RemovePlayerText(client);
    
    // Get player position
    float position[3];
    GetClientAbsOrigin(client, position);
    
    // Adjust height to be above player's head (approximately 85 units above the origin)
    position[2] += 85.0;
    
    // Create the world text
    int color[4] = {255, 255, 255, 255}; // White color
    
    // Create the entity
    int entity = CreateEntityByName("point_worldtext");
    if (IsValidEntity(entity)) {
        char buffer[256];
        
        // Set entity properties
        DispatchKeyValue(entity, "message", text);
        
        // Set position
        FormatEx(buffer, sizeof(buffer), "%f %f %f", position[0], position[1], position[2]);
        DispatchKeyValue(entity, "origin", buffer);
        
        // Set color
        FormatEx(buffer, sizeof(buffer), "%d %d %d %d", color[0], color[1], color[2], color[3]);
        DispatchKeyValue(entity, "textcolor", buffer);
        
        // Other settings
        DispatchKeyValue(entity, "font", "1"); // Default font
        DispatchKeyValue(entity, "orientation", "0"); // Normal orientation
        
        // Spawn the entity
        DispatchSpawn(entity);
        
        // Store the entity reference
        g_TextEntities[client] = EntIndexToEntRef(entity);
        
        // Create a timer to remove the text after 10 seconds
        CreateTimer(10.0, Timer_RemoveText, client, TIMER_FLAG_NO_MAPCHANGE);
        
        // Create a timer to update the text position
        g_hUpdateTimer[client] = CreateTimer(0.1, Timer_UpdateTextPosition, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
        
        PrintToChat(client, "[SM] Текст показан сверху твоей головы на 10 секунд.");
    }
    else {
        PrintToChat(client, "[SM] Error: Не удалось создать энтити.");
    }
}

public Action Timer_RemoveText(Handle timer, any client) {
    RemovePlayerText(client);
    return Plugin_Stop;
}

public Action Timer_UpdateTextPosition(Handle timer, any client) {
    if (!IsClientInGame(client) || g_TextEntities[client] == INVALID_ENT_REFERENCE) {
        g_hUpdateTimer[client] = null;
        return Plugin_Stop;
    }
    
    int entity = EntRefToEntIndex(g_TextEntities[client]);
    if (entity == INVALID_ENT_REFERENCE) {
        g_hUpdateTimer[client] = null;
        return Plugin_Stop;
    }
    
    // Get player position
    float position[3];
    GetClientAbsOrigin(client, position);
    
    // Adjust height to be above player's head
    position[2] += 85.0;
    
    // Update the text position using teleport
    TeleportEntity(entity, position, NULL_VECTOR, NULL_VECTOR);
    
    return Plugin_Continue;
}

void RemovePlayerText(int client) {
    // Kill the update timer if it exists
    if (g_hUpdateTimer[client] != null) {
        KillTimer(g_hUpdateTimer[client]);
        g_hUpdateTimer[client] = null;
    }
    
    // Remove the text entity if it exists
    if (g_TextEntities[client] != INVALID_ENT_REFERENCE) {
        int entity = EntRefToEntIndex(g_TextEntities[client]);
        if (entity != INVALID_ENT_REFERENCE) {
            AcceptEntityInput(entity, "Kill");
        }
        g_TextEntities[client] = INVALID_ENT_REFERENCE;
    }
}

bool IsValidText(const char[] text) {
    // This function checks if the text contains only allowed characters
    // Allowed: ASCII 32-126 (standard English keyboard)
    for (int i = 0; i < strlen(text); i++) {
        int c = text[i];
        // Check if character is outside the standard ASCII range
        if (c < 32 || c > 126) {
            return false;
        }
    }
    
    return true;
}