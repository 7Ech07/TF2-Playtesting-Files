#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2utils>
#include <tf2items>
//#include <tf2condhooks>
#include <tf2attributes>

#pragma newdecls required


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


	// -={ Preps the all of the other functions }=-

enum struct Player {
	int headshot_frame;		// checks for headshots later on
	int iHeads;		// Count Heads for the Sniper Rifle
	float fBleed_Timer;		// Counts how much Bleed is left on us from the Shiv
	float fBoosting;		// Stores BFB alt-fire boost duration
	float fAirtimeTrack;		// Tracks time spent parachuting
	bool bAudio;		// Tracks whether or not we've played the audio cue yet
	float parachute_cond_time;
}

Player players[MAXPLAYERS+1];

Handle cvar_ref_tf_parachute_aircontrol;


public void OnPluginStart() {
	cvar_ref_tf_parachute_aircontrol = FindConVar("tf_parachute_aircontrol");
		
	// This is used for clearing variables on respawn
	HookEvent("player_spawn", OnGameEvent, EventHookMode_Post);
}


public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_TraceAttack, TraceAttack);
	
	players[client].iHeads  = 0;
}


public void OnMapStart() {
	PrecacheSound("weapons/discipline_device_power_up.wav", true);
}


	// -={ Modifies attributes }=-

public Action TF2Items_OnGiveNamedItem(int client, char[] class, int index, Handle& item) {
	Handle item1;
	
	// Scout
	if (StrEqual(class, "tf_weapon_pep_brawler_blaster")) {		// BFB
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 1, 419, 0.001); // hype resets on jump (removed)
		TF2Items_SetAttribute(item1, 2, 733, 0.001); // lose hype on take damage (removed)
	}
	
	// Sniper
	if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {		// Sniper Rifle
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.8); // damage penalty (80%)
		TF2Items_SetAttribute(item1, 1, 75, 1.25); // aiming movespeed increased (+25%)
		TF2Items_SetAttribute(item1, 2, 90, 1.09); // SRifle charge rate increased (109%)
		TF2Items_SetAttribute(item1, 3, 76, 0.56); // maxammo primary decreased (-44%, 14 rounds left)
	}
	
	if (StrEqual(class, "tf_weapon_sniperrifle_decap")) {		// The Bazaar Bargain specifically
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.8); // damage penalty (80%)
		TF2Items_SetAttribute(item1, 1, 75, 2.5); // aiming movespeed increased (+250%)
		TF2Items_SetAttribute(item1, 2, 90, 1.935); // SRifle charge rate increased (193.5%)
		TF2Items_SetAttribute(item1, 3, 46, 1.667); // sniper zoom penalty (~40% reduced zoom)
	}
	
	if (StrEqual(class, "tf_weapon_club")) {		// All of Sniper's melees
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 1, 0.731); // damage penalty (-26.9%)
		TF2Items_SetAttribute(item1, 1, 6, 0.75); // fire rate bonus (-25%; 0.25 sec)
	}
	
	if (StrEqual(class, "tf_weapon_smg")) {		// SMG (the Carbine is a different archetype)
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.25); // damage bonus (+25%)
		TF2Items_SetAttribute(item1, 1, 96, 1.3636); // reload time increased (36.36%; 1.5 sec)
		TF2Items_SetAttribute(item1, 2, 397, 1.0); // projectile penetration heavy
	}
	
	if (index == 231) {		// Darwin's Danger Shield
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 26, 15.0); // max health additive bonus (15)
		TF2Items_SetAttribute(item1, 1, 60, 1.0); // dmg taken from fire reduced (removed)
		TF2Items_SetAttribute(item1, 2, 527, 0.0); // afterburn immunity (removed)
	}
	
	if (index == 171) {		// The Tribalman's Shiv specifically
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 6, 0.875); // fire rate bonus (-12.5%; half of stock)
		TF2Items_SetAttribute(item1, 1, 772, 1.3); // single wep holster time increased (30%)
		TF2Items_SetAttribute(item1, 2, 149, 0.0); // bleeding duration (removed, because we're rebuilding this behaviour elsewhere)
	}
	
	/*if (index == 401) {		// The Shahanshah specifically
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 1.0); // damage penalty (removed)
		TF2Items_SetAttribute(item1, 1, 6, 1.0); // fire rate bonus (removed)
		TF2Items_SetAttribute(item1, 2, 224, 1.5); // damage bonus when half dead (the upside; increased to 50%)
		TF2Items_SetAttribute(item1, 3, 225, 1.0); // damage penalty when half alive (the downside; removed)
	}*/
	
	// Spy
	if (StrEqual(class, "tf_weapon_revolver")) {
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 51, 1.0); // revolver use hit locations
		TF2Items_SetAttribute(item1, 1, 97, 0.8826); // reload time decreased (+33.3%)
		TF2Items_SetAttribute(item1, 2, 107, 1.0654); // faster move speed on wearer (+33.3%)
	}

	if (StrEqual(class, "tf_weapon_knife")) {
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 2, 1.25); // damage bonus (25%)
		TF2Items_SetAttribute(item1, 1, 6, 0.75); // fire rate bonus (25%)
	}
	
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

