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

#define DMG_MELEE DMG_BLAST_SURFACE		// Used for the Atomizer
#define TF_DMG_CUSTOM_BACKSTAB 2		// Used for detecting backstabs


	// -={ Stock functions -- taken from Valve themselves }=-
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


	// -={ Precaches audio }=-

public void OnMapStart() {
	PrecacheSound("misc/banana_slip.wav", true);
}


	// -={ Modifies attributes without needing to go through another plugin }=-

public Action TF2Items_OnGiveNamedItem(int iClient, char[] class, int index, Handle& item) {
	Handle item1;
	
	// Multi-class
	if (index == 415) {	// Reserve Shooter
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 106, 0.8); // weapon spread bonus (20%)
		TF2Items_SetAttribute(item1, 1, 3, 0.33); // clip size penalty (66%)
		TF2Items_SetAttribute(item1, 2, 114, 0.00); // mod mini-crit airborne (removed; we're handling this internally)
		TF2Items_SetAttribute(item1, 3, 547, 1.00); // single wep deploy time decreased (removed)
		TF2Items_SetAttribute(item1, 4, 1, 0.90); // damage penalty (10%)
	}
	
	// Scout (includes Engie Pistol)
	if (StrEqual(class, "tf_weapon_pistol")) {	// All Pistols
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 106, 0.7); // weapon spread bonus
	}
	
	if (index == 450) {	// Atomizer
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 1, 1.0); // damage penalty (removed)
		TF2Items_SetAttribute(item1, 1, 250, 0.0); // air dash count (disabled; we're handling this manually)
		TF2Items_SetAttribute(item1, 2, 773, 1.0); // single wep deploy time increased (removed)
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
		TF2Items_SetAttribute(item1, 1, 205, 0.05); // dmg from ranged reduced (15% reduction)
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
		TF2Items_SetAttribute(item1, 3, 676, 0.0); // lose demo charge on damage when charging (removed)
	}
	
	// Spy
	if (index == 460) {	// Enforcer
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 2, 1.20); // damage bonus (20%)
		TF2Items_SetAttribute(item1, 1, 5, 1.00); // fire rate penalty (removed
		TF2Items_SetAttribute(item1, 2, 410, 0.00); // damage bonus while disguised (removed)
		TF2Items_SetAttribute(item1, 3, 797, 0.00); // dmg pierces resists absorbs (removed)
	}
	
	if (index == 525) {	// Diamondback
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 3, 0.67); // clip size penalty (33%)
		TF2Items_SetAttribute(item1, 1, 296, 0.00); // sapper kills collect crits (removed)
	}
	
	if (index == 59) {	// Dead Ringer
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 33, 0.00); // set cloak is feign death (removed)
		TF2Items_SetAttribute(item1, 1, 83, 1.00); // cloak consume rate decreased (removed)
		TF2Items_SetAttribute(item1, 2, 84, 1.00); // cloak regen rate increased (removed)
		TF2Items_SetAttribute(item1, 3, 726, 0.00); // cloak_consume_on_feign_death_activate (removed)
		TF2Items_SetAttribute(item1, 4, 728, 1.00); // NoCloakWhenCloaked (added; this prevents cloak from ammo while active)
	}

	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}


	// -={ Preps all of the other functions }=-

enum struct Player {
	float fHitscan_Accuracy;		// Tracks dynamic accuracy on hitscan weapons
	int iHitscan_Ammo;				// Tracks ammo changeon hitscan weapons so we can determine when a shot is fired
	float fCrit_Status;			// Timer that counts down Crit status after a charge
	float fJuggle_Timer;			// Timer that counts down after taking explosive damage so we can (hopefully) tell when a player is launched airborne
	int iAirdash_Count;			// Tracks the number of double jumps performed by an Atomizer-wielder
}

Player players[MAXPLAYERS+1];


public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}


