#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tf2utils>
#include <tf2attributes>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Sile's Team Synergy 2 Mini-mod",
	author = "Ech0",
	description = "Contains stock weapon changes from Sile's document",
	version = "0.1.1",
	url = ""
};

	// ==={{ Stock functions }}==
	// -={ Remapping and ramp-up/fall-off curve -- taken from Valve themselves }=-
	// https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/public/mathlib/mathlib.h#L648s

float SimpleSpline(float value) {		// Takes a value from 0-1 and modifies it using the ramp-up-fall-off function
	float valueSquared = value * value;

	// Spline curve -- equation y = 3x^2 - 2x^3
	return (3 * valueSquared - 2 * valueSquared * value);
}

float clamp(float val, float minVal, float maxVal) {		// Used in the following function to clamp values for SimpleSpline
	if (maxVal < minVal) {return maxVal;}
	else if (val < minVal) {return minVal;}
	else if (val > maxVal) {return maxVal;}
	else {return val;}
}

float RemapValClamped( float val, float A, float B, float C, float D)		// Remaps val from the A-B range to the C-D range
{
	if (A == B) {
		return val >= B ? D : C;
	}
	float cVal = (val - A) / (B - A);
	cVal = clamp(cVal, 0.0, 1.0);

	return C + (D - C) * cVal;
}

float SimpleSplineRemapValClamped(float val, float A, float B, float C, float D) {		// Remaps val from the A-B range to the C-D range, and applies SimpleSpline
	if (A == B) {
		return val >= B ? D : C;
	}
	float cVal = (val - A) / (B - A);
	cVal = clamp( cVal, 0.0, 1.0 );
	return C + (D - C) * SimpleSpline(cVal);
}


	// -={ Identifies sources of (Mini-)Crits -- taken from ShSilver }=-

bool isKritzed(int client) {
	return (TF2_IsPlayerInCondition(client,TFCond_Kritzkrieged) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnFirstBlood) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnWin) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnFlagCapture) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnKill) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnDamage) ||
	TF2_IsPlayerInCondition(client,TFCond_CritDemoCharge));
}

bool isMiniKritzed(int client,int victim=-1) {
	bool result=false;
	if(victim!=-1) {
		if (TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeathSilent)) {
			result = true;
		}
	}
	if (TF2_IsPlayerInCondition(client,TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(client,TFCond_Buffed) || TF2_IsPlayerInCondition(client,TFCond_CritCola)) {
		result = true;
	}
	return result;
}


	// ==={{ Initialisation and stuff }}==

enum struct Player {
	// Multi-class
	float fTHREAT;		// THREAT
	float fTHREAT_Timer;	// Timer when after building THREAT we start to get rid of it
	float fHeal_Penalty;		// Tracks how long after taking damage we restore our incoming healing to normal
	int bFirst_Reload;		// Tracks when we firefor the purpose of identifying the first-shot portion of the reload on certain weapons
	float fAfterburn;		// Tracks Afterburn diration
	
	// Scout
	float fAirjump;		// Tracks damage taken while airborne
	
	// Pyro
	int iAmmo;	// Tracks ammo for the purpose of making the hitscan beam
	
	// Heavy
	float fRev;		// Tracks how long we've been revved for the purposes of undoing the L&W nerf
	float fSpeed;		// Tracks how long we've been firing for the purposes of modifying Heavy's speed and reverting the JI buff
	
	// Medic
	int iSyringe_Ammo;		// Tracks loaded syringes for the purposes of determining when we fire a shot
	
	// Sniper
	int iHeadshot_Frame;		// Identifies frames where we land a headshot
	
	// Spy
	float fHitscan_Accuracy;		// Tracks dynamic accuracy on the revolver
	int iHitscan_Ammo;			// Tracks ammo change on the revolver so we can determine when a shot is fired (for the purposes of dynamic accuracy)
	float fCloak_Timer;			// Tracks how long we've been cloaked (so we can disable cloak drain during the cloaking animation)
}

enum struct Entity {
	float fConstruction_Health;
	int iLevel;		// Stores building level for the purpose of identifying when it changes
}

Player players[MAXPLAYERS+1];
Entity entities[2048];

Handle g_hSDKFinishBuilding;


public void OnPluginStart() {
	// This is used for clearing variables on respawn
	HookEvent("player_spawn", OnGameEvent, EventHookMode_Post);
	// This detects healing we do
	HookEvent("player_healed", OnPlayerHealed);
	GameData data = new GameData("buildings");
	if (!data) {
		SetFailState("Failed to open gamedata.buildings.txt. Unable to load plugin");
	}
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(data, SDKConf_Virtual, "CBaseObject::FinishedBuilding");
	g_hSDKFinishBuilding = EndPrepSDKCall();
}


public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	SDKHook(iClient, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
	SDKHook(iClient, SDKHook_TraceAttack, TraceAttack);
}

public void OnMapStart() {
	PrecacheSound("weapons/syringegun_shoot.wav", true);
	PrecacheSound("weapons/syringegun_shoot_crit.wav", true);
	
	PrecacheModel("models/weapons/w_models/w_syringe_proj.mdl",true);
}


	// -={ Modifies attributes without needing to go through another plugin }=-
