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
	version = "1.3.2",
	url = ""
};


	// ==={{ Initialisation and stuff }}==

enum struct Player {
	// Multi-class
	float fTHREAT;		// THREAT
	float fTHREAT_Timer;	// Timer when after building THREAT we start to get rid of it
	float fHeal_Penalty;		// Tracks how long after taking damage we restore our incoming healing to normal
	float fAfterburn;		// Tracks Afterburn max health debuff
	int iEquipped;		// Tracks the equipped weapon's index in order to determine when it changes
	int iMilk_Cooldown;		// Blocks repeated healing ticks from Mad Milk
	//int iHealthkit_Cooldown;	// Tracks when we've used a small health kit
	
	// Scout
	float fAirjump;		// Tracks damage taken while airborne
	
	// Soldier
	float fBlack_Box_Healing;	// Tracks damage we do with the Black Box
	
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
	float fConstruction_Health;		// Tracks the amount of health a building is *supposed* to have during its construction animation
}

Player players[MAXPLAYERS+1];
Entity entities[2048];

Handle g_hSDKFinishBuilding;

Handle cvar_ref_tf_use_fixed_weaponspreads;
Handle cvar_ref_tf_sentrygun_damage;
Handle cvar_ref_tf_flamethrower_boxsize;

Handle cvar_ref_tf_movement_aircurrent_aircontrol_mult;
Handle cvar_ref_tf_movement_aircurrent_friction_mult;
Handle cvar_ref_tf_airblast_cray_ground_minz;
Handle cvar_ref_tf_airblast_cray_ground_reflect;
Handle cvar_ref_tf_airblast_cray_lose_footing_duration;
Handle cvar_ref_tf_airblast_cray_pitch_control;

Handle cvar_ref_tf_fireball_airblast_recharge_penalty;
Handle cvar_ref_tf_fireball_burn_duration;
Handle cvar_ref_tf_fireball_burning_bonus;
Handle cvar_ref_tf_fireball_damage;
Handle cvar_ref_tf_fireball_hit_recharge_boost;
Handle cvar_ref_tf_fireball_max_lifetime;
Handle cvar_ref_tf_fireball_radius;
Handle cvar_ref_tf_fireball_speed;


