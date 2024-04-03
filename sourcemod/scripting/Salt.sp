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


	// -={ Stock functions -- taken from Valve themselves }=-
	// https://github.com/ValveSoftware/source-sdk-2013/blob/master/sp/src/public/mathlib/mathlib.h#L648s

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


	// -={ Modifies attributes without needing to go through another plugin }=-

public Action TF2Items_OnGiveNamedItem(int client, char[] class, int index, Handle& item) {
	Handle item1;
	
	// Scout (includes Engie Pistol)
	if (StrEqual(class, "tf_weapon_pistol")) {	// All Pistols
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 106, 0.7); // weapon spread bonus (removed)
	}
	
	// Demoman
	if (index == 405 || index == 608) {	// Ali Baba's Wee Booties (& Bootlegger)
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 107, 1.10); // move speed bonus (10%; same as existing one)
		TF2Items_SetAttribute(item1, 1, 788, 1.00); // move speed bonus shield required (removed)
		TF2Items_SetAttribute(item1, 2, 252, 0.75); // damage force reduction (25%)
	}

	if (StrEqual(class, "tf_wearable_demoshield")) {	// All Shields
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 6);
		TF2Items_SetAttribute(item1, 0, 64, 1.0); // dmg taken from blast reduced (removed)
		TF2Items_SetAttribute(item1, 1, 60, 1.0); // dmg taken from fire reduced (removed)
		TF2Items_SetAttribute(item1, 2, 249, 1.15); // charge recharge rate increased (15%; reduces cooldown to 10 seconds)
		TF2Items_SetAttribute(item1, 3, 205, 0.75); // dmg from ranged reduced (25% reduction)
		TF2Items_SetAttribute(item1, 4, 206, 0.75); // dmg from melee increased (25% reduction, in spite of what the attribute says)
		TF2Items_SetAttribute(item1, 5, 252, 0.75); // damage force reduction (25%)
	}
	
	if (index == 406) {	// Splendid Screen
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 249, 1.0); // charge recharge rate increased (removed)
		TF2Items_SetAttribute(item1, 1, 205, 0.85); // dmg from ranged reduced (15% reduction)
		TF2Items_SetAttribute(item1, 2, 206, 0.85); // dmg from melee increased (15% reduction)
		TF2Items_SetAttribute(item1, 3, 252, 0.85); // damage force reduction (15%)
	}
	
	if (index == 1099) {	// Tide Turner
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 205, 0.90); // dmg from ranged reduced (10% reduction)
		TF2Items_SetAttribute(item1, 1, 206, 0.90); // dmg from melee increased (10% reduction)
		TF2Items_SetAttribute(item1, 2, 252, 0.90); // damage force reduction (10%)
		TF2Items_SetAttribute(item1, 3, 676, 0.0); // lose demo charge on damage when charging
	}
}


	// -={ Preps all of the other functions }=-

enum struct Player {
	float fHitscan_Accuracy;		// Tracks dynamic accuracy on hitscan weapons
	int iHitscan_Ammo;				// Tracks ammo changeon hitscan weapons so we can determine when a shot is fired
	float fCrit_Status;			// Timer that counts down Crit status after a charge
}

Player players[MAXPLAYERS+1];


public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}


public void OnPluginStart() {
	HookEvent("player_death", Event_PlayerDeath);	
}


public Action Event_PlayerSpawn(Handle hEvent, const char[] cName, bool dontBroadcast) {
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));

	char[] event = new char[64];
	GetEventName(hEvent,event,64);
	DataPack pack = new DataPack();
	pack.Reset();
	pack.WriteCell(iClient);
	pack.WriteString(event);
	float time=0.1;
	if(IsFakeClient(iClient)) time=0.25;
	CreateTimer(time,PlayerSpawn,pack);

	SetCommandFlags("r_screenoverlay", GetCommandFlags("r_screenoverlay") & ~FCVAR_CHEAT);
	ClientCommand(iClient, "r_screenoverlay \"\"");
	SetCommandFlags("r_screenoverlay", GetCommandFlags("r_screenoverlay") | FCVAR_CHEAT);
	return Plugin_Changed;
}


public Action PlayerSpawn(Handle timer, DataPack dPack) {
	dPack.Reset();
	int iClient = dPack.ReadCell();
	char[] event = new char[64];
	dPack.ReadString(event,64);

	if (iClient >= 1 && iClient <= MaxClients) {
		int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		int secondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int secondaryIndex = -1;
		if(secondary>0) secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
		int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);

		if (secondaryIndex == 406) {		// Splendid Screen
			TF2Attrib_SetByDefIndex(primary, 6, 0.85); // fire rate bonus (15%)
			TF2Attrib_SetByDefIndex(melee, 6, 0.85); // fire rate bonus (15%)
		}
	}
	return Plugin_Changed;
}


	// -={ Pistol Dynamic Accuracy; Demo Charge Crits }=-

