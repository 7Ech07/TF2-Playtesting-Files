#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2utils>
#include <tf2items>
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
	float fBleed_Timer;		// Counts how much Bleed is left on us from the Shiv
	float fBoosting;		// Stores BFB alt-fire boost duration
	float fAirtimeTrack;		// Tracks time spent parachuting
	bool bAudio;		// Tracks whether or not we've played the BASE Jumper buff audio cue yet
	float parachute_cond_time;
	
	// Pyro
	int iAxe_Count;		// Tracks the number of hits we've made with the Fire Axe for each attack we perform
	float fAxe_Cooldown;		// Stores the cooldown timer of our axe throw ability
	
	// Heavy
	float fFists_Sprint;	// Tracks how long we've been out of combat for determining Heavy sprint
	float fUppercut_Cooldown;	// Puts a 1 second hard cooldown on alt-fire use
	float fRev;
	float fBrace_Time;		// Stores how long we've been braced for for the purpose of increasing ramp-up over time
	
	// Medic
	int iSyringe_Ammo;		// Tracks loaded syringes for the purposes of determining when we fire a shot
	float fTac_Reload;		// Tracks how long the weapon has been holstered for if not full, for the purposes of determining when to perform backpack or tactical reloads
	
	// Sniper
	int headshot_frame;		// checks for headshots later on
	int iRifle_Ammo;
	int iHeads;		// Count Heads for the Sniper Rifle
}

Player players[MAXPLAYERS+1];
float g_meterPri[MAXPLAYERS+1];

Handle cvar_ref_tf_parachute_aircontrol;


public void OnPluginStart() {
	cvar_ref_tf_parachute_aircontrol = FindConVar("tf_parachute_aircontrol");

	// This is used for clearing variables on respawn
	HookEvent("player_spawn", OnGameEvent, EventHookMode_Post);
	// This detects healing we do for the purpose of building Uber
	HookEvent("player_healed", OnPlayerHealed);
	HookEvent("item_pickup", OnGameEvent, EventHookMode_Post);
}


public void OnClientPutInServer(int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(iClient, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
	SDKHook(iClient, SDKHook_TraceAttack, TraceAttack);
}


public void OnMapStart() {
	PrecacheSound("player/recharged.wav", true);
	PrecacheSound("weapons/cleaver_throw.wav", true);
	PrecacheSound("weapons/syringegun_shoot.wav", true);
	PrecacheSound("weapons/syringegun_shoot_crit.wav", true);
	PrecacheSound("weapons/discipline_device_power_up.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_back.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_forward.wav", true);
	PrecacheSound("weapons/sniper_shoot.wav", true);
	
	PrecacheModel("models/weapons/c_models/c_fireaxe_pyro.mdl",true);
	PrecacheModel("models/weapons/w_models/w_syringe_proj.mdl",true);
}


	// -={ Modifies attributes }=-

public Action TF2Items_OnGiveNamedItem(int iClient, char[] class, int index, Handle& item) {
	Handle item1;
	
	// Scout
	if (StrEqual(class, "tf_weapon_scattergun")) {		// Scattergun
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 37, 0.5625); // hidden primary max ammo bonus (reduced to 18)
		TF2Items_SetAttribute(item1, 1, 96, 1.1); // reload time decreased (0.55 seconds)
	}
	else if (StrEqual(class, "tf_weapon_pep_brawler_blaster")) {		// BFB
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 37, 0.5625); // hidden primary max ammo bonus (reduced to 18)
		TF2Items_SetAttribute(item1, 1, 96, 1.1); // reload time decreased (0.55 seconds)
		TF2Items_SetAttribute(item1, 2, 419, 0.001); // hype resets on jump (removed)
		TF2Items_SetAttribute(item1, 3, 733, 0.0); // lose hype on take damage (removed)
	}
	else if (StrEqual(class, "tf_weapon_bat")) {		// Bat
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.1428); // damage bonus (40)
		TF2Items_SetAttribute(item1, 1, 199, 0.7); // holster time decreased (30%)
		TF2Items_SetAttribute(item1, 2, 547, 0.7); // deploy time decreased (30%)
	}

	// Soldier
	else if (StrEqual(class, "tf_weapon_rocketlauncher")) {		// Rocket Launcher
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 2, 0.84); // damage penalty (90 to 75)
		TF2Items_SetAttribute(item1, 1, 107, 1.075); // move speed bonus (80% to 86%)
	}
	else if (StrEqual(class, "tf_weapon_rocketlauncher_directhit")) {		// Direct Hit
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 1, 1.0); // damage bonus (112 to 90)
		TF2Items_SetAttribute(item1, 1, 107, 1.075); // move speed bonus (80% to 86%)
	}
	else if (index == 133) {	// Gunboats
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 135, 0.8); // rocket jump damage reduction (20% base)
		TF2Items_SetAttribute(item1, 1, 610, 2.0); // Increased air control (200%)
	}
	else if (StrEqual(class, "tf_weapon_shovel")) {		// Shovel
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 1, 0.77); // damage penalty (down to 50)
	}
	
	// Pyro
	else if (StrEqual(class, "tf_weapon_flamethrower")) {		// All Flamethrowers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 839, 0.0); // flame_spread_degree (none)
		TF2Items_SetAttribute(item1, 1, 863, 0.0); // flame_random_lifetime_offset (none)
	}
	else if (StrEqual(class, "tf_weapon_fireaxe")) {		// Fire Axe
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty
	}
	
	// Demoman
	else if (StrEqual(class, "tf_weapon_pipebomblauncher")) {	// All Sticky Launchers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 1, 0.833333); // damage penalty (120 to 100)
		TF2Items_SetAttribute(item1, 1, 3, 0.75); // clip size penalty (6)
		TF2Items_SetAttribute(item1, 2, 37, 0.75); // hidden primary max ammo bonus (reduced to 18)
		TF2Items_SetAttribute(item1, 3, 96, 0.917431); // reload time decreased (first shot reload 1.0 seconds)
		TF2Items_SetAttribute(item1, 4, 670, 0.5); // stickybomb charge rate (50% faster)
	}
	
	// Heavy
	else if (StrEqual(class, "tf_weapon_minigun")) {	// All Miniguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 1, 0.88888); // damage bonus ()
		TF2Items_SetAttribute(item1, 1, 86, 1.15); // minigun spinup time increased (15%)
		TF2Items_SetAttribute(item1, 3, 107, 1.1217); // move speed bonus (10%)
	}
	else if ((StrEqual(class, "tf_weapon_shotgun") || StrEqual(class, "tf_weapon_shotgun_hwg")) && TF2_GetPlayerClass(iClient) == TFClass_Heavy) {	// All Heavy Shotguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 2, 1.666667); // damage bonus (6 to 10)
		TF2Items_SetAttribute(item1, 1, 45, 0.6); // bullets per shot penalty
		TF2Items_SetAttribute(item1, 2, 96, 0.8); // reload time decreased (consecutive reload 0.4 seconds; was 0.5)
		TF2Items_SetAttribute(item1, 3, 106, 0.8); // spread bonus (20%)
	}
	else if (TF2_GetPlayerClass(iClient) == TFClass_Heavy && (StrEqual(class, "tf_weapon_fists") || StrEqual(class, "saxxy"))) {	// All Fists
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 2, 1.1538); // damage bonus (65 to 75)
		TF2Items_SetAttribute(item1, 1, 547, 0.5); // single wep deploy time bonus (50%)
	}
	
	// Engineer
	else if (StrEqual(class, "tf_weapon_pistol") && TF2_GetPlayerClass(iClient) == TFClass_Engineer) {	// All Engineer Pistols
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 78, 0.18); // maxammo secondary reduced (36)
	}
	else if (StrEqual(class, "tf_weapon_wrench")) {	// All Engineer Pistols
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 95, 0.88); // repair rate decreased (102 to 90)
	}
	
	// Medic
	else if (StrEqual(class, "tf_weapon_syringegun_medic") && index != 412) {	// All Syringe Guns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 6);
		TF2Items_SetAttribute(item1, 0, 4, 0.5); // clip size bonus (20)
		TF2Items_SetAttribute(item1, 1, 37, 0.533333); // hidden primary max ammo bonus (150 to 60)
		TF2Items_SetAttribute(item1, 2, 6, 1.66); // fire rate bonus (0.166/sec)
		TF2Items_SetAttribute(item1, 3, 280, 9.0); // override projectile type (to flame rocket, which disables projectiles entirely)
		TF2Items_SetAttribute(item1, 4, 772, 0.7); // deploy time decreased (30%)
		TF2Items_SetAttribute(item1, 5, 96, 1.15);		// Slower reload speed
	}
	else if (StrEqual(class, "tf_weapon_medigun")) {	// All Medi-Guns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 9, 0.0); //  ubercharge rate penalty (No normal Uber build)
	}
	
	// Sniper
	else if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {		// Sniper Rifle
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 6);
		TF2Items_SetAttribute(item1, 0, 1, 0.8); // damage penalty (80%)
		TF2Items_SetAttribute(item1, 1, 318, 0.533333); // fire rate bonus (0.8 seconds)
		TF2Items_SetAttribute(item1, 2, 75, 1.25); // aiming movespeed increased (+25%)
		TF2Items_SetAttribute(item1, 3, 90, 1.09); // SRifle charge rate increased (109%)
		TF2Items_SetAttribute(item1, 4, 76, 0.56); // maxammo primary decreased (-44%, 14 rounds left)
		TF2Items_SetAttribute(item1, 5, 647, 1.0); // sniper fires tracers HIDDEN
	}
	
	else if (StrEqual(class, "tf_weapon_sniperrifle_decap")) {		// The Bazaar Bargain specifically
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 1, 0.8); // damage penalty (80%)
		TF2Items_SetAttribute(item1, 1, 75, 2.25); // aiming movespeed increased (+225%)
		TF2Items_SetAttribute(item1, 2, 90, 1.935); // SRifle charge rate increased (193.5%)
		TF2Items_SetAttribute(item1, 3, 46, 1.667); // sniper zoom penalty (~40% reduced zoom)
		TF2Items_SetAttribute(item1, 4, 647, 1.0); // sniper fires tracers HIDDEN
	}
	
	else if (StrEqual(class, "tf_weapon_smg")) {		// SMG (the Carbine is a different archetype)
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.25); // damage bonus (+25%)
		TF2Items_SetAttribute(item1, 1, 96, 1.3636); // reload time increased (36.36%; 1.5 sec)
	}
	
	else if (index == 58 || index == 1083) {		// Jarate
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 874, 1.5); // mult_item_meter_charge_rate
	}
	
	else if (index == 231) {		// Darwin's Danger Shield
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 26, 15.0); // max health additive bonus (15)
		TF2Items_SetAttribute(item1, 1, 60, 1.0); // dmg taken from fire reduced (removed)
		TF2Items_SetAttribute(item1, 2, 527, 0.0); // afterburn immunity (removed)
	}
	
	else if (StrEqual(class, "tf_weapon_club")) {		// All of Sniper's melees
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 1, 0.731); // damage penalty (-26.9%)
		TF2Items_SetAttribute(item1, 1, 6, 0.75); // fire rate bonus (-25%; 0.25 sec)
	}
	
	else if (index == 171) {		// The Tribalman's Shiv specifically
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 6, 0.875); // fire rate bonus (-12.5%; half of stock)
		TF2Items_SetAttribute(item1, 1, 772, 1.3); // single wep holster time increased (30%)
		TF2Items_SetAttribute(item1, 2, 149, 4.0); // bleeding duration (4 seconds)
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
	else if (StrEqual(class, "tf_weapon_revolver")) {
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 51, 1.0); // revolver use hit locations
		TF2Items_SetAttribute(item1, 1, 97, 0.8826); // reload time decreased (+33.3%)
		TF2Items_SetAttribute(item1, 2, 107, 1.0654); // faster move speed on wearer (+6.5%)
	}

	else if (StrEqual(class, "tf_weapon_knife")) {
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


public void OnEntityCreated(int iEnt, const char[] classname) {
	if (IsValidEdict(iEnt)) {
		if (StrEqual(classname,"obj_sentrygun") || StrEqual(classname,"obj_dispenser") || StrEqual(classname,"obj_teleporter")) {
			//SDKHook(iEnt, SDKHook_SetTransmit, BuildingThink);
			SDKHook(iEnt, SDKHook_OnTakeDamage, BuildingDamage);
		}
		if (StrEqual(classname, "tf_projectile_syringe")) {
			SDKHook(iEnt, SDKHook_SpawnPost, needleSpawn);
		}
	}
}


	// -={ Sniper Rifle noscope headshot hit registration }=-

Action TraceAttack(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& ammo_type, int hitbox, int hitgroup) {		// Need this for noscope headshot hitreg
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {
		if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
			if (damage_type & DMG_CLUB || damage_type & DMG_SLASH) {		// Multi-hit axe
				//CreateTimer(0.2, AxeSwing, attacker); 
			}
		}
		
		if (hitgroup == 1 && (TF2_GetPlayerClass(attacker) == TFClass_Sniper)) {		// Hitgroup 1 is the head
			players[attacker].headshot_frame = GetGameTickCount();		// We store headshot status in a variable for the next function to read
		}
	}
	return Plugin_Continue;
}