public void OnPluginStart() {
	// Catalogue of game events
	// https://wiki.alliedmods.net/Team_Fortress_2_Events
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("post_inventory_application", Event_PlayerSpawn);
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
		if(secondary > 0) secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
		
		int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);

		if (secondaryIndex == 406) {		// Splendid Screen
			TF2Attrib_SetByDefIndex(primary, 6, 0.85); // fire rate bonus (15%)
			TF2Attrib_SetByDefIndex(melee, 6, 0.85); // fire rate bonus (15%)
		}
	}
	return Plugin_Changed;
}


	// -={ Restores charge on Tide on kills with non-melees }=-

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast) {
	
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = event.GetInt("victim_entindex");
	int weaponIndex = event.GetInt("weapon_def_index");
	int inflict = event.GetInt("inflictor_entindex");
	//int iCritType = event.GetInt("crit_type");

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
			
			// Reserve Shooter
			if ((attacker != victim) && (players[victim].fJuggle_Timer > 0.0)) {		// Mini-Crit kill on another player
				if (weaponIndex == 415) {
					TF2Util_TakeHealth(attacker, 50.0);		// Heal on kill
				}
			}
			
			// Tide Turner
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

public void updateShield(DataPack pack) {
	pack.Reset();
	int iClient = pack.ReadCell();
	float fMeter = pack.ReadFloat();
	
	SetEntPropFloat(iClient, Prop_Send, "m_flChargeMeter", fMeter);
}


	// -={ Iterates every frame }=-
		// > Detects when shots are fired
			// Handles dynamic accuracy on Pistol and Revolver
			// Reduces cloak on Enforcer shot
		// > Ties Demo charge Crits to the Booties
		// > Handles Dead Ringer attributes
		// > Handles Diamondback conditional damage penalty

public void OnGameFrame() {
	int iClient;		// Index; lets us run through all the players on the server	

	for (iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
				
			int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int primaryIndex = -1;
			if(primary > 0) primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int secondaryIndex = -1;
			if(iSecondary > 0) secondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int meleeIndex = -1;
			if(melee > 0) meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
			
			int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
			int watchIndex = -1;
			if(iWatch > 0) watchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
			
			int iCurrent = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
			
			// Hitscan accuracy
			int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
			int iClip = GetEntData(iSecondary, iAmmoTable, 4);		// We can detect shots by checking ammo changes
			if (iClip == (players[iClient].iHitscan_Ammo - 1)) {		// We update iHitscan_Ammo after this check, so iClip will always be 1 lower on frames in which we fire a shot
				players[iClient].fHitscan_Accuracy += 0.50025;
				if (secondaryIndex == 460) {	// Enforcer
					
					float fCloak;
					fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
					SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak > 20.0 ? fCloak - 20.0 : 0.0);		// Subtract 20 cloak per shot
				}
			}
			players[iClient].iHitscan_Ammo = iClip;
			
			// > Clamping
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
				
				else if (secondaryIndex == 24 || secondaryIndex == 210 || secondaryIndex == 61 || secondaryIndex == 161 || secondaryIndex == 224 	// Do we have a Revolver equipped?
				|| secondaryIndex == 460 || secondaryIndex == 525 || secondaryIndex == 1006 || secondaryIndex == 1142 || secondaryIndex == 15011
				|| secondaryIndex == 15027 || secondaryIndex == 15042 || secondaryIndex == 15051 || secondaryIndex == 15062 || secondaryIndex == 15163
				|| secondaryIndex == 15063 || secondaryIndex == 15065 || secondaryIndex == 15103 || secondaryIndex == 15128 || secondaryIndex == 15127 || secondaryIndex == 15149) {
					int time = RoundFloat(players[iClient].fHitscan_Accuracy * 1000);
					if (time%90 == 0) {		// Only adjust accuracy every so often
						TF2Attrib_SetByDefIndex(iSecondary, 106, RemapValClamped(players[iClient].fHitscan_Accuracy, 0.0, 1.005, 0.0001, 0.1));		// Spread bonus
					}
				}
			}
			if (players[iClient].fJuggle_Timer > 0.0) {
				players[iClient].fJuggle_Timer -= 0.015;
			}
			
			// Scout
			if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
				// Atomizer
				if (meleeIndex == 450) {
				
					int airdash_value = GetEntProp(iClient, Prop_Send, "m_iAirDash");
					if (airdash_value > 0) {		// Did we double jump this frame?
						
						players[iClient].iAirdash_Count++;		// Count the double jump
						
						if (players[iClient].iAirdash_Count >= 1) {
							EmitSoundToAll("misc/banana_slip.wav", iClient, SNDCHAN_AUTO, 30, (SND_CHANGEVOL|SND_CHANGEPITCH), 1.0, 100);
							if (players[iClient].iAirdash_Count == 1) {		// Deal damage to us when double jumping
								SDKHooks_TakeDamage(iClient, iClient, iClient, 18.0, (DMG_MELEE|DMG_PREVENT_PHYSICS_FORCE), melee, NULL_VECTOR, NULL_VECTOR);	// This does 15 damage (no, I don't know why)
							}
						}
					}
					
					else {
						if ((GetEntityFlags(iClient) & FL_ONGROUND) != 0) {		// Reset the jump count when grounded
							players[iClient].iAirdash_Count = 0;
						}
					}
					
					if (airdash_value >= 1) {		// Reset the double jump variable to 0 if we haven't maxed out our double jumps yet
						if (players[iClient].iAirdash_Count < 2) {
							airdash_value = 0;
						}
					}
					
					if (airdash_value != GetEntProp(iClient, Prop_Send, "m_iAirDash")) {
						SetEntProp(iClient, Prop_Send, "m_iAirDash", airdash_value);
					}
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
				
				float fCharge = GetEntPropFloat(iClient, Prop_Send, "m_flChargeMeter");
				
				// Booties + Tide Turner case
				if (primaryIndex == 405 || primaryIndex == 608) {
					if (fCharge < 40.0  && TF2_IsPlayerInCondition(iClient, TFCond_Charging) && iCurrent == melee) {		// Are we eligible for a Crit?
						TF2_AddCondition(iClient, TFCond_CritOnFirstBlood, 0.35);		// We want a buffer so we still get Crits if the charge breaks by hitting an enemy
					}
				}
				// Hybrid-knight case
				else if (fCharge < 40.0  && TF2_IsPlayerInCondition(iClient, TFCond_Charging) && iCurrent == melee) {	// If we aren't recieving Crits from an external source, nulify our charge Crit
					if (!(TF2_IsPlayerInCondition(iClient, TFCond_Kritzkrieged) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnFirstBlood) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnWin) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnFlagCapture) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnKill) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnDamage))) {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "crits_become_minicrits", 1.0, 0.45);
					}
				}
			}
			
			// Spy
			// This section needs optimisation
			if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
				// Dead Ringer
				if (watchIndex == 59) {
					if (TF2_IsPlayerInCondition(iClient, TFCond_Cloaked) == true) {
						TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, 0.015, 0);		// Repeatedly adds a 1-frame speed buff while cloaked (this is a hackjob, but hopefully it works)
						TF2Attrib_AddCustomPlayerAttribute(iClient, "dmg from ranged reduced", 0.75);		// Add resistance (25% resist stacks with cloak base 20% to give 40%)
						TF2Attrib_AddCustomPlayerAttribute(iClient, "dmg from melee increased", 0.75);		// Ranged and melee resistances added separately
					}
					else {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "dmg from ranged reduced", 1.0);		// Remove resistance
						TF2Attrib_AddCustomPlayerAttribute(iClient, "dmg from melee increased", 1.0);
					}
				}
				
				// Diamondback
				if (secondaryIndex == 525) {
					if ((TF2_IsPlayerInCondition(iClient, TFCond_Kritzkrieged) ||		// Are we (Mini-)Crit boosted?
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnFirstBlood) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnWin) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnFlagCapture) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnKill) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritOnDamage) ||
						TF2_IsPlayerInCondition(iClient, TFCond_CritMmmph) || 
						TF2_IsPlayerInCondition(iClient, TFCond_MiniCritOnKill) || 
						TF2_IsPlayerInCondition(iClient, TFCond_Buffed) || 
						TF2_IsPlayerInCondition(iClient, TFCond_CritCola))) {
						
						TF2Attrib_SetByDefIndex(iSecondary, 1, 1.0);		// Remove damage penalty
					}
					
					else {
						TF2Attrib_SetByDefIndex(iSecondary, 1, 0.85);
					}
				}
			}
		}
	}
}


	// -={ Handles on-hit effects }=-
		// > Handles Reserve Shooter increased damage to airborne targets
		// > Prevents Tide Turner charge loss from taking damage
		// > Grants Mini-Crits on backstab for the Diamondback

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	
	if (IsClientInGame(attacker) && IsPlayerAlive(attacker) && IsClientInGame(victim) && IsPlayerAlive(victim)) {
	
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
		int secondaryIndex = -1;
		if (iSecondary > 0) secondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		
		// Reserve Shooter
		if ((damage_type & DMG_BLAST) && (TF2_GetClientTeam(victim) != TF2_GetClientTeam(attacker))) {
			players[victim].fJuggle_Timer = 1.5;		// 1.5 second timer
		}
		
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			char class[64];
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 415) {
				if (!(GetEntityFlags(victim) & FL_ONGROUND)) {
					//PrintToChatAll("Before Damage: %f", damage); 
					//damage *= 1.11;
					
					// We're doing this awfulness in the hopes that it makes the Mini-Crit actually work
					float vecAttacker[3];
					float vecVictim[3];
					float fDmgMod;
					GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
					GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
					float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our distance multiplier
					damage = damage * fDmgMod * 1.1;
					damage_type |= DMG_CRIT;
					
					//PrintToChatAll("After Damage: %f", damage); 
					if (players[victim].fJuggle_Timer > 0.0) {		// If our target has been launched into the air by an explosive, apply a Mini-Crit
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.001, 0);	
						//PrintToChatAll("Mini-Crit");
					}
				}
				return Plugin_Changed;
			}
		}
		
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
		
		// Diamondback
		if (secondaryIndex == 525) {
			if (damagecustom == TF_DMG_CUSTOM_BACKSTAB) {
				TF2_AddCondition(attacker, TFCond_CritCola, 5.0, 0);		// The Buff Banner Mini-Crit effect applies its icon, so we're using this instead
			}
		}
		return Plugin_Continue;
	}
}


	// -={ Dead Ringer cloak drain on use }=-

public void TF2_OnConditionAdded(int iClient, TFCond Condition) {

	float fCloak;

	int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
	int watchIndex = -1;
	if(iWatch > 0) watchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
	
	if (watchIndex == 59) {
		if (TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
			fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
			SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak / 2);
		}
	}
}