/*
public Action Event_PlayerSpawn(Handle hEvent, const char[] cName, bool dontBroadcast) {
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	int meleeIndex = -1;
	if(melee >= 0) meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");

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
		int primaryIndex = -1;
		if(primary >= 0) primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
		int secondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int secondaryIndex = -1;
		if(secondary>0) secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
		int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
		int meleeIndex = -1;
		if(melee >= 0) meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");

		switch(TF2_GetPlayerClass(iClient)) {
			
			// Scout
			case TFClass_Scout: {
				switch(primaryIndex) {
					// Baby Face's Blaster
					case 772: {
						TF2Attrib_SetByDefIndex(primary, 419, 0.001); // hype resets on jump (removed; it must be a non-zero number else it won't work)
						TF2Attrib_SetByDefIndex(primary, 733, 0.001); // lose hype on take damage (removed)
					}
				}
			}
			
			// Sniper
			case TFClass_Sniper: {
				switch(primaryIndex) {
					// Sniper Rifle (all)
					case 14, 201, 230, 526, 664, 757, 792, 801, 851, 881, 890, 899, 908, 957, 966, 1098, 15000, 15007, 15019, 15023, 15033, 15059, 15080, 15071, 15072, 15111, 15112, 15135, 15136, 15154, 30665: {
						TF2Attrib_SetByDefIndex(primary, 1, 0.8); // damage penalty (80%)
						TF2Attrib_SetByDefIndex(primary, 75, 1.25); // aiming movespeed increased (+25%)
						TF2Attrib_SetByDefIndex(primary, 90, 1.09); // SRifle charge rate increased (109%)
						int primaryAmmo = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 12 , _, primaryAmmo);
					}
					
					// Bazaar Bargain
					case 402: {
						TF2Attrib_SetByDefIndex(primary, 1, 0.8); // damage penalty (80%)
						TF2Attrib_SetByDefIndex(primary, 75, 2.5); // aiming movespeed increased (+250%)
						TF2Attrib_SetByDefIndex(primary, 90, 1.935); // SRifle charge rate increased (193.5%)
						TF2Attrib_SetByDefIndex(primary, 46, 1.667); // sniper zoom penalty (~40% reduced zoom)
						int primaryAmmo = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 12 , _, primaryAmmo);
					}
				}
				
				switch(meleeIndex) {	
					// Kukri (and reskins)
					case 3, 193, 264, 423, 474, 880, 939, 954, 1013, 1071, 1123, 1127, 30758: {
						TF2Attrib_SetByDefIndex(melee, 1, 0.731); // damage penalty (-26.9%)
						TF2Attrib_SetByDefIndex(melee, 6, 0.75); // fire rate bonus (-25%; 0.25 sec)
					}
					
					// Tribalman's Shiv
					case 171: {
						TF2Attrib_SetByDefIndex(melee, 1, 0.5); // damage penalty (-50%)
						TF2Attrib_SetByDefIndex(melee, 6, 0.875); // fire rate bonus (-12.5%; half of stock)
						TF2Attrib_SetByDefIndex(melee, 772, 1.3); // single wep holster time increased (30%)
						TF2Attrib_SetByDefIndex(melee, 149, 0.0); // bleeding duration (removed, because we're rebuilding this behaviour elsewhere)
					}
					
					// Shahanshah
					case 401: {
						TF2Attrib_SetByDefIndex(melee, 1, 1.0); // damage penalty (removed)
						TF2Attrib_SetByDefIndex(melee, 6, 1.0); // fire rate bonus (removed)
						TF2Attrib_SetByDefIndex(melee, 224, 1.5); // damage bonus when half dead (the upside; increased to 50%)
						TF2Attrib_SetByDefIndex(melee, 225, 1.0); // damage penalty when half alive (the downside; removed)
					}
				}
			}
			
			// Spy
			case TFClass_Spy: {
				// Revolvers (all)
				if(secondary != -1) {
					TF2Attrib_SetByDefIndex(secondary, 51, 1.0); // revolver use hit locations
					TF2Attrib_SetByDefIndex(secondary, 97, 0.8826); // reload time decreased (+33.3%)
					TF2Attrib_SetByDefIndex(secondary, 107, 1.0654); // faster move speed on wearer (+33.3%)
				}
				
				// Knives (all)
				if(melee != -1) {
					TF2Attrib_SetByDefIndex(melee, 2, 1.25); // damage bonus (25%)
					TF2Attrib_SetByDefIndex(melee, 6, 0.75); // fire rate bonus (25%)
				}
			}
		}
	}
	return Plugin_Changed;
}
*/

	// -={ Sniper Rifle noscope headshot hit registration }=-

