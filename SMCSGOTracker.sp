#pragma semicolon 1
#define DEBUG
#define PLUGIN_AUTHOR "Niko Kahilainen"
#define PLUGIN_VERSION "0.00"

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Player viewangle logger", 
	author = PLUGIN_AUTHOR, 
	description = "A plugin for recording players viewangle moves", 
	version = PLUGIN_VERSION, 
	url = "TBD"
};

EngineVersion g_Game;
int g_CurrentTick;
char validWeapons[][] = {"m249", 
						 "mag7", 
					     "negev", 
						 "nova", 
					 	 "sawedoff", 
						 "xm1014", 
						 "deagle", 
						 "elite", 
						 "fiveseven", 
						 "glock", 
						 "hkp2000", 
						 "p250", 
						 "revolver", 
						 "tec9", 
						 "usp_silencer", 
						 "ak47", 
						 "aug", 
						 "awp", 
						 "famas", 
						 "g3sg1", 
						 "m4a1", 
						 "m4a1_silencer", 
						 "scar20", 
						 "sg556", 
						 "ssg08", 
						 "bizon", 
						 "mac10", 
						 "mp5sd", 
						 "mp7", 
						 "mp9", 
						 "p90", 
						 "ump45"};
// Queue q;

// bool emptying = false;
// int ClientsTest[MAXPLAYERS + 1] = {1, ...};
// PlayerObject[] players = new PlayerObject[MaxClients];

// int maxBufferSize = 128;

enum struct ViewAngleSnapshot {
	float Pitch;
	float Yaw;
	int MouseX;
	int MouseY;
	float EngineTime;	// Intended for debugging only
	int currentTick;	// Intended for debugging only
	
	// Turns out you can't return strings in Pawn, so here we are
	void toString(char[] returnString, int returnStringLength) {
		char temp[512];
		Format(temp, sizeof(temp), "%f;%f;%i;%i;%f;%i", this.Pitch, this.Yaw, this.MouseX, this.MouseY, this.EngineTime, this.currentTick);
		strcopy(returnString, returnStringLength, temp);
	}
}

enum struct PlayerObject {
	// using steamid is the pretty much the only way I can make this work
	int steamID64;
	int clientIndex;
	// The "front" buffer
	ArrayList VasBufferQueue;
	int maxBufferSize;
	ArrayList killBuffer;
	bool hasRecentlyKilled;
	ArrayList killIndexes;
	ArrayList killWeapons;
	// int killIndexesIncrementer;
	int killTickTimer;
	// sint currentBackBufferSize;
	
	char name[17];
	int steamAccountID;
	char _baseFilePath[PLATFORM_MAX_PATH];
	int _writes;
	
	void Initialize(int index, char name[10]) {
		PrintToServer("Initializing player index %d", index);
		/*
		char temp[17];
		if (GetClientAuthId(index, AuthId_SteamID64, temp, 17, false)) {
			PrintToServer("Got steamID64 succesfully");
			this.steamID64 = StringToInt(temp);
			this.name = temp;
		} else {
			PrintToServer("Apparently failed to get client steamID64 :(");
			this.name = name;
		}
		*/
		
		this.steamAccountID = GetSteamAccountID(index);
		PrintToServer("Client's steam account id is %d ", this.steamAccountID);

		this.clientIndex = index;
		this.VasBufferQueue = new ArrayList(sizeof(ViewAngleSnapshot), 64);
		this.maxBufferSize = 64;
		this.killBuffer = new ArrayList(sizeof(ViewAngleSnapshot));
		
		this.hasRecentlyKilled = false;
		// this.killIndexesIncrementer = -1;
		this.killIndexes = new ArrayList(sizeof(ViewAngleSnapshot));
		this.killWeapons = new ArrayList(64);
		this.killTickTimer = 0;
		this._writes = 0;
		
		// Create a folder for this player's kills
		BuildPath(Path_SM, this._baseFilePath, PLATFORM_MAX_PATH, "kills/%d", this.steamAccountID);
		CreateDirectory(this._baseFilePath, 511);
		PrintToServer("Creating a folder at %s", this._baseFilePath);
		
		int validWeaponCount = sizeof(validWeapons);
		for (int i = 0; i < validWeaponCount; i++) {
			char WeaponPath[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, WeaponPath, PLATFORM_MAX_PATH, "kills/%d/%s", this.steamAccountID, validWeapons[i]);
			CreateDirectory(WeaponPath, 511);
			PrintToServer("Creating weapon folder %s", WeaponPath);
		}
		
		
	}