public void OnPluginStart() {
	cvar_ref_tf_use_fixed_weaponspreads = FindConVar("tf_use_fixed_weaponspreads");
	cvar_ref_tf_sentrygun_damage = FindConVar("tf_sentrygun_damage");
	cvar_ref_tf_flamethrower_boxsize = FindConVar("tf_flamethrower_boxsize");
	
	cvar_ref_tf_movement_aircurrent_aircontrol_mult = FindConVar("tf_movement_aircurrent_aircontrol_mult");
	cvar_ref_tf_movement_aircurrent_friction_mult = FindConVar("tf_movement_aircurrent_friction_mult");
	cvar_ref_tf_airblast_cray_ground_minz = FindConVar("tf_airblast_cray_ground_minz");
	cvar_ref_tf_airblast_cray_ground_reflect = FindConVar("tf_airblast_cray_ground_reflect");
	cvar_ref_tf_airblast_cray_lose_footing_duration = FindConVar("tf_airblast_cray_lose_footing_duration");
	cvar_ref_tf_airblast_cray_pitch_control = FindConVar("tf_airblast_cray_pitch_control");
	
	cvar_ref_tf_fireball_airblast_recharge_penalty = FindConVar("tf_fireball_airblast_recharge_penalty");
	cvar_ref_tf_fireball_burn_duration = FindConVar("tf_fireball_burn_duration");
	cvar_ref_tf_fireball_burning_bonus = FindConVar("tf_fireball_burning_bonus");
	cvar_ref_tf_fireball_damage = FindConVar("tf_fireball_damage");
	cvar_ref_tf_fireball_hit_recharge_boost = FindConVar("tf_fireball_hit_recharge_boost");
	cvar_ref_tf_fireball_max_lifetime = FindConVar("tf_fireball_max_lifetime");
	cvar_ref_tf_fireball_radius = FindConVar("tf_fireball_radius");
	cvar_ref_tf_fireball_speed = FindConVar("tf_fireball_speed");
	
	
	SetConVarString(cvar_ref_tf_use_fixed_weaponspreads, "0");
	SetConVarString(cvar_ref_tf_sentrygun_damage, "15");
	SetConVarString(cvar_ref_tf_flamethrower_boxsize, "1");
	
	SetConVarString(cvar_ref_tf_movement_aircurrent_aircontrol_mult, "1.0");
	SetConVarString(cvar_ref_tf_movement_aircurrent_friction_mult, "1.0");
	SetConVarString(cvar_ref_tf_airblast_cray_ground_minz, "268.3281572999747");
	SetConVarString(cvar_ref_tf_airblast_cray_ground_reflect, "0");
	SetConVarString(cvar_ref_tf_airblast_cray_lose_footing_duration, "0.0");
	SetConVarString(cvar_ref_tf_airblast_cray_pitch_control, "0.0");
	
	SetConVarString(cvar_ref_tf_fireball_airblast_recharge_penalty, "1.0");
	SetConVarString(cvar_ref_tf_fireball_burn_duration, "3");
	SetConVarString(cvar_ref_tf_fireball_burning_bonus, "2");
	SetConVarString(cvar_ref_tf_fireball_damage, "40");
	SetConVarString(cvar_ref_tf_fireball_hit_recharge_boost, "1.0");
	SetConVarString(cvar_ref_tf_fireball_max_lifetime, "0.323232");
	SetConVarString(cvar_ref_tf_fireball_radius, "1.0");
	SetConVarString(cvar_ref_tf_fireball_speed, "1980.0");
	
	
	// This is used for clearing variables on respawn
	HookEvent("player_spawn", OnGameEvent, EventHookMode_Post);
	// This detects healing we do
	HookEvent("player_healed", OnPlayerHealed);
	// This detects when we touch a cabinet
	HookEvent("post_inventory_application", OnGameEvent, EventHookMode_Post);
	// Detects health and ammo pickups
	HookEvent("item_pickup", OnGameEvent, EventHookMode_Post);
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
	PrecacheSound("player/recharged.wav", true);
	PrecacheSound("weapons/pipe_bomb1.wav", true);
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
	if (StrEqual(class, "tf_weapon_soda_popper")) {	// Soda Popper
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 6);
		TF2Items_SetAttribute(item1, 0, 37, 0.555555); // hidden primary max ammo bonus (reduced to 20)
		TF2Items_SetAttribute(item1, 1, 68, -1.0); // increase player capture value (lowered to 1)
		TF2Items_SetAttribute(item1, 2, 6, 1.0); // fire rate bonus (nil)
		TF2Items_SetAttribute(item1, 3, 793, 0.0); // hype on damage (nil)
		TF2Items_SetAttribute(item1, 4, 96, 0.60699); // reload time decreased (reduced to 0.87 sec)
		TF2Items_SetAttribute(item1, 5, 3, 0.5); // clip size
	}
	else if ((StrEqual(class, "tf_weapon_pistol") || StrEqual(class, "tf_weapon_pistol_scout")) && TF2_GetPlayerClass(iClient) == TFClass_Scout) {	// Undo ammo penalty from Engineer Pistol
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 78, 1.0); // maxammo secondary reduced (reset)
	}
	else if (StrEqual(class, "tf_weapon_jar_milk")) {	// Mad Milk
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 801, 15.0); // item_meter_recharge_rate (15 seconds)
		TF2Items_SetAttribute(item1, 1, 848, 1.0); // item_meter_resupply_denied
		TF2Items_SetAttribute(item1, 2, 845, 1.0); // grenade1_resupply_denied
		TF2Items_SetAttribute(item1, 3, 856, 3.0); //meter type
	}
	else if (TF2_GetPlayerClass(iClient) == TFClass_Scout && (StrEqual(class, "tf_weapon_bat") || StrEqual(class, "tf_weapon_bat_fish") || StrEqual(class, "saxxy"))) {	// All Bats
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
	if (index == 228 || index == 1085) {	// Black Box
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 1, 0.888888); // damage penalty (90 to 80)
		TF2Items_SetAttribute(item1, 1, 37, 0.6); // hidden primary max ammo bonus (reduced to 12)
		TF2Items_SetAttribute(item1, 2, 741, 0.0);	// Health on radius damage (removed; we're handling this separately)
	}
	else if (index == 237) {	// Rocket Jumper
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 37, 0.6); // hidden primary max ammo bonus (reduced to 12)
		TF2Items_SetAttribute(item1, 1, 1, 0.0); // damage penalty (100%)
		TF2Items_SetAttribute(item1, 2, 76, 1.0); // maxammo primary increased (nil)
	}
	else if (index == 414) {	// Liberty Launcher
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 4, 1.0); // clip size bonus (nil)
		TF2Items_SetAttribute(item1, 1, 37, 0.6); // hidden primary max ammo bonus (reduced to 12)
		TF2Items_SetAttribute(item1, 2, 135, 1.0); // rocket jump damage reduction (nil)
	}
	else if (StrEqual(class, "tf_weapon_rocketlauncher_directhit")) {	// Direct Hit
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.111111); // damage bonus (112 to 100)
		TF2Items_SetAttribute(item1, 1, 37, 0.6); // hidden primary max ammo bonus (reduced to 12)
		TF2Items_SetAttribute(item1, 2, 100, 0.67); // blast radius decreased (increased to -33%)
	}
	else if (StrEqual(class, "tf_weapon_rocketlauncher_airstrike")) {	// Air Strike
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.888888); // damage penalty (90 to 80)
		TF2Items_SetAttribute(item1, 1, 37, 0.4); // hidden primary max ammo bonus (reduced to 8) (This is temporary)
		TF2Items_SetAttribute(item1, 2, 100, 1.0); // blast radius decreased (nil)
		TF2Items_SetAttribute(item1, 3, 135, 1.0); // rocket jump damage reduction (nil)
	}
	else if (TF2_GetPlayerClass(iClient) == TFClass_Soldier && (StrEqual(class, "tf_weapon_shovel") || StrEqual(class, "tf_weapon_katana") || StrEqual(class, "saxxy"))) {		// All Shovels
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.230769); // damage bonus (65 to 80)
	}
	if (index == 128) {		// Equalizer
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 2, 1.230769); // damage bonus (65 to 80)
		TF2Items_SetAttribute(item1, 1, 115, 0.0); // mod shovel damage boost (removed)
		TF2Items_SetAttribute(item1, 2, 740, 1.0); // reduced_healing_from_medics (removed)
	}
	
	// Pyro
	else if (StrEqual(class, "tf_weapon_flamethrower")) {		// All Flamethrowers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 11);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty (100%; prevents damage from flame particles)
		TF2Items_SetAttribute(item1, 1, 174, 1.333333); // flame_ammopersec_increased (33%)
		TF2Items_SetAttribute(item1, 2, 844, 2300.0); // flame_speed (enough to travel 450 HU from out centre in lifetime)
		TF2Items_SetAttribute(item1, 3, 862, 0.13); // flame_lifetime
		TF2Items_SetAttribute(item1, 4, 72, 0.0); // weapon burn dmg reduced (nil)
		TF2Items_SetAttribute(item1, 5, 839, 0.0); // flame_spread_degree (none)
		TF2Items_SetAttribute(item1, 6, 841, 0.0); // flame_gravity (none)
		TF2Items_SetAttribute(item1, 7, 843, -9.75); // flame_drag (none)
		TF2Items_SetAttribute(item1, 8, 865, 0.0); // flame_up_speed (removed)
		TF2Items_SetAttribute(item1, 9, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 10, 863, 0.0); // flame_random_lifetime_offset (none)
	}
	if (index == 40 || index == 1146) {		// Backburner
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 13);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty (100%; prevents damage from flame particles)
		TF2Items_SetAttribute(item1, 1, 174, 1.333333); // flame_ammopersec_increased (33%)
		TF2Items_SetAttribute(item1, 2, 844, 2300.0); // flame_speed (enough to travel 450 HU from out centre in lifetime)
		TF2Items_SetAttribute(item1, 3, 862, 0.13); // flame_lifetime
		TF2Items_SetAttribute(item1, 4, 72, 0.0); // weapon burn dmg reduced (nil)
		TF2Items_SetAttribute(item1, 5, 839, 0.0); // flame_spread_degree (none)
		TF2Items_SetAttribute(item1, 6, 841, 0.0); // flame_gravity (none)
		TF2Items_SetAttribute(item1, 7, 843, -9.75); // flame_drag (none)
		TF2Items_SetAttribute(item1, 8, 865, 0.0); // flame_up_speed (removed)
		TF2Items_SetAttribute(item1, 9, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 10, 863, 0.0); // flame_random_lifetime_offset (none)
		TF2Items_SetAttribute(item1, 11, 26, 25.0); // max health additive bonus (25)
		TF2Items_SetAttribute(item1, 12, 170, 2.0); // airblast cost increased (50 to 40)
	}
	else if (StrEqual(class, "tf_weapon_rocketlauncher_fireball")) {	// Dragon's Fury
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 72, 0.0); // weapon burn dmg reduced (nil)
		TF2Items_SetAttribute(item1, 1, 318, 0.625); // faster reload rate (1.25 sec)
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
		TF2Items_SetNumAttributes(item1, 0);
		//TF2Items_SetAttribute(item1, 0, 4, 1.5); // clip size bonus (6)
		//TF2Items_SetAttribute(item1, 1, 37, 1.5); // hidden primary max ammo bonus (16 to 24)
	}
	if (index == 308) {	// Loch-n-Load
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 6);
		TF2Items_SetAttribute(item1, 0, 3, 1.0); // clip size penalty (nil)
		TF2Items_SetAttribute(item1, 1, 100, 1.0); // blast radius reduced (removed)
		TF2Items_SetAttribute(item1, 2, 127, 0.0); // sticky air burst mode (this is the thing that makes bombs shatter on impact; removed)
		TF2Items_SetAttribute(item1, 3, 137, 1.0); // dmg bonus vs buildings (nil)
		TF2Items_SetAttribute(item1, 4, 681, 0.0); // grenade no spin (removed)
		TF2Items_SetAttribute(item1, 5, 671, 1.0); // grenade no bounce
	}
	else if (StrEqual(class, "tf_weapon_pipebomblauncher")) {	// All Sticky Launchers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.833333); // damage penalty (120 to 100)
		//TF2Items_SetAttribute(item1, 1, 3, 0.75); // clip size penalty (6)
		TF2Items_SetAttribute(item1, 1, 96, 0.917431); // reload time decreased (first shot reload 1.0 seconds)
		TF2Items_SetAttribute(item1, 2, 670, 0.5); // stickybomb charge rate (50% faster)
		TF2Items_SetAttribute(item1, 3, 121, 1.0); // stickies destroy stickies
	}
	if (index == 265) {	// Scottish Resistance
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty (100%)
		TF2Items_SetAttribute(item1, 1, 96, 0.917431); // reload time decreased (first shot reload 1.0 seconds)
		TF2Items_SetAttribute(item1, 2, 78, 1.0); // maxammo secondary increased (nil)
		TF2Items_SetAttribute(item1, 3, 670, 0.5); // stickybomb charge rate (50% faster)
	}
	if (index == 265) {	// Sticky Jumper
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty (100%)
		TF2Items_SetAttribute(item1, 1, 96, 0.917431); // reload time decreased (first shot reload 1.0 seconds)
		TF2Items_SetAttribute(item1, 2, 78, 1.0); // maxammo secondary increased (nil)
		TF2Items_SetAttribute(item1, 3, 670, 0.5); // stickybomb charge rate (50% faster)
	}
	if (index == 1150) {	// Quickiebomb Launcher
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 1, 1.0); // damage penalty (nil)
		TF2Items_SetAttribute(item1, 1, 3, 0.75); // clip size penalty (6)
		TF2Items_SetAttribute(item1, 2, 96, 0.917431); // reload time decreased (first shot reload 1.0 seconds)
		TF2Items_SetAttribute(item1, 3, 78, 1.0); // maxammo secondary increased (nil)
		TF2Items_SetAttribute(item1, 4, 670, 0.15); // stickybomb charge rate (70% faster than stock)
		//TF2Items_SetAttribute(item1, 4, 121, 0.0); // stickies destroy stickies (removed)
	}
	
	// Heavy
	else if (StrEqual(class, "tf_weapon_minigun")) {	// All Miniguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 125, -50.0); // max health additive penalty (-50)
		TF2Items_SetAttribute(item1, 1, 45, 0.75); // bullets per shot bonus (-25%)
		TF2Items_SetAttribute(item1, 2, 75, 1.57); // aiming movespeed increased (to 180 HU/s, 75% of Heavy's new base)
		TF2Items_SetAttribute(item1, 3, 37, 0.75); // hidden primary max ammo bonus (-25%)
		TF2Items_SetAttribute(item1, 4, 107, 1.043478); // move speed bonus (10%)
	}
	/*else if (index == 424) {	// Tomislav
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 5, 1.15); // move speed bonus (10%)
	}*/
	else if ((StrEqual(class, "tf_weapon_shotgun") || StrEqual(class, "tf_weapon_shotgun_hwg")) && TF2_GetPlayerClass(iClient) == TFClass_Heavy) {	// All Heavy Shotguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.1); // damage bonus (25%)
	}
	else if (TF2_GetPlayerClass(iClient) == TFClass_Heavy && (StrEqual(class, "tf_weapon_fists") || StrEqual(class, "saxxy"))) {	// All Fists
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 2, 1.230769); // damage bonus (65 to 80)
	}
	else if (index == 43) {	// Killing Gloves of Boxing
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 2, 1.230769); // damage bonus (65 to 80)
		TF2Items_SetAttribute(item1, 0, 5, 1.0); // fire rate penalty (nil)
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
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 286, 0.9); // engy building health bonus (reduced 10%)
		TF2Items_SetAttribute(item1, 1, 2043, 2.0); // upgrade rate decrease (increased; 100%)
	}
	else if (StrEqual(class, "tf_weapon_robot_arm")) {	// Gunslinger
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 286, 0.9); // engy building health bonus (reduced 10%)
		TF2Items_SetAttribute(item1, 1, 2043, 2.0); // upgrade rate decrease (increased; 100%)
		TF2Items_SetAttribute(item1, 2, 124, 0.0); // mod wrench builds minisentry (removed)
		TF2Items_SetAttribute(item1, 3, 321, 0.6667); // build rate bonus (Hopefully this is 50% slower)
		TF2Items_SetAttribute(item1, 4, 464, 1.0); // engineer sentry build rate multiplier (nil)
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
	if (index == 36) {	// Blutsauger
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 4, 1.0); // clip size bonus (nil)
		TF2Items_SetAttribute(item1, 1, 37, 0.8); // hidden primary max ammo bonus (150 to 120)
		TF2Items_SetAttribute(item1, 2, 280, 9.0); // override projectile type (to flame rocket, which disables projectiles entirely)
		TF2Items_SetAttribute(item1, 3, 81, 0.0); // health drain medic (nil)
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
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 37, 0.6); // hidden primary max ammo bonus (25 to 15)
		TF2Items_SetAttribute(item1, 1, 75, 1.851851); // aiming movespeed increased (27% to 50%)
	}
	else if (StrEqual(class, "tf_weapon_jar")) {	// Jarate
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 848, 1.0); // item_meter_resupply_denied
		TF2Items_SetAttribute(item1, 1, 845, 1.0); // grenade1_resupply_denied
		TF2Items_SetAttribute(item1, 2, 856, 3.0); //meter type
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
	else if (index == 60) {	// Cloak and Dagger
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 89, 0.86666); // cloak consume rate decreased (duration increased from 6.5 to 7.5)
		TF2Items_SetAttribute(item1, 1, 729, 1.0); // ReducedCloakFromAmmo (nil)
	}
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}


	// -={ Resets variables on death }=-

Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {
	int iClient;
	
	if (StrEqual(name, "player_spawn")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsPlayerAlive(iClient)) {
			
			players[iClient].fTHREAT = 0.0;
			players[iClient].fTHREAT_Timer = 0.0;
			players[iClient].fHeal_Penalty = 0.0;
			players[iClient].fAfterburn = 0.0;
			
			players[iClient].iAmmo = 0;
			
			players[iClient].iSyringe_Ammo = 0;
			
			players[iClient].iHeadshot_Frame = 0;
			
			players[iClient].fHitscan_Accuracy = 0.0;
			players[iClient].iHitscan_Ammo = 0;
			players[iClient].fCloak_Timer = 0.0;
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			
			// Syncs Demo's ammo count between launchers
			if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
				int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
				int iPrimaryIndex = -1;
				if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
				
				int AmmoOffset = 0, ClipOffset = 0;
				
				if (iSecondaryIndex == 265) {		// Sticky Jumper
					AmmoOffset += 6;
				}
				else if (iSecondaryIndex == 131 || iSecondaryIndex == 406 || iSecondaryIndex == 1099 || iSecondaryIndex == 1144) {		// Shields
					AmmoOffset -= 12;
				}
				
				if (iPrimaryIndex == 308) {		// Loch-n-Load
					ClipOffset -= 2;
				}
				if (iSecondaryIndex == 130) {		// Scottish Resistance
					ClipOffset += 2;
				}
				else if (iSecondaryIndex == 1150) {		// Quickiebomb Launcher
					ClipOffset -= 2;
				}
				
				
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				
				
				if (!(iPrimaryIndex == 1101 || iPrimaryIndex == 405 || iPrimaryIndex == 608)) {		// Make sure we actually have a launcher in this slot
					int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");		// Reserve ammo
					SetEntData(iPrimary, iAmmoTable, 6 + ClipOffset, 4, true);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 24 + AmmoOffset, _, iPrimaryAmmo);
					TF2Attrib_SetByDefIndex(iPrimary, 4, (6.0 + ClipOffset) / 4.0);		// Clip size
					TF2Attrib_SetByDefIndex(iPrimary, 37, (24.0 + AmmoOffset) / 16.0);		// Reserves
				}
				if (!(iSecondaryIndex == 131 || iSecondaryIndex == 406 || iSecondaryIndex == 1099 || iSecondaryIndex == 1144)) {
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntData(iSecondary, iAmmoTable, 6 + ClipOffset, 4, true);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 24 + AmmoOffset, _, iSecondaryAmmo);
					TF2Attrib_SetByDefIndex(iSecondary, 3, (6.0 + ClipOffset) / 8.0);
					TF2Attrib_SetByDefIndex(iSecondary, 25, (24.0 + AmmoOffset) / 24.0);
				}
			}
		}
	}
	
	else if (StrEqual(name, "post_inventory_application")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(iClient)) {
			players[iClient].fAfterburn = 0.0;		// Restore health lost from Afterburn
			int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
			GetEntProp(iClient, Prop_Send, "m_iHealth", iMaxHealth);
		}
	}
	
	else if (StrEqual(name, "item_pickup")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		
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
			CreateTimer(0.4, HealPopup, iClient, newHealth);
		}
		else if (StrContains(class, "ammopack_small") == 0) {
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
		}
	}
	return Plugin_Continue;
}