public Action AxeSwing(Handle timer, int iClient) {
	if (IsValidClient(iClient)) {
		
		players[iClient].iAxe_Count += 1;
		if (players[iClient].iAxe_Count <= 3) {
		
			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
			
			if (iActive == iMelee) {
				float vecPos[3], vecAng[3], maxs[3], mins[3];
				
				GetClientEyePosition(iClient, vecPos);
				GetClientEyeAngles(iClient, vecAng);
				
				GetAngleVectors(vecAng, vecAng, NULL_VECTOR, NULL_VECTOR);		// generates a vector in the direction of the eye angles
				ScaleVector(vecAng, 48.0);							// Scale this vector up to match melee range
				AddVectors(vecPos, vecAng, vecAng);							// adding this vector to the position vector lets the game better identify what we're looking at
				
				maxs[0] = 20.0;
				maxs[1] = 20.0;
				maxs[2] = 5.0;
				
				mins[0] = (0.0 - maxs[0]);
				mins[1] = (0.0 - maxs[1]);
				mins[2] = (0.0 - maxs[2]);
				
				TR_TraceHullFilter(vecPos, vecAng, mins, maxs, MASK_SOLID, TraceFilter_ExcludeSingle, iClient);
				
				if (TR_DidHit()) {
					int iEnt = TR_GetEntityIndex();
					
					if (iEnt >= 1 && iEnt <= MaxClients && GetClientTeam(iEnt) != GetClientTeam(iClient)) {
						SDKHooks_TakeDamage(iEnt, iClient, iClient, 30.0, DMG_SHOCK, iMelee,_,_, false);
					}
				}
				
				CreateTimer(0.2, AxeSwing, iClient); 
			}
		}
	}
	return Plugin_Continue;
}


bool TraceFilter_ExcludeSingle(int entity, int contentsmask, any data) {
	return (entity != data);
}


	// -={ Dynamically updates the attributes of Sniper's melees based on the Head counter, and handles Rifle reload }=-