public Action TF2Items_OnGiveNamedItem(int iClient, char[] class, int index, Handle& item) {
	Handle item1;
	// Scout
	if (StrEqual(class, "tf_weapon_scattergun")) {	// All Scatterguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 37, 0.555555); // hidden primary max ammo bonus (reduced to 20)
		TF2Items_SetAttribute(item1, 1, 68, -1.0); // increase player capture value (lowered to 1)
	}
	else if (StrEqual(class, "tf_weapon_bat")) {	// All Bats
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.14296); // damage bonus (35 to 40)
	}
	
	// Soldier
	else if (StrEqual(class, "tf_weapon_rocketlauncher")) {	// All Rocket Launchers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 1, 0.888888); // damage penalty (90 to 80)
		TF2Items_SetAttribute(item1, 1, 37, 0.6); // hidden primary max ammo bonus (reduced to 12)
	}
	else if (StrEqual(class, "tf_weapon_rocketlauncher_directhit")) {	// Direct Hit
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.111111); // damage bonus (112 to 100)
		TF2Items_SetAttribute(item1, 1, 37, 0.6); // hidden primary max ammo bonus (reduced to 12)
		TF2Items_SetAttribute(item1, 2, 100, 0.67); // blast radius decreased (increased to -33%)
	}
	else if (StrEqual(class, "tf_weapon_shovel")) {		// All Shovels
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.230769); // damage bonus (65 to 80)
	}
	
	// Pyro
	else if (StrEqual(class, "tf_weapon_flamethrower")) {		// All Flamethrowers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 11);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty (100%; prevents damage from flame particles)
		TF2Items_SetAttribute(item1, 1, 174, 1.333333); // flame_ammopersec_increased (33%)
		TF2Items_SetAttribute(item1, 2, 844, 2200.0); // flame_speed (enough to travel 350 HU from out centre in 0.1 sec)
		TF2Items_SetAttribute(item1, 3, 862, 0.1); // flame_lifetime (nil)
		TF2Items_SetAttribute(item1, 4, 72, 0.0); // weapon burn dmg reduced (nil)
		TF2Items_SetAttribute(item1, 5, 839, 0.0); // flame_spread_degree (none)
		TF2Items_SetAttribute(item1, 6, 841, 0.0); // flame_gravity (none)
		TF2Items_SetAttribute(item1, 7, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 8, 865, 0.0); // flame_up_speed (removed)
		TF2Items_SetAttribute(item1, 9, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 10, 863, 0.0); // flame_random_lifetime_offset (none)
	}
	else if (StrEqual(class, "tf_weapon_flaregun")) {	// All Flare Guns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 72, 0.0); // weapon burn dmg reduced (nil)
		TF2Items_SetAttribute(item1, 1, 318, 0.625); // faster reload rate (1.25 sec)
	}
	
	// Demoman
	else if (StrEqual(class, "tf_weapon_grenadelauncher")) {	// All Grenade Launchers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 4, 1.5); // clip size bonus (6)
		TF2Items_SetAttribute(item1, 1, 37, 1.5); // hidden primary max ammo bonus (16 to 24)
	}
	else if (StrEqual(class, "tf_weapon_pipebomblauncher")) {	// All Sticky Launchers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.833333); // damage penalty (120 to 100)
		TF2Items_SetAttribute(item1, 1, 3, 0.75); // clip size penalty (6)
		TF2Items_SetAttribute(item1, 2, 96, 0.917431); // reload time decreased (first shot reload 1.0 seconds)
		TF2Items_SetAttribute(item1, 3, 670, 0.5); // stickybomb charge rate (50% faster)
	}
	
	// Heavy
	else if (StrEqual(class, "tf_weapon_minigun")) {	// All Miniguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 125, -50.0); // max health additive penalty (-50)
		TF2Items_SetAttribute(item1, 1, 45, 0.75); // bullets per shot bonus (-25%)
		TF2Items_SetAttribute(item1, 2, 75, 1.6); // aiming movespeed increased (to 80% of Heavy's base)
		TF2Items_SetAttribute(item1, 3, 37, 0.7); // hidden primary max ammo bonus (-30%)
	}
	else if ((StrEqual(class, "tf_weapon_shotgun") || StrEqual(class, "tf_weapon_shotgun_hwg")) && TF2_GetPlayerClass(iClient) == TFClass_Heavy) {	// All Heavy Shotguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.25); // damage bonus (25%)
	}
	else if (StrEqual(class, "tf_weapon_fists")) {	// All Fists
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.230769); // damage bonus (65 to 80)
	}
	
	// Engineer
	else if ((StrEqual(class, "tf_weapon_shotgun") || StrEqual(class, "tf_weapon_shotgun_primary") || StrEqual(class, "tf_weapon_shotgun_revenge")) && TF2_GetPlayerClass(iClient) == TFClass_Engineer) {	// All Engineer Shotguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 106, 0.6); // weapon spread bonus (40%)
	}
	else if (StrEqual(class, "tf_weapon_pistol") && TF2_GetPlayerClass(iClient) == TFClass_Engineer) {	// All Engineer Pistols
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 78, 0.18); // maxammo secondary reduced (36)
	}
	else if (StrEqual(class, "tf_weapon_wrench")) {	// All Wrenches
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		//TODO: Validate this
		TF2Items_SetAttribute(item1, 0, 2043, 2.0); // upgrade rate decrease (increased; 100%)
	}
	
	// Medic
	else if (StrEqual(class, "tf_weapon_syringegun_medic")) {	// All Syringe Guns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 4, 1.25); // clip size bonus (50)
		TF2Items_SetAttribute(item1, 1, 37, 1.333333); // hidden primary max ammo bonus (150 to 200)
		TF2Items_SetAttribute(item1, 2, 280, 9.0); // override projectile type (to flame rocket, which disables projectiles entirely)
	}
	else if (StrEqual(class, "tf_weapon_medigun")) {	// All Medi-Guns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 9, 0.0); //  ubercharge rate penalty (No normal Uber build)
		TF2Items_SetAttribute(item1, 1, 12, 0.333333); // overheal decay penalty (10%/sec)
	}
	
	// Sniper
	else if (StrEqual(class, "tf_weapon_sniperrifle")) {	// All Sniper Rifles
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 37, 0.6); // hidden primary max ammo bonus (25 to 15)
		TF2Items_SetAttribute(item1, 1, 42, 1.0); // sniper no headshots (we're handling them elsewhere)
		TF2Items_SetAttribute(item1, 2, 75, 1.851851); // aiming movespeed increased (27% to 50%)
	}
	
	// Spy
	else if (StrEqual(class, "tf_weapon_sapper")) {	// All Sappers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 426, 0.88); // sapper damage penalty (25 DPS to 22)
	}
	else if (StrEqual(class, "tf_weapon_revolver")) {	// All Revolvers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.25); // damage bonus (50)
		TF2Items_SetAttribute(item1, 1, 78, 0.75); // maxammo secondary reduced (24 to 18)
		TF2Items_SetAttribute(item1, 2, 96, 1.191527); // reload time increased (1.133 sec to 1.35)
	}
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}


	// -={ Resets THREAT on death }=-

Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {
	int iClient;
	
	if (StrEqual(name, "player_spawn")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsPlayerAlive(iClient)) {
			
			players[iClient].fTHREAT = 0.0;
			players[iClient].fTHREAT_Timer = 0.0;
		}
	}
	return Plugin_Continue;
}


	// -={ Iterates every frame }=-