Action HealPopup(int iClient, int newHealth) {
	Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
	if (event) {
		event.SetInt("amount", newHealth);
		event.SetInt("entindex", iClient);
		
		event.FireToClient(iClient);
		delete event;
	}
	return Plugin_Continue;
}


	// -={ Iterates every frame }=-

public void OnGameFrame() {
	
	for (int iClient = 1; iClient <= MaxClients; iClient++) {
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			
			int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
			int iActiveIndex = -1;
			if(iActive > 0) iActiveIndex = GetEntProp(iActive, Prop_Send, "m_iItemDefinitionIndex");
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			//int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			//int iMeleeIndex = -1;
			//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			//int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
			//int iWatchIndex = -1;
			//if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
			
			
			//THREAT
			if (players[iClient].fTHREAT_Timer > 0.0) {
				players[iClient].fTHREAT_Timer -= 0.75;		// If we're not doing more than 50 DPS, this value will decrease
				if (players[iClient].fTHREAT_Timer > 500.0) {
					players[iClient].fTHREAT_Timer = 500.0;
				}
			}
			
			if (players[iClient].fTHREAT > 0.0 && TF2_IsPlayerInCondition(iClient, TFCond_Jarated)) {		// Jarate
				players[iClient].fTHREAT -= 3.0;		// Equivalent of removing 200 THREAT per second
			}
			
			if (players[iClient].fTHREAT > 0.0 && iActiveIndex == 128) {		// Equalizer
				players[iClient].fTHREAT -= 1.5;
			}
			else if (players[iClient].fTHREAT > 0.0 && players[iClient].fTHREAT_Timer <= 0.0) {
				players[iClient].fTHREAT -= 0.75;		// Equivalent of removing 50 THREAT per second
			}
			if(players[iClient].fTHREAT < 0.0) {		// Clamping
				players[iClient].fTHREAT = 0.0;
			}
			
			
			SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);		// Displays THREAT
			ShowHudText(iClient, 1, "THREAT: %.0f", players[iClient].fTHREAT);
			
			// Define gold as the target colour (max THREAT)
			int R2 = 255, G2 = 215, B2 = 0; // Gold colour

			// Ensure RemapValClamped is defined and returns a valid float
			float fThreatScale = RemapValClamped(players[iClient].fTHREAT, 0.0, 1000.0, 0.0, 1.0);
			if (fThreatScale < 0.0 || fThreatScale > 1.0) {
				fThreatScale = 0.0; // Clamp to valid range if out-of-bounds
			}

			// Use the fixed baseline colour
			int R1 = 255, G1 = 255, B1 = 255; 

			// Interpolate RGB channels based on fThreatScale
			int R = R1 + RoundToZero((R2 - R1) * fThreatScale);
			int G = G1 + RoundToZero((G2 - G1) * fThreatScale);
			int B = B1 + RoundToZero((B2 - B1) * fThreatScale);

			// Check if the new colour differs from the current one to prevent redundant updates
			int currentR = 0, currentG = 0, currentB = 0, currentA = 255; // Initialise variables
			GetEntityRenderColor(iActive, currentR, currentG, currentB, currentA);

			if (currentR != R || currentG != G || currentB != B) {
				// Apply the interpolated colour to the weapon
				//SetEntityRenderMode(iActive, RENDER_GLOW);
				SetEntityRenderColor(iActive, R, G, B, 255); // Set alpha to 255 (full visibility)
			}

			// In-combat healing penalty
			if (players[iClient].fHeal_Penalty > 0.0) {
				players[iClient].fHeal_Penalty -= 0.015;
			} else {
				TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.5);
			}


			// Afterburn
			//int MaxHP = GetEntProp(iClient, Prop_Send, "m_iMaxHealth");
			if (TF2Util_GetPlayerBurnDuration(iClient) > 8.0) {
				TF2Util_SetPlayerBurnDuration(iClient, 8.0);
			}
			if (TF2Util_GetPlayerBurnDuration(iClient) > 0.0) {
				players[iClient].fAfterburn += 0.015;
				if (players[iClient].fAfterburn > 5.0) {
					players[iClient].fAfterburn = 5.0;
				}
			}
			else {
				players[iClient].fAfterburn -= 0.015;
				if (players[iClient].fAfterburn < 0.0) {
					players[iClient].fAfterburn = 0.0;
				}
			}
			if (TF2_GetPlayerClass(iClient) == TFClass_Pyro) {
				players[iClient].fAfterburn = 0.0;
			}

			int fHealthProp = GetEntProp(iClient, Prop_Send, "m_iHealth") / GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
			
			int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
			TF2Attrib_AddCustomPlayerAttribute(iClient, "max health additive penalty", -(iMaxHealth * 0.066666) * players[iClient].fAfterburn);
			int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
			iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);		// Redefine this later on after we update max health
			if (fHealthProp < iHealth / iMaxHealth) {
				SetEntProp(iClient, Prop_Send, "m_iHealth", fHealthProp * iMaxHealth);
			}
			
			// Mad Milk removal
			if (TF2_IsPlayerInCondition(iClient, TFCond_Milked)) {
				TF2_RemoveCondition(iClient, TFCond_Milked);
			}
			
			
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
					ShowHudText(iClient, 2, "Jump Disabled!");
				}
				
				else if (!(GetEntityFlags(iClient) & FL_ONGROUND)) {		// Don't play this message when grounded
					ShowHudText(iClient, 2, "Damage taken: %.0f", players[iClient].fAirjump);
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
				
				// Pistol autoreload
				if (players[iClient].iEquipped != iActive && players[iClient].iEquipped == iSecondary) {			// Weapon swap off Pistol
					CreateTimer(1.005, AutoreloadPistol, iClient);
				}
				players[iClient].iEquipped = iActive;
			}
			
			// Soldier
			else if (TF2_GetPlayerClass(iClient) == TFClass_Soldier) {
				// Gunboats airborne splash radius penalty
				if (iSecondaryIndex == 133) {
					if (TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping)) {
						if (iPrimaryIndex == 127) {		// Direct Hit
							TF2Attrib_SetByDefIndex(iPrimary, 100, 0.4489); // blast radius decreased (reduced 33%)
						}
						else {
							TF2Attrib_SetByDefIndex(iPrimary, 100, 0.67);
						}
					}
					else {
						if (iPrimaryIndex == 127) {
							TF2Attrib_SetByDefIndex(iPrimary, 100, 0.67);
						}
						else {
							TF2Attrib_SetByDefIndex(iPrimary, 100, 1.0);
						}
					}
				}
				// Air Strike
				if (iPrimaryIndex == 1104) {
					if (TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping)) {
						TF2Attrib_SetByDefIndex(iPrimary, 100, 1.25);	// blast radius (25%; cancels out rapid fire attribute)
						TF2Attrib_SetByDefIndex(iPrimary, 411, 2.0);	// projectile spread angle penalty (2 deg)
					}
					else {
						TF2Attrib_SetByDefIndex(iPrimary, 100, 1.0);
						TF2Attrib_SetByDefIndex(iPrimary, 411, 0.0);
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
				
				if (weaponState == 2 || weaponState == 1) {		// Are we firing?
					
					int Ammo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, Ammo);		// Only fire the beam on frames where the ammo changes
					if (ammoCount == (players[iClient].iAmmo - 1)) {		// We update iAmmo after this check, so clip will always be 1 lower on frames in which we fire a shot
						
						float vecPos[3], vecAng[3], vecEnd[3];
						
						GetClientEyePosition(iClient, vecPos);
						GetClientEyeAngles(iClient, vecAng);
						
						GetAngleVectors(vecAng, vecAng, NULL_VECTOR, NULL_VECTOR);
						ScaleVector(vecAng, 450.0);		// Scales this vector 450 HU out
						AddVectors(vecPos, vecAng, vecAng);		// Add this vector to the position vector so the game can aim it better
						
						int iEntity;
						
						for (iEntity = 1; iEntity < 2048; iEntity++) {		// Loops through all entities
							if (IsValidEdict(iEntity) && iEntity != iClient) {
								char class[64];
								GetEntityClassname(iEntity, class, sizeof(class));
								if (iEntity <= MaxClients || StrEqual(class, "obj_sentrygun") || StrEqual(class, "obj_dispenser") || StrEqual(class, "obj_teleporter") || StrEqual(class, "tf_projectile_pipe_remote")) {	// Are we targeting a valid player or building?
									float vecVictim[3];
									GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
									float fDistance = GetVectorDistance(vecPos, vecVictim);
									if (fDistance <= 450.0 && GetEntProp(iEntity, Prop_Send, "m_iTeamNum") != GetEntProp(iClient, Prop_Send, "m_iTeamNum")) {		// Is the target an enemy and in range?
						
										TR_TraceRayFilter(vecPos, vecAng, MASK_SOLID, RayType_EndPoint, SingleTargetTraceFilter, iEntity);
										TR_GetEndPosition(vecEnd);
										
										if (TR_DidHit() && TR_GetEntityIndex() == iEntity) {
											if (iEntity <= MaxClients) {		// Players
												float fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 450.0, 1.5, 1.0);		// Gives us our distance multiplier
												float fDmgModTHREAT = RemapValClamped(fDistance, 0.0, 450.0, 0.0, 0.5) * players[iClient].fTHREAT / 1000 + 1;
												
												if (iPrimaryIndex == 40) {		// Backburner
													float vecVictimFacing[3], vecDirection[3];
													MakeVectorFromPoints(vecPos, vecVictim, vecDirection);		// Calculate direction we are aiming in
													
													GetClientEyeAngles(iEntity, vecVictimFacing);
													GetAngleVectors(vecVictimFacing, vecVictimFacing, NULL_VECTOR, NULL_VECTOR);
													
													float dotProduct = GetVectorDotProduct(vecDirection, vecVictimFacing);
													bool isBehind = dotProduct > 0.707;		// 90 degrees back angle
													
													if (isBehind) {
														TF2_AddCondition(iEntity, TFCond_MarkedForDeathSilent, 0.015);
													}
												}
												
												float fDamage = 10.0 * fDmgMod * fDmgModTHREAT;
												int iDamagetype = DMG_IGNITE|DMG_USE_HITLOCATIONS;
												
												if (isMiniKritzed(iClient, iEntity)) {
													TF2_AddCondition(iEntity, TFCond_MarkedForDeathSilent, 0.015);
													fDamage *= 1.35;
												}
												else if (isKritzed(iClient)) {
													fDamage = 10.0;
													iDamagetype |= DMG_CRIT;
												}
												SDKHooks_TakeDamage(iEntity, iPrimary, iClient, fDamage, iDamagetype, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage (credited to the Phlog)
												if (TF2_GetPlayerClass(iEntity) != TFClass_Pyro) {
													TF2Util_SetPlayerBurnDuration(iEntity, 8.0);
												}
												
												// Add THREAT
												players[iClient].fTHREAT += fDamage;		// Add THREAT
												if (players[iClient].fTHREAT > 1000.0) {
													players[iClient].fTHREAT = 1000.0;
												}
												players[iClient].fTHREAT_Timer += fDamage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
											}
											
											else if (StrEqual(class,"obj_sentrygun") || StrEqual(class,"obj_teleporter") || StrEqual(class,"obj_dispenser")) {		// Buildings
												float fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 450.0, 1.5, 1.0);		// Gives us our distance multiplier
												float fDmgModTHREAT = RemapValClamped(fDistance, 0.0, 450.0, 0.0, 0.5) * players[iClient].fTHREAT / 1000 + 1;
												
												float fDamage = 10.0 * fDmgMod * fDmgModTHREAT;
												int iDamagetype = DMG_IGNITE;
												
												SDKHooks_TakeDamage(iEntity, iPrimary, iClient, fDamage, iDamagetype, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage
											}
											
											else if (StrEqual(class, "tf_projectile_pipe_remote")) {		// Handles sticky destruction on hit
												int iPyroTeam = GetClientTeam(iClient);

												// Check if the sticky belongs to the opposing team
												int iStickyTeam = GetEntProp(iEntity, Prop_Data, "m_iTeamNum");
												if (iPyroTeam != iStickyTeam) {
													AcceptEntityInput(iEntity, "Kill"); // Destroy the sticky
												}
											}
										}
									}
								}
							}
						}
					}
					players[iClient].iAmmo = ammoCount;
				}
			}				
			
			// Demoman
			else if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
				// Make sure we have no Demoknight stuff equipped
				if (!(iPrimaryIndex == 1101 || iPrimaryIndex == 405 || iPrimaryIndex == 608 || iSecondaryIndex == 131 || iSecondaryIndex == 406 || iSecondaryIndex == 1099 || iSecondaryIndex == 1144)) {

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
						if (iPrimaryIndex == 424) {	// Tomislav
							players[iClient].fSpeed = players[iClient].fSpeed + 0.03;		// Unlike fRev, fSpeed regenerates back up slowly
						}
						else {
							players[iClient].fSpeed = players[iClient].fSpeed + 0.015;
						}
					}
					else {
						players[iClient].fSpeed = 1.005;		// Clamp
					}
				}
				
				float DmgBase;
				if (iPrimaryIndex == 424) {	// Tomislav damage bonus
					DmgBase = 1.1;
				}
				else {
					DmgBase = 1.0;
				}
				
				int time = RoundFloat(players[iClient].fRev * 1000);		// Time slowly decreases
				if (time % 100 == 0) {		// Only trigger an update every 0.1 sec
					float factor = 1.0 + time / 1000.0;		// This value continuously decreases from ~2 to 1 over time
					TF2Attrib_SetByDefIndex(iPrimary, 106, 0.8 / factor);		// Spread bonus
					TF2Attrib_SetByDefIndex(iPrimary, 2, DmgBase * factor * RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 1.0, 0.666));		// Damage bonus (33% damage penalty inversely proportional to speed)
				}
				
				TF2Attrib_SetByDefIndex(iPrimary, 54, RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 0.666, 1.0));		// Speed
				
				// Tomislav holster
				if (iPrimaryIndex == 424 && players[iClient].iEquipped != iActive && iActive != iPrimary) {			// Weapon swap off primary
					int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
					
					//TODO: add audio(?)
					if (ammoCount > 15) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - 15, _, primaryAmmo);
					}
					else {		// Take away all our ammo if we only have <=15 in reserve
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 0, _, primaryAmmo);
					}
				}
				players[iClient].iEquipped = iActive;
			}
			
			// Engineer
			else if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
				// Pistol autoreload
				if (players[iClient].iEquipped != iActive && players[iClient].iEquipped == iSecondary) {			// Weapon swap off Pistol
					CreateTimer(1.005, AutoreloadPistol, iClient);
				}
				players[iClient].iEquipped = iActive;
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
				
				// Syringe autoreload
				if (players[iClient].iEquipped != iActive) {			// Weapon swap
					CreateTimer(1.6, AutoreloadSyringe, iClient);
				}
				players[iClient].iEquipped = iActive;
				
				// Passive Uber build (0.625%/sec base)
				float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
				if (fUber < 1.0 && !(TF2_IsPlayerInCondition(iClient, TFCond_Ubercharged) || TF2_IsPlayerInCondition(iClient, TFCond_Kritzkrieged))) {		// Disble this when Ubered
					if (iSecondaryIndex == 35) {		// Kritzkreig
						fUber += 0.0001166 * 0.5;
					}
					else {
						fUber += 0.00009328 * 0.5;		// This is being added every *tick*
					}
					SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber);
				}
			}
			
			// Sniper
			else if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
				char class[64];
				GetEntityClassname(iClient, class,64);
				if (StrEqual(class,"tf_weapon_sniperrifle")) {
					float fCharge = GetEntPropFloat(iPrimary, Prop_Send, "m_flChargedDamage");
					TF2Attrib_SetByDefIndex(iClient, 54, RemapValClamped(fCharge, 0.0, 150.0, 1.0, 0.6));			// Lower movement speed as the weapon charges}
				}
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
						//SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak + 5.0);		// This is how much cloak we normally drain per frame
					}
					else {
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

/*bool TraceFilter_ExcludeSingle(int entity, int contentsmask, any data) {
	return (entity != data);
}*/

bool SingleTargetTraceFilter(int entity, int contentsMask, any data) {
	if(entity != data)
		return (false);
	return (true);
}

public void OnEntityCreated(int iEnt, const char[] classname) {
	if(IsValidEdict(iEnt)) {
		
		//if(StrContains(classname, "ammopack") != -1 || StrContains(classname, "ammo_pack") != -1) {
		//	SDKHook(iEnt, SDKHook_StartTouch, Event_PickUpAmmo);
		//}
		
		if (StrEqual(classname,"obj_sentrygun") || StrEqual(classname,"obj_dispenser") || StrEqual(classname,"obj_teleporter")) {
			entities[iEnt].fConstruction_Health = 0.0;
			SDKHook(iEnt, SDKHook_SetTransmit, BuildingThink);
			SDKHook(iEnt, SDKHook_OnTakeDamage, BuildingDamage);
		}
		
		else if(StrEqual(classname, "tf_projectile_rocket")) {
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}

		else if(StrEqual(classname, "tf_projectile_jar_milk")) {
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}
		
		else if(StrEqual(classname,"tf_projectile_pipe")) {
			SDKHook(iEnt, SDKHook_Think, PipeSet);
		}
		
		else if(StrEqual(classname, "tf_projectile_syringe")) {
			SDKHook(iEnt, SDKHook_SpawnPost, needleSpawn);
		}
	}
}

	// -={ Sniper Rifle headshot hit registration }=-

Action TraceAttack(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& ammo_type, int hitbox, int hitgroup) {		// Need this for noscope headshot hitreg
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {
		//PrintToChatAll("Hitgroup %i:", hitgroup);
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
			int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			
			float vecAttacker[3];
			float vecVictim[3];
			GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
			GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
			float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
			float fDmgMod = 1.0;		// Distance mod
			float fDmgModTHREAT = 1.0;	// THREAT mod
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			
			/*int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");*/
			
			int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
			int iMeleeIndex = -1;
			if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			int iWatch = TF2Util_GetPlayerLoadoutEntity(victim, 6, true);		// NB: This checks the victim rather than the attacker
			int iWatchIndex = -1;
			if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
			
			// Remove Jarate Mini-Crits
			if (TF2_IsPlayerInCondition(victim, TFCond_Jarated)) {
				if (!(isKritzed(attacker) || isMiniKritzed(attacker, victim))) {		// If we should not otherwise be recieving a Crit
					damage_type = (damage_type & ~DMG_CRIT);
					damage /= 1.35;
					
					if (fDistance > 512.0) {		// Re-add fall-off
						if (StrEqual(class, "tf_weapon_syringegun_medic")) {		// -20%
							damage *= SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);
						}
						else if (StrEqual(class, "tf_weapon_pipebomblauncher")) {		// -25%
							damage *= SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);
						}
						else if (!(StrEqual(class, "tf_weapon_grenadelauncher") ||
							StrEqual(class, "tf_weapon_flaregun") ||
							StrEqual(class, "tf_weapon_sniperrifle") ||
							iPrimaryIndex == 414)) {		// Exclude everything with no fall-off
							damage *= SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
					}
				}
			}
			
			// Cloak and Dagger no resistance
			if (TF2_IsPlayerInCondition(victim, TFCond_Cloaked) && iWatchIndex == 60) {
				damage /= 0.8;
			}
			
			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if ((StrEqual(class, "tf_weapon_scattergun") || StrEqual(class, "tf_weapon_soda_popper") || StrEqual(class, "tf_weapon_pep_brawler_blaster")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Scale the ramp-up down to 150%
				}
			}

			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if ((StrEqual(class, "tf_weapon_rocketlauncher") || StrEqual(class, "tf_weapon_rocketlauncher_airstrike") || StrEqual(class, "tf_weapon_particle_cannon")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.6) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 140%
				}
				else	if (iPrimaryIndex == 414 && fDistance > 512.0) {		// Liberty Launcher
					fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Remove fall-off
				}
			}
			
			// Pyro
			if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				// Disables damage from fire particles
				if (StrEqual(class, "tf_weapon_flamethrower")) {
					if (damage_type & DMG_USE_HITLOCATIONS) {
						damage_type &= ~DMG_USE_HITLOCATIONS;
					}
					else {
						damage = 0.0;
					}
				}
				else if (StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge")) {
					if (damage_type & DMG_CRIT != 0 && !isKritzed(attacker)) {		// Remove Crits on burning players
						damage_type = (damage_type & ~DMG_CRIT);
						damage /= 3.0;
					}
					if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier
					}
					if (TF2Util_GetPlayerBurnDuration(victim) > 0.0) {		// Add a Mini-Crit instead
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015, 0);		// Applies a Mini-Crit
						damage *= 1.35;
						if (fDistance > 512.0) {
							fDmgMod = 1.0;
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
					
					//SDKHooks_TakeDamage(victim, attacker, attacker, 1.0, DMG_BULLET, weapon,_,_, false);		// Applying this fake extra hit produces hitmarkers
					damage_type |= DMG_BULLET;
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
					damage = 10.0;
				}
			}
			
			// Sniper
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
				// Rifle custom ramp-up/fall-off and Mini-Crit headshot damage
				if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {
					
					damage = 45.0;		// We're overwriting the Rifle charge behaviour so we manually set the baseline damage here
					float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
					fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 1.75);		// Apply up to 75% bonus damage depending on charge
					damage *= fDmgMod;
					
					if (players[attacker].iHeadshot_Frame == GetGameTickCount()) {		// Here we look at headshot status
						damage_type |= DMG_CRIT;		// Apply a Crit
						fDmgMod *= 2.0;
						damagecustom = TF_CUSTOM_HEADSHOT;		// No idea if this does anything, honestly
					}
					
					else if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up multiplier
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
				}
				
				else if (		// List of all weapon archetypes with atypical ramp-up and/or fall-off
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher") ||	// +40
				StrEqual(class, "tf_weapon_rocketlauncher_airstrike") ||
				StrEqual(class, "tf_weapon_particle_cannon") ||
				// Demoman
				StrEqual(class, "tf_weapon_pipebomblauncher")) {
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
					float fDmgModTHREATHighMelee;
					
					if (iWeaponIndex == 128) {		// Equalizer
						fDmgModTHREAT = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 1.0, 2.0);
					}
					else if (TF2_GetPlayerClass(attacker) == TFClass_Scout && damage > 40) {		// If the weapon has an intrinsic damage bonus, we reduce theamount of extra damage from THREAT
						fDmgModTHREATHighMelee = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 0.0, 20.0);		// 20 is the max melee damage we'd normally gain from THREAT
					}
					else if ((TF2_GetPlayerClass(attacker) == TFClass_Soldier || TF2_GetPlayerClass(attacker) == TFClass_Heavy) && damage > 80) {
						fDmgModTHREATHighMelee = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 0.0, 40.0);
					}
					else if ((TF2_GetPlayerClass(attacker) == TFClass_Pyro ||
					TF2_GetPlayerClass(attacker) == TFClass_DemoMan ||
					TF2_GetPlayerClass(attacker) == TFClass_Engineer ||
					TF2_GetPlayerClass(attacker) == TFClass_Medic ||
					TF2_GetPlayerClass(attacker) == TFClass_Sniper) &&
					damage > 65) {
						fDmgModTHREATHighMelee = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 0.0, 32.5);
					}
					else if (iMeleeIndex != 43 && iMeleeIndex != 329) {		// No THREAT for KGB or Jag
						fDmgModTHREAT = RemapValClamped(players[attacker].fTHREAT, 0.0, 1000.0, 1.0, 1.5);
					}
					damage += fDmgModTHREATHighMelee;
				}
				
				if (isMiniKritzed(attacker, victim)) {
					if (fDistance > 512.0) {
						fDmgModTHREAT = 0.5 * players[attacker].fTHREAT/1000 + 1;
					}
				}
				
				if (players[attacker].iHeadshot_Frame != GetGameTickCount()) {	// No THREAT impact on headshots
					damage *= fDmgModTHREAT;
				}
			}
			if (StrEqual(class, "tf_weapon_syringegun_medic")) {		// This is to disable the intrinsic damage of the syringes so only the damage dealt in needletouch counts
				if (!(damage_type & DMG_USE_HITLOCATIONS)) {
					damage = 0.0;
				}
			}
		}
	}
	// Sentry damage
	if (attacker >= 1 && IsValidEdict(attacker) && attacker >= 1 && attacker <= MaxClients) {
		if (IsValidEdict(inflictor) && weapon) {
			GetEntityClassname(inflictor, class, sizeof(class));		// Retrieve the inflictor
			if (StrEqual(class,"obj_sentrygun")) {
				/*float vecAttacker[3];
				float vecVictim[3];
				GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
				float fDmgMod = 1.0;		// Distance mod
				if (damage_type & DMG_BULLET) {		// Only process bullet damage
					GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets building position
					float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
					if (fDistance > 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
					}
				}
				
				damage *= fDmgMod;*/
				
			}
			else if (StrEqual(class,"tf_projectile_sentryrocket")) {		// Handle explosive damage from sentry rockets
				float vecAttacker[3];
				float vecVictim[3];
				GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
				float fDmgMod = 1.0;		// Distance mod
				GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets Engineer position
				float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
				fDmgMod = 1 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				damage *= fDmgMod;
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
			int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			
			// Add THREAT
			players[attacker].fTHREAT += damage;		// Add THREAT
			if (players[attacker].fTHREAT > 1000.0) {
				players[attacker].fTHREAT = 1000.0;
			}
			players[attacker].fTHREAT_Timer += damage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
			
			// Reduce Medi-Gun healing on victim
			players[victim].fHeal_Penalty = 5.0;
			TF2Attrib_AddCustomPlayerAttribute(victim, "health from healers reduced", 0.5);
			
			// -== Victims ==-
			// Scout
			if (TF2_GetPlayerClass(victim) == TFClass_Scout) {
				
				int iPrimary = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Primary, true);
				int iPrimaryIndex = -1;
				if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
				
				if (!((GetEntityFlags(victim) & FL_ONGROUND) || iPrimaryIndex == 448)) {		// Soda Popper exception
					players[victim].fAirjump += damage;		// Records the damage we take while airborne (resets on landing; handled in OnGameFrame)
				}
			}
			
			// -== Attackers ==-
			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if (iWeaponIndex == 228 || iWeaponIndex == 1085) {		// Black Box
					players[attacker].fBlack_Box_Healing += damage / 6;
					CreateTimer(0.015, BlackBoxHeal, attacker);		// We do this to collate the healing from multi-hits
				}
			}
		}
	}
}