Action TraceAttack(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& ammo_type, int hitbox, int hitgroup) {		// Need this for noscope headshot hitreg
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {
		if (hitgroup == 1 && (TF2_GetPlayerClass(attacker) == TFClass_Sniper)) {		// Hitgroup 1 is the head
			players[attacker].headshot_frame = GetGameTickCount();		// We store headshot status in a variable for the next function to read
		}
	}
	return Plugin_Continue;
}


	// -={ Resets variables on death; sets Spy's collision hull }=-
	
Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {
	int client;
	
	if (StrEqual(name, "player_spawn")) {
		client = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsPlayerAlive(client)) {
			
			players[client].iHeads = 0;
			players[client].fBleed_Timer = 0;
			players[client].fBoosting = 0;
			
			if (TF2_GetPlayerClass(client) == TFClass_Spy) {		// Shrink Spy's colision hull
				// Normal collision hull dimensions are 49, 49 83
				// Or mins { -24.5, -24.5, 0.0 } maxs { 24.5, 24.5, 83.0 }
				SetEntPropVector(client, Prop_Send, "m_vecSpecifiedSurroundingMins", {-18.375, -18.375, 0.0});
				SetEntPropVector(client, Prop_Send, "m_vecSpecifiedSurroundingMaxs", {18.375, 18.375, 83.0});
			}
		}
	}
	return Plugin_Continue;
}


	// -={ Shortens debuff duration with the DDS equipped }=-