public void OnGameFrame() {
	for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {		// When the building associated with this ID goes down, reset its level
		if (!IsValidEdict(iEnt)) {
			entities[iEnt].iLevel = 0;
			/*if (StrEqual(class,"obj_teleporter")) {		// If a Teleporter dies, find the other half and reset its level
				int iOwner = GetEntPropEnt(iEnt, Prop_Send, "m_hBuilder");
				if (iOwner != -1) {
					for (int iEnt2 = 0; iEnt2 < GetMaxEntities(); iEnt2++) {
						char class2[64];
						GetEntityClassname(iEnt2, class2, 64);
						if (StrEqual(class,"obj_teleporter") && iOwner == GetEntPropEnt(iEnt2, Prop_Send, "m_hBuilder")) {
							entities[iEnt2].iLevel = 1;
						}
					}
				}
			}*/
		}
		else {
			char class[64];
			GetEntityClassname(iEnt, class, 64);
			if (StrEqual(class,"obj_sentrygun") || StrEqual(class,"obj_teleporter") || StrEqual(class,"obj_dispenser")) {
				
				if (entities[iEnt].iLevel == 1) {
					SetEntProp(iEnt, Prop_Data, "m_iMaxHealth", 130);
				}
				else if (entities[iEnt].iLevel == 2) {
					SetEntProp(iEnt, Prop_Data, "m_iMaxHealth", 160);
				}	
				else if (entities[iEnt].iLevel == 3) {
					SetEntProp(iEnt, Prop_Data, "m_iMaxHealth", 200);
				}
				
				if (GetEntProp(iEnt, Prop_Data, "m_iHealth") > GetEntProp(iEnt, Prop_Data, "m_iMaxHealth")) {		// Lowering of current health as nessesary
					SetEntProp(iEnt, Prop_Data, "m_iHealth", GetEntProp(iEnt, Prop_Data, "m_iMaxHealth"));
				}
			}
		}
	}
	
	for (int iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			
			int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			//int iPrimaryIndex = -1;
			//if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			//int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			//int iMeleeIndex = -1;
			//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
			//int iWatchIndex = -1;
			//if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
			
			
			//THREAT
			if (players[iClient].fTHREAT_Timer > 0.0) {
				players[iClient].fTHREAT_Timer -= 0.75;		// If we're not doing more than 50 DPS, this value will decrease
				if (players[iClient].fTHREAT_Timer > 500.0) {
					players[iClient].fTHREAT_Timer = 500.0;
				}
			}
			
			if (players[iClient].fTHREAT > 0.0 && players[iClient].fTHREAT_Timer <= 0.0) {
				players[iClient].fTHREAT -= 0.75;		// Equivalent of removing 50 THREAT per second
			}
			
			SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);		// Displays THREAT
			ShowHudText(iClient, 1, "THREAT: %.0f", players[iClient].fTHREAT);
			
			// Define gold and default colour
			//int R1 = 0, G1 = 225, B1 = 0; // Default colour (green)
			//int R2 = 255, G2 = 215, B2 = 0; // Gold colour

			// Remap fTHREAT to 0–1 range (e.g., max 500 THREAT)
			//float fThreatScale = RemapValClamped(players[iClient].fTHREAT, 0.0, 500.0, 0.0, 1.0);

			// Interpolate RGB channels
			//int R = R1 + (R2 - R1) * fThreatScale;
			//int G = G1 + (G2 - G1) * fThreatScale;
			//int B = B1 + (B2 - B1) * fThreatScale;

			// Apply colour to the weapon
			if (players[iClient].fTHREAT > 500.0) {
				SetEntityRenderColor(iActive, 255, 255, 0, 200); // Set alpha to 0 or desired value
			}
			else {
				SetEntityRenderColor(iActive, 255, 255, 255, 255);
			}
			
			// In-combat healing penalty
			if (players[iClient].fHeal_Penalty > 0.0) {
				players[iClient].fHeal_Penalty -= 0.015;
			}
			else {
				TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.5);
			}
			
			
			// Afterburn
			//int MaxHP = GetEntProp(iClient, Prop_Send, "m_iMaxHealth");
			if (TF2Util_GetPlayerBurnDuration(iClient) > 6.0) {
				TF2Util_SetPlayerBurnDuration(iClient, 6.0);
				/*players[iClient].fAfterburn += MaxHP / 20.0;		// Adds 5% of the victim's max health to this value
				if (players[iClient].fAfterburn > MaxHP / 5.0) {
					players[iClient].fAfterburn = MaxHP / 5.0;		// Clamping
				}*/
			}
			/*if (TF2Util_GetPlayerBurnDuration(iClient) > 0.0) {
				players[iClient].fAfterburn -= 0.015;
				if (players[iClient].fAfterburn < 0.0) {
					players[iClient].fAfterburn = 0.0;
				}
			}
			else if (TF2Util_GetPlayerBurnDuration(iClient) <= 0.0) {
				players[iClient].fAfterburn -= MaxHP / 10.0;
			}
			TF2Attrib_AddCustomPlayerAttribute(iClient, "max health additive penalty", -players[iClient].fAfterburn);*/
			
			
			// Scout
			if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
				// Removes double jump when taking daamge while airborne
				// fAirjump handled in OnTakeDamagePost
				if ((GetEntityFlags(iClient) & FL_ONGROUND) && players[iClient].fAirjump > 0.0) {
					players[iClient].fAirjump = 0.0;
				}
				
				if (players[iClient].fAirjump > 50.0) {
					SetEntProp(iClient, Prop_Send, "m_iAirDash", 1);		// Consumes our double jump prematurely
				}
				
				SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
				if (!(GetEntityFlags(iClient) & FL_ONGROUND) && players[iClient].fAirjump >= 50.0 || GetEntProp(iClient, Prop_Send, "m_iAirDash") > 0) {
					ShowHudText(iClient, 2, "Jump Disabled!");
				}
				
				else if (!(GetEntityFlags(iClient) & FL_ONGROUND)) {		// Don't play this message when grounded
					ShowHudText(iClient, 2, "Damage taken: %.0f", players[iClient].fAirjump);
				}
				
				else {
					ShowHudText(iClient, 2, "");		// By having a message with nothing in it, we make the other messages load in faster
				}
				
				// Scattergun first-shot reload				
				int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
				int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
				
				if (sequence == 28 && iActive == iPrimary) {		// This animation plays at the start of our first-shot reload
					SetEntPropFloat(view, Prop_Send, "m_flPlaybackRate", 0.540541);		// Make this a little longer (0.7 to 0.87 sec)
				}
				
				// Disable Medic speed matching (this is awkward, but it's the best I've got)
				if (TF2_IsPlayerInCondition(iClient, TFCond_Healing)) {
					int iHealer = TF2Util_GetPlayerConditionProvider(iClient, TFCond_Healing);
					if (IsClientInGame(iHealer) && IsPlayerAlive(iHealer))  {
						if (TF2_GetPlayerClass(iHealer) == TFClass_Medic) {
							TF2Attrib_SetByDefIndex(iHealer, 54, 0.8);		// Speed
							//PrintToChatAll("Slowdown");
						}
					}
				}
			}
			
			// Pyro
			else if (TF2_GetPlayerClass(iClient) == TFClass_Pyro) {
				
				/* *Flamethrower weaponstates*
					0 = Idle
					1 = Start firing
					2 = Firing
					3 = Airblasting
				*/
				
				// Hitscan Flamethrower
				int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
				
				if (weaponState == 2) {		// Are we firing?
					
					int Ammo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, Ammo);		// Only fire the beam on frames where the ammo changes
					if (ammoCount == (players[iClient].iAmmo - 1)) {		// We update iAmmo after this check, so clip will always be 1 lower on frames in which we fire a shot
						
						float vecPos[3], vecAng[3], vecEnd[3];
						
						GetClientEyePosition(iClient, vecPos);
						GetClientEyeAngles(iClient, vecAng);
						
						GetAngleVectors(vecAng, vecAng, NULL_VECTOR, NULL_VECTOR);
						ScaleVector(vecAng, 350.0);		// Scales this vector 350 HU out
						AddVectors(vecPos, vecAng, vecAng);		// Add this vector to the position vector so the game can aim it better
						
						Handle hndl = TR_TraceRayFilter(vecPos, vecAng, MASK_SOLID, RayType_EndPoint, TraceFilter_ExcludeSingle, iClient);		// Create a trace that starts at us and ends 512 HU forward
						TR_GetEndPosition(vecEnd);
						
						//float angle = vecAng[1]*0.01745329;
						//float Xoffset = (80-FloatAbs(vecAng[0])) * Cosine(angle);
						//float Yoffset = (80-FloatAbs(vecAng[0])) * Sine(angle);
						//float Zoffset = 50.0 - vecAng[0];
						
						//CreateParticle(iPrimary, "new_flame", 0.1, _, _, _,  _, _, 5.7);
						
						if (TR_DidHit()) {
							int iEntity = TR_GetEntityIndex();		// This is the ID of the thing we hit
							if (iEntity >= 1 && iEntity <= MaxClients && GetClientTeam(iEntity) != GetClientTeam(iClient)) {		// Did we hit an enemy?
								
								float vecVictim[3], fDmgMod;
								GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
								float fDistance = GetVectorDistance(vecPos, vecVictim, false);		// Distance calculation
								fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 350.0, 1.5, 1.0);		// Gives us our distance multiplier
								float fDmgModTHREAT = RemapValClamped(players[iClient].fTHREAT, 0.0, 350.0, 1.0, 1.5);
								// TODO: knockback equation
								
								int hit = TR_GetHitGroup(hndl);
								PrintToChatAll("Hitgroup: %i", hit);
								
								float fDamage = 8.0 * fDmgMod * fDmgModTHREAT;
								int iDamagetype = DMG_IGNITE;
								
								if (isMiniKritzed(iClient, iEntity)) {
									TF2_AddCondition(iEntity, TFCond_MarkedForDeathSilent, 0.015);
									fDamage *= 1.35;
								}
								else if (isKritzed(iClient)) {
									fDamage = 8.0;
									iDamagetype |= DMG_CRIT;
								}
								SDKHooks_TakeDamage(iEntity, iPrimary, iClient, fDamage, iDamagetype, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage (credited to the Phlog)
								TF2Util_SetPlayerBurnDuration(iEntity, 6.0);
								
								// Add THREAT
								players[iClient].fTHREAT += fDamage;		// Add THREAT
								if (players[iClient].fTHREAT > 1000.0) {
									players[iClient].fTHREAT = 1000.0;
								}
								players[iClient].fTHREAT_Timer += fDamage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
							}
							else if(IsValidEdict(iEntity)) {		// Handles building damage
								char class[64];
								GetEntityClassname(iEntity, class,64);
								if (StrEqual(class,"obj_sentrygun") || StrEqual(class,"obj_teleporter") || StrEqual(class,"obj_dispenser")) {
									float vecVictim[3], fDmgMod;
									GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
									float fDistance = GetVectorDistance(vecPos, vecVictim, false);		// Distance calculation
									fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 350.0, 1.5, 1.0);		// Gives us our distance multiplier
									float fDmgModTHREAT = RemapValClamped(players[iClient].fTHREAT, 0.0, 350.0, 1.0, 1.5);
									
									float fDamage = 8.0 * fDmgMod * fDmgModTHREAT;
									int iDamagetype = DMG_IGNITE;
									
									SDKHooks_TakeDamage(iEntity, iPrimary, iClient, fDamage, iDamagetype, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage (credited to the Phlog)
								}
								
								else if (StrEqual(class, "tf_projectile_pipe_remote")) {		// Handles sticky destruction on hit
									int iStickyTeam = GetEntProp(iEntity, Prop_Data, "m_iTeamNum");

									// Check if the sticky belongs to the opposing team
									int iProjTeam = GetEntProp(iEntity, Prop_Data, "m_iTeamNum");
									if (iStickyTeam != iProjTeam) {
										AcceptEntityInput(iEntity, "Kill"); // Destroy the sticky
									}
								}
							}
						}
					}
					players[iClient].iAmmo = ammoCount;
				}
			}				
			
			// Demoman
			if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
				// Ensures both launchers share the same pool of ammo
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int iClipGrenade = GetEntData(iPrimary, iAmmoTable, 4);		// Loaded ammo of our launchers
				int iClipSticky = GetEntData(iSecondary, iAmmoTable, 4);
				
				int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");		// Reserve ammo
				int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
				int iPrimaryReserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, iPrimaryAmmo);
				int iSecondaryReserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, iSecondaryAmmo);
				
				if (iActive == iPrimary) {
					if (iClipGrenade != iClipSticky) {		// If our two launchers have different ammo...
						SetEntData(iSecondary, iAmmoTable, iClipGrenade, 4, true);	// Set the unequipped one to have the same ammo as the equipped
						SetEntProp(iClient, Prop_Data, "m_iAmmo", iPrimaryReserves, _, iSecondaryAmmo);
					}
					
					// Grenade Launcher first-shot reload
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					
					if (sequence == 28 && iActive == iPrimary) {		// This animation plays at the start of our first-shot reload
						SetEntPropFloat(view, Prop_Send, "m_flPlaybackRate", 1.9375);		// Make this a little shorter (1.24 to 1.0 sec)
					}
				}
				
				else if (iActive == iSecondary) {
					if (iClipSticky != iClipGrenade) {
						SetEntData(iPrimary, iAmmoTable, iClipSticky, 4, true);
						SetEntProp(iClient, Prop_Data, "m_iAmmo", iSecondaryReserves, _, iPrimaryAmmo);
					}
				}
			}
			
			// Heavy
			else if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
			
				int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
				int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
				int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
				float cycle = GetEntPropFloat(view, Prop_Data, "m_flCycle");
				
				/* *Minigun weaponstates*
					0 = Idle
					1 = Revving up
					2 = Firing
					3 = Revved but not firing
				*/
				
				
				// Counteracts the L&W nerf by dynamically adjusting damage and accuracy
				if (weaponState == 1) {		// Are we revving up?
					players[iClient].fRev = 1.005;		// This is our rev meter; it's a measure of how close we are to being free of the L&W nerf
				}
				
				else if ((weaponState == 2 || weaponState == 3) && players[iClient].fRev > 0.0) {		// If we're revved (or firing) but the rev meter isn't empty...
					players[iClient].fRev = players[iClient].fRev - 0.015;		// It takes us 67 frames (1 second) to fully deplete the rev meter
				}
				
				// Fast holster when unrevving
				else if (weaponState == 0 && sequence == 23) {		// Are we unrevving?
					int bDone = GetEntProp(view, Prop_Data, "m_bSequenceFinished");
					if (bDone == 0) SetEntProp(view, Prop_Data, "m_bSequenceFinished", true, .size = 1);

					if(cycle < 0.2) {		//set idle time faster
						SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle",GetGameTime() + 1.0);
					}
					float fAnimSpeed = 2.0;
					SetEntPropFloat(view, Prop_Send, "m_flPlaybackRate", fAnimSpeed);		//speed up animation
				}
				
				
				// Adjust damage, accuracy and movement speed dynamically as we shoot
				if (weaponState == 2) {
					if (players[iClient].fSpeed > 0.0) {		// If we're firing but the speed meter isn't empty...
						players[iClient].fSpeed = players[iClient].fSpeed - 0.015;		// It takes us 67 frames (1 second) to fully deplete the meter
					}
				}
				
				else {	// If we're not firing...
					if (players[iClient].fSpeed < 1.005) {
						players[iClient].fSpeed = players[iClient].fSpeed + 0.015;		// Unlike fRev, fSpeed regenerates back up slowly
					}
				}
				
				
				TF2Attrib_SetByDefIndex(iPrimary, 106, RemapValClamped(players[iClient].fRev, 0.0, 1.005, 1.0, 2.0) * RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 1.0, 1.5));		// Spread bonus
				TF2Attrib_SetByDefIndex(iPrimary, 2, RemapValClamped(players[iClient].fRev, 0.0, 1.005, 1.0, 2.0) * RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 1.0, 0.666666));		// Damage bonus
				TF2Attrib_SetByDefIndex(iClient, 54, RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 0.5, 1.0));		// Speed
				
				if (!TF2_IsPlayerInCondition(iClient, TFCond_Slowed)) {		// Base speed buff
					if (TF2_IsPlayerInCondition(iClient, TFCond_SpeedBuffAlly)) {
						SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 336.0);
					}
					else {
						SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 240.0);
					}
				}
			}
			
			// Medic
			else if (TF2_GetPlayerClass(iClient) == TFClass_Medic) {
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int iClip = GetEntData(iPrimary, iAmmoTable, 4);		// We can detect shots by checking ammo changes
				if (iClip == (players[iClient].iSyringe_Ammo - 1)) {		// We update iSyringe_Ammo after this check, so iClip will always be 1 lower on frames in which we fire a shot
					float vecAng[3];
					GetClientEyeAngles(iClient, vecAng);
					Syringe_PrimaryAttack(iClient, iPrimary, vecAng);
				}
				players[iClient].iSyringe_Ammo = iClip;
				
				// Disables Medic speed matching
				if (TF2_IsPlayerInCondition(iClient, TFCond_SpeedBuffAlly)) {
					SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 432.0);
				}
				else {
					SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 320.0);
				}
				
				// Passive Uber build (0.625%/sec base)
				float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
				if (fUber < 1.0 && !(TF2_IsPlayerInCondition(iClient, TFCond_Ubercharged) || TF2_IsPlayerInCondition(iClient, TFCond_Kritzkrieged))) {		// Disble this when Ubered
					if (iSecondaryIndex == 35) {		// Kritzkreig
						fUber += 0.0001166;
					}
					else {
						fUber += 0.00009328;		// This is being added every *tick*
					}
					SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber);
				}
			}
			
			// Sniper
			else if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
				float fCharge = GetEntPropFloat(iPrimary, Prop_Send, "m_flChargedDamage");
				TF2Attrib_SetByDefIndex(iClient, 54, RemapValClamped(fCharge, 0.0, 150.0, 1.0, 0.6));	// Lower movement speed as the weapon charges
			}
			
			// Spy
			else if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
				// Spy sprint
				if (TF2_IsPlayerInCondition(iClient, TFCond_Disguised) && !TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
					if (iActive != iSecondary) {		// Are we holding something other than the revolver?
						if (TF2_IsPlayerInCondition(iClient, TFCond_SpeedBuffAlly)) {
							SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 432.0);
						}
						else {
							SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 320.0);
						}
					}
					else {
						int class = GetEntProp(iClient, Prop_Send, "m_nDisguiseClass");		// Else, return us to normal disguise speed
						TFClassType disguiseClass = view_as<TFClassType>(class);
						float speed = 320.0;
						switch(disguiseClass)
						{
							case TFClass_Pyro, TFClass_Engineer, TFClass_Sniper:
								speed = 300.0;
							case TFClass_DemoMan:
								speed = 280.0;
							case TFClass_Soldier, TFClass_Heavy:
								speed = 240.0;
						}
						if (TF2_IsPlayerInCondition(iClient, TFCond_SpeedBuffAlly)) {
							speed += 105;
						}
						SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", speed);
					}
				}
				
				float fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
				
				// Determines when we're in the cloaking animation
				if (TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
					players[iClient].fCloak_Timer += 0.015;
					if (players[iClient].fCloak_Timer > 1.0) {
						players[iClient].fCloak_Timer = 1.0;
						SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak + 0.149254);		// This is how much cloak we normally drain per frame
					}
				}
				else {
					players[iClient].fCloak_Timer = 0.0;
				}

				// Cloak debuff resistance
				if (players[iClient].fCloak_Timer >= 1.0) {
					bool debuffed = false;
					if (TF2Util_GetPlayerBurnDuration(iClient) > 2.0) {		// For all debuffs, if they are longer than two seconds, lower them down to this value
						TF2Util_SetPlayerBurnDuration(iClient, 2.0);
						debuffed = true;
					}
					if (TF2_IsPlayerInCondition(iClient, TFCond_Jarated)) {
						if (TF2Util_GetPlayerConditionDuration(iClient, TFCond_Jarated) > 2.0)
						TF2Util_SetPlayerConditionDuration(iClient, TFCond_Jarated, 2.0);
						debuffed = true;
					}
					if (TF2_IsPlayerInCondition(iClient, TFCond_Milked)) {
						if (TF2Util_GetPlayerConditionDuration(iClient, TFCond_Milked) > 2.0)
						TF2Util_SetPlayerConditionDuration(iClient, TFCond_Milked, 2.0);
						debuffed = true;
					}
					if (TF2_IsPlayerInCondition(iClient, TFCond_Gas)) {
						if (TF2Util_GetPlayerConditionDuration(iClient, TFCond_Gas) > 2.0)
						TF2Util_SetPlayerConditionDuration(iClient, TFCond_Gas, 2.0);
						debuffed = true;
					}
					
					if (debuffed == true) {
						SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak - 0.149254);	// mult cloak meter consume rate (doubled)
					}
				}
			
				// Hitscan accuracy
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int iClip = GetEntData(iSecondary, iAmmoTable, 4);		// We can detect shots by checking ammo changes
				if (iClip == (players[iClient].iHitscan_Ammo - 1)) {		// We update iHitscan_Ammo after this check, so iClip will always be 1 lower on frames in which we fire a shot
					players[iClient].fHitscan_Accuracy += 1.25;
				}
				players[iClient].iHitscan_Ammo = iClip;
				
				// > Clamping
				if (players[iClient].fHitscan_Accuracy > 1.25) {
					players[iClient].fHitscan_Accuracy = 1.25;
				}
				else if (players[iClient].fHitscan_Accuracy < 0.0) {
					players[iClient].fHitscan_Accuracy = 0.0;
				}
				
				if (players[iClient].fHitscan_Accuracy > 0.0) {	
					int time = RoundFloat(players[iClient].fHitscan_Accuracy * 1000);
					if (time%90 == 0) {		// Only adjust accuracy every so often
						TF2Attrib_SetByDefIndex(iSecondary, 106, RemapValClamped(players[iClient].fHitscan_Accuracy, 0.0, 1.25, 0.0001, 1.25));		// Spread bonus
					}
				}
			}
		}
	}
}

	// -={ Handles data filtering when performing traces (taken from Bakugo) }=-

