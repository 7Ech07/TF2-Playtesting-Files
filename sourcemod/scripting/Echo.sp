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


enum struct Player {
	bool AirblastJumpCD;
	bool ParticleCD;
	int iTempLevel;
	float fRev;		// Tracks how long we've been revved for the purposes of undoing the L&W nerf
	float fBoost;		// Natascha Boost
	float fFlare_Cooldown;		// HLH firing interval (to prevent tapfiring)
	float fRev;		// This must be a global variable, else it doesn't track properly
	float fBoost;		// Natascha Boost
	float fFlare_Cooldown;		// HLH firing interval (to prevent tapfiring)
}


	// -={ Precaches audio }=-

public void OnMapStart()
{
	PrecacheSound("weapons/widow_maker_pump_action_back.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_forward.wav", true);
		PrecacheSound("weapons/flare_detonator_explode.wav", true);
}


	// -={ Handles Pyro cvars }=-

Handle cvar_ref_tf_flame_dmg_mode_dist;	
Handle cvar_ref_tf_flamethrower_boxsize;
Handle cvar_ref_tf_flamethrower_drag;
Handle cvar_ref_tf_flamethrower_flametime;
Handle cvar_ref_tf_flamethrower_float;	
Handle cvar_ref_tf_flamethrower_maxdamagedist;
Handle cvar_ref_tf_flamethrower_new_flame_offset;
Handle cvar_ref_tf_flamethrower_shortrangedamagemultiplier;
Handle cvar_ref_tf_flamethrower_vecrand;
Handle cvar_ref_tf_flamethrower_velocity;
Handle cvar_ref_tf_flamethrower_velocityfadeend;
Handle cvar_ref_tf_flamethrower_velocityfadestart;

Handle cvar_ref_tf_fireball_airblast_recharge_penalty;
Handle cvar_ref_tf_fireball_burn_duration;
Handle cvar_ref_tf_fireball_burning_bonus;
Handle cvar_ref_tf_fireball_damage;
Handle cvar_ref_tf_fireball_radius;

Handle cvar_ref_tf_airblast_cray_power;
Handle cvar_ref_tf_airblast_cray_reflect_coeff;

Player players[MAXPLAYERS+1];


public void OnClientPutInServer (int iClient)
{
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
}


	// -={ Accesses the dev only Flanethrower cvars }=-

public void OnPluginStart() {
	cvar_ref_tf_flame_dmg_mode_dist = FindConVar("tf_flame_dmg_mode_dist");
	cvar_ref_tf_flamethrower_boxsize = FindConVar("tf_flamethrower_boxsize");
	cvar_ref_tf_flamethrower_drag = FindConVar("tf_flamethrower_drag");
	cvar_ref_tf_flamethrower_flametime = FindConVar("tf_flamethrower_flametime");
	cvar_ref_tf_flamethrower_float = FindConVar("tf_flamethrower_float");
	cvar_ref_tf_flamethrower_maxdamagedist = FindConVar("tf_flamethrower_maxdamagedist");
	cvar_ref_tf_flamethrower_new_flame_offset = FindConVar("tf_flamethrower_new_flame_offset");
	cvar_ref_tf_flamethrower_shortrangedamagemultiplier = FindConVar("tf_flamethrower_shortrangedamagemultiplier");
	cvar_ref_tf_flamethrower_vecrand = FindConVar("tf_flamethrower_vecrand");
	cvar_ref_tf_flamethrower_velocity = FindConVar("tf_flamethrower_velocity");
	cvar_ref_tf_flamethrower_velocityfadeend = FindConVar("tf_flamethrower_velocityfadeend");
	cvar_ref_tf_flamethrower_velocityfadestart = FindConVar("tf_flamethrower_velocityfadestart");
	
	cvar_ref_tf_fireball_airblast_recharge_penalty = FindConVar("tf_fireball_airblast_recharge_penalty");
	cvar_ref_tf_fireball_burn_duration = FindConVar("tf_fireball_burn_duration");
	cvar_ref_tf_fireball_burning_bonus = FindConVar("tf_fireball_burning_bonus");
	cvar_ref_tf_fireball_damage = FindConVar("tf_fireball_damage");
	cvar_ref_tf_fireball_radius = FindConVar("tf_fireball_radius");
	
	cvar_ref_tf_airblast_cray_power = FindConVar("tf_airblast_cray_power");
	cvar_ref_tf_airblast_cray_reflect_coeff = FindConVar("tf_airblast_cray_reflect_coeff");
}


	// -={ Modifies attributes without needing to go through another plugin }=-