/*public Action TF2_OnAddCond(int iClient,TFCond &condition,float &time, int &provider) {
	// Sniper
	if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
		int secondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int secondaryIndex = -1;
		if(secondary>0) secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
		
		if (secondaryIndex == 231) {		// Darwin's Danger Shield
			switch(condition) {
				case TFCond_Jarated, TFCond_Bleeding, TFCond_Milked, TFCond_MarkedForDeath, TFCond_MarkedForDeathSilent, TFCond_Gas:	// Are we debuffed?
				{
					time *= 0.667;		// Shortens debuff durations by 33% (Afterburn has to be handled separately)
				}
			}
		}
	}
}*/


	// -={ Calculates damage }=-

Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& weapon, float damage_force[3], float damage_position[3], int damage_custom) {

	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			TFClassType tfAttackerClass = TF2_GetPlayerClass(attacker);
			switch(tfAttackerClass)
			{
				// Scout
				case TFClass_Scout: {
					int primary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
					int primaryIndex = -1;
					if (primary >= 0) {
						primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
					}
					
					if (primaryIndex == 772) {
						float vecAttacker[3];
						float vecVictim[3];
						float fDmgMod;
						//int iDamage = RoundFloat(damage);
						GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
						GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
						float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
						
						if (weapon == TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true)) {		// Primary weapon (75% ramp-up; normal fall-off)		
							if (fDistance < 512.0001) {
								fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Gives us our distance multiplier
							}
							else {
								fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
							}
						}
						else if (weapon == TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true)) {		// Pistol (normal ramp-up and fall-off)
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
						else {		// Melees and Flying Guillotine (no distance modifiers)
							fDmgMod = 1.0;
						}
						damage *= fDmgMod;		// This is the true amount of damage we do
						float fHype = GetEntPropFloat(attacker, Prop_Send, "m_flHypeMeter");		// This is our Boost
						
						if (players[attacker].fBoosting > 0.0) {
							SetEntPropFloat(attacker, Prop_Send, "m_flHypeMeter", fHype - damage);		// Subtract all of the added Boost
						}
						else {
							SetEntPropFloat(attacker, Prop_Send, "m_flHypeMeter", fHype - 0.6 * damage);		// Subtract 60% of the damage (this should be applied at the same time Valve's code is)
						}
					}
				}
			
			
				// Sniper
				case TFClass_Sniper: {
					if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {
				
						float vecAttacker[3];
						float vecVictim[3];
						float fDmgMod;
						int iDamage;		// This must be an int to prevent insanity later on
						GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
						GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
						float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
						
						if (GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage") < 0.001) {		// Detects if we have no charge (because we're unscoped)
							iDamage = RoundFloat(damage);
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our distance multiplier
							iDamage *= fDmgMod;
							damage = iDamage;		// This gives a warning, but damage needs to be an int else it gives insane numbers
							
							if (damage_type & DMG_CRIT != 0) {		// Removes headshot Crits when we aren't detected to be scoped in (as a precaution, and to prevent Crits during the 0.1 second interval where we're able to headshot but not charge)
								damage_type = (damage_type & ~DMG_CRIT);
							}
							
							if (fDistance < 512.0001) {
								if (players[attacker].headshot_frame == GetGameTickCount()) {		// Here we look at headshot status
									TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.001, 0);		// Applies a Mini-Crit
									damage_custom = TF_CUSTOM_HEADSHOT;		// This ensures that no-scope headshots still increment the Head counter
									SMG_Autoreload(attacker);
								}
							}
						}
						
						else {		// If we're scoped...
							if (StrEqual(class, "tf_weapon_sniperrifle")) {		// Stock Rifle
							
								iDamage = 40;
								fDmgMod = RemapValClamped(fDistance, 0.0, 1024.0, 0.75, 1.25);		// We've swapped to a linear equation for now
								if (fDistance < 512) {		// Only do damage fall-off(?) up close
									iDamage *= fDmgMod;
									damage = iDamage;
								}
								
								else {		// If we're not up close...
									float fCharge;
									fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");		// Records charge damage
									if (fCharge < 38.8889) {		// If we've spend less than 0.7 seconds charging, fix this value
										fCharge = 38.8889;
									}
									fDmgMod += -1.0;		// Gives us the amount of *extra* ramp-up damage only (0.0-0.25)
									fDmgMod = 4 * fDmgMod * (0.0225 * fCharge - 0.625) + 1.0; // Generate the charge multiplier fCharge (0.25-2.75), multiply by 4 times the distance multiplier fDmgMod (0-1), and add 1
										// We multiply by 4 because it turns fDmgMod into a proportion from 0 to 1 for this range of distances
										// https://www.omnicalculator.com/math/line-equation-from-two-points gives us an equation that hits both ([0.7/2.7]*150, 0.25) and (150, 2.75)
										// y = 0.0225000023x - 0.6250003394
									iDamage *= fDmgMod;
									damage = iDamage;					
								}
								
								if (damage_type & DMG_CRIT != 0) {		// Removes headshot Crits when we aren't detected to be scoped in (as a precaution, and to prevent Crits during the 0.1 second interval where we're able to headshot but not charge)
									SMG_Autoreload(attacker);
								}
							}
						
							else if (StrEqual(class, "tf_weapon_sniperrifle_decap")) {		// Bazaar Bargain
							
								iDamage = 40;
								fDmgMod = RemapValClamped(fDistance, 0.0, 1024.0, 0.75, 1.25);		// We've swapped to a linear equation for now
								
								// We actually want the ramp-up/fall-off curve to vary with charge regardless of distance on this weapon, so we handle all of this stuff earlier this time
								float fCharge;
								fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");		// Records charge damage
								if (fCharge < 70.0) {		// If we've spend less than 0.7 seconds charging, fix this value
									fCharge = 70.0;
								}
								if (fDistance < 512) {		// If we're up close...
									fDmgMod += -1.0;		// Gives us the amount of *extra* fall-off damage only (-0.25-0.0)
									fDmgMod = 4 * fDmgMod * (-0.003125 * fCharge + 0.46875) + 1.0; // Generate the charge multiplier fCharge (0.25-2.75), multiply by 4 times the distance multiplier fDmgMod (0-1), and add 1
										// We want the multiplier to become 0 at max (150) charge
										// https://www.omnicalculator.com/math/line-equation-from-two-points gives us an equation that hits both ([0.7/1.5]*150, -0.25) and (150, 0)
										// y = 0.0022500002x - 0.3375000328
										// y = -0.003125x + 0.46875
									iDamage *= fDmgMod;
									damage = iDamage;	
								}
								
								else {		// If we're not up close...
									fDmgMod += -1.0;		// Gives us the amount of *extra* ramp-up damage only (0.0-0.25)
									fDmgMod = 4 * fDmgMod * (0.015625 * fCharge - 0.84375) + 1.0; // Generate the charge multiplier fCharge (0.25-2.75), multiply by 4 times the distance multiplier fDmgMod (0-1), and add 1
										// https://www.omnicalculator.com/math/line-equation-from-two-points gives us an equation that hits both ([0.7/1.5]*150, 0.25) and (150, 1.5)
										// y = 0.015625x - 0.84375
									iDamage *= fDmgMod;
									damage = iDamage;					
								}
								
								if (damage_type & DMG_CRIT != 0) {		// Removes headshot Crits when we aren't detected to be scoped in (as a precaution, and to prevent Crits during the 0.1 second interval where we're able to headshot but not charge)
									SMG_Autoreload(attacker);
								}
							}
						}
						return Plugin_Changed;
					}						
					// Tribalman's Shiv Bleed interaction
					else if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 171 && damage_type & DMG_CLUB) {		// Are we using the Tribalman's Shiv?
						if (players[victim].fBleed_Timer == 0.0) {		// If the victim isn't bleeding...
							TF2_AddCondition(victim, TFCond_Bleeding, 4.0, attacker);		// ...apply Bleed and track it
							players[victim].fBleed_Timer = 4.0;
						}
						else {
							TF2_AddCondition(victim, TFCond_Bleeding);
							damage += 8 * players[victim].fBleed_Timer;		// Otherwise, consume the Bleed to deal extra damage
							players[victim].fBleed_Timer = 0.0;
						}
						return Plugin_Changed;
					}
				}
				
				// Spy
				case TFClass_Spy: {
					if (StrEqual(class, "tf_weapon_revolver")) {
				
						float vecAttacker[3];
						float vecVictim[3];
						float fDmgMod = 1.0;
						GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
						GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
						float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
						
						int secondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
						int secondaryIndex = -1;
						if (secondary != -1) {
							secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
						}
						
						if ((damage_type & DMG_CRIT != 0 || damage_custom == TF_CUSTOM_HEADSHOT) && secondaryIndex != 61 && secondaryIndex != 1006 && !(TF2_IsPlayerInCondition(attacker, TFCond_Kritzkrieged) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnFirstBlood) 
						|| TF2_IsPlayerInCondition(attacker, TFCond_CritOnWin) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnFlagCapture) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnKill) 
						|| TF2_IsPlayerInCondition(attacker, TFCond_CritOnDamage))) {		// Did we get a headshot with a non-Amby revolver?
							damage_type = (damage_type & ~DMG_CRIT);		// Remove the Crit if we aren't supposed to be Critting
							if (fDistance < 512.0001 && !(TF2_IsPlayerInCondition(attacker, TFCond_Disguised))) {
								TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.001, 0);		// Applies a Mini-Crit on close-range headshots while undisguised
							}
						}
						
						if (fDistance < 510.0001) {
							fDmgMod = RemapValClamped(fDistance, 0.0, 512.0, 0.9333333, 1.0);		// Scale the ramp-up down to 140%
						}
						
						damage *= fDmgMod;
						return Plugin_Changed;
					}
				}
			}
		}
	}
	
	return Plugin_Continue;
}


	// -={ SMG Autoreload }=-