bool TraceFilter_ExcludeSingle(int entity, int contentsmask, any data) {
	return (entity != data);
}


public void OnEntityCreated(int iEnt, const char[] classname) {
	if(IsValidEdict(iEnt)) {
		if (StrEqual(classname,"obj_sentrygun") || StrEqual(classname,"obj_dispenser") || StrEqual(classname,"obj_teleporter")) {
			entities[iEnt].fConstruction_Health = 0.0;
			SDKHook(iEnt, SDKHook_SetTransmit, BuildingThink);
			SDKHook(iEnt, SDKHook_OnTakeDamage, BuildingDamage);
		}
		
		else if(StrEqual(classname, "tf_projectile_rocket")) {
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}
		
		else if(StrEqual(classname, "tf_projectile_syringe")) {
			SDKHook(iEnt, SDKHook_SpawnPost, needleSpawn);
		}
	}
}

	// -={ Sniper Rifle headshot hit registration }=-

Action TraceAttack(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& ammo_type, int hitbox, int hitgroup) {		// Need this for noscope headshot hitreg
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {
		if (hitgroup == 1 && (TF2_GetPlayerClass(attacker) == TFClass_Sniper)) {		// Hitgroup 1 is the head
			players[attacker].iHeadshot_Frame = GetGameTickCount();		// We store headshot status in a variable for the next function to read
		}
	}
	return Plugin_Continue;
}


	/* -={ Modifies damage }=-
	* Deals with altered ramp-up/fall-off
	* Applies THREAT modifiers
	* Handles Sniper Rifle headshots and charge damage */

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients && victim != attacker) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			float vecAttacker[3];
			float vecVictim[3];
			GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
			GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
			float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
			float fDmgMod = 1.0;		// Distance mod
			float fDmgModTHREAT = 1.0;	// THREAT mod
			
			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if ((StrEqual(class, "tf_weapon_scattergun") || StrEqual(class, "tf_weapon_soda_popper") || StrEqual(class, "tf_weapon_pep_brawler_blaster")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Scale the ramp-up down to 150%
				}
			}

			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if ((StrEqual(class, "tf_weapon_rocketlauncher") || StrEqual(class, "tf_weapon_rocketlauncher_airstrike") || StrEqual(class, "tf_weapon_particle_cannon")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 150%
				}
			}
			
			// Pyro
			if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				if (StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge")) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier
					if (damage_type & DMG_CRIT != 0 && !isKritzed(attacker)) {		// Remove Crits on burning players
						damage_type = (damage_type & ~DMG_CRIT);
						damage /= 3.0;
						if (TF2Util_GetPlayerBurnDuration(victim) > 0.0) {		// Add a Mini-Crit instead
							TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015, 0);		// Applies a Mini-Crit
							damage *= 1.35;
							if (fDistance > 512.0) {
								fDmgMod = 1.0;
							}
						}
					}
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
					if (fDistance < 512.0) {
						SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.7) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Scale the ramp-up up to 140%
					}
					else {
						SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Scale the fall-off up to 75%
					}
				}
			}
			
			// Medic
			if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {
					if (!isKritzed(attacker)) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our ramp-up/fall-off multiplier (+/- 20%)
						if (isMiniKritzed(attacker, victim) && fDistance > 512.0) {
							fDmgMod = 1.0;
						}
					}
					else {
						fDmgMod = 3.0;
						damage_type |= DMG_CRIT;
					}
					fDmgMod *= 0.4;	// I don't know why, but syringes do way too much damage if we don't have this
				}
			}
			
			// Sniper
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
				// Rifle custom ramp-up/fall-off and Mini-Crit headshot damage
				if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {
					
					damage = 50.0;		// We're overwriting the Rifle charge behaviour so we manually set the baseline damage here
					float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
					if (fCharge == 150.0) {		// Apply equivalent of two 50% damage bonuses when fully charged
						damage = 113.0;
					}
					else {
						fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 1.5);		// Else, apply up to 50% bonus damage depending on charge
						damage *= fDmgMod;
					}
					
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier
					
					if (players[attacker].iHeadshot_Frame == GetGameTickCount()) {		// Here we look at headshot status
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015);		// Applies a Mini-Crit
						fDmgMod *= 1.35;
						damagecustom = TF_CUSTOM_HEADSHOT;		// No idea if this does anything, honestly
						if (fDistance > 512.0) {
							fDmgMod = 1.35;
						}
					}
				}
			}
			
			// Spy
			if (TF2_GetPlayerClass(attacker) == TFClass_Spy) {
				if (StrEqual(class, "tf_weapon_revolver") && fDistance < 512.0) {		// Scale ramp-up down to 120
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				}
			}
			
			if (isKritzed(attacker) && !StrEqual(class, "tf_weapon_syringegun_medic")) {	// No modified ramp-up for Crits (ignore Syringe Gun as we've already handled it)
				fDmgMod = 1.0;
			}
			else if (isMiniKritzed(attacker, victim) && !StrEqual(class, "tf_weapon_syringegun_medic")) {
				if (fDmgMod < 1.0) {		// Remove fall-off on Mini-Crits
					fDmgMod = 1.0;
				}
			}
			
			if (StrEqual(class, "tf_weapon_knife")) {
				if (damagecustom == TF_CUSTOM_BACKSTAB) {	// If we get a backstab...
					damage = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, victim) * 1.25;		// Override damage to 125% of victim's max health
				}
			}
			
			damage *= fDmgMod;		// This applies *all* ramp-up/fall-off modifications for all classes
			
			// THREAT modifier
			if (players[attacker].fTHREAT > 0.0 && !isKritzed(attacker)) {
				// Apply THREAT modifiers
				if (		// List of all weapon archetypes with standard ramp-up/fall-off
				// Multi-class
				StrEqual(class, "tf_weapon_shotgun") ||
				StrEqual(class, "tf_weapon_pistol") ||
				// Scout
				StrEqual(class, "tf_weapon_scattergun") ||
				StrEqual(class, "tf_weapon_soda_popper") ||
				StrEqual(class, "tf_weapon_pep_brawler_blaster") ||
				StrEqual(class, "tf_weapon_handgun_scout_primary") ||
				StrEqual(class, "tf_weapon_handgun_scout_secondary") ||
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher") ||
				StrEqual(class, "tf_weapon_rocketlauncher_directhit") ||
				StrEqual(class, "tf_weapon_rocketlauncher_airstrike") ||
				StrEqual(class, "tf_weapon_particle_cannon") ||
				StrEqual(class, "tf_weapon_raygun") ||
				StrEqual(class, "tf_weapon_shotgun_soldier") ||
				// Pyro
				StrEqual(class, "tf_weapon_shotgun_pyro") ||
				StrEqual(class, "tf_weapon_flaregun") ||
				StrEqual(class, "tf_weapon_flaregun_revenge") ||
				// Heavy
				StrEqual(class, "tf_weapon_minigun") ||
				StrEqual(class, "tf_weapon_shotgun_hwg") ||
				// Engineer
				StrEqual(class, "tf_weapon_shotgun_primary") ||
				StrEqual(class, "tf_weapon_sentry_revenge") ||
				StrEqual(class, "tf_weapon_shotgun_building_rescue") ||
				StrEqual(class, "tf_weapon_drg_pomson") ||
				// Sniper
				StrEqual(class, "tf_weapon_sniperrifle") ||
				StrEqual(class, "tf_weapon_smg")) {
					
					if (fDistance < 512.0) {
						// The formula for this is (max_rampup_mult/rampup_falloff_mod - 1) * THREAT_proportion + 1
						// First, we figure out what number we have to multiply the ramp-up multiplier for any given distance to give the max ramp-up amount. 
						// Then, we subtract 1 to only get the extra damage. We scale the extra damage amount by the amount of THREAT we have. 
						// Finally, we re-add 1 to get the multiplier.
						// Simple!
						fDmgModTHREAT = (1.5/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					
					else {
						// This is just a scaling linear multiplier
						fDmgModTHREAT = RemapValClamped(fDistance, 512.0, 1024.0, 0.5, 0.0) * players[attacker].fTHREAT/1000 + 1.0;
					}
					
					if (StrEqual(class, "tf_weapon_sniperrifle") && fDistance > 512.0 && players[attacker].iHeadshot_Frame == GetGameTickCount()) {	// Standardise the multiplier for headshots
						fDmgModTHREAT = 0.5 * players[attacker].fTHREAT/1000 + 1;
					}
				}
				
				else if (		// List of all weapon archetypes with atypical ramp-up and/or fall-off
				// Demoman
				StrEqual(class, "tf_weapon_pipebomblauncher")) {	// +40
					if (fDistance < 512.0) {
						fDmgModTHREAT = (1.4/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.7) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					
					else {
						fDmgModTHREAT = RemapValClamped(fDistance, 512.0, 1024.0, 0.4, 0.0) * players[attacker].fTHREAT/1000 + 1.0;
					}
				}
				else if (
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher_directhit") ||	// +20
				// Medic
				StrEqual(class, "tf_weapon_syringegun_medic") ||
				// Spy
				StrEqual(class, "tf_weapon_revolver")) {
					if (fDistance < 512.0) {
						fDmgModTHREAT = (1.2/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					
					else {
						fDmgModTHREAT = RemapValClamped(fDistance, 512.0, 1024.0, 0.2, 0.0) * players[attacker].fTHREAT/1000 + 1.0;
					}
				}
				
				// Melee
				else if ((damage_type & DMG_CLUB || damage_type & DMG_SLASH) && !StrEqual(class, "tf_weapon_knife")) {		// Handle melee damage (excluding knives)
					fDmgModTHREAT = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 1.0, 1.5);		// TODO: lower this for melees with intrinsic damage bonuses
				}
				
				if (isMiniKritzed(attacker, victim)) {
					if (fDistance > 512.0) {
						fDmgModTHREAT = 0.5 * players[attacker].fTHREAT/1000 + 1;
					}
				}
				
				//PrintToChat(attacker, "THREAT mod: %f", fDmgModTHREAT);
				damage *= fDmgModTHREAT;
				//PrintToChat(attacker, "Damage: %f", damage); 
			}
		}
	}
	
	return Plugin_Changed;
}


public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damage_type, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients && victim != attacker) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			// Add THREAT
			players[attacker].fTHREAT += damage;		// Add THREAT
			if (players[attacker].fTHREAT > 1000.0) {
				players[attacker].fTHREAT = 1000.0;
			}
			players[attacker].fTHREAT_Timer += damage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
			
			// Reduce Medi-Gun healing on victim
			players[victim].fHeal_Penalty = 5.0;
			TF2Attrib_AddCustomPlayerAttribute(victim, "health from healers reduced", 0.5);
			
			// Scout
			if (TF2_GetPlayerClass(victim) == TFClass_Scout) {
				if (!(GetEntityFlags(victim) & FL_ONGROUND)) {
					players[victim].fAirjump += damage;		// Records the damage we take while airborne (resets on landing; handled in OnGameFrame)
				}
			}
		}
	}
}


	// -={ Generates Uber from healing }=-