	void OnPlayerMove(ViewAngleSnapshot v) {
		// PrintToServer("Handling this player's movements: %s", this.name);
		this.VasBufferQueue.PushArray(v);
		if (this.VasBufferQueue.Length >= this.maxBufferSize) {
			// We're handling our buffers as queues, so this would essentially be a .pop()
			this.VasBufferQueue.Erase(0);
		}
		
		// Player has killed someone, so we're handling our killbuffer
		if (this.hasRecentlyKilled) {
			if (this.killBuffer.Length == 0) {
				this.killBuffer = this.VasBufferQueue.Clone();
				return;
			}
			if (this.killTickTimer >= 0 && this.killTickTimer <= this.maxBufferSize) {
				this.killBuffer.PushArray(v);
				this.killTickTimer += 1;
			} else {
				// player has not killed any other players for the recording duration,
				// So we will parse the killbuffer for individual kill events.
				this.hasRecentlyKilled = false;
				this.killTickTimer = 0;
				this._ParseKillBuffer();
			}
		}
	}
	
	void OnPlayerKill(char[] weapon) {
		int tickOfKill = GetGameTickCount();
		PrintToServer("Player has killed another player at tick %d with weapon %s", tickOfKill, weapon);
		this.hasRecentlyKilled = true;
		if (this.killTickTimer == 0) {
			int ind = this.maxBufferSize - 1;
			PrintToServer("First kill, marking index %d", ind);
			this.killIndexes.Push(ind);
		} else {
			int ind = this.killBuffer.Length - 1;
			PrintToServer("Another kill during killbuffer time, marking index %d", ind);
			this.killIndexes.Push(ind);
		}
		this.killTickTimer = 0;
		this.killWeapons.PushString(weapon);
		// this.killTicks.Push(tickOfKill);
	}
	
	// Parses the killbuffer for individual kill events.
	// The end goal for this function is to print out 
	// the view angles between each kill, so roughly 
	// {64 viewangle updates, 64 viewangle updates} (replace 64 with 32 if running at 64 ticks) (Either of the middle updates being the actual kill tick) 
	// I hope this makes my life easier going forward.
	void _ParseKillBuffer() {
		PrintToServer("Beginning to parse kills, killbuffer length is %d", this.killBuffer.Length);
		for (int i = 0; i < this.killIndexes.Length; i++) {
			int Index = this.killIndexes.Get(i);
			PrintToServer("first killIndex is %d", Index);
			ArrayList killEvent = new ArrayList( sizeof(ViewAngleSnapshot));
			
			// (Source)Pawn doesn't offer any easy ways to slice arrays so here we are 🤷‍
			for (int j = Index - this.maxBufferSize + 1; j < Index + this.maxBufferSize + 1; j++) {
				ViewAngleSnapshot temp;
				GetArrayArray(this.killBuffer, j, temp);
				killEvent.PushArray(temp);
				// PrintToServer("Pitch: %f Yaw: %f MouseX: %d MouseY: %d Tick: /%d", temp.Pitch, temp.Yaw, temp.MouseX, temp.MouseY, temp.currentTick);
			}
			PrintToServer("Killevent array length is: %d", killEvent.Length);
			this._WriteKillEventToFile(killEvent);
		}
		this.killIndexes.Clear();
		this.killBuffer.Clear();
	}
	