void SMG_Autoreload(int client) {
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Secondary, true);		// Retrieve the seconadry weapon
	
	char class[64];
	GetEntityClassname(iSecondary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_smg")) {		// If we have the stock SMG equipped (the Carbine is a different class)
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our SMG
		int ammoSubtract = 25 - clip;		// Don't take away more ammo than is nessesary
		
		int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(client, Prop_Data, "m_iAmmo", _, secondaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < 25 && ammoCount > 0) {		// weapon is the weapon we swap to; check if we're swapping to something other than the bow
			if (ammoCount < 25) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(client, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, secondaryAmmo);		// Subtract reserve ammo
			SetEntData(iSecondary, iAmmoTable, 25, 4, true);		// Add loaded ammo
		}
	}
}


	// -={ Detects headshot kills for the Heads counter and handles Rifle clip }=-

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	int victim = event.GetInt("victim_entindex");
	int customKill = event.GetInt("customkill");

	players[victim].iHeads = 0;			// Reset Heads to 0 on death
			
	if (victim > 0 && victim <= MaxClients && attacker > 0 && attacker <= MaxClients && IsClientInGame(victim) && IsClientInGame(attacker)) {		// Check that we have good data
		if (victim != attacker && GetEventInt(event, "inflictor_entindex") == attacker && IsPlayerAlive(attacker)) {		// Make sure if wasn't a finish off or feign
	
			if (customKill == TF_CUSTOM_HEADSHOT || players[attacker].headshot_frame == GetGameTickCount()) {		// Did we get a headshot?
				players[attacker].iHeads += 1;		// Add a Head
				if 	(players[attacker].iHeads > 3) {
					players[attacker].iHeads = 3;
				}
			}
		}
	}
	return Plugin_Continue;
}


	// -={ Dynamically updates the attributes of Sniper's melees based on the Head counter, and handles Rifle reload }=-