public Action OnPlayerHealed(Event event, const char[] name, bool dontBroadcast) {
	int iPatient = GetClientOfUserId(event.GetInt("patient"));
	int iHealer = GetClientOfUserId(event.GetInt("healer"));
	int iHealing = event.GetInt("amount");

	if (iPatient >= 1 && iPatient <= MaxClients && iHealer >= 1 && iHealer <= MaxClients && iPatient != iHealer) {
		if (TF2_GetPlayerClass(iHealer) == TFClass_Medic) {
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iHealer, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
			if (iSecondaryIndex == 35) {		// Kritzkreig
				fUber += iHealing * 0.00125;		// Add this to our Uber amount (multiply by 0.001 as 1 HP -> 1%, and Uber is stored as a 0 - 1 proportion)
			}
			else {
				fUber += iHealing * 0.001;
			}
			if (fUber > 1.0) {
				SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", 1.0);
			}
			else {
				SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber);
			}
		}
	}

	return Plugin_Continue;
}


public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);

		// Pistol autoreload
		char class[64];
		GetEntityClassname(iSecondary, class, sizeof(class));
		
		if (StrEqual(class, "tf_weapon_pistol")) {
			if (iActive != weapon) {		// Are we swapping weapons?
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our secondary
				
				int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
				int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
				
				if (clip < 12 && ammoCount > 0) {
					CreateTimer(1.005, AutoreloadPistol, iClient);
				}
			}
		}

		// Medic
		// Syringe Gun autoreload
		else if (TF2_GetPlayerClass(iClient) == TFClass_Medic) {
			if (iActive != weapon) {		// Are we swapping weapons?
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our secondary
				
				int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
				int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
				
				if (clip < 50 && ammoCount > 0) {
					CreateTimer(1.6, AutoreloadSyringe, iClient);
				}
			}
		}
	}
	return Plugin_Continue;
}