	// Writes the given killbuffer to a file
	void _WriteKillEventToFile(ArrayList list) {
		PrintToServer("Creating file to write to");
		char filename[512];
		char weapon[64];
		this.killWeapons.GetString(0, weapon, sizeof(weapon));
		PrintToServer(weapon);
		Format(filename, sizeof(filename), "%s/%s/Kill_%i.csv", this._baseFilePath, weapon, this._writes);
		File file = OpenFile(filename, "w");
		file.WriteLine("Pitch;Yaw;MouseX;MouseY;EngineTime;Tick");
		for (int i = 0; i < list.Length; i++) {
			ViewAngleSnapshot tempSnapShot;
			GetArrayArray(list, i, tempSnapShot);
			char snapShotString[512];
			tempSnapShot.toString(snapShotString, sizeof(snapShotString));
			// PrintToServer(snapShotString);
			// char formattedString[512];
			// Format(formattedString, sizeof(formattedString), "%f %f %i %i %f %i", temp.Pitch, temp.Yaw, temp.MouseX, temp.MouseY, temp.EngineTime, temp.currentTick);
			file.WriteLine(snapShotString);
		}
		file.Flush();
		file.Close();
		PrintToServer("Kill write event completed");
		this._writes++;
		this.killWeapons.Erase(0);
	}	
}

PlayerObject playerInServer[MAXPLAYERS + 1];

// A helper object to allow PlayerObjects to work properly
// and to make things easier. hopefully
enum struct PlayerHandler {
	int dummy;
	
	void Initialize() {
		// Not sure I even need something here
	}
	
	void OnPlayerJoin(int index) {
			PlayerObject p;
			playerInServer[index] = p;
			playerInServer[index].Initialize(index, "TESTNAME");
	}
	
	void OnPlayerKill(int killerIndex, char[] weapon) {
		playerInServer[killerIndex].OnPlayerKill(weapon);
	}
	
	void OnPlayerMove(int playerIndex, ViewAngleSnapshot v) {
		// PrintToServer("Handler is handing players movement");
		playerInServer[playerIndex].OnPlayerMove(v);
	}
}
PlayerHandler handler;

public void OnPluginStart()
{
	g_Game = GetEngineVersion();
	if (g_Game != Engine_CSGO && g_Game != Engine_CSS)
	{
		SetFailState("This plugin is for CSGO/CSS only.");
	}
	
	// Hooks into the player_death event, from which we get to know when players defeat each other.
	// EventHookMode has basically 2 modes, pre and post, for calling the hook before and after the event,
	// I hope EventHookMode_Pre works fine?
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
}

// An event which is called everytime a player death occurs on the server
public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	char weapon[64]; // Use this name
	event.GetString("weapon", weapon, sizeof(weapon));
	// char weapon_id[64];
	
	if (attacker != victim && IsValidClient(attacker)) {
		// PrintToServer("Client %d Killed Client %d", attacker, victim);
		PrintToServer("weapon bare name is: %s", weapon);
		// PrintToServer("weapon id is: %s", weapon_id);
		// PrintToServer("weapon faux name is: %s", weapon_faux_id);
		
		handler.OnPlayerKill(attacker, weapon);
	} else {
		// PrintToServer("Player at user ID %d committed not-alive or killed by bot", attacker);
	}
	return Plugin_Continue;
}

stock bool IsValidClient(int client, bool allowBot = false) {
    if ( !( 1 <= client <= MaxClients ) || !IsClientInGame(client) || IsClientSourceTV(client) || (!allowBot && IsFakeClient(client) ) ){
        return false;
    }
    return true;
}

public void OnClientPostAdminCheck(int client) {
	if (IsValidClient(client)){
		PrintToServer("Authorizing client %d", client);
		handler.OnPlayerJoin(client);
	}
}

// Called every tick for every player
public Action OnPlayerRunCmd(int client, int & buttons, int & impulse, float vel[3], float angles[3], int & weapon, int & subtype, int & cmdnum, int & tickcount, int & seed, int mouse[2]) {
	// Not going to do anything if the player is dead, not in game, or a bot client
	if (!IsPlayerAlive(client) || !IsClientInGame(client) || IsFakeClient(client)) {
		return Plugin_Continue;
	}
	ViewAngleSnapshot v;
	v.Pitch = angles[0];
	v.Yaw = angles[1];
	v.MouseX = mouse[0];
	v.MouseY = mouse[1];
	v.EngineTime = GetEngineTime();
	v.currentTick = g_CurrentTick;
	
	handler.OnPlayerMove(client, v);
	return Plugin_Continue;
}

public void OnGameFrame() {
	g_CurrentTick = GetGameTickCount();
}