public void OnGameFrame() {
	int iClient;		// Index; lets us run through all the players on the server	
	SetConVarString(cvar_ref_tf_parachute_aircontrol, "3.5");

	for (iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			TFClassType tfAttackerClass = TF2_GetPlayerClass(iClient);
			switch(tfAttackerClass)
			{
				// Scout
				case TFClass_Scout: {
					
					int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
					int primaryIndex = -1;
					if (primary >= 0) {
						primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
					}
					
					// Baby Face's Blaster
					if (primaryIndex == 772) {
						float fHype = GetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter");		// This is our Boost
						float vecVel[3];
						GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
						if (vecVel[2] != 0 && !(GetEntityFlags(iClient) & FL_ONGROUND) && fHype > 24.75) {		// Are we airborne with more than 25% Boost?
							TF2Attrib_SetByDefIndex(primary, 326, 1.0 - ((fHype - 24.75) / 74.25));		// increased jump height attribute (decreasing proportionally to Boost)
						}
						else {
							TF2Attrib_SetByDefIndex(primary, 326, 1.0);		// Reset jump height to normal while grounded
						}
						if (players[iClient].fBoosting > 0.0) {
							SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
							ShowHudText(iClient, 1, "Boosting!: %.00f", players[iClient].fBoosting);
							
							players[iClient].fBoosting -= 0.015;		// Decrease by 1 second every ~66.6 server ticks
						}
						if (players[iClient].fBoosting < 0.0) {
							players[iClient].fBoosting = 0.0;	// Failsafe
						}
					}
				}
				
				// BASE Jumper
				case TFClass_Soldier, TFClass_DemoMan: {
					
					if (TF2_IsPlayerInCondition(iClient, TFCond_Parachute)) {		// Are we parachuting?
						players[iClient].parachute_cond_time = GetGameTime();		// Record the time, so we can set a redeploy cooldown
						players[iClient].fAirtimeTrack += 0.015;		// Add a frame to the airtime counter
						if ((players[iClient].fAirtimeTrack) > 0.35) {
							if (players[iClient].bAudio == false) {		// We only want this to play once
								EmitSoundToClient(iClient, "weapons/discipline_device_power_up.wav");
							}
							players[iClient].bAudio = true;
							TF2Attrib_AddCustomPlayerAttribute(iClient, "faster reload rate", 0.75, 0.35);	// If so, buff reload speed (no point in checking for explosive launchers since reload speed on melee weapons doesn't matter)
							players[iClient].fAirtimeTrack = 0.35;
						}
					}
					else if (TF2_IsPlayerInCondition(iClient, TFCond_ParachuteDeployed) && (GetGameTime() - players[iClient].parachute_cond_time) > 0.35) {		// Do we have the parachute lockout debuff but have exceeded the plugin's defined cooldown?
						players[iClient].parachute_cond_time = GetGameTime();		// Record the time, so we can set a redeploy cooldown
						TF2_RemoveCondition(iClient, TFCond_ParachuteDeployed);		// Cleanse the debuff
					}
					
					else {		// If we aren't parachuting...
						players[iClient].fAirtimeTrack = 0.0;		// Reset the airtime tracker
						players[iClient].bAudio = false;				
					}
				}
				
				// Sniper
				case TFClass_Sniper: {
					
					int secondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
					int secondaryIndex = -1;
					if (secondary >= 0) {
						secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
					}
					
					int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
					int meleeIndex = -1;
					if (melee >= 0) {
						meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
					}
					
					// Melees
					// Dynamically adjusts melee stats depending on Heads
					switch(meleeIndex) {		// Kukri
						case 3, 193, 264, 423, 474, 880, 939, 954, 1013, 1071, 1123, 1127, 30758: {		// Kukri and reskins
							TF2Attrib_SetByDefIndex(melee, 123, 1.0 + 0.04 * players[iClient].iHeads);		// Speed bonus while active
						}
						case 171: {		// Tribalman's Shiv
							TF2Attrib_SetByDefIndex(melee, 205, 1.0 - 0.5 * players[iClient].iHeads);		// dmg from ranged reduced
							TF2Attrib_SetByDefIndex(melee, 206, 1.0 - 0.5 * players[iClient].iHeads);		// dmg from melee reduced
							if (GetClientHealth(iClient) < 38.0) {		// Disable holster at low health
								TF2_AddCondition(iClient, TFCond_RestrictToMelee, 0.02, 0);		// Buffalo Steak strip to melee debuff
							}
						}
						/*case 401: {		// Shahanshah
							TF2Attrib_SetByDefIndex(melee, 26, 10 * players[iClient].iHeads);		// max health additive bonus
						}*/
					}
					
					// Dynamically adjusts Sniper fire rate depending on scope status (avoids the need for DHooks)
					int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
					if (GetEntPropFloat(primary, Prop_Send, "m_flChargedDamage") < 0.001) {
						TF2Attrib_SetByDefIndex(primary, 5, 0.933333);		// fire rate penalty
					}
					else {
						TF2Attrib_SetByDefIndex(primary, 5, 1.2);
					}
					
					// Heads counter display
					if (GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon") == TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true) ||
					GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon") == TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true)) {		// Display Heads if we're holding a primary or melee
						SetHudTextParams(-0.1, -0.13, 0.0, 255, 255, 255, 255);
						ShowHudText(iClient, 1, "Heads: %i", players[iClient].iHeads);
					}
					
					// DDS Afterburn reduction
					if (secondaryIndex == 231) {
						float fAfterburn = TF2Util_GetPlayerBurnDuration(iClient);
						fAfterburn -= 0.0105;
						TF2Util_SetPlayerBurnDuration(iClient, fAfterburn);
					}
				}
			}
			
			// These things are not class-dependent
			if (TF2_GetPlayerClass(iClient) != TFClass_Sniper) {
				players[iClient].iHeads = 0;		// Reset Heads if we change classes without dying
			}
			
			// Tracks Bleed on Tribalman's Shiv victims
			if (players[iClient].fBleed_Timer > 0.0) {
				SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
				
				players[iClient].fBleed_Timer -= 0.015;		// Decrease by 1 second every ~66.6 server ticks
			}
			if (players[iClient].fBleed_Timer < 0.0) {
				players[iClient].fBleed_Timer = 0.0;	// Failsafe
			}
		}
	}
}


	// -={ Lets us expend BFB Boost for an AoE speed buff }=-