public void OnGameFrame() {
	int iClient;		// Index; lets us run through all the players on the server	
	SetConVarString(cvar_ref_tf_parachute_aircontrol, "3.5");

	for (iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int primaryIndex = -1;
			if (iPrimary >= 0) {
				primaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			}
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int secondaryIndex = -1;
			if (iSecondary >= 0) {
				secondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			}
			
			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int meleeIndex = -1;
			if (iMelee >= 0) {
				meleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			}
			
			int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
			
			
			float dmgTime = GetEntDataFloat(iClient, 8968); //m_flLastDamageTime
			float currTime = GetGameTime();
			if (currTime - dmgTime < 10.0 && currTime - dmgTime > 1.0) {		// Normally, Crit heals start ramping up at 10 seconds; we want it to start at 1
				SetEntDataFloat(iClient, 8968, dmgTime - 0.045, true);		// Scale up three times as fast, so that we reach this point after 
			}
			else if (currTime - dmgTime < 15.0) {		// We want Crit heals to max out at 10 seconds now
				SetEntDataFloat(iClient, 8968, dmgTime - 0.0075, true);		// Scale this up four times as fast
			}
			
			
			// BASE Jumper
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
			
			TFClassType tfAttackerClass = TF2_GetPlayerClass(iClient);
			switch(tfAttackerClass)
			{
				// Scout
				case TFClass_Scout: {
					
					// Baby Face's Blaster
					if (primaryIndex == 772) {
						float fHype = GetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter");		// This is our Boost
						float vecVel[3];
						GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
						if (vecVel[2] != 0 && !(GetEntityFlags(iClient) & FL_ONGROUND) && fHype > 24.75) {		// Are we airborne with more than 25% Boost?
							TF2Attrib_SetByDefIndex(iPrimary, 326, 1.0 - ((fHype - 24.75) / 74.25));		// increased jump height attribute (decreasing proportionally to Boost)
						}
						else {
							TF2Attrib_SetByDefIndex(iPrimary, 326, 1.0);		// Reset jump height to normal while grounded
						}
						if (players[iClient].fBoosting > 0.0) {
							SetHudTextParams(-0.1, -0.16, 0.1, 255, 255, 255, 255);
							ShowHudText(iClient, 1, "Boosting!: %.1f", players[iClient].fBoosting);
							
							players[iClient].fBoosting -= 0.015;		// Decrease by 1 second every ~66.6 server ticks
							SetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter", 0.0);
						}
						if (players[iClient].fBoosting < 0.0) {
							players[iClient].fBoosting = 0.0;	// Failsafe
						}
					}
				}
				
				// Soldier
				case TFClass_Soldier: {
					// Gunboats scaling resistance after blast jump
					if (players[iClient].fAxe_Cooldown < 15.0) {
						
					}
					if (secondaryIndex == 133) {
						if (TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping)) {
							TF2Attrib_SetByDefIndex(iSecondary, 135, 0.6);		// rocket jump damage reduction (doubled to 40%)
						}
						else {
							TF2Attrib_SetByDefIndex(iSecondary, 135, 0.8);		// rocket jump damage reduction (doubled to 40%)
						}
						TF2Attrib_SetByDefIndex(iSecondary, 610, 2.0);
					}
					else {
						TF2Attrib_SetByDefIndex(iSecondary, 135, 1.0);		// Reset this if the Gunboats are not equipped
						TF2Attrib_SetByDefIndex(iSecondary, 610, 1.0);
					}
					
					// Shovel faster deploy when out of rockets
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int clip = GetEntData(iPrimary, iAmmoTable, 4);
					
					if (clip > 0) {
						TF2Attrib_SetByDefIndex(iMelee, 772, 1.0);
					}
					else {
						TF2Attrib_SetByDefIndex(iMelee, 772, 0.6);
					}
				}

				// Pyro
				case TFClass_Pyro: {
					// Faster melee deploy on Airblast
					
					/* *Flamethrower weaponstates*
						0 = Idle
						1 = Start firing
						2 = Firing
						3 = Airblasting
					*/
					
					SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 1, "Axe: %.0f%%", 6.667 * players[iClient].fAxe_Cooldown);
					
					if (players[iClient].fAxe_Cooldown < 15.0) {
						players[iClient].fAxe_Cooldown += 0.015;
					}
					else if (players[iClient].fAxe_Cooldown >= 15.0) {
						players[iClient].fAxe_Cooldown = 15.0;
					}
				
					// Phlogistinator
					int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
					if (weaponState == 3) {
						TF2Attrib_SetByDefIndex(iMelee, 772, 0.6);
					}
				}
				
				// Heavy
				case TFClass_Heavy: {
					
					int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					float cycle = GetEntPropFloat(view, Prop_Data, "m_flCycle");
					
					SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 1, "Sprint: %.0f%%", 10.0 * players[iClient].fFists_Sprint);
					
					if (players[iClient].fFists_Sprint < 10.0) {
						players[iClient].fFists_Sprint += 0.015;		// Count up to 10 seconds
					}
					else if (players[iClient].fFists_Sprint >= 10.0) {
						players[iClient].fFists_Sprint = 10.0;
					}

					if (players[iClient].fUppercut_Cooldown < 1.0) {
						players[iClient].fUppercut_Cooldown += 0.015;
					}
					else if (players[iClient].fUppercut_Cooldown >= 1.0) {
						players[iClient].fUppercut_Cooldown = 1.0;
						TF2Attrib_AddCustomPlayerAttribute(iClient, "fire rate penalty", 1.0);
					}
					
					if (iActive == iMelee) {
						SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 258.0 + 1.5 * players[iClient].fFists_Sprint);
					}
					
					if (iActive == iPrimary && weaponState == 0) {		// Weaponstate 0 = idle
						SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 232.2);
					}
					
					// Counteracts the L&W nerf by dynamically adjusting damage and accuracy
					if (weaponState == 1) {		// Are we revving up?
						players[iClient].fRev = 1.005;		// This is our rev meter; it's a measure of how close we are to being free of the L&W nerf
						players[iClient].fBrace_Time = 3.0;
					}
					
					else if ((weaponState == 2 || weaponState == 3) && players[iClient].fRev > 0.0) {		// If we're revved (or firing) but the rev meter isn't empty...
						players[iClient].fRev = players[iClient].fRev - 0.015;		// It takes us 67 frames (1 second) to fully deplete the rev meter
					}
					
					if (weaponState == 2 || weaponState == 3) {
						players[iClient].fBrace_Time -= 0.015;
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
					
					int time = RoundFloat(players[iClient].fRev * 1000);		// Time slowly decreases
					if (time % 100 == 0) {		// Only trigger an update every 0.1 sec
						float factor = 1.0 + time / 1000.0;		// This value continuously decreases from ~2 to 1 over time
						TF2Attrib_SetByDefIndex(iPrimary, 106, 1.0 / factor);		// Spread bonus
						TF2Attrib_SetByDefIndex(iPrimary, 2, 1.0 * factor);		// Damage bonus
					}
				}

				// Medic
				case TFClass_Medic: {
					
					// Handles Syringe Gun rebuild
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int iClip = GetEntData(iPrimary, iAmmoTable, 4);		// We can detect shots by checking ammo changes
					if (iClip == (players[iClient].iSyringe_Ammo - 1) && primaryIndex != 412) {		// We update iSyringe_Ammo after this check, so iClip will always be 1 lower on frames in which we fire a shot
						float vecAng[3];
						GetClientEyeAngles(iClient, vecAng);
						Syringe_PrimaryAttack(iClient, iPrimary, vecAng);
					}
					players[iClient].iSyringe_Ammo = iClip;
					
					// Syringe tactical and autoreload
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					if (iClip < 20) {
						if (iActive == iPrimary && sequence != 7) {	// 7 = Syringe Gun draw (basically, don't reset until we've fully drawn)
							players[iClient].fTac_Reload = 2.0;		// Prep the 1.5 second timer to start when we swap weapons
						}
						else {
							players[iClient].fTac_Reload -= 0.015;		// Starts timer
						}
						
						if (players[iClient].fTac_Reload <= 0.0) {		// This happens in exactly 100 ticks
							Syringe_Autoreload(iClient);	// Perform an autoreload
						}
						
						TF2Attrib_SetByDefIndex(iPrimary, 547, RemapValClamped(players[iClient].fTac_Reload, 2.0, 0.0, 4.0, 1.0));		// Deploy time extended proportionally to fTac_Reload
					}
					else {
						players[iClient].fTac_Reload = 0.0;
						TF2Attrib_SetByDefIndex(iPrimary, 547, 1.0);		// Reset this
					}
					//PrintToChatAll("TacReload: %f", players[iClient].fTac_Reload);
				}
				
				// Sniper
				case TFClass_Sniper: {
					
					// Reload
					if (primaryIndex != 56 && primaryIndex != 1005 && primaryIndex != 1092) {		// Do not trigger on Huntsman
						int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
						int reload = GetEntProp(iPrimary, Prop_Send, "m_iReloadMode");
						int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
						float cycle = GetEntPropFloat(view, Prop_Data, "m_flCycle");
						if (sequence == 29 || sequence == 28) {
							if (cycle >= 1.0) SetEntProp(view, Prop_Send, "m_nSequence", 30);
						}

						if (reload != 0) {
							float reloadSpeed = 1.5;
							float clientPos[3];
							GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", clientPos);

							int relSeq = 51;		// This used to be 41
							float altRel = 0.875;
							
							SetEntPropFloat (view, Prop_Send, "m_flPlaybackRate",(altRel*2.0)/reloadSpeed);
							
							if (reload == 1) {
								if (sequence != relSeq) SetEntProp(view, Prop_Send, "m_nSequence",relSeq);
								SetEntPropFloat(view, Prop_Data, "m_flCycle", g_meterPri[iClient]); //1004
								SetEntDataFloat(view, 1004, g_meterPri[iClient], true); //1004
								if (g_meterPri[iClient] / reloadSpeed > 0.1) {
									EmitAmbientSound("weapons/widow_maker_pump_action_forward.wav", clientPos, iClient, SNDLEVEL_TRAIN, _, 0.4);
									SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 2);
								}
							}
							else if (reload == 2) {
								if(sequence != relSeq) SetEntProp(view, Prop_Send, "m_nSequence",relSeq);
								SetEntPropFloat(view, Prop_Data, "m_flCycle",g_meterPri[iClient]); //1004
								SetEntDataFloat(view, 1004,g_meterPri[iClient], true); //1004
								if(g_meterPri[iClient] / reloadSpeed > 0.4) {
									EmitAmbientSound("weapons/revolver_reload_cylinder_arm.wav", clientPos, iClient, SNDLEVEL_TRAIN, _, 0.4);
									SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 3);
								}
							}
							else if (reload == 3) {
								if(sequence != relSeq) SetEntProp(view, Prop_Send, "m_nSequence",relSeq);
								SetEntPropFloat(view, Prop_Data, "m_flCycle",g_meterPri[iClient]); //1004
								SetEntDataFloat(view, 1004,g_meterPri[iClient], true); //1004
								if(g_meterPri[iClient] / reloadSpeed > 0.8) {
									EmitAmbientSound("weapons/widow_maker_pump_action_back.wav", clientPos, iClient, SNDLEVEL_TRAIN, _, 0.4);
									SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 4);
								}
							}
							g_meterPri[iClient] += 1.0 / 66;
						}
					}
					
					// Sniper Rifle tactical and autoreload
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int iClip = GetEntData(iPrimary, iAmmoTable, 4);
					
					// Sniper Rifle audio to other players
					if (iClip == (players[iClient].iRifle_Ammo - 1)) {		// We update iRifle_Ammo after this check, so iClip will always be 1 lower on frames in which we fire a shot
						if (GetEntPropFloat(iPrimary, Prop_Send, "m_flChargedDamage") <= 0.0) {		// Were we scoped?
							for (int iNearby = 1; iNearby <= MaxClients; iNearby++) {		// This variable is meant to identify players who are close enough to the Sniper
								if (IsClientInGame(iNearby) && IsPlayerAlive(iNearby)) {
									float vecShooter[3], vecNearby[3];
									GetClientEyePosition(iClient, vecShooter);
									GetClientEyePosition(iNearby, vecNearby);
									
									float fDistance = GetVectorDistance(vecShooter, vecNearby);
									
									if (GetEntProp(iClient, Prop_Send, "m_iTeamNum") != GetEntProp(iNearby, Prop_Send, "m_iTeamNum")) {
										
										if (fDistance <= 2000.0 && fDistance >= 500.0) {
											EmitSoundToClient(iNearby, "weapons/sniper_shoot.wav", _, _, _, _, RemapValClamped(fDistance, 500.0, 1000.0, 0.35, 0.7));
										}
										else if (fDistance >= 2000.0) {
											EmitSoundToClient(iNearby, "weapons/sniper_shoot.wav", _, _, _, _, RemapValClamped(fDistance, 2000.0, 4000.0, 0.7, 0.0));
										}
									}
									
								}
							}
							
							SetEntPropFloat(iPrimary, Prop_Send, "m_flNextPrimaryAttack", (GetGameTime() + 0.8));
						}
						else {
							SetEntPropFloat(iPrimary, Prop_Send, "m_flNextPrimaryAttack", (GetGameTime() + 0.6));
						}
					}
					players[iClient].iRifle_Ammo = iClip;
					
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					if (iClip < 3) {
						if (iActive == iPrimary && sequence != 28) {	// 28 = Sniper Rifle draw (basically, don't reset until we've fully drawn)
							players[iClient].fTac_Reload = 2.0;		// Prep the 2 second timer to start when we swap weapons
						}
						else {
							players[iClient].fTac_Reload -= 0.015;		// Starts timer
						}
						
						if (players[iClient].fTac_Reload <= 0.0) {		// This happens in exactly 100 ticks
							Rifle_Autoreload(iClient);	// Perform an autoreload
						}
						
						TF2Attrib_SetByDefIndex(iPrimary, 547, RemapValClamped(players[iClient].fTac_Reload, 2.0, 0.0, 4.0, 1.0));		// Deploy time extended proportionally to fTac_Reload
					}
					else {
						players[iClient].fTac_Reload = 0.0;
						TF2Attrib_SetByDefIndex(iPrimary, 547, 1.0);		// Reset this
					}
					//PrintToChatAll("TacReload: %f", players[iClient].fTac_Reload);
					
					// Melees
					// Dynamically adjusts melee stats depending on Heads
					if (iActive == iMelee) {
						switch(meleeIndex) {		// Kukri
							case 3, 193, 264, 423, 474, 880, 939, 954, 1013, 1071, 1123, 1127, 30758: {		// Kukri and reskins
								//TF2Attrib_SetByDefIndex(iMelee, 107, 1.0 + 0.04 * players[iClient].iHeads);		// Speed bonus while active
								SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 300.0 + 15.0 * players[iClient].iHeads);
							}
							case 171: {		// Tribalman's Shiv
								TF2Attrib_SetByDefIndex(iMelee, 205, 1.0 - 0.5 * players[iClient].iHeads);		// dmg from ranged reduced
								TF2Attrib_SetByDefIndex(iMelee, 206, 1.0 - 0.5 * players[iClient].iHeads);		// dmg from melee reduced
								if (GetClientHealth(iClient) < 38.0) {		// Disable holster at low health
									TF2_AddCondition(iClient, TFCond_RestrictToMelee, 0.02, 0);		// Buffalo Steak strip to melee debuff
								}
							}
							/*case 401: {		// Shahanshah
								TF2Attrib_SetByDefIndex(iMelee, 26, 10 * players[iClient].iHeads);		// max health additive bonus
							}*/
						}
					}
					else {
						TF2Attrib_SetByDefIndex(iMelee, 107, 1.0);
					}
					
					// Dynamically adjusts Sniper fire rate depending on scope status
					if (primaryIndex != 56 && primaryIndex != 1005 && primaryIndex != 1092) {
						if (GetEntPropFloat(iPrimary, Prop_Send, "m_flChargedDamage") < 0.001) {
							TF2Attrib_SetByDefIndex(iPrimary, 5, 0.933333);		// fire rate penalty
						}
						else {
							TF2Attrib_SetByDefIndex(iPrimary, 5, 1.2);
						}
					}
					
					// Heads counter display
					if (GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon") == TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true) ||
					GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon") == TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true)) {		// Display Heads if we're holding a primary or melee
						SetHudTextParams(-0.1, -0.13, 0.1, 255, 255, 255, 255);
						ShowHudText(iClient, 1, "Heads: %i", players[iClient].iHeads);
					}

					// DDS debuff reduction
					if (secondaryIndex == 231) {		// Darwin's Danger Shield
						float fDebuff;
						if (TF2Util_GetPlayerBurnDuration(iClient) > 0.0) {		// Shave off 33% of duration
							fDebuff = TF2Util_GetPlayerBurnDuration(iClient);
							TF2Util_SetPlayerBurnDuration(iClient, fDebuff - 0.00495);		// This is the equivalent of 33% of a tick
						}
						
						if (TF2_IsPlayerInCondition(iClient, TFCond_Jarated)) {
							fDebuff = TF2Util_GetPlayerConditionDuration(iClient, TFCond_Jarated);
							TF2Util_SetPlayerConditionDuration(iClient, TFCond_Jarated, fDebuff - 0.00495);
						}
						
						if (TF2_IsPlayerInCondition(iClient, TFCond_Milked)) {
							fDebuff = TF2Util_GetPlayerConditionDuration(iClient, TFCond_Milked);
							TF2Util_SetPlayerConditionDuration(iClient, TFCond_Milked, fDebuff - 0.00495);
						}

						if (TF2_IsPlayerInCondition(iClient, TFCond_Gas)) {
							fDebuff = TF2Util_GetPlayerConditionDuration(iClient, TFCond_Gas);
							TF2Util_SetPlayerConditionDuration(iClient, TFCond_Gas, fDebuff - 0.00495);
						}
					}
				}
			}
			
			// These things are not class-dependent
			if (TF2_GetPlayerClass(iClient) != TFClass_Sniper) {
				players[iClient].iHeads = 0;		// Reset Heads if we change classes without dying
			}
			
			// Tracks Bleed on Tribalman's Shiv victims
			if (players[iClient].fBleed_Timer > 0.0) {	
				players[iClient].fBleed_Timer -= 0.015;		// Decrease by 1 second every ~66.6 server ticks
			}
			if (players[iClient].fBleed_Timer < 0.0) {
				players[iClient].fBleed_Timer = 0.0;	// Failsafe
			}
		}
	}
}


	// -={ Resets variables on death; sets Spy's collision hull }=-
	
Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {
	int iClient;
	
	if (StrEqual(name, "player_spawn")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsPlayerAlive(iClient)) {
			
			players[iClient].iHeads = 0;
			players[iClient].fBleed_Timer = 0.0;
			players[iClient].fBoosting = 0.0;
			players[iClient].fTac_Reload = 0.0;
			players[iClient].fFists_Sprint = 0.0;
			
			/*if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {		// Shrink Spy's colision hull
				// Normal collision hull dimensions are 49, 49 83
				// Or mins { -24.5, -24.5, 0.0 } maxs { 24.5, 24.5, 83.0 }
				SetEntPropVector(iClient, Prop_Send, "m_vecSpecifiedSurroundingMins", {-18.375, -18.375, 0.0});
				SetEntPropVector(iClient, Prop_Send, "m_vecSpecifiedSurroundingMaxs", {18.375, 18.375, 83.0});
			}
			else {
				SetEntPropVector(iClient, Prop_Send, "m_vecSpecifiedSurroundingMins", {-24.5, -24.5, 0.0});
				SetEntPropVector(iClient, Prop_Send, "m_vecSpecifiedSurroundingMaxs", {24.5, 24.5, 83.0});
			}*/
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			//int iSecondaryIndex = -1;
			//if (iSecondary >= 0) {
			//	iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			//}

			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if (iPrimary >= 0) {
				iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			}
			
			// Prevents incorrect ammo distrubition when swapping from one Pistol-wielder to the other
			if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
				char class[64];
				GetEntityClassname(iSecondary, class, sizeof(class));	
				if (StrEqual(class, "tf_weapon_pistol") || StrEqual(class, "tf_weapon_pistol_scout")) {
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, iSecondaryAmmo);
					TF2Attrib_SetByDefIndex(iSecondary, 78, 1.0);		// Reserves
				}
			}

			else if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
				char class[64];
				GetEntityClassname(iSecondary, class, sizeof(class));	
				if (StrEqual(class, "tf_weapon_pistol")) {
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, iSecondaryAmmo);
					TF2Attrib_SetByDefIndex(iSecondary, 78, 0.18);
				}
			}
			
			// Sniper
			else if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
				if (iPrimaryIndex != 56 && iPrimaryIndex != 1005 && iPrimaryIndex != 1092) {		// Ignore the Huntsman and reskins
				
					TF2Attrib_SetByDefIndex(iPrimary, 77, 0.8); //set max ammo

					//set clip and reserve
					TF2Attrib_SetByDefIndex(iPrimary, 303, 3.0); //set clip ammo
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int clip = 3;		// Default mag of 3

					SetEntData(iPrimary, iAmmoTable, clip, 4, true);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1",clip);
					int reserve = 12;

					int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", reserve , _, primaryAmmo);
				}
			}
		}
	}
	
	else if (StrEqual(name, "item_pickup")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(iClient)) {
		
			char class[64];
			GetEventString(event, "item", class, sizeof(class));
			
			if (StrContains(class, "medkit_small") == 0) {
				
				int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
				int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
				int newHealth = RoundFloat(iHealth + iMaxHealth * 0.05);
				if (newHealth > iMaxHealth) {
					newHealth = iMaxHealth;
				}
				SetEntProp(iClient, Prop_Send, "m_iHealth", newHealth);
				//CreateTimer(0.4, HealPopup, iClient, newHealth);
			}
			/*else if (StrContains(class, "ammopack_small") == 0) {
				if (IsValidClient(iClient)) {
					
					int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
					int iPrimaryIndex = -1;
					if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
					int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
				
					if (iPrimary != -1) {
						int PrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
						int PrimaryAmmoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, PrimaryAmmo);
						
						GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
						// Scatterguns
						if (StrEqual(class, "tf_weapon_scattergun")) {
							if (PrimaryAmmoCount < 18) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 11, _, PrimaryAmmo);
							}
						}
						// Flamethrowers, Syringe Guns (excluding Blutsauger)
						else if (StrEqual(class, "tf_weapon_flamethrower") || (StrEqual(class, "tf_weapon_syringegun_medic") && iPrimaryIndex != 36)) {
							if (PrimaryAmmoCount < 190) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 10, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 200, _, PrimaryAmmo);
							}
						}
						// Miniguns
						else if (StrEqual(class, "tf_weapon_minigun")) {
							if (PrimaryAmmoCount < 142) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 8, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 150, _, PrimaryAmmo);
							}
						}
						// Grenade Launchers
						else if (StrEqual(class, "tf_weapon_grenadelauncher")) {
							if (PrimaryAmmoCount < 24) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 1, _, PrimaryAmmo);
							}
						}
						// Engie Shotgun
						else if (StrEqual(class, "tf_weapon_shotgun_primary")) {
							if (PrimaryAmmoCount < 36) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 1, _, PrimaryAmmo);
							}
						}
						// Blutsauger
						else if (iPrimaryIndex == 36) {
							if (PrimaryAmmoCount < 114) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 6, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 120, _, PrimaryAmmo);
							}
						}
					}
					if (iSecondary != -1) {
						int SecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
						int SecondaryAmmoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, SecondaryAmmo);
						
						GetEntityClassname(iPrimary, class, sizeof(class));	
						// Pistol
						if (StrEqual(class, "tf_weapon_pistol") || StrEqual(class, "tf_weapon_pistol_scout")) {
							if (SecondaryAmmoCount < 35) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 1, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, SecondaryAmmo);
							}
						}
						// Sticky Launchers
						else if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
							if (SecondaryAmmoCount < 24) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 1, _, SecondaryAmmo);
							}
						}
						// Shotguns
						else if (StrEqual(class, "tf_weapon_shotgun") || StrEqual(class, "tf_weapon_shotgun_hwg") || StrEqual(class, "tf_weapon_shotgun_pyro") || StrEqual(class, "tf_weapon_shotgun_soldier")) {
							if (SecondaryAmmoCount < 36) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 1, _, SecondaryAmmo);
							}
						}
						// SMG
						else if (StrEqual(class, "tf_weapon_smg")) {
							if (SecondaryAmmoCount < 71) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 4, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 75, _, SecondaryAmmo);
							}
						}
						// SMG
						else if (StrEqual(class, "tf_weapon_revolver")) {
							if (SecondaryAmmoCount < 17) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 1, _, SecondaryAmmo);
							}
						}
					}

					// Metal
					int iMetal = GetEntData(iClient, FindDataMapInfo(iClient, "m_iAmmo") + (3 * 4), 4);
					if (iMetal < 190) {
						SetEntData(iClient, FindDataMapInfo(iClient, "m_iAmmo") + (3 * 4), iMetal + 10, 4);
					}
					else {
						SetEntData(iClient, FindDataMapInfo(iClient, "m_iAmmo") + (3 * 4), 200, 4);
					}
					
					// Cloak
					float fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
					SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak + 5.0);
				}
			}*/
		}
	}
	return Plugin_Continue;
}


	// -={ Calculates damage }=-

Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& weapon, float damage_force[3], float damage_position[3], int damage_custom) {

	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients && GetClientTeam(victim) != GetClientTeam(attacker)) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			float vecAttacker[3];
			float vecVictim[3];
			float fDmgMod = 1.0;
			GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
			GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
			float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
			
			TFClassType tfAttackerClass = TF2_GetPlayerClass(attacker);
			
			int primary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int primaryIndex = -1;
			if (primary >= 0) {
				primaryIndex = GetEntProp(primary, Prop_Send, "m_iItemDefinitionIndex");
			}
			
			switch(tfAttackerClass)
			{
				// Scout
				case TFClass_Scout: {
					
					if (primaryIndex == 772) {
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
						
						if (isKritzed(attacker)) {		// Account for critical damage
							fDmgMod = 3.0;
						}
						else if (isMiniKritzed(attacker, victim)) {
							if (fDistance > 512.0) {
								fDmgMod = 1.35;
							}
							else {
								fDmgMod *= 1.35;
							}
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
			
				// Soldier
				case TFClass_Soldier: {
					if ((StrEqual(class, "tf_weapon_rocketlauncher") || StrEqual(class, "tf_weapon_rocketlauncher_directhit")) && fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 150%
						damage *= fDmgMod;
						return Plugin_Changed;
					}
					else if (StrEqual(class, "tf_weapon_shovel")) {
						damage += 0.12 * GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, victim);		// Adds 12% of victim's max health as damage
						
						if (damage > GetEntProp(victim, Prop_Send, "m_iHealth")) {
							// Reload 1 rocket
							int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
							int clip = GetEntData(primary, iAmmoTable, 4);
							
							int primaryAmmo = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
							int ammoCount = GetEntProp(attacker, Prop_Data, "m_iAmmo", _, primaryAmmo);
							
							if (clip < 4 && ammoCount > 0) {
								SetEntProp(attacker, Prop_Data, "m_iAmmo", ammoCount - 1 , _, primaryAmmo);
								SetEntData(primary, iAmmoTable, clip + 1, 4, true);
							}
						}
			
						return Plugin_Changed;
					}
				}

				// Heavy
				case TFClass_Heavy: {
					if (StrEqual(class, "tf_weapon_minigun") && fDistance < 512.0) {
						float fBraceMod = SimpleSplineRemapValClamped(players[attacker].fBrace_Time, 3.0, 0.0, 1.0, 1.5);
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, fBraceMod, -fBraceMod + 2.0) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Ramp-up increases to 150% over time
						damage *= fDmgMod;
						return Plugin_Changed;
					}
				}
				
				// Medic
				case TFClass_Medic: {
					if (StrEqual(class, "tf_weapon_syringegun_medic")) {
						if (!isKritzed(attacker)) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 0.5, 1.5);		// Gives us our ramp-up/fall-off multiplier (+/- -50%)
							if (isMiniKritzed(attacker, victim) && fDistance < 512.0) {
								fDmgMod = 1.0;
							}
						}
						else {
							fDmgMod = 3.0;
							damage_type |= DMG_CRIT;
						}
						damage = 15.0;
						damage *= fDmgMod;
						return Plugin_Changed;
					}
				}
			
				// Sniper
				case TFClass_Sniper: {
					if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {						
						if (GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage") <= 0.0) {		// Detects if we have no charge (because we're unscoped)
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our distance multiplier
							damage *= fDmgMod;
							
							if (damage_type & DMG_CRIT != 0) {		// Removes headshot Crits when we aren't detected to be scoped in (as a precaution, and to prevent Crits during the 0.1 second interval where we're able to headshot but not charge)
								damage_type = (damage_type & ~DMG_CRIT);
							}
							
							if (fDistance < 512.0) {		// Noscope headshots
								if (players[attacker].headshot_frame == GetGameTickCount()) {		// Here we look at headshot status
									TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.001, 0);		// Applies a Mini-Crit
									damage_custom = TF_CUSTOM_HEADSHOT;		// No idea if this does anything, honestly
									SMG_Autoreload(attacker);
									if (GetEntProp(victim, Prop_Send, "m_iHealth") < damage * 1.35) {		// If we land a kill
										players[attacker].iHeads += 1;		// Add a Head
										if 	(players[attacker].iHeads > 3) {
											players[attacker].iHeads = 3;
										}
									}
								}
							}
						}
						
						else {		// If we're scoped...
							if (StrEqual(class, "tf_weapon_sniperrifle")) {		// Stock Rifle
							
								damage = 40.0;
								fDmgMod = RemapValClamped(fDistance, 0.0, 1024.0, 0.75, 1.25);		// We've swapped to a linear equation for now
								
								float fCharge;
								fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");		// Records charge damage
								if (fDistance < 512) {		// If we're up close...
									fDmgMod += -1.0;		// Gives us the amount of *extra* fall-off damage only (-0.25-0.0)
									fDmgMod = 4 * fDmgMod * (-0.003125 * fCharge + 0.46875) + 1.0; // Generate the charge multiplier fCharge (0.25-2.75), multiply by 4 times the distance multiplier fDmgMod (0-1), and add 1
										// We want the multiplier to become 0 at max (150) charge
										// https://www.omnicalculator.com/math/line-equation-from-two-points gives us an equation that hits both ([0.7/1.5]*150, -0.25) and (150, 0)
										// y = 0.0022500002x - 0.3375000328
										// y = -0.003125x + 0.46875
									damage *= fDmgMod;
								}
								
								else {		// If we're not up close...
									if (fCharge < 38.8889) {		// If we've spent less than 0.7 seconds charging, fix this value
										fCharge = 38.8889;
									}
									fDmgMod += -1.0;		// Gives us the amount of *extra* ramp-up damage only (0.0-0.25)
									fDmgMod = 4 * fDmgMod * (0.0225 * fCharge - 0.625) + 1.0; // Generate the charge multiplier fCharge (0.25-2.75), multiply by 4 times the distance multiplier fDmgMod (0-1), and add 1
										// We multiply by 4 because it turns fDmgMod into a proportion from 0 to 1 for this range of distances
										// https://www.omnicalculator.com/math/line-equation-from-two-points gives us an equation that hits both ([0.7/2.7]*150, 0.25) and (150, 2.75)
										// y = 0.0225000023x - 0.6250003394
									damage *= fDmgMod;									
								}
								
								if (damage_type & DMG_CRIT != 0) {		// Removes headshot Crits when we aren't detected to be scoped in (as a precaution, and to prevent Crits during the 0.1 second interval where we're able to headshot but not charge)
									damage_custom = TF_CUSTOM_HEADSHOT;	
									SMG_Autoreload(attacker);
									if (GetEntProp(victim, Prop_Send, "m_iHealth") < damage * 3) {		// If we land a kill
										players[attacker].iHeads += 1;		// Add a Head
										if 	(players[attacker].iHeads > 3) {
											players[attacker].iHeads = 3;
										}
									}
								}
							}
						
							else if (StrEqual(class, "tf_weapon_sniperrifle_decap")) {		// Bazaar Bargain
							
								damage = 40.0;
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
									damage *= fDmgMod;
								}
								
								else {		// If we're not up close...
									fDmgMod += -1.0;		// Gives us the amount of *extra* ramp-up damage only (0.0-0.25)
									fDmgMod = 4 * fDmgMod * (0.015625 * fCharge - 0.84375) + 1.0; // Generate the charge multiplier fCharge (0.25-2.75), multiply by 4 times the distance multiplier fDmgMod (0-1), and add 1
										// https://www.omnicalculator.com/math/line-equation-from-two-points gives us an equation that hits both ([0.7/1.5]*150, 0.25) and (150, 1.5)
										// y = 0.015625x - 0.84375
									damage *= fDmgMod;
								}
								
								if (damage_type & DMG_CRIT != 0) {		// Removes headshot Crits when we aren't detected to be scoped in (as a precaution, and to prevent Crits during the 0.1 second interval where we're able to headshot but not charge)
									SMG_Autoreload(attacker);
									if (GetEntProp(victim, Prop_Send, "m_iHealth") < damage * 3) {		// If we land a kill
										players[attacker].iHeads += 1;		// Add a Head
										if 	(players[attacker].iHeads > 3) {
											players[attacker].iHeads = 3;
										}
									}
								}
							}
						}
						return Plugin_Changed;
					}

					// Tribalman's Shiv Bleed interaction
					if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 171 && damage_type & DMG_CLUB) {		// Are we using the Tribalman's Shiv?
						if (!(damage_type & DMG_SHOCK)) {		// Use DMG_SHOCK to prevent recursive callbacks
							if (players[victim].fBleed_Timer == 0.0) {		// If the victim isn't bleeding...
								TF2Attrib_SetByDefIndex(weapon, 149, 4.0);
								TF2_AddCondition(victim, TFCond_Bleeding, 4.0, attacker);		// ...apply Bleed and track it
								players[victim].fBleed_Timer = 4.0;
							}
							else {
								TF2Attrib_SetByDefIndex(weapon, 149, 0.0);
								TF2_RemoveCondition(victim, TFCond_Bleeding);
								float fDamage, target_pos[3];
								fDamage = 8 * players[victim].fBleed_Timer;		// Otherwise, consume the Bleed to deal extra damage
								GetEntPropVector(victim, Prop_Send, "m_vecOrigin", target_pos);
								SDKHooks_TakeDamage(victim, weapon, attacker, fDamage, DMG_CLUB | DMG_SHOCK, weapon, NULL_VECTOR, target_pos, false);
								players[victim].fBleed_Timer = 0.0;
							}
							return Plugin_Changed;
						}
					}
				}
				
				// Spy
				case TFClass_Spy: {
					if (StrEqual(class, "tf_weapon_revolver")) {
						
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
						
						damage *= fDmgMod;
						return Plugin_Changed;
					}
				}
			}
			
			// Removal of Mini-Crits from Jarate
			/*if (TF2_IsPlayerInCondition(victim, TFCond_Jarated)) {		// If we're Jarate'd
				damage *= 3.0;
				if (!isKritzed(attacker) && !isMiniKritzed(attacker, victim)) {		// If the attack has no other Crit modifiers
					damage_type = (damage_type & ~DMG_CRIT);
				}
			}*/
		}
	}
	
	return Plugin_Continue;
}