public Action TF2Items_OnGiveNamedItem(int client, char[] class, int index, Handle& item) {
	Handle item1;
	
	if (StrEqual(class, "tf_weapon_flamethrower")) {
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 7);
		TF2Items_SetAttribute(item1, 0, 841, 0.0); // flame_gravity (none)
		TF2Items_SetAttribute(item1, 1, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 2, 844, 1920.0); // flame_speed (1920 HU/s)
		TF2Items_SetAttribute(item1, 3, 862, 0.2); // flame_lifetime (0.2 s)
		TF2Items_SetAttribute(item1, 4, 865, 0.0); // flame_up_speed (Draf wanted this)
		TF2Items_SetAttribute(item1, 5, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 6, 863, 0.0); // flame_random_lifetime_offset (none)
	}
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}


	// -={ Iterates every frame }=-
	
	// Somethhing in here might be broken

public void OnGameFrame() {
	
	SetConVarString(cvar_ref_tf_flame_dmg_mode_dist, "0.0");
	SetConVarString(cvar_ref_tf_flamethrower_boxsize, "12.0");
	SetConVarString(cvar_ref_tf_flamethrower_drag, "0.0");
	SetConVarString(cvar_ref_tf_flamethrower_flametime, "0.2");
	SetConVarString(cvar_ref_tf_flamethrower_float, "0.0");
	SetConVarString(cvar_ref_tf_flamethrower_maxdamagedist, "384.0");
	SetConVarString(cvar_ref_tf_flamethrower_new_flame_offset, "0.0");
	SetConVarString(cvar_ref_tf_flamethrower_shortrangedamagemultiplier, "1.0");
	SetConVarString(cvar_ref_tf_flamethrower_vecrand, "0.0");
	SetConVarString(cvar_ref_tf_flamethrower_velocity, "1920.0");
	SetConVarString(cvar_ref_tf_flamethrower_velocityfadeend, "0.2");
	SetConVarString(cvar_ref_tf_flamethrower_velocityfadestart, "1.2");


	SetConVarString(cvar_ref_tf_fireball_airblast_recharge_penalty, "0.55");
	SetConVarString(cvar_ref_tf_fireball_burn_duration, "3");
	SetConVarString(cvar_ref_tf_fireball_burning_bonus, "2");
	SetConVarString(cvar_ref_tf_fireball_damage, "37.5");
	SetConVarString(cvar_ref_tf_fireball_radius, "17.5");


	SetConVarString(cvar_ref_tf_airblast_cray_power, "400");
	SetConVarString(cvar_ref_tf_airblast_cray_reflect_coeff, "1");
	
	// Afterburn
	for (int i = 1; i <= MaxClients; i++) {		// Caps Afterburn at 8 and handles Temperature
		if (IsClientInGame(i) && IsPlayerAlive(i)) {
			float fBurn = TF2Util_GetPlayerBurnDuration(i);
			if (fBurn > 8.0) {
				TF2Util_SetPlayerBurnDuration(i, 8.0);
				players[i].iTempLevel = 2;
				if (players[i].ParticleCD == true) {
					CreateParticle(i,"dragons_fury_effect", 0.5);
					players[i].ParticleCD = false;
				}
			}
			
			else if (fBurn > 5.5) {
				players[i].iTempLevel = 1;
			}
			
			else {
				players[i].iTempLevel = 0;
				players[i].ParticleCD = true;
			}
			
			// Airblast jump chaining prevention
			float vecVel[3];
			GetEntPropVector(i, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
			if (vecVel[2] == 0 && (GetEntityFlags(i) & FL_ONGROUND)) {		// Are we grounded?
				players[i].AirblastJumpCD = true;
			}
			else {
			}
			
			// Heavy
			// Counteracts the L&W nerf by dynamically adjusting damage and accuracy; handles Natascha speed
			if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
				
				players[iClient].fFlare_Cooldown -= 0.015;
				
				int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
				int primaryIndex = -1;
				if (primary >= 0) {
					primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
				}
				
				float fDmgMult = 1.0;		// Default values -- for stock, and in case of emergency
				float fAccMult = 1.0;
				
				switch(primaryIndex) {		// Determine unique damage and accuracy multipliers for the unlocks
					case 424: {		// Tomislav
						fDmgMult = 1.0;
						fAccMult = 0.8;
					}
					case 41: {		// Natascha
						fDmgMult = 1.0;
						fAccMult = 1.0;
					}
					case 811, 832: {		// Huo-Long Heater
						fDmgMult = 2.4074;
						fAccMult = 1.0;
					}
					case 312: {		// Brass Beast
						fDmgMult = 1.2;
						fAccMult = 1.0;
					}
				}
				
				int weaponState = GetEntProp(primary, Prop_Send, "m_iWeaponState");
				int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
				int sequence = GetEntProp(view, Prop_Send, "m_nSequence");		// We use viewmodel animation as an additional check for being unrevved for Natascha
				
				if (weaponState == 1) {		// Are we revving up?
					players[iClient].fRev = 1.005;		// This is our rev meter; it's a measure of how close we are to being free of the L&W nerf
				}
				
				else if ((weaponState == 2 || weaponState == 3) && players[iClient].fRev > 0.0) {		// If we're revved but the rev meter isn't empty...
					players[iClient].fRev = players[iClient].fRev - 0.015;		// It takes us 67 frames (1 second) to fully deplete the rev meter
					int time = RoundFloat(players[iClient].fRev * 1000);
					if (time%90 == 0) {		// Only adjust the damage every so often
						float factor = 1.0 + time/990.0;		// We increase damage and accuracy over time proportional to the rev meter
						TF2Attrib_SetByDefIndex(primary, 106, fAccMult * 1.0/factor);		// Spread bonus
						TF2Attrib_SetByDefIndex(primary, 2, fDmgMult * 1.0 * factor);		// Damage bonus
					}
				}
				
				// Natascha
				else if (weaponState == 0 && sequence == 23 && players[iClient].fBoost > 0.0) {		// If we're unrevved with at least some Boost...
					TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, RemapValClamped(players[iClient].fBoost, 0.0, 300.0, 0.0, 3.0));		// Apply speed to us depending on the amount of Boost we have
					players[iClient].fBoost = 0;
				}
				
				if (players[iClient].fBoost > 0.0){		// Draw Boost on the HUD
					SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 1, "Boost: %.0f", players[iClient].fBoost);
				}
			}
		}
	}
}


	// -={ Preps Airblast jump }=-

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if (client >= 1 && client <= MaxClients) {
		
		// Pyro
		if (TF2_GetPlayerClass(client) == TFClass_Pyro) {

			int iPrimary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Primary, true);		// Retrieve the primary weapon
			char class[64];
			GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
			
			// Airblast jump
			if (StrEqual(class, "tf_weapon_flamethrower") || StrEqual(class, "tf_weapon_rocketlauncher_fireball")) {		// Are we holding an Airblast-capable weapon?
				int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
				float vecVel[3];
				GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
				if (weaponState == 3 && (vecVel[2] != 0 && !(GetEntityFlags(client) & FL_ONGROUND))) {		// Did we do an Airblast while airborne? (FT_STATE_SECONDARY = 3)
					if (players[client].AirblastJumpCD == true) {
						AirblastJump(client);
						players[client].AirblastJumpCD = false;		// Prevent Airblast jump from triggering multiple times in one Airblast
					}
				}
			}
		}
		
		// Sniper
		if (TF2_GetPlayerClass(client) == TFClass_Sniper) {
			
			// Huntsman passive reload
			if (iPrimary != -1) {
				if (iActive == iPrimary) {		// Are we holding our primary?
					primaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");		// Retrieve the primary weapon index for later
					int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");		// Retrieve the active weapon
					if (primaryIndex == 56 || primaryIndex == 1005 || primaryIndex == 1092) {		// Is the primary a bow?
					
						int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
						int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our primary
						
						int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
						int ammoCount = GetEntProp(client, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve primary ammo
						
						if (clip == 0 && ammoCount > 0 && weapon != 0 && weapon != iPrimary) {		// weapon is the weapon we swap to; check if we're swapping to something other than the bow
							SetEntProp(client, Prop_Data, "m_iAmmo", ammoCount-1 , _, primaryAmmo);		// Subtract reserve ammo
							SetEntData(iPrimary, iAmmoTable, 1, 4, true);		// Add loaded ammo
						}
					}
				}
			}
		}

		// Panic Attack
		else if (TF2_GetPlayerClass(client) == TFClass_Soldier || TF2_GetPlayerClass(client) == TFClass_Pyro || TF2_GetPlayerClass(client) == TFClass_Heavy) {
		
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Secondary, true);		// Retrieve the secondary weapon
			int secondaryIndex = -1;
			secondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");		// Retrieve the primary weapon index for later
			int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");		// Retrieve the active weapon
		
			if (iSecondary != -1) {
				if (iActive != iSecondary) {		// Are we holding our secondary?
					if (secondaryIndex == 1153) {		// Is the secondary the Panic Attack
						int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
						int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our secondary
						
						int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
						int ammoCount = GetEntProp(client, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
						
						if (clip < 2 && ammoCount > 0) {
							CreateTimer(2.0, AutoreloadSecondary, client);
						}
					}
				}
			}
		}
		else if (TF2_GetPlayerClass(client) == TFClass_Engineer) {
		
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Primary, true);		// Retrieve the primary weapon (for Engineer)
			int primaryIndex = -1;
			primaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");		// Retrieve the primary weapon index for later
			int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");		// Retrieve the active weapon
			
			if (iPrimary != -1) {
				if (iActive != iPrimary) {		// Are we holding our primary?
					if (primaryIndex == 1153) {		// Is the primary the Panic Attack
						int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
						int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our primary
						
						int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
						int ammoCount = GetEntProp(client, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve primary ammo
						
						if (clip < 2 && ammoCount > 0) {		// weapon is the weapon we swap to; check if we're swapping to something other than the PA
							CreateTimer(2.0, AutoreloadPrimary, client);
						}
					}
				}
			}
		}
	}
	
	return Plugin_Continue;
}