Action BlackBoxHeal(Handle timer, int iClient) {
	if (players[iClient].fBlack_Box_Healing > 0.0) {
		float HealAmount = players[iClient].fBlack_Box_Healing;
		TF2Util_TakeHealth(iClient, HealAmount);
		Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
		if (event) {
			event.SetInt("amount", RoundFloat(HealAmount));
			event.SetInt("entindex", iClient);
			
			event.FireToClient(iClient);
			delete event;
		}
	}
	players[iClient].fBlack_Box_Healing = 0.0;
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
			// Ratio changed to 1% per 8 HP
			if (iSecondaryIndex == 35) {		// Kritzkreig
				fUber += iHealing * 0.00125 * 1.25;		// Add this to our Uber amount (multiply by 0.001 as 1 HP -> 1%, and Uber is stored as a 0 - 1 proportion)
			}
			else {
				fUber += iHealing * 0.00125;
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


public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		//int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		
		/*int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		int iPrimaryIndex = -1;
		if(iPrimary != -1) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");*/
		
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);

		char class[64];
		GetEntityClassname(iSecondary, class, sizeof(class));
		
		// Demoman
		if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
			// Sticky destruction of other stickies
			if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
				if(buttons & IN_ATTACK2) {		// Are we using the alt-fire?

					for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
						if (!IsValidEntity(iEnt)) continue;		// Skip invalid entities

						GetEntityClassname(iEnt, class, sizeof(class));
						if (StrEqual(class, "tf_projectile_pipe_remote")) {		// Check if the entity is a sticky bomb
							
							int iOwner = GetEntPropEnt(iEnt, Prop_Send, "m_hOwnerEntity");
							if (iOwner == iClient) {		// Check if the sticky belongs to us
								
								int iShooterTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
								float vecShooterProjectilePos[3];
								GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecShooterProjectilePos);
								
								for (int jEnt = 0; jEnt < GetMaxEntities(); jEnt++) {
									if (!IsValidEntity(jEnt)) continue;
									
									GetEntityClassname(jEnt, class, sizeof(class));
									if (StrEqual(class, "tf_projectile_pipe_remote")) {		// Check if the entity is a sticky bomb
							
										int iTargetTeam = GetEntProp(jEnt, Prop_Data, "m_iTeamNum");
										if (iTargetTeam != iShooterTeam) {
											float vecTargetPos[3];
											GetEntPropVector(jEnt, Prop_Send, "m_vecOrigin", vecTargetPos);

											// Check if the sticky is within the appropriate distance for our sticky to do 70 damage
											if (GetVectorDistance(vecShooterProjectilePos, vecTargetPos) <= 87.6) {
												AcceptEntityInput(jEnt, "Kill"); // Destroy the sticky
											}
										}
									}
								}
							}
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action AutoreloadPistol(Handle timer, int iClient) {
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);		// Retrieve the secondary weapon
	
	char class[64];
	GetEntityClassname(iSecondary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_pistol") || StrEqual(class, "tf_weapon_pistol_scout")) {		// If we have a Syringe Gun equipped
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our SMG
		int ammoSubtract = 12 - clip;		// Don't take away more ammo than is nessesary
		
		int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < 12 && ammoCount > 0) {
			if (ammoCount < 12) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iSecondary, iAmmoTable, 12, 4, true);		// Add loaded ammo
		}
	}
	return Plugin_Handled;
}