public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damage_type, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	players[victim].fFists_Sprint = 0.0;		// Reset the OoC timer when we take damage
	
	int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
	int iMeleeIndex = -1;
	if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	if (TF2_GetPlayerClass(attacker) == TFClass_Pyro && weapon == iMelee) {
		TF2_RemoveCondition(victim, TFCond_Bleeding);		// Removes the Bleed from the throwing axe hit
	}
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
			
			// Medic
			if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {
					damage *= 0.6;	// I don't know why, but syringes do way too much damage if we don't have this
				}
			}
		}
	}

	return Plugin_Changed;
}


	// -={ Syringe Gun projectiles }=-

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
	
	SDKHook(entity, SDKHook_StartTouch, needleTouch);
}

Action needleTouch(int entity, int other) {
	int weapon = GetEntPropEnt(entity, Prop_Send, "m_hLauncher");
	int wepIndex = -1;
	if (weapon != -1) wepIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	switch(wepIndex) {
		case 17,204,36,412: {
			int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
			if (IsValidClient(owner)) {
				if (other != owner && other >= 1 && other <= MaxClients) {
					TFTeam team = TF2_GetClientTeam(other);
					if (TF2_GetClientTeam(owner) == team) {		// Hitting heammates
						
						int iHealth = GetEntProp(other, Prop_Send, "m_iHealth");
						int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, other);
						if (iHealth < iMaxHealth) {		// If the teammate is below max health
							
							float vecVictim[3], vecPos[3];
							GetClientEyePosition(owner, vecPos);		// Gets shooter position
							GetEntPropVector(other, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
							float fDistance = GetVectorDistance(vecPos, vecVictim, false);		// Distance calculation
							
							float fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 0.5, 1.5);
							fDmgMod *= 0.4;		// Heal for 40% of the damage you would've done
							float healing = 15 * fDmgMod;
						
							if (iHealth > iMaxHealth - healing) {		// Heal us to full
								SetEntProp(other, Prop_Send, "m_iHealth", iMaxHealth);
							} 
							else {
								TF2Util_TakeHealth(other, healing);
							}

							// Build Uber
							int iSecondary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Secondary, true);
							int iSecondaryIndex = -1;
							if (iSecondary >= 0) {
								iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
							}
							
							float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
							// The ratio is 12 healing per 1%
							if (iSecondaryIndex == 35) {		// Kritzkreig
								fUber += healing * 0.00085 * 1.25;		// Add this to our Uber amount (multiply by 0.001 as 1 HP -> 1%, and Uber is stored as a 0 - 1 proportion)
							}
							else {
								fUber += healing * 0.00085;
							}
							if (fUber > 1.0) {
								SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", 1.0);
							}
							else {
								SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber);
							}
						
							EmitSoundToClient(owner, "player/recharged.wav");
							EmitSoundToClient(other, "player/recharged.wav");
						}
					}
				}
				else if (other == 0) {		// Impact world
					CreateParticle(entity, "impact_metal", 1.0,_,_,_,_,_,_,false);
				}
			}
		}
	}
	return Plugin_Continue;
}