public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			// Natascha
			if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 41) {		// Do we have Natascha equipped?

				players[attacker].fBoost += damage;		// Increases Boost by the amount of damage we do
				if (players[attacker].fBoost > 300.0) {		// Cap at 300 damage
					players[attacker].fBoost = 300.0;
				}
			}
		}
	}
}


	// -={ Performs the Airblast jump }=-

void AirblastJump(int client) {
	
	float vecAngle[3], vecVel[3], fRedirect, fBuffer, vecBuffer[3];
	GetClientEyeAngles(client, vecAngle);		// Identify where we're looking
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
	
	float vecForce[3];
	vecForce[0] = -Cosine(vecAngle[1] * 0.01745329) * Cosine(vecAngle[0] * 0.01745329);		// We are facing straight down the X axis when pitch and yaw are both 0; Cos(0) is 1
	vecForce[1] = -Sine(vecAngle[1] * 0.01745329) * Cosine(vecAngle[0] * 0.01745329);		// We are facing straight down the Y axis when pitch is 0 and yaw is 90
	vecForce[2] = Sine(vecAngle[0] * 0.01745329); 	// We are facing straight up the Z axis when pitch is 90 (yaw is irrelevant)
	
	fBuffer = GetVectorDotProduct(vecForce, vecVel) / GetVectorLength(vecVel, false);
	vecBuffer = vecVel;
	ScaleVector(vecBuffer, fBuffer);
	float vecProjection[3];
	vecProjection[0] = -vecBuffer[0];		// Takes the negative of the projection of our velocity vector in the aim direction
	vecProjection[1] = -vecBuffer[1];
	vecProjection[2] = -vecBuffer[2];
	
	if (vecVel[2] < 0.0) {
		fRedirect = vecVel[2];		// Stores this momentum for later
		vecVel[2] = 0.0;		// Makes sure we always have at least enough push force to break our fall (unless we aim downwards for some reason)
	}
	
	// Convert pitch and yaw into a directional vector (and make it face behind us)
	float fForce = 200.0 + (fRedirect / 2);		// Add half of our redirected falling speed to this
	vecForce[0] *= fForce;
	vecForce[1] *= fForce;
	vecForce[2] *= fForce;
	
	vecForce[2] += 50.0;		// Some fixed upward force to make the jump feel beter
	AddVectors(vecVel, vecForce, vecForce);		// Add the Airblast push force to our velocity
	//AddVectors(vecProjection, vecForce, vecForce); This bit is terrible
	
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vecForce);		// Sets the Pyro's momentum to the appropriate value

	return;
}


	// -={ Calculates damage }=-

Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& weapon, float damage_force[3], float damage_position[3], int damage_custom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			// Pyro
			// Flamethrower rebuild
			if(StrEqual(class, "tf_weapon_flamethrower") && (damage_type & DMG_IGNITE) && !(damage_type & DMG_BLAST)) {
				//recreate flamethrower damage scaling, code inpsired by NotnHeavy
				//base damage plus any bonus
				/*Address bonus = TF2Attrib_GetByDefIndex(weapon, 2);
				float value = bonus == Address_Null ? 1.0 : TF2Attrib_GetValue(bonus);*/
				damage = 6.8181 + (2.727272 * players[victim].iTempLevel);

				//crit damage multipliers
				if (damage_type & DMG_CRIT) {
					if (isMiniKritzed(attacker,victim) && !isKritzed(attacker))
						damage *= 1.35;
					else
						damage *= 3.0;
				}

				damage_type &= ~DMG_USEDISTANCEMOD;

				if(damage_type & DMG_SONIC) {
					damage_type &= ~DMG_SONIC;
					damage = 0.01;
				}
			}
			
			// Heavy
			// HLH Damage
			else if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 811 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 832) {		// Do we have the HLH equipped?
			
				float vecAttacker[3];
				float vecVictim[3];
				GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
				GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
				float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
				
				float fDmgMod;
				int iDamage;		// This must be an int to prevent insanity later on
				iDamage = RoundFloat(damage);

				if (TF2Util_GetPlayerBurnDuration(victim) > 0 && !(TF2_IsPlayerInCondition(attacker, TFCond_Kritzkrieged) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnFirstBlood) 
					|| TF2_IsPlayerInCondition(attacker, TFCond_CritOnWin) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnFlagCapture) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnKill) 
					|| TF2_IsPlayerInCondition(attacker, TFCond_CritOnDamage))) {		// If we're shooting a burning person but not supposed to be dealing Crits...
					damage_type &= ~DMG_CRIT;		// ...Remove the Crits
					if (TF2_IsPlayerInCondition(victim, TFCond_Jarated) || TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeathSilent)
						|| TF2_IsPlayerInCondition(attacker, TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(attacker, TFCond_Buffed) || TF2_IsPlayerInCondition(attacker, TFCond_CritCola)) {		// But, if we're suppose doing Mini-Crits...
						TF2_AddCondition(victim,TFCond_MarkedForDeathSilent, 0.015);		// Apply Mini-Crits via Mark-for-Death
					}
				}

				if (!(damage_type & DMG_CRIT)) {
					if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Generates a proportion from 0.5 to 1.0 depending on distance (from 1024 to 1536 HU)
					}
					else {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
					}
				}
				iDamage *= 3 * fDmgMod;
				damage = iDamage;		// This gives a warning, but damage needs to be an int else it gives insane numbers
				damage_type = (damage_type & ~DMG_IGNITE);
				return Plugin_Changed;
			}
			
			// Sniper
			// Huntsman damage fall-off
			else if (StrEqual(class, "tf_weapon_compound_bow")) {
					
				float vecAttacker[3];
				float vecVictim[3];
				GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
				GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
				float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
				
				if (fDistance > 1000.0) {
					float fDmgMod;
					int iDamage;		// This must be an int to prevent insanity later on
					iDamage = RoundFloat(damage);

					fDmgMod = SimpleSplineRemapValClamped(fDistance, 1000.0, 1200.0, 1.0, 0.5);		// Generates a proportion from 0.5 to 1.0 depending on distance (from 1024 to 1536 HU)

					iDamage *= fDmgMod;
					damage = iDamage;		// This gives a warning, but damage needs to be an int else it gives insane numbers
					// The following code removes headshot Crits after a certain distance
					if (fDistance > 1200.0 && damage_type & DMG_CRIT != 0) {		// Removes headshot Crits after 1200 HU
						damage_type = (damage_type & ~DMG_CRIT);
					}
					return Plugin_Changed;
				}
			}
		}
	}
	
	return Plugin_Continue;
}


	// -={ Panic Attack passive autoreload }=-