Action AutoreloadPistol(Handle timer, int iClient) {
	int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
	
	if (iActive == iSecondary) {
		return Plugin_Handled;
	}
	
	int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
	int clip = GetEntData(iSecondary, iAmmoTable, 4);
	
	int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
	int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
	
	int diff;		// If we have less than 12 bullets in reserve, make sure to only load in that many
	if (ammoCount < 12 - clip) {
		diff = ammoCount;
	}
	else {
		diff = 12 - clip;
	}
	
	if (clip < 12) {
		SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - (12 - clip) , _, primaryAmmo);
		SetEntData(iSecondary, iAmmoTable, clip + diff, 4, true);
	}
	return Plugin_Handled;
}

Action AutoreloadSyringe(Handle timer, int iClient) {
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");		// Recheck everything so we don't perform the autoreload if the weapon is out
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		
		if (iActive == iPrimary) {
			return Plugin_Handled;
		}
		
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iPrimary, iAmmoTable, 4);
		
		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
		
		if (clip < 50 && ammoCount > 0) {
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - (50 - clip) , _, primaryAmmo);
			SetEntData(iPrimary, iAmmoTable, 50, 4, true);
		}
	}
	return Plugin_Handled;
}

public void Syringe_PrimaryAttack(int iClient, int iPrimary, float vecAng[3]) {
	int iSyringe = CreateEntityByName("tf_projectile_syringe");
	
	if (iSyringe != -1) {
		int team = GetClientTeam(iClient);
		float vecPos[3], vecVel[3],  offset[3];
		
		GetClientEyePosition(iClient, vecPos);
		
		offset[0] = (1.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		offset[1] = (-1.0 * Cosine(DegToRad(vecAng[1])));
		offset[2] = -2.5;
		
		vecPos[0] += offset[0];
		vecPos[1] += offset[1];
		vecPos[2] += offset[2];

		if (isKritzed(iClient)) EmitAmbientSound("weapons/syringegun_shoot_crit.wav", vecPos, iClient);
		else EmitAmbientSound("weapons/syringegun_shoot.wav", vecPos, iClient);
		
		SetEntPropEnt(iSyringe, Prop_Send, "m_hOwnerEntity", iClient);	// Attacker
		SetEntPropEnt(iSyringe, Prop_Send, "m_hLauncher", iPrimary);	// Weapon
		SetEntProp(iSyringe, Prop_Data, "m_iTeamNum", team);		// Team
		SetEntProp(iSyringe, Prop_Send, "m_iTeamNum", team);
		SetEntProp(iSyringe, Prop_Data, "m_CollisionGroup", 24);		// Collision
		SetEntProp(iSyringe, Prop_Data, "m_usSolidFlags", 0);
		SetEntProp(iSyringe, Prop_Data, "m_nSkin", team - 2);		// Skin
		SetEntProp(iSyringe, Prop_Send, "m_nSkin", team - 2);
		SetEntPropVector(iSyringe, Prop_Data, "m_angRotation", vecAng);		// Orientation of model
		SetEntityModel(iSyringe, "models/weapons/w_models/w_syringe_proj.mdl"); // Model
		SetEntPropFloat(iSyringe, Prop_Data, "m_flGravity", 0.3);
		SetEntPropFloat(iSyringe, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iSyringe, Prop_Send, "m_flModelScale", 1.5);
		
		DispatchSpawn(iSyringe);
		
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 1200.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 1200.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -1200.0;

		TeleportEntity(iSyringe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
}


	// -={ Handles sticky destruction by explosives }=-

Action ProjectileTouch(int iProjectile, int other) {
	char class[64];
	GetEntityClassname(iProjectile, class, sizeof(class));
	
	if (StrEqual(class, "tf_projectile_rocket")) {		// Explosions destroy stickies
		if (other == 0) {		// If we hit the ground
			int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");
			float vecRocketPos[3];
			GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecRocketPos);
			
			// Iterate through all entities
			for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
                if (!IsValidEntity(iEnt)) continue; // Skip invalid entities

                // Check if the entity is a sticky bomb
                GetEntityClassname(iEnt, class, sizeof(class));
                if (StrEqual(class, "tf_projectile_pipe_remote")) {
                    int iStickyTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");

                    // Check if the sticky belongs to the opposing team
                    if (iStickyTeam != iProjTeam) {
                        float vecStickyPos[3];
                        GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecStickyPos);

                        // Check if the sticky is within the appropriate distance for the rocke to do 70 damage
                        if (GetVectorDistance(vecRocketPos, vecStickyPos) <= 102.2) {
                            AcceptEntityInput(iEnt, "Kill"); // Destroy the sticky
                        }
                    }
                }
			}
		}
	}
	return Plugin_Handled;
}