public void OnGameFrame() {
	int iClient;		// Index; lets us run through all the players on the server	

	for (iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			//PrintToChatAll("Accuracy: %f", players[iClient].fHitscan_Accuracy);
			if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
				
				int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
				int primaryIndex = -1;
				if(primary > 0) primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
				
				int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
				int secondaryIndex = -1;
				if(iSecondary > 0) secondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
				
				int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
				
				int current = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
				
				// Hitscan accuracy
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int clip = GetEntData(iSecondary, iAmmoTable, 4);		// We can detect shots by checking ammo changes
				if (clip == (players[iClient].iHitscan_Ammo - 1)) {		// We update iHitscan_Ammo after this check, so clip will always be 1 lower on frames in which we fire a shot
					players[iClient].fHitscan_Accuracy += 0.50025;
				}
				players[iClient].iHitscan_Ammo = clip;
				
				// Clamping
				if (players[iClient].fHitscan_Accuracy > 1.005) {
					players[iClient].fHitscan_Accuracy = 1.005;
				}
				else if (players[iClient].fHitscan_Accuracy < 0.0) {
					players[iClient].fHitscan_Accuracy = 0.0;
				}
				
				if (players[iClient].fHitscan_Accuracy > 0.0) {
					if (secondaryIndex == 22 || secondaryIndex == 23 || secondaryIndex == 209 || secondaryIndex == 294 || secondaryIndex == 449 	// Do we have a Pistol equipped?
					|| secondaryIndex == 773 || secondaryIndex == 15013 || secondaryIndex == 15018 || secondaryIndex == 15035 || secondaryIndex == 15041
					|| secondaryIndex == 15046 || secondaryIndex == 15056 || secondaryIndex == 15060 || secondaryIndex == 15061 || secondaryIndex == 15100
					|| secondaryIndex == 15101 || secondaryIndex == 15102 || secondaryIndex == 15126 || secondaryIndex == 15148 || secondaryIndex == 15148 || secondaryIndex == 30666) {
						int time = RoundFloat(players[iClient].fHitscan_Accuracy * 1000);
						if (time%90 == 0) {		// Only adjust accuracy every so often
							TF2Attrib_SetByDefIndex(iSecondary, 106, RemapValClamped(players[iClient].fHitscan_Accuracy, 0.0, 1.005, 0.0001, 0.7));		// Spread bonus
						}
					}
				}
				players[iClient].fHitscan_Accuracy -= 0.015;
				
				// Demoman
				if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
					
					float fCharge = GetEntPropFloat(iClient, Prop_Send, "m_flChargeMeter");
					
					// Booties + Tide Turner case
					if (primaryIndex == 405 || primaryIndex == 608) {
						if (fCharge < 40.0  && TF2_IsPlayerInCondition(iClient, TFCond_Charging) && current == melee) {		// Are we eligible for a Crit
							TF2_AddCondition(iClient, TFCond_CritOnFirstBlood, 0.35);		// We want a buffer so we still get Crits if the charge breaks by hitting an enemy
						}
					}
					// Hybrid-knight case
					else if (fCharge < 40.0  && TF2_IsPlayerInCondition(iClient, TFCond_Charging) && current == melee) {	// If we aren't recieving Crits from an external source, nulify our charge Crit
						if (!(TF2_IsPlayerInCondition(iClient,TFCond_Kritzkrieged) ||
							TF2_IsPlayerInCondition(iClient,TFCond_CritOnFirstBlood) ||
							TF2_IsPlayerInCondition(iClient,TFCond_CritOnWin) ||
							TF2_IsPlayerInCondition(iClient,TFCond_CritOnFlagCapture) ||
							TF2_IsPlayerInCondition(iClient,TFCond_CritOnKill) ||
							TF2_IsPlayerInCondition(iClient,TFCond_CritOnDamage))) {
							TF2Attrib_AddCustomPlayerAttribute(iClient, "crits_become_minicrits", 1.0, 0.45);
						}
					}
				}
			}
		}
	}
}


	// -={ Removes Tide Turner charge loss from damage }=-

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	
	// Tide Turner
	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && victim > 0 && victim <= MaxClients && IsClientInGame(victim)) {
		if (victim != attacker && (damage_type & DMG_FALL) == 0 && TF2_GetPlayerClass(victim) == TFClass_DemoMan && TF2_IsPlayerInCondition(victim, TFCond_Charging)) {
		
			if (GetEntProp(victim, Prop_Send, "m_iItemDefinitionIndex") == 1099) {
				float fCharge = GetEntPropFloat(victim, Prop_Send, "m_flChargeMeter");
				
				fCharge = (fCharge + damage);
				fCharge = (fCharge < 0.0 ? 0.0 : fCharge);
				
				SetEntPropFloat(victim, Prop_Send, "m_flChargeMeter", fCharge);
				
				return Plugin_Changed;
			}
		}
	}
	return Plugin_Continue;
}


	// -={ Restores charge on Tide on kills with non-melees }=-

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast) {
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	int victim = event.GetInt("victim_entindex");
	int weaponIndex = event.GetInt("weapon_def_index");
	int inflict = event.GetInt("inflictor_entindex");

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)) {		// Check that we have good data
		if (victim != attacker) {		// Make sure if wasn't a finish off or feign
			int secondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			int secondaryIndex = -1;
			if (secondary >= 0) {
				secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
			}
			int melee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);		// Exclude melee weapons since this is already handled by the game
			int meleeIndex = -1;
			if(melee >= 0) meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
	
			if (secondaryIndex == 1099 && (weaponIndex != meleeIndex) || inflict == secondary) {		// Tide Turner
				float meter = GetEntPropFloat(attacker, Prop_Send,"m_flChargeMeter");
				if (meter + 75.0 > 100) meter = 100.0;
				else meter += 75.0;

				if (inflict == secondary) {		// We have to handle shield bash kills on a different frame, otherwise the charge breaking immediately undoes everything
					DataPack pack = new DataPack();
					pack.Reset();
					pack.WriteCell(attacker);
					pack.WriteFloat(meter);
					RequestFrame(updateShield,pack);
				}

				SetEntPropFloat(attacker, Prop_Send, "m_flChargeMeter", meter);		// Updates charge meter
			}
		}
	}
	return Plugin_Continue;
}

public void updateShield(DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();
	float meter = pack.ReadFloat();
	
	SetEntPropFloat(client, Prop_Send,"m_flChargeMeter",meter);
}