Action AutoreloadPrimary(Handle timer, int client) {
	int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");		// Recheck everything so we don't perform the autoreload if the PA is out
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Primary, true);
	
	if (iActive == iPrimary) {
		return Plugin_Handled;
	}
	
	int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
	int clip = GetEntData(iPrimary, iAmmoTable, 4);
	
	int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
	int ammoCount = GetEntProp(client, Prop_Data, "m_iAmmo", _, primaryAmmo);
	
	if (clip < 2 && ammoCount > 0) {
		SetEntProp(client, Prop_Data, "m_iAmmo", ammoCount - 2 , _, primaryAmmo);
		SetEntData(iPrimary, iAmmoTable, 2, 4, true);
		EmitSoundToClient(client, "weapons/widow_maker_pump_action_back.wav");
	}
	return Plugin_Handled;
}

Action AutoreloadSecondary(Handle timer, int client) {
	int iActive = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Secondary, true);
	
	if (iActive == iSecondary) {
		return Plugin_Handled;
	}
	
	int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
	int clip = GetEntData(iSecondary, iAmmoTable, 4);
	
	int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
	int ammoCount = GetEntProp(client, Prop_Data, "m_iAmmo", _, primaryAmmo);
	
	if (clip < 2 && ammoCount > 0) {
		SetEntProp(client, Prop_Data, "m_iAmmo", ammoCount - 2 , _, primaryAmmo);
		SetEntData(iSecondary, iAmmoTable, 2, 4, true);
		EmitSoundToClient(client, "weapons/widow_maker_pump_action_back.wav");
	}
	return Plugin_Handled;
}


	// -={ Sets HLH projectiles to fire from a specific spot, and destroys them on a timer }=-