void needleSpawn(int entity) {
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	int team = GetEntProp(entity, Prop_Send, "m_iTeamNum");
	float ang[3];
	GetEntPropVector(entity, Prop_Data, "m_angRotation", ang);
	ang[0] = DegToRad(ang[0]); ang[1] = DegToRad(ang[1]); ang[2] = DegToRad(ang[2]);
	
	if (team == 2) {
		if (isKritzed(owner)) {
			CreateParticle(entity,"nailtrails_medic_red_crit",1.0,ang[0],ang[1],_,_,_,_,_,false);
		}
		else {
			CreateParticle(entity,"nailtrails_medic_red",1.0,ang[0],ang[1],_,_,_,_,_,false);
		}
	}
	if (team == 3) {
		if (isKritzed(owner)) {
			CreateParticle(entity,"nailtrails_medic_blue_crit",1.0,ang[0],ang[1],_,_,_,_,_,false);
		}
		else {
			CreateParticle(entity,"nailtrails_medic_blue",1.0,ang[0],ang[1],_,_,_,_,_,false);
		}
	}

	//SDKHook(entity, SDKHook_StartTouch, needleTouch);
}

Action BuildingDamage (int building, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3]) {
	char class[64];
	
	if (building >= 1 && IsValidEdict(building) && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {
			GetEntityClassname(weapon, class, sizeof(class));
			
			float vecAttacker[3];
			float vecBuilding[3];
			GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
			GetEntPropVector(building, Prop_Send, "m_vecOrigin", vecBuilding);		// Gets building position
			float fDistance = GetVectorDistance(vecAttacker, vecBuilding, false);		// Distance calculation
			float fDmgMod = 1.0;		// Distance mod
			float fDmgModTHREAT = 1.0;	// THREAT mod
			

			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if ((StrEqual(class, "tf_weapon_scattergun") || StrEqual(class, "tf_weapon_soda_popper") || StrEqual(class, "tf_weapon_pep_brawler_blaster")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Scale the ramp-up down to 150%
				}
			}

			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if ((StrEqual(class, "tf_weapon_rocketlauncher") || StrEqual(class, "tf_weapon_rocketlauncher_airstrike") || StrEqual(class, "tf_weapon_particle_cannon")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 150%
				}
			}
			
			// Pyro
			if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				if (StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge")) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
					if (fDistance < 512.0) {
						SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.7) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Scale the ramp-up up to 140%
					}
					else {
						SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Scale the fall-off up to 75%
					}
				}
			}
			
			// Medic
			if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our ramp-up/fall-off multiplier (+/- 20%)
					fDmgMod *= 0.4;	// I don't know why, but syringes do way too much damage if we don't have this
				}
			}
			
			// Sniper
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
				// Rifle custom ramp-up/fall-off and Mini-Crit headshot damage
				if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {
					
					damage = 50.0;		// We're overwriting the Rifle charge behaviour so we manually set the baseline damage here
					float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
					if (fCharge == 150.0) {		// Apply equivalent of two 50% damage bonuses when fully charged
						damage = 113.0;
					}
					else {
						fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 1.5);		// Else, apply up to 50% bonus damage depending on charge
						damage *= fDmgMod;
					}
					
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier
				}
			}
			
			// Spy
			if (TF2_GetPlayerClass(attacker) == TFClass_Spy) {
				if (StrEqual(class, "tf_weapon_revolver") && fDistance < 512.0) {		// Scale ramp-up down to 120
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				}
			}
			
			damage *= fDmgMod;		// This applies *all* ramp-up/fall-off modifications for all classes
			
			// THREAT modifier
			if (players[attacker].fTHREAT > 0.0 && !isKritzed(attacker)) {
				// Apply THREAT modifiers
				if (		// List of all weapon archetypes with standard ramp-up/fall-off
				// Multi-class
				StrEqual(class, "tf_weapon_shotgun") ||
				StrEqual(class, "tf_weapon_pistol") ||
				// Scout
				StrEqual(class, "tf_weapon_scattergun") ||
				StrEqual(class, "tf_weapon_soda_popper") ||
				StrEqual(class, "tf_weapon_pep_brawler_blaster") ||
				StrEqual(class, "tf_weapon_handgun_scout_primary") ||
				StrEqual(class, "tf_weapon_handgun_scout_secondary") ||
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher") ||
				StrEqual(class, "tf_weapon_rocketlauncher_directhit") ||
				StrEqual(class, "tf_weapon_rocketlauncher_airstrike") ||
				StrEqual(class, "tf_weapon_particle_cannon") ||
				StrEqual(class, "tf_weapon_raygun") ||
				StrEqual(class, "tf_weapon_shotgun_soldier") ||
				// Pyro
				StrEqual(class, "tf_weapon_shotgun_pyro") ||
				StrEqual(class, "tf_weapon_flaregun") ||
				StrEqual(class, "tf_weapon_flaregun_revenge") ||
				// Heavy
				StrEqual(class, "tf_weapon_minigun") ||
				StrEqual(class, "tf_weapon_shotgun_hwg") ||
				// Engineer
				StrEqual(class, "tf_weapon_shotgun_primary") ||
				StrEqual(class, "tf_weapon_sentry_revenge") ||
				StrEqual(class, "tf_weapon_shotgun_building_rescue") ||
				StrEqual(class, "tf_weapon_drg_pomson") ||
				// Sniper
				StrEqual(class, "tf_weapon_sniperrifle") ||
				StrEqual(class, "tf_weapon_smg")) {
					
					if (fDistance < 512.0) {
						// The formula for this is (max_rampup_mult/rampup_falloff_mod - 1) * THREAT_proportion + 1
						// First, we figure out what number we have to multiply the ramp-up multiplier for any given distance to give the max ramp-up amount. 
						// Then, we subtract 1 to only get the extra damage. We scale the extra damage amount by the amount of THREAT we have. 
						// Finally, we re-add 1 to get the multiplier.
						// Simple!
						fDmgModTHREAT = (1.5/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					
					else {
						// This is just a scaling linear multiplier
						fDmgModTHREAT = RemapValClamped(fDistance, 512.0, 1024.0, 0.5, 0.0) * players[attacker].fTHREAT/1000 + 1.0;
					}
					
					if (StrEqual(class, "tf_weapon_sniperrifle") && fDistance > 512.0 && players[attacker].iHeadshot_Frame == GetGameTickCount()) {	// Standardise the multiplier for headshots
						fDmgModTHREAT = 0.5 * players[attacker].fTHREAT/1000 + 1;
					}
				}
				
				else if (		// List of all weapon archetypes with atypical ramp-up and/or fall-off
				// Demoman
				StrEqual(class, "tf_weapon_pipebomblauncher")) {	// +40
					if (fDistance < 512.0) {
						fDmgModTHREAT = (1.4/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.7) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					
					else {
						fDmgModTHREAT = RemapValClamped(fDistance, 512.0, 1024.0, 0.4, 0.0) * players[attacker].fTHREAT/1000 + 1.0;
					}
				}
				else if (
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher_directhit") ||	// +20
				// Medic
				StrEqual(class, "tf_weapon_syringegun_medic") ||
				// Spy
				StrEqual(class, "tf_weapon_revolver")) {
					if (fDistance < 512.0) {
						fDmgModTHREAT = (1.2/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					
					else {
						fDmgModTHREAT = RemapValClamped(fDistance, 512.0, 1024.0, 0.2, 0.0) * players[attacker].fTHREAT/1000 + 1.0;
					}
				}
				
				// Melee
				else if ((damage_type & DMG_CLUB || damage_type & DMG_SLASH) && !StrEqual(class, "tf_weapon_knife")) {		// Handle melee damage (excluding knives)
					fDmgModTHREAT = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 1.0, 1.5);		// TODO: lower this for melees with intrinsic damage bonuses
				}
				
				damage *= fDmgModTHREAT;
			}
		}
		
		int seq = GetEntProp(building, Prop_Send, "m_nSequence");
		//reduce building health while constructing
		if(seq == 1)
		{
			entities[building].fConstruction_Health -= damage;
		}
	}
	
	// THREAT
	if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
		GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
		
		// Add THREAT
		players[attacker].fTHREAT += damage;		// Add THREAT
		if (players[attacker].fTHREAT > 1000.0) {
			players[attacker].fTHREAT = 1000.0;
		}
		players[attacker].fTHREAT_Timer += damage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
	}
	return Plugin_Changed;
}