public void Syringe_PrimaryAttack(int iClient, int iPrimary, float vecAng[3]) {
	int iSyringe = CreateEntityByName("tf_projectile_syringe");
	
	if (iSyringe != -1) {
		int team = GetClientTeam(iClient);
		float vecPos[3], vecVel[3],  offset[3];
		
		GetClientEyePosition(iClient, vecPos);
		
		//vecAng[0] += GetRandomFloat(-1.4, 1.4) - 1.5;		// Random spread
		//vecAng[1] += GetRandomFloat(-1.4, 1.4) + 0.25;
		
		offset[0] = (16.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		offset[1] = (-6.0 * Cosine(DegToRad(vecAng[1])));
		offset[2] = -10.0;
		
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
		SetEntPropFloat(iSyringe, Prop_Send, "m_flModelScale", 2.0);
		
		DispatchSpawn(iSyringe);
		
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 1600.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 1600.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -1600.0;

		TeleportEntity(iSyringe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
}


	// -={ Autoreloads }=-

void SMG_Autoreload(int iClient) {
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);		// Retrieve the seconadry weapon
	
	char class[64];
	GetEntityClassname(iSecondary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_smg")) {		// If we have the stock SMG equipped (the Carbine is a different class)
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our SMG
		int ammoSubtract = 25 - clip;		// Don't take away more ammo than is nessesary
		
		int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, secondaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < 25 && ammoCount > 0) {
			if (ammoCount < 25) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, secondaryAmmo);		// Subtract reserve ammo
			SetEntData(iSecondary, iAmmoTable, 25, 4, true);		// Add loaded ammo
		}
	}
}

void Syringe_Autoreload(int iClient) {
	
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);		// Retrieve the seconadry weapon
	
	char class[64];
	GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_syringegun_medic")) {		// If we have a Syringe Gun equipped
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our SMG
		int ammoSubtract = 20 - clip;		// Don't take away more ammo than is nessesary
		
		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < 20 && ammoCount > 0) {
			if (ammoCount < 20) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iPrimary, iAmmoTable, 20, 4, true);		// Add loaded ammo
			
			EmitSoundToClient(iClient, "weapons/widow_maker_pump_action_back.wav");
		}
	}
}

void Rifle_Autoreload(int iClient) {
	
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);		// Retrieve the seconadry weapon
	
	char class[64];
	GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_syringegun_medic")) {		// If we have a Syringe Gun equipped
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our SMG
		int ammoSubtract = 3 - clip;		// Don't take away more ammo than is nessesary
		
		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < 3 && ammoCount > 0) {
			if (ammoCount < 3) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iPrimary, iAmmoTable, 3, 4, true);		// Add loaded ammo
			
			EmitSoundToClient(iClient, "weapons/widow_maker_pump_action_back.wav");
		}
	}
}


	// -={ Detects headshot kills for the Heads counter and handles Rifle clip }=-

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast) {
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (!attacker || !IsClientInGame(attacker)) {
		return Plugin_Continue;
	}

	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	//int victim = event.GetInt("victim_entindex");
	int weaponIndex = event.GetInt("weapon_def_index");
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
		
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);		// Retrieve the seconadry weapon
		
		if (weaponIndex == 6 && IsPlayerAlive(attacker)) {		// Shovel
			PrintToChatAll("Rocket reload");
			// Reload 1 rocket
			int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
			int clip = GetEntData(iPrimary, iAmmoTable, 4);
			
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			int ammoCount = GetEntProp(attacker, Prop_Data, "m_iAmmo", _, primaryAmmo);
			
			if (clip < 4 && ammoCount > 0) {
				SetEntProp(attacker, Prop_Data, "m_iAmmo", ammoCount - 1 , _, primaryAmmo);
				SetEntData(iPrimary, iAmmoTable, 4, 4, true);
				EmitSoundToClient(attacker, "weapons/widow_maker_pump_action_back.wav");
			}
		}
	}
	return Plugin_Continue;
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
			// The ratio is 12 healing per 1%
			if (iSecondaryIndex == 35) {		// Kritzkreig
				fUber += iHealing * 0.00085 * 1.25;		// Add this to our Uber amount (multiply by 0.001 as 1 HP -> 1%, and Uber is stored as a 0 - 1 proportion)
			}
			else {
				fUber += iHealing * 0.00085;
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
		
		//int secondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		//int secondaryIndex = -1;
		//if(secondary != -1) secondaryIndex = GetEntProp(secondary, Prop_Send, "m_iItemDefinitionIndex");
		
		int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
		//int meleeIndex = -1;
		//if(iMelee != -1) meleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
		
		switch(tfClientClass) {
			// Scout
			case TFClass_Scout:
			{
				// Baby-Face's Blaster
				if(primaryIndex == 772 && iActive == primary) {
					if(buttons & IN_ATTACK2 && players[iClient].fBoosting == 0.0) {		// Are we using the alt-fire?
						float fHype = GetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter");

						SetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter", 0.0);
						TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, RemapValClamped(fHype, 0.0, 99.0, 0.0, 4.0));		// Apply speed to us depending on the amount of Boost we have
						
						players[iClient].fBoosting = RemapValClamped(fHype, 0.0, 99.0, 0.0, 4.0);		// Tracks whether or not the alt-fire is active and for how long
						
						for (int i = 1; i <= MaxClients; i++) {
							if (IsClientInGame(i) && IsPlayerAlive(i)) {
								float vecTeammate[3];
								float vecUs[3];
								float distance;
								GetEntPropVector(i, Prop_Send, "m_vecOrigin", vecTeammate);
								GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", vecUs);
								distance = GetVectorDistance(vecUs, vecTeammate);
								if (distance < 300 && GetClientTeam(i) == GetClientTeam(iClient)) {		// Identify players on the same team within 300 HU of us
									TF2_AddCondition(i, TFCond_SpeedBuffAlly, RemapValClamped(fHype, 0.0, 99.0, 0.0, 4.0));		// Apply speed to teammates
								}
							}
						}
					}
				}
				
				// Bat deflect
				else if (iActive == iMelee) {
					if (buttons & IN_ATTACK) {
						CreateTimer(0.2, BatDeflect, iClient);
					}
				}
			}
			
			case TFClass_Pyro:
			{
				// Melee multi-hit
				if (iMelee == iActive && buttons & IN_ATTACK && GetEntPropFloat(iMelee, Prop_Data, "m_flNextPrimaryAttack") < GetGameTime()) {		// Are we performing a swing?
					players[iClient].iAxe_Count = 0;
					CreateTimer(0.0, AxeSwing, iClient);
				}
				else if (iMelee == iActive && buttons & IN_ATTACK) {
					//PrintToChatAll("Fail");
				}
				// Axe throw
				else if (iMelee == iActive && buttons & IN_ATTACK2) {
					if (players[iClient].fAxe_Cooldown >= 15.0) {
						players[iClient].fAxe_Cooldown = 0.0;
						
						float vecAng[3];
						GetClientEyeAngles(iClient, vecAng);
						
						AxeThrow(iClient, iMelee, vecAng);
					}
				}
			}

			case TFClass_Heavy:
			{
				// Uppercut
				if (iMelee == iActive && buttons & IN_ATTACK2 && players[iClient].fUppercut_Cooldown >= 1.0 && GetEntPropFloat(iMelee, Prop_Data, "m_flNextPrimaryAttack") < GetGameTime()) {		// Are we performing a swing?
					TF2_AddCondition(iClient, TFCond_CritDemoCharge, 0.8);
					players[iClient].fUppercut_Cooldown = 0.0;
					float vecVel[3];
					GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
					vecVel[2] = 282.84;		// This is approximately what jump velocity is
					TeleportEntity(iClient , _, _, vecVel);
					TF2Attrib_AddCustomPlayerAttribute(iClient, "fire rate penalty", 1.25);
				}
			}
			
			case TFClass_Sniper:
			{
				//handle Sniper rifle reloads
				int reload = GetEntProp(primary, Prop_Send, "m_iReloadMode");
				int viewmodel = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
				int sequence = GetEntProp(viewmodel, Prop_Send, "m_nSequence");

				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int clip = GetEntData(primary, iAmmoTable, 4);

				int primaryAmmo = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
				int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);

				float reloadSpeed = 2.0;
				if(primaryIndex == 230) reloadSpeed = 1.5;
				int maxClip = 3;

				int ReloadAnim = 51;
				float altRel = 0.875;

				if (iActive == primary) {
					
					// Attempt to fire sniper without ammo
					if ((buttons & IN_ATTACK || buttons & IN_ATTACK2) && clip > 0 && ammoCount == 0) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 1, _, primaryAmmo);
						RequestFrame(DryFireSniper, iClient);
					}

					if (((buttons & IN_RELOAD) || clip == 0) && reload == 0 && (sequence == 30 || sequence == 33) && clip < maxClip && ammoCount > 0) {	// Handle reloads
						g_meterPri[iClient] = 0.0;
						SetEntProp(primary, Prop_Send, "m_iReloadMode", 1);
						SetEntProp(viewmodel, Prop_Send, "m_nSequence", ReloadAnim);
						SetEntPropFloat(viewmodel, Prop_Send, "m_flPlaybackRate", (2.0 * altRel) / reloadSpeed);
						if (TF2_IsPlayerInCondition(iClient, TFCond_Slowed) && !TF2_IsPlayerInCondition(iClient, TFCond_FocusBuff))
							buttons |= IN_ATTACK2;
					}
					if (reload != 0) {
						if (buttons & IN_ATTACK) {
							if (clip > 0) {
								SetEntProp(primary, Prop_Send, "m_iReloadMode", 0);		// Cancel reload to fire a shot
								g_meterPri[iClient] = 0.0;
							}
							else
								buttons &= ~IN_ATTACK;
						}
						if (buttons & IN_ATTACK2 && !TF2_IsPlayerInCondition(iClient, TFCond_FocusBuff))
							buttons &= ~IN_ATTACK2;		// Disable scope when out of ammo
						if (g_meterPri[iClient] >= reloadSpeed) {
							int newClip = ammoCount - maxClip + clip < 0 ? ammoCount + clip : maxClip;
							int newAmmo  = ammoCount - maxClip + clip >= 0 ? ammoCount - maxClip + clip : 0;
							SetEntProp(iClient, Prop_Data, "m_iAmmo", newAmmo , _, primaryAmmo);
							SetEntData(primary, iAmmoTable, newClip, 4, true);
							SetEntProp(primary, Prop_Send, "m_iReloadMode", 0);
							SetEntProp(viewmodel, Prop_Send, "m_nSequence", 30);
							g_meterPri[iClient] = 0.0;
						}
					}
					else if (TF2_IsPlayerInCondition(iClient, TFCond_FocusBuff) && clip < maxClip) {
						int newClip = ammoCount - maxClip < 1 ? (ammoCount - maxClip + clip > maxClip ? maxClip : ammoCount - 1 + clip) : maxClip;
						int newAmmo  = ammoCount - maxClip + clip >= 1 ? ammoCount - maxClip + clip : 1;
						SetEntProp(iClient, Prop_Data, "m_iAmmo", newAmmo , _, primaryAmmo);
						SetEntData(primary, iAmmoTable, newClip, 4, true);
					}
					if (buttons & IN_RELOAD) buttons &= ~IN_RELOAD;
					if (buttons & IN_ATTACK3) buttons |= IN_RELOAD;
				}
			}
		}
	}
	return Plugin_Continue;
}

public void AxeThrow(int iClient, int iMelee, float vecAng[3]) {
	int iAxe = CreateEntityByName("tf_projectile_cleaver");
	
	if (iAxe != -1) {
		int team = GetClientTeam(iClient);
		float vecPos[3], vecVel[3],  offset[3];
		
		GetClientEyePosition(iClient, vecPos);
		
		//offset[0] = (15.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		//offset[1] = (-6.0 * Cosine(DegToRad(vecAng[1])));
		//offset[2] = -10.0;
		
		//vecPos[0] += offset[0];
		//vecPos[1] += offset[1];
		//vecPos[2] += offset[2];

		EmitAmbientSound("weapons/cleaver_throw.wav", vecPos, iClient);
		
		SetEntPropEnt(iAxe, Prop_Send, "m_hOwnerEntity", iClient);	// Attacker
		SetEntPropEnt(iAxe, Prop_Send, "m_hLauncher", iMelee);	// Weapon
		SetEntProp(iAxe, Prop_Data, "m_iTeamNum", team);		// Team
		SetEntProp(iAxe, Prop_Send, "m_iTeamNum", team);
		SetEntProp(iAxe, Prop_Data, "m_CollisionGroup", 24);		// Collision
		SetEntProp(iAxe, Prop_Data, "m_usSolidFlags", 0);
		SetEntProp(iAxe, Prop_Data, "m_nSkin", team - 2);		// Skin
		SetEntProp(iAxe, Prop_Send, "m_nSkin", team - 2);
		//SetEntPropVector(iAxe, Prop_Data, "m_angRotation", vecAng);		// Orientation of model
		SetEntityModel(iAxe, "models/weapons/c_models/c_fireaxe_pyro.mdl"); // Model
		SetEntPropFloat(iAxe, Prop_Data, "m_flGravity", 0.2);
		SetEntPropFloat(iAxe, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iAxe, Prop_Send, "m_flModelScale", 1.0);
		
		DispatchSpawn(iAxe);
		
		// Calculates forward velocity
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 2000.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 2000.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -2000.0 + 200.0;
		
		// Calculate minor leftward velocity to help us aim better
		/*float leftVel[3];
		leftVel[0] = -Sine(DegToRad(vecAng[1])) * 0.015;
		leftVel[1] = Cosine(DegToRad(vecAng[1])) * 0.015;
		leftVel[2] = 0.0;  // No change in the vertical direction

		vecVel[0] += leftVel[0];
		vecVel[1] += leftVel[1];*/

		TeleportEntity(iAxe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
}

public void DryFireSniper(int iClient) {
	int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int primaryAmmo = GetEntProp(primary, Prop_Send, "m_iPrimaryAmmoType");
	SetEntProp(iClient, Prop_Data, "m_iAmmo", 0, _, primaryAmmo);
}

public Action BatDeflect(Handle timer, int iClient) {
	float vecPos[3], vecAng[3];
	
	//PrintToChat(iClient, "Swing");
	
	GetClientEyePosition(iClient, vecPos);
	GetClientEyeAngles(iClient, vecAng);
	
	float vecForce[3];		// Generates a vector pointing in the direction we are facing
	vecForce[0] = -Cosine(vecAng[1] * 0.01745329) * Cosine(vecAng[0] * 0.01745329);		// We are facing straight down the X axis when pitch and yaw are both 0; Cos(0) is 1
	vecForce[1] = -Sine(vecAng[1] * 0.01745329) * Cosine(vecAng[0] * 0.01745329);		// We are facing straight down the Y axis when pitch is 0 and yaw is 90
	vecForce[2] = Sine(vecAng[0] * 0.01745329); 	// We are facing straight up the Z axis when pitch is 90 (yaw is irrelevant)
	
	for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
		if (!IsValidEntity(iEnt)) continue; // Skip invalid entities

		// Check if the entity is a projectile
		char class[64];
		GetEntityClassname(iEnt, class, sizeof(class));
		if (StrContains(class, "tf_projectile") != -1) {
			int iProjTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
			int iScoutTeam = TF2_GetClientTeam(iClient);

			// Check if the projectile belongs to the opposing team
			if (iScoutTeam != iProjTeam) {
				float vecProjPos[3];
				GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecProjPos);

				if (GetVectorDistance(vecPos, vecProjPos) <= 1000.0) {
					float fProjSpeed;
					float vecVel[3];
					
					GetEntPropVector(iEnt, Prop_Data, "m_vecAbsVelocity", vecVel);
					fProjSpeed = GetVectorLength(vecVel, false);
					
					ScaleVector(vecForce, fProjSpeed);
					
					SetEntPropVector(iEnt, Prop_Send, "m_vecAbsVelocity", vecForce);		// Deflect it in the direction we're facing
					//TODO: Make it target the crosshair exactly
					SetEntProp(iEnt, Prop_Data, "m_iTeamNum", iScoutTeam);		// Credit any projectile hits to the Scout
					SetEntProp(iEnt, Prop_Data, "m_hOwnerEntity", iClient);
				}
			}
		}
	}
	return Plugin_Continue;
}

	// -={ Identifies sources of (Mini-)Crits (taken from ShSilver) }=-

bool isKritzed (int client) {
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
		if (TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeathSilent))
			result = true;
	}
	if (TF2_IsPlayerInCondition(client,TFCond_CritMmmph) || TF2_IsPlayerInCondition(client,TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(client,TFCond_Buffed) || TF2_IsPlayerInCondition(client,TFCond_CritCola))
		result = true;
	return result;
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

stock bool IsValidClient(int iClient) {
	if (iClient <= 0 || iClient > MaxClients) return false;
	if (!IsClientInGame(iClient)) return false;
	return true;
}