public void OnEntityCreated(int iEnt, const char[] classname) {
	if(IsValidEdict(iEnt)) {
		if(StrEqual(classname,"tf_projectile_flare")) {
			SDKHook(iEnt, SDKHook_SpawnPost, FlareSpawn);
		}
	}
}

Action FlareSpawn(int entity) {
	char class[64];
	int owner;
	GetEntityClassname(entity, class, sizeof(class));
	if (StrEqual(class, "tf_projectile_flare")) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if (TF2_GetPlayerClass(owner) == TFClass_Heavy) {
			
			if (players[owner].fFlare_Cooldown > 0.0) {		// If we shouldn't be allowed to fire yet...
				AcceptEntityInput(entity, "KillHierarchy");		// Instantly delete the flare
				
				int primary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Primary, true);
				int primaryAmmo = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
				int ammoCount = GetEntProp(owner, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve primary ammo
				if (ammoCount < 80) {
					ammoCount += 1;
					SetEntProp(owner, Prop_Data, "m_iAmmo", ammoCount + 1, _, primaryAmmo);		// Restore the ammo
				}
				
				return Plugin_Handled;
			}
			
			float vecPos[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecPos);		// Gets flare position
			
			EmitSoundToClient(owner, "weapons/flare_detonator_explode.wav");
			RequestFrame(FlareVel, entity);		// It doesn't like it when we try to modify velocity on this frame, so we do it on the next one
			
			vecPos[2] -= 24.0;		// Make the flare appear 16 HU down so it's fired out of the chest rather than the face

			TeleportEntity(entity, vecPos, NULL_VECTOR, NULL_VECTOR);
			players[owner].fFlare_Cooldown = 0.285;
			
			int primary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Primary, true);
			SetEntPropEnt(entity, Prop_Send, "m_hLauncher", primary);

			CreateTimer(0.5, KillFlare, entity);		// A flare will travel about 1000 HU in this time
		}
	}
	
	return Plugin_Continue;
}