Action BuildingThink(int building, int client) {
	char class[64];
	GetEntityClassname(building, class, 64);
	
	// update animation speeds for building construction
	float rate = RoundToFloor(GetEntPropFloat(building, Prop_Data, "m_flPlaybackRate") * 100) / 100.0;
	int sequence = GetEntProp(building, Prop_Send, "m_nSequence");

	if (rate > 0) {
		if ((StrEqual(class,"obj_teleporter") || StrEqual(class,"obj_dispenser")) && sequence == 1) {
			float cycle = GetEntPropFloat(building, Prop_Send, "m_flCycle");
			float cons = GetEntPropFloat(building, Prop_Send, "m_flPercentageConstructed");
			int maxHealth = GetEntProp(building, Prop_Send, "m_iMaxHealth");
			switch(rate) {
				case 0.50: { rate = 1.00; SetEntPropFloat(building, Prop_Send, "m_flPlaybackRate", 1.00);  } //not boosted
				case 1.25: { rate = 2.50; SetEntPropFloat(building, Prop_Send, "m_flPlaybackRate", 2.50);  } //wrench boost
				case 1.47: { rate = 2.94; SetEntPropFloat(building, Prop_Send, "m_flPlaybackRate", 2.94); } //jag boost
				case 0.87: { rate = 1.74; SetEntPropFloat(building, Prop_Send, "m_flPlaybackRate", 1.74); } //EE boost
				case 2.00: { rate = 4.00; SetEntPropFloat(building, Prop_Send, "m_flPlaybackRate", 4.00);  } //redeploy no boost
				case 2.75: { rate = 5.50; SetEntPropFloat(building, Prop_Send, "m_flPlaybackRate", 5.50);  } //redeploy boosted
			}
			if (rate != 3.60 || rate != 4.95) {	// if not redeployed
				if(GetEntProp(building, Prop_Send, "m_iHealth") < RoundFloat(entities[building].fConstruction_Health)) {
					SetVariantInt(1);
					AcceptEntityInput(building, "AddHealth");
				}
			}
			SetEntPropFloat(building, Prop_Send, "m_flPercentageConstructed",cycle*1.70 > 1.0 ? 1.0 : cycle*1.70);
			if (cons >= 1.00) {
				if (rate != 3.60 || rate != 4.95) SetEntProp(building, Prop_Send, "m_iHealth", maxHealth);
				SDKCall(g_hSDKFinishBuilding, building);
				RequestFrame(healBuild, building);
			}
			entities[building].fConstruction_Health += rate / 4.75;
		}
	}
	
	if (GetEntProp(building, Prop_Send, "m_iUpgradeLevel") == 1 && entities[building].iLevel <= 1) {
		if (entities[building].iLevel < 1) {
			entities[building].iLevel = 1;
		}
	}
	else if (GetEntProp(building, Prop_Send, "m_iUpgradeLevel") == 2 && entities[building].iLevel <= 2) {
		if (entities[building].iLevel < 2) {
			entities[building].iLevel = 2;
		}
	}
	else if (GetEntProp(building, Prop_Send, "m_iUpgradeLevel") == 3) {
		if (entities[building].iLevel < 3) {
			entities[building].iLevel = 3;
		}
	}
	
	if (entities[building].iLevel < GetEntProp(building, Prop_Send, "m_iUpgradeLevel")) {
		entities[building].iLevel = GetEntProp(building, Prop_Send, "m_iUpgradeLevel");
	}
	return Plugin_Continue;
}

void healBuild(int building)
{
	SetVariantInt(10);
	AcceptEntityInput(building,"AddHealth");
}


	// ==={{ Do not touch anything below this point }}===

	// -={ Displays particles (taken from ShSilver) }=-
	
	// -={ Particle stuff below }=-

stock int CreateParticle(int ent, char[] particleType, float time,float angleX=0.0,float angleY=0.0,float Xoffset=0.0,float Yoffset=0.0,float Zoffset=0.0,float size=1.0,bool update=true,bool parent=true,bool attach=false,float angleZ=0.0,int owner=-1) {
	int particle = CreateEntityByName("info_particle_system");

	char[] name = new char[64];

	if (IsValidEdict(particle)) {
		float position[3];
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", position);
		position[0] += Xoffset;
		position[1] += Yoffset;
		position[2] += Zoffset;
		float angles[3];
		angles[0] = angleX;
		angles[1] = angleY;
		angles[2] = angleZ;
		TeleportEntity(particle, position, angles, NULL_VECTOR);
		GetEntPropString(ent, Prop_Data, "m_iName", name, 64);
		DispatchKeyValue(ent, "targetname", name);
		DispatchKeyValue(particle, "targetname", "tf2particle");
		DispatchKeyValue(ent, "start_active", "0");
		DispatchKeyValue(particle, "parentname", name);
		DispatchKeyValue(particle, "effect_name", particleType);
		if(size!=-1.0) SetEntPropFloat(ent, Prop_Data, "m_flRadius",size);

		if(ent!=0) {
			if(parent) {
				SetVariantString(name);
				AcceptEntityInput(particle, "SetParent", particle, particle, 0);
			}
			
			else {
				SetVariantString("!activator");
				AcceptEntityInput(particle, "SetParent", ent, particle, 0);
			}
			
			if(attach) {
				SetVariantString("head");
				AcceptEntityInput(particle, "SetParentAttachment", particle, particle, 0);
			}
		}

		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "Start");

		if(owner!=-1) {
			SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", owner);
		}
		
		if(update) {
			DataPack pack = new DataPack();
			pack.Reset();
			pack.WriteCell(particle);
			pack.WriteCell(ent);
			pack.WriteFloat(time);
			pack.WriteFloat(Xoffset);
			pack.WriteFloat(Yoffset);
			pack.WriteFloat(Zoffset);
			CreateTimer(0.015, UpdateParticle, pack, TIMER_REPEAT);
		}
		else
			CreateTimer(time, DeleteParticle, particle);
	}
	return particle;
}

public Action DeleteParticle(Handle timer, int particle) {
	char[] classN = new char[64];
	if (IsValidEdict(particle))
	{
		GetEdictClassname(particle, classN, 64);
		if (StrEqual(classN, "info_particle_system", false))
			RemoveEdict(particle);
	}
	return Plugin_Continue;
}

public Action UpdateParticle(Handle timer, DataPack pack) {
	pack.Reset();
	int particle = pack.ReadCell();
	int parent = pack.ReadCell();
	float time = pack.ReadFloat();
	float Xoffset = pack.ReadFloat();
	float Yoffset = pack.ReadFloat();
	float Zoffset = pack.ReadFloat();
	static float timePassed[MAXPLAYERS+1];

	if(IsValidEdict(particle))
	{
		char[] classN = new char[64];
		GetEdictClassname(particle, classN, 64);
		if (StrEqual(classN, "info_particle_system", false))
		{
			if(IsValidClient(parent))
			{
				if(timePassed[parent] >= time)
				{
					timePassed[parent] = 0.0;
					RemoveEdict(particle);
					return Plugin_Stop;
				}
				else
				{
					float position[3];
					GetEntPropVector(parent, Prop_Send, "m_vecOrigin", position);
					position[0] += Xoffset;
					position[1] += Yoffset;
					position[2] += Zoffset;
					TeleportEntity(particle, position, NULL_VECTOR, NULL_VECTOR);
				}
				timePassed[parent] += 0.015;
			}
			else if(!IsValidEdict(parent))
			{
				CreateTimer(0.015, DeleteParticle, particle);
			}
		}
		else
			return Plugin_Stop;
	}
	else
		return Plugin_Stop;
	
	return Plugin_Continue;
}

stock bool IsValidClient(int iClient, bool replaycheck = true) {
	if (iClient <= 0 || iClient > MaxClients) return false;
	if (!IsClientInGame(iClient)) return false;
	return true;
}