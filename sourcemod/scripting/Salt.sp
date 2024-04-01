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
		TF2Items_SetAttribute(item1, 0, 107, 1.1); // move speed bonus (10%; same as existing one)
		TF2Items_SetAttribute(item1, 1, 788, 1.0); // move speed bonus shield required (removed)
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
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 205, 0.90); // dmg from ranged reduced (10% reduction)
		TF2Items_SetAttribute(item1, 1, 206, 0.90); // dmg from melee increased (10% reduction)
		TF2Items_SetAttribute(item1, 2, 252, 0.90); // damage force reduction (10%)
	}
}


	// -={ Preps all of the other functions }=-

enum struct Player {
	float fHitscan_Accuracy;		// Tracks dynamic accuracy on hitscan weapons
	float fCrit_Status;			// Timer that counts down Crit status after a charge
}

Player players[MAXPLAYERS+1];


public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
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


	// -={ Pistol Dynamic Accuracy }=-

/*Action TraceAttack(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& ammo_type, int hitbox, int hitgroup) {
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {
		int iActive = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");		// Retrieve the active weapon
		char class[64];
		GetEntityClassname(iActive, class, sizeof(class));		// Retrieve the weapon
		
		if ((StrEqual(class, "tf_weapon_pistol"))) {		// Are we holding a Pistol?
			players[attacker].fHitscan_Accuracy += 0.50025;
		}
	}
	return Plugin_Continue;
}*/


/*
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if (client >= 1 && client <= MaxClients) {
		bool buttonsModified = false;
		if (weapon > 0) {
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Primary, true);		// Retrieve the primary weapon
			int primaryIndex = -1;
			if(iPrimary >= 0) primaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");		// Retrieve the primary weapon index for later
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Secondary, true);		// Retrieve the secondary weapon
			int secondaryIndex = -1;
			if(iSecondary >= 0) secondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");		// Retrieve the primary weapon index for later
			
			int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");		// Retrieve the active weapon
			int clientFlags = GetEntityFlags(client);
			
			// Pistol
			if ((TF2_GetPlayerClass(client) == TFClass_Scout) || (TF2_GetPlayerClass(client) == TFClass_Engineer)) {
				if(buttons & IN_ATTACK) {
					if (iActive == iSecondary) {
						players[client].fHitscan_Accuracy += 0.50025;
					}
				}
			}
		}
	}
	return Plugin_Continue;
}*/


public void OnGameFrame() {
	int iClient;		// Index; lets us run through all the players on the server	

	for (iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			//PrintToChatAll("Accuracy: %f", players[iClient].fHitscan_Accuracy);
			if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
				
				int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
				int primaryIndex = -1;
				if(primary > 0) primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
				int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
				int current = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
				
				if (players[iClient].fHitscan_Accuracy > 1.005) {
					players[iClient].fHitscan_Accuracy = 1.005;
				}
				else if (players[iClient].fHitscan_Accuracy < 0.0) {
					players[iClient].fHitscan_Accuracy = 0.0;
				}
				players[iClient].fHitscan_Accuracy -= 0.015;
				if (players[iClient].fHitscan_Accuracy > 0.0) {
					int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);		// Retrieve the secondary weapon
					if (iSecondary >= 0) {
						int time = RoundFloat(players[iClient].fHitscan_Accuracy * 1000);
						if (time%90 == 0) {		// Only adjust accuracy every so often
							TF2Attrib_SetByDefIndex(iSecondary, 106, RemapValClamped(players[iClient].fHitscan_Accuracy, 0.0, 1.005, 0.0001, 0.7));		// Spread bonus
						}
					}
				}
				
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


	// -={ Removes Crits when the Booties are unequipped }=-

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	
	/*if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			
			int primary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int primaryIndex = -1;
			if(primary > 0) primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
			int melee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
		}
	}*/
	
	// Tide Turner
	if (victim != attacker && (damage_type & DMG_FALL) == 0 && TF2_GetPlayerClass(victim) == TFClass_DemoMan && TF2_IsPlayerInCondition(victim, TFCond_Charging)) {
			
		if (GetEntProp(victim, Prop_Send, "m_iItemDefinitionIndex") == 1099) {
			float fCharge = GetEntPropFloat(victim, Prop_Send, "m_flChargeMeter");
			
			fCharge = (fCharge - damage);
			fCharge = (fCharge < 0.0 ? 0.0 : fCharge);
			
			SetEntPropFloat(victim, Prop_Send, "m_flChargeMeter", fCharge);
			
			return Plugin_Changed;
		}
	}
	return Plugin_Continue;
}


	// -={ Restores charge on Tide on kills with non-melees }=-

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	int victim = event.GetInt("victim_entindex");
	int weaponIndex = event.GetInt("weapon_def_index");

	if (victim > 0 && victim <= MaxClients && attacker > 0 && attacker <= MaxClients && IsClientInGame(victim) && IsClientInGame(attacker)) {		// Check that we have good data
		if (victim != attacker && GetEventInt(event, "inflictor_entindex") == attacker && IsPlayerAlive(attacker)) {		// Make sure if wasn't a finish off or feign
	
			int secondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			int secondaryIndex = -1;
			if (secondary >= 0) {
				secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
			}
			int melee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);		// Exclude melee weapons since this is already handled by the game
			int meleeIndex = -1;
			if(melee >= 0) meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
	
			if (secondaryIndex == 1099 && weaponIndex != meleeIndex) {		// Tide Turner
				float meter = GetEntPropFloat(attacker, Prop_Send,"m_flChargeMeter");
				if (meter + 25.0 > 100) meter = 100.0;
				else meter += 25.0;

				SetEntPropFloat(attacker, Prop_Send,"m_flChargeMeter", meter);		// Updates charge meter
			}
		}
	}
	return Plugin_Continue;
}


	// -={ Prevents charge loss from damage on the Tide Turner }=-
	
/*public void OnTakeDamage(int victim, int attacker, int inflictor, float damage, int damage_type, int weapon, const float damage_Force[3], const float damage_Position[3], int damage_custom) {
	if (victim != attacker && (damage_type & DMG_FALL) == 0 && TF2_GetPlayerClass(victim) == TFClass_DemoMan && TF2_IsPlayerInCondition(victim, TFCond_Charging)) {
			
		if (GetEntProp(victim, Prop_Send, "m_iItemDefinitionIndex") == 1099) {
			float fCharge = GetEntPropFloat(victim, Prop_Send, "m_flChargeMeter");
			
			fCharge = (fCharge - damage);
			fCharge = (fCharge < 0.0 ? 0.0 : fCharge);
			
			SetEntPropFloat(victim, Prop_Send, "m_flChargeMeter", fCharge);
		}
	}
}*/