void FlareVel(int entity) {
	float vecVel[3]; 
	GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vecVel);		// Gets flare velocity
	
	vecVel[2] += 80.0;

	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vecVel);
}

Action KillFlare(Handle timer, int flare) {
	if(IsValidEdict(flare)) {
		CreateParticle(flare, "arm_muzzleflash_flare", 0.15, _, _, _, _, _, 10.0);		// Displays particle on natural flare death (0.15 s duration, 10 HU size)
		AcceptEntityInput(flare,"KillHierarchy");
	}
	return Plugin_Continue;
}


	// ==={{ Do not touch anything below this point }}===
	
	// -={ Displays particles (taken from ShSilver) }=-

stock int CreateParticle(int ent, char[] particleType, float time,float angleX=0.0,float angleY=0.0,float Xoffset=0.0,float Yoffset=0.0,float Zoffset=0.0,float size=1.0,bool update=true,bool parent=true,bool attach=false,float angleZ=0.0,int owner=-1)
{
	int particle = CreateEntityByName("info_particle_system");

	char[] name = new char[64];

	if (IsValidEdict(particle))
	{
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

		if(ent!=0)
		{
			if(parent)
			{
				SetVariantString(name);
				AcceptEntityInput(particle, "SetParent", particle, particle, 0);

			}
			else
			{
				SetVariantString("!activator");
				AcceptEntityInput(particle, "SetParent", ent, particle, 0);
			}
			if(attach)
			{
				SetVariantString("head");
				AcceptEntityInput(particle, "SetParentAttachment", particle, particle, 0);
			}
		}

		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "Start");

		if(owner!=-1)
			SetEntPropEnt(particle, Prop_Send, "m_hOwnerEntity", owner);
		
		if(update)
		{
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

public Action DeleteParticle(Handle timer, int particle)
{
	char[] classN = new char[64];
	if (IsValidEdict(particle))
	{
		GetEdictClassname(particle, classN, 64);
		if (StrEqual(classN, "info_particle_system", false))
			RemoveEdict(particle);
	}
	return Plugin_Continue;
}

public Action UpdateParticle(Handle timer, DataPack pack)
{
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


	// -={ Identifies sources of (Mini-)Crits (taken from ShSilver) }=-

bool isKritzed(int client)
{
	return (TF2_IsPlayerInCondition(client,TFCond_Kritzkrieged) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnFirstBlood) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnWin) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnFlagCapture) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnKill) ||
	TF2_IsPlayerInCondition(client,TFCond_CritOnDamage) ||
	TF2_IsPlayerInCondition(client,TFCond_CritDemoCharge));
}

bool isMiniKritzed(int client,int victim=-1)
{
	bool result=false;
	if(victim!=-1)
	{
		if (TF2_IsPlayerInCondition(victim,TFCond_Jarated) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeathSilent))
			result = true;
	}
	if (TF2_IsPlayerInCondition(client,TFCond_CritMmmph) || TF2_IsPlayerInCondition(client,TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(client,TFCond_Buffed) || TF2_IsPlayerInCondition(client,TFCond_CritCola))
		result = true;
	return result;
}


stock bool IsValidClient(int client, bool replaycheck = true)
{
	if (client <= 0 || client > MaxClients) return false;
	if (!IsClientInGame(client)) return false;
	return true;
}