public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if((IsClientInGame(iClient) && IsPlayerAlive(iClient))) {
		TFClassType tfClientClass = TF2_GetPlayerClass(iClient);
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		float position[3];
		GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", position);
		
		int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		int primaryIndex = -1;
		if(primary != -1) primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
		
		int melee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
		int meleeIndex = -1;
		if(melee >= 0) meleeIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
		
		// Scout
		if (tfClientClass == TFClass_Scout) {
			if(primaryIndex == 772 && iActive == primary) {		// Are we holding the BFB?
				if(buttons & IN_ATTACK2 && players[iClient].fBoosting == 0.0) {		// Are we using the alt-fire?
					float fHype = GetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter");

					SetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter", 0.0);
					TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, RemapValClamped(fHype, 0.0, 99.0, 0.0, 5.0));		// Apply speed to us depending on the amount of Boost we have
					
					players[iClient].fBoosting = RemapValClamped(fHype, 0.0, 99.0, 0.0, 5.0);		// Tracks whether or not the alt-fire is active and for how long
					
					for (int i = 1; i <= MaxClients; i++) {
							if (IsClientInGame(i) && IsPlayerAlive(i)) {
							float vecTeammate[3];
							float vecUs[3];
							float distance;
							GetEntPropVector(i, Prop_Send, "m_vecOrigin", vecTeammate);
							GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", vecUs);
							distance = GetVectorDistance(vecUs, vecTeammate);
							if (distance < 300 && GetClientTeam(i) == GetClientTeam(iClient)) {		// Identify players on the same team within 300 HU of us
								TF2_AddCondition(i, TFCond_SpeedBuffAlly, RemapValClamped(fHype, 0.0, 99.0, 0.0, 5.0));		// Apply speed to teammates
							}
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}