public Action AutoreloadSyringe(Handle timer, int iClient) {
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);		// Retrieve the primary weapon
	int iPrimaryIndex = -1;
	if(iPrimary != -1) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	char class[64];
	GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_syringegun_medic")) {		// If we have a Syringe Gun equipped
		int iClipMax = 50;
		switch(iPrimaryIndex) {
			case 36: {
				iClipMax = 40;
			}
		}
		
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our SMG
		int ammoSubtract = iClipMax - clip;		// Don't take away more ammo than is nessesary
		
		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < iClipMax && ammoCount > 0) {
			if (ammoCount < iClipMax) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iPrimary, iAmmoTable, iClipMax, 4, true);		// Add loaded ammo
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
		
		offset[0] = (15.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
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
		SetEntPropFloat(iSyringe, Prop_Send, "m_flModelScale", 1.5);
		
		DispatchSpawn(iSyringe);
		
		// Calculates forward velocity
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 1200.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 1200.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -1200.0;
		
		// Calculate minor leftward velocity to help us aim better
		float leftVel[3];
		leftVel[0] = -Sine(DegToRad(vecAng[1])) * 133.0;
		leftVel[1] = Cosine(DegToRad(vecAng[1])) * 133.0;
		leftVel[2] = 0.0;  // No change in the vertical direction

		vecVel[0] += leftVel[0];
		vecVel[1] += leftVel[1];

		TeleportEntity(iSyringe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
}


	// -={ Increases ammo from small packs }=-

/*public Action Event_PickUpAmmo(int entity, int iClient) {
	if (IsValidClient(iClient)) {
		char class[64];
		GetEntityClassname(entity, class, sizeof(class));
		if (StrContains(class, "small") != -1) {		// Detect small packs
		
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		
			if (iPrimary != -1) {
				int PrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
				int PrimaryAmmoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, PrimaryAmmo);
				
				GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
				// Flamethrowers
				if (StrEqual(class, "tf_weapon_flamethrower")) {
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
			}
			if (iSecondary != -1) {
				int SecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
				int SecondaryAmmoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, SecondaryAmmo);
				
				GetEntityClassname(iPrimary, class, sizeof(class));	
				// Sticky Launchers
				if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
					if (SecondaryAmmoCount < 24) {
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
	}
	return Plugin_Continue;
}*/


	// -={ Handles sticky destruction by explosives }=-

Action ProjectileTouch(int iProjectile, int other) {
	char class[64];
	GetEntityClassname(iProjectile, class, sizeof(class));
	
	// Explosions destroy stickies
	if (StrEqual(class, "tf_projectile_rocket")) {
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

                        // Check if the sticky is within the appropriate distance for the rocket to do 70 damage
                        if (GetVectorDistance(vecRocketPos, vecStickyPos) <= 102.2) {
                            AcceptEntityInput(iEnt, "Kill"); // Destroy the sticky
                        }
                    }
                }
			}
		}
	}
	// Mad Milk
	else if (StrEqual(class, "tf_projectile_jar_milk")) {
		//int weapon = GetEntPropEnt(iProjectile, Prop_Send, "m_hLauncher");
		//int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
		int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");
		float vecRocketPos[3];
		GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecRocketPos);
		
		// Iterate through all players
		for (int iTarget = 0; iTarget < MaxClients; iTarget++) {
			if (!IsValidClient(iTarget)) continue; // Skip invalid players

			// Check if the player belongs to the opposing team
			//int iTargetTeam = TF2_GetClientTeam(iTarget);
			if (GetEntProp(iTarget, Prop_Send, "m_iTeamNum") == iProjTeam) {
				float vecTargetPos[3];
				GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);

				// Check if the target is within our splash radius
				if (GetVectorDistance(vecRocketPos, vecTargetPos) <= 200.0) {
					TF2Util_TakeHealth(iTarget, 75.0);
				
					Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
					if (event && players[iTarget].iMilk_Cooldown == 0) {
						event.SetInt("amount", 75);
						event.SetInt("entindex", iTarget);
						
						EmitSoundToClient(iTarget, "player/recharged.wav");
						event.FireToClient(iTarget);
						delete event;
						players[iTarget].iMilk_Cooldown = 1;
						CreateTimer(0.3, MilkCooldown, iTarget);
					}
				}
			}
		}
	}
	return Plugin_Handled;
}

Action MilkCooldown(Handle timer, int iTarget) {
	players[iTarget].iMilk_Cooldown = 0;
	return Plugin_Handled;
}

Action PipeSet(int iProjectile) {
	char class[64];
	GetEntityClassname(iProjectile, class, sizeof(class));
	// Loch-n-Load pipes detonating on surface hits
	if (StrEqual(class, "tf_projectile_pipe")) {
		if (GetEntProp(iProjectile, Prop_Send, "m_bTouched") == 1) {
			int weapon = GetEntPropEnt(iProjectile, Prop_Send, "m_hLauncher");
			int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
			int index = -1;
			if (weapon != -1) index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			
			if (index == 308) {		// Loch-n-Load
				float vecGrenadePos[3];
				GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecGrenadePos);
			
				CreateParticle(iProjectile, "ExplosionCore_MidAir", 2.0);
				EmitAmbientSound("weapons/pipe_bomb1.wav", vecGrenadePos, iProjectile);
				
				for (int iTarget = 1 ; iTarget <= MaxClients ; iTarget++) {		// The player being damaged by the grenade
					if (IsValidClient(iTarget)) {
						float vecTargetPos[3];
						GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);
						vecTargetPos[2] += 5;
						
						float fDist = GetVectorDistance(vecGrenadePos, vecTargetPos);		// Store distance
						if (fDist <= 148.0 && (TF2_GetClientTeam(owner) != TF2_GetClientTeam(iTarget) || owner == iTarget)) {
							Handle hndl = TR_TraceRayFilterEx(vecGrenadePos, vecTargetPos, MASK_SOLID, RayType_EndPoint, PlayerTraceFilter, iProjectile);
							if (TR_DidHit(hndl) == false || IsValidClient(TR_GetEntityIndex(hndl))) {
								float damage = RemapValClamped(fDist, 0.0, 148.0, 40.0, 20.0);

								int type = DMG_BLAST;
								if (owner == iTarget) {		// Apply self damage resistance
									damage *= 0.75;
								}
								else if (owner != iTarget) {		// Check if the pipe is a crit
									int crit = GetEntProp(iProjectile, Prop_Send, "m_bCritical");
									if(crit) {
										type |= DMG_CRIT;
									}
								}
								SDKHooks_TakeDamage(iTarget, iProjectile, owner, damage, type, weapon, NULL_VECTOR, vecGrenadePos, false);
							}
							delete hndl;
						}
					}
				}
				AcceptEntityInput(iProjectile, "Kill");
			}
		}
	}
	return Plugin_Changed;
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
	
	SDKHook(entity, SDKHook_StartTouch, needleTouch);
}

Action needleTouch(int Syringe, int other) {
	int weapon = GetEntPropEnt(Syringe, Prop_Send, "m_hLauncher");
	int wepIndex = -1;
	if (weapon != -1) wepIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	switch(wepIndex) {
		case 17,204,36,412: {
			int owner = GetEntPropEnt(Syringe, Prop_Send, "m_hOwnerEntity");
			if (IsValidClient(owner)) {
				if (other != owner && other >= 1 && other <= MaxClients) {
					TFTeam team = TF2_GetClientTeam(other);
					if (TF2_GetClientTeam(owner) != team) {		// Hitting enemies
					
						int damage_type = DMG_BULLET | DMG_USE_HITLOCATIONS;
						SDKHooks_TakeDamage(other, owner, owner, 1.0, damage_type, weapon,_,_, false);		// Do this to ensure we get hit markers
						
						// Add THREAT
						players[owner].fTHREAT += 1.0;		// Add THREAT
						if (players[owner].fTHREAT > 1000.0) {
							players[owner].fTHREAT = 1000.0;
						}
						players[owner].fTHREAT_Timer += 1.0;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
					}
				}
				else if (other == 0) {		// Impact world
					CreateParticle(Syringe, "impact_metal", 1.0,_,_,_,_,_,_,false);
				}
			}
		}
	}
	return Plugin_Continue;
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
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			

			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if ((StrEqual(class, "tf_weapon_scattergun") || StrEqual(class, "tf_weapon_soda_popper") || StrEqual(class, "tf_weapon_pep_brawler_blaster")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Scale the ramp-up down to 150%
				}
			}

			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if ((StrEqual(class, "tf_weapon_rocketlauncher") || StrEqual(class, "tf_weapon_rocketlauncher_airstrike") || StrEqual(class, "tf_weapon_particle_cannon")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.6) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 150%
				}
				else	if (iPrimaryIndex == 414 && fDistance > 512.0) {		// Liberty Launcher
					fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Remove fall-off
				}
			}
			
			// Pyro
			if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				if (StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge")) {
					if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier
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
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our ramp-up/fall-off multiplier (+/- 20%)
					fDmgMod *= 0.4;	// I don't know why, but syringes do way too much damage if we don't have this
				}
			}
			
			// Sniper
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
				// Rifle custom ramp-up/fall-off and Mini-Crit headshot damage
				if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {
					
					damage = 45.0;		// We're overwriting the Rifle charge behaviour so we manually set the baseline damage here
					float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
					fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 1.75);		// Apply up to 75% bonus damage depending on charge
					damage *= fDmgMod;
					
					if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up multiplier
					}
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
				StrEqual(class, "tf_weapon_raygun") ||
				StrEqual(class, "tf_weapon_shotgun_soldier") ||
				// Pyro
				StrEqual(class, "tf_weapon_shotgun_pyro") ||
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
				// Pyro
				StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge")) {		// No fall-off
					if (fDistance < 512.0) {
						fDmgModTHREAT = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
					}
				}
				else if (	
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher") ||	// +40
				StrEqual(class, "tf_weapon_rocketlauncher_airstrike") ||
				StrEqual(class, "tf_weapon_particle_cannon") ||
				// Demoman
				StrEqual(class, "tf_weapon_pipebomblauncher")) {
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
	
	/*if (GetEntProp(building, Prop_Send, "m_iUpgradeLevel") == 1 && entities[building].iLevel <= 1) {
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
	}*/
	return Plugin_Continue;
}

void healBuild(int building)
{
	SetVariantInt(10);
	AcceptEntityInput(building,"AddHealth");
}



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

	// ==={{ Do not touch anything below this point }}===

	// -={ Displays particles (taken from ShSilver) }=-
	
	// -={ Particle stuff below }=-
	
bool PlayerTraceFilter(int entity, int contentsMask, any data)
{
	if(entity == data)
		return (false);
	if(IsValidClient(entity))
		return (false);
	return (true);
}
	

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