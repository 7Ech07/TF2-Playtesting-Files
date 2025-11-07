#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tf2utils>
#include <tf2attributes>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Ech0's Mod",
	author = "Ech0",
	description = "It's Ech0's balance changes no way",
	version = "1.1.0",
	url = ""
};

int FreeDataPack;		// Taken from rocket drop plugin
int DataPackEntRefNumber[256];
DataPack AttrPackDrop[256];

static int g_modelLaser;		// Phlog laser beam
static int g_modelHalo;

enum struct Player {
	// General
	float fPAReload;		// Stores how long until we autoreload a new shell into the Panic Attack
	float fBurningHealthLoss;	// Stores how much our max health should be reduced by Afterburn
	float fVacuumRampup;	// Stores knockback ramp-up from Natascha
	float fLastDmgTrack;	// Stores how long until we last took damage for the purpose of modifying crit heals
	float fRegenTimer;		// Tracks how long we have the regen buff from heal bolt hits
	int iEquipped;		// Tracks the equipped weapon's index in order to determine when it changes
	
	// Soldier	
	float fTreadsTimer;	// Tracks how long we've been charging the Mantreads slam attack
	float fSpeedometer;	// Tracks our falling speed during the Mantreads slam
	bool bSlam;		// Stores whether we're in the slam state
	
	// Pyro
	bool AirblastJumpCD;
	float fPressure;		// Tracks pressure (wow)
	float fPressureCD;	// Tracks Airblast repressurisation cooldown
	bool ParticleCD;
	int iPhlog_Ammo;		// Tracks ammo on the Phlog so we can determine when to fire the beam
	
	// Heavy
	float fRev;		// Tracks how long we've been revved for the purposes of undoing the L&W nerf
	float fFlare_Cooldown;		// HLH firing interval (to prevent tapfiring)
	
	// Medic
	int iSyringe_Ammo;		// Tracks loaded syringes for the purposes of determining when we fire a shot
	
	//int iTempLevel;
	int iEnforcer_Mark;	// Tracks when a person is Marked by the Enforcer, and the Spy who marked them
	int iAirdash_Count;	// Tracks the number of double jumps performed by an Atomizer-wielder
}

enum struct Entity {
	// Stickies
	float fHealth;		// Tracks the health of Demo's bombs
}

	// -={ Precaches audio }=-

public void OnMapStart() {
	g_modelLaser = PrecacheModel("sprites/laser.vmt");
	g_modelHalo = PrecacheModel("materials/sprites/halo01.vmt");
	
	PrecacheSound("misc/banana_slip.wav", true);
	PrecacheSound("weapons/explode2.wav", true);
	PrecacheSound("misc/rd_finale_beep01.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_back.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_forward.wav", true);
	PrecacheSound("weapons/flare_detonator_explode.wav", true);
	PrecacheSound("weapons/syringegun_shoot.wav", true);
	PrecacheSound("weapons/syringegun_shoot_crit.wav", true);
	PrecacheSound("weapons/crusaders_crossbow_shoot.wav", true);
	PrecacheSound("weapons/crusaders_crossbow_shoot_crit.wav", true);
	PrecacheSound("weapons/drg_pomson_drain_01.wav", true);
	
	PrecacheModel("models/weapons/w_models/w_syringe_proj.mdl",true);
}


	// -={ Modifies attributes without needing to go through another plugin }=-

public Action TF2Items_OnGiveNamedItem(int iClient, char[] class, int index, Handle& item) {
	Handle item1;
	
	// Multi-class
	if (index == 1153) {	// Panic Attack
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 7);
		TF2Items_SetAttribute(item1, 0, 1, 0.85); // damage penalty (15%)
		TF2Items_SetAttribute(item1, 1, 3, 0.5); // clip size penalty (50%)
		TF2Items_SetAttribute(item1, 2, 6, 0.4); // fire rate bonus (60%)
		TF2Items_SetAttribute(item1, 3, 45, 1.0); // bullets per shot bonus (10)
		TF2Items_SetAttribute(item1, 4, 547, 1.0); // single wep deploy time decreased (nil)
		TF2Items_SetAttribute(item1, 5, 808, 0.0); // mult_spread_scales_consecutive (removed)
		TF2Items_SetAttribute(item1, 6, 809, 0.0); // fixed_shot_pattern (removed)
	}
	
	// Scout	
	if (StrEqual(class, "tf_weapon_scattergun") && index != 1103) {	// Scattergun
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 36, 0.6); // spread penalty (40% bonus; 20% less accurate than current combined with fixed pattern)
		TF2Items_SetAttribute(item1, 1, 45, 1.5); // bullets per shot bonus (10 -> 15)
		TF2Items_SetAttribute(item1, 2, 809, 1.0); // fixed_shot_pattern
	}
	if (index == 1103) {	// Back Scatter
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 36, 0.72); // spread penalty (20% less accurate than Scattergun)
		TF2Items_SetAttribute(item1, 1, 45, 1.5); // bullets per shot bonus (10 -> 15)
		TF2Items_SetAttribute(item1, 2, 809, 1.0); // fixed_shot_pattern
		TF2Items_SetAttribute(item1, 3, 3, 1.0); // clip size penalty (nil)
		TF2Items_SetAttribute(item1, 4, 619, 0.0); // closerange backattack minicrits
	}
	if (index == 220) {	// Shortstop
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		//TF2Items_SetAttribute(item1, 0, 26, 25.0); // max health additive bonus
		TF2Items_SetAttribute(item1, 0, 3, 1.25); // clip size penalty (5 shots)
		//TF2Items_SetAttribute(item1, 0, 241, 1.15); // reload speed penalty
		TF2Items_SetAttribute(item1, 1, 128, 0.0); // when weapon is active (removed)
		TF2Items_SetAttribute(item1, 2, 36, 1.2); // spread penalty
	}
	
	/*if (index == 450) {	// Atomizer
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 125, -25.0); // max health additive penalty (-25)
		TF2Items_SetAttribute(item1, 1, 250, 0.0); // air dash count (disabled; we're handling this manually)
		TF2Items_SetAttribute(item1, 2, 773, 1.0); // single wep deploy time increased (removed)
		TF2Items_SetAttribute(item1, 3, 1, 1.0); // damage penalty (removed)
	}*/
	
	// Soldier	
	if (index == 414) {	// Liberty Launcher
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 1, 1.0); // damage penalty (removed)
		TF2Items_SetAttribute(item1, 1, 4, 1.0); // clip size bonus (removed)
		TF2Items_SetAttribute(item1, 2, 5, 1.3); // fire rate penalty (30%)
		TF2Items_SetAttribute(item1, 3, 58, 1.2); // self dmg push force increased (20%)
		TF2Items_SetAttribute(item1, 4, 135, 0.7); // rocket jump damage reduction (30%)
	}
	if (index == 133) {		// Gunboats
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 135, 0.5); // rocket jump damage reduction (50%)
	}
	
	// Pyro
	if (StrEqual(class, "tf_weapon_flamethrower") && (index != 594)) {	// All Flamethrowers
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 11);
		TF2Items_SetAttribute(item1, 0, 72, 0.0); // weapon burn dmg reduced (nil)
		TF2Items_SetAttribute(item1, 1, 839, 0.0); // flame_spread_degree (none)
		TF2Items_SetAttribute(item1, 2, 841, 0.0); // flame_gravity (none)
		TF2Items_SetAttribute(item1, 3, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 4, 844, 1920.0); // flame_speed (1920 HU/s)
		TF2Items_SetAttribute(item1, 5, 862, 0.2); // flame_lifetime (0.2 s)
		TF2Items_SetAttribute(item1, 6, 865, 0.0); // flame_up_speed (removed)
		TF2Items_SetAttribute(item1, 7, 843, 0.0); // flame_drag (none)
		TF2Items_SetAttribute(item1, 8, 863, 0.0); // flame_random_lifetime_offset (none)
		TF2Items_SetAttribute(item1, 9, 838, 1.0); // flame_reflect_on_collision (flames riccochet off surfaces)
		TF2Items_SetAttribute(item1, 10, 174, 1.33); // flame_ammopersec_increased (33%)
	}
	
	if (index == 594) {	// Phlogistinator
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 1, 0.0); // damage penalty (100%; prevents damage from flame particles)
		TF2Items_SetAttribute(item1, 1, 174, 1.33); // flame_ammopersec_increased (33%)
		TF2Items_SetAttribute(item1, 2, 844, 0.0); // flame_speed (nil)
		TF2Items_SetAttribute(item1, 3, 862, 0.0); // flame_lifetime (nil)
		TF2Items_SetAttribute(item1, 4, 828, -7.5); // weapon burn time reduced (turns off Afterburn)
	}
	
	/*else if (StrEqual(class, "tf_weapon_flaregun")) {	// All Flare Guns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 72, 0.0); // weapon burn dmg reduced (nil)
	}*/
	
	if (index == 1179) {	// Thermal Thruster
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 535, 1.0); // damage force increase hidden
		TF2Items_SetAttribute(item1, 1, 840, 0.5); // holster_anim_time
	}
	
	if (index == 214) {	// Powerjack
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 125, -25.0); // max health additive penalty
		TF2Items_SetAttribute(item1, 1, 128, 0.0); // provide on active (removed)
		TF2Items_SetAttribute(item1, 2, 180, 75.0); // heal on kill
	}
	
	// Heavy
	if (StrEqual(class, "tf_weapon_minigun")) {	// All Miniguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 2);
		TF2Items_SetAttribute(item1, 0, 45, 4.0); // bullets per shot bonus (16)
		TF2Items_SetAttribute(item1, 1, 106, 0.8); // weapon spread bonus (20%)
	}
	
	if (index == 41) {	// Natascha
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 45, 4.0); // bullets per shot bonus (16)
		TF2Items_SetAttribute(item1, 1, 106, 0.8); // weapon spread bonus (20%)
		TF2Items_SetAttribute(item1, 2, 32, 0.0); // chance to slow target (removed)
		TF2Items_SetAttribute(item1, 3, 738, 1.0); // spinup_damage_resistance (removed)
	}
	
	if (index == 312) {	// Brass Beast
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 45, 4.0); // bullets per shot bonus (16)
		TF2Items_SetAttribute(item1, 1, 106, 0.8); // weapon spread bonus (20%)
		TF2Items_SetAttribute(item1, 2, 738, 1.0); // spinup_damage_resistance (removed)
	}
	
	if (index == 424) {	// Tomislav
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 4);
		TF2Items_SetAttribute(item1, 0, 45, 2.75); // bullets per shot bonus (11)
		TF2Items_SetAttribute(item1, 1, 87, 0.287); // minigun spinup time decreased (-75% of Minigun's new speed)
		TF2Items_SetAttribute(item1, 2, 106, 0.6); // weapon spread bonus (removed)
		TF2Items_SetAttribute(item1, 3, 125, -50.0); // max health additive penalty
	}
	
	if (index == 811 || index == 832) {	// Huo-Long Heater
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 10);
		TF2Items_SetAttribute(item1, 0, 5, 5.0); // fire rate penalty (300%)
		TF2Items_SetAttribute(item1, 1, 76, 0.16); // maxammo primary reduced (32)
		TF2Items_SetAttribute(item1, 2, 86, 1.15); // minigun spinup time increased (15%)
		TF2Items_SetAttribute(item1, 3, 280, 2.0); // override projectile type (to flare)
		TF2Items_SetAttribute(item1, 4, 289, 1.0); // centerfire projectile
		TF2Items_SetAttribute(item1, 5, 430, 0.0); // ring of fire while aiming (removed)
		TF2Items_SetAttribute(item1, 6, 431, 0.0); // uses ammo while aiming (removed)
		TF2Items_SetAttribute(item1, 7, 100, 0.75); // Blast radius decreased (25%)
		TF2Items_SetAttribute(item1, 8, 103, 1.5); // Projectile speed increased (50%)
	}
	
	// Medic
	
	// Sniper
	if (StrEqual(class, "tf_weapon_compound_bow")) {	// Huntsman
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 26, 25.0); // max health additive bonus (25)
		TF2Items_SetAttribute(item1, 1, 37, 0.28); // hidden primary max ammo bonus (12 to 7)
		TF2Items_SetAttribute(item1, 2, 318, 0.75); // faster reload rate (1.5 sec)
	}
	
	// Spy
	if (index == 460) {	// Enforcer
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 3);
		TF2Items_SetAttribute(item1, 0, 5, 1.3); // fire rate penalty (30%)
		TF2Items_SetAttribute(item1, 1, 410, 1.0); // damage bonus while disguised (removed)
		TF2Items_SetAttribute(item1, 2, 797, 0.0); // dmg pierces resists absorbs (removed)
	}
	
	// Scout (includes Engie Pistol)
	if (StrEqual(class, "tf_weapon_pistol")) {	// All Pistols
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 106, 0.7); // weapon spread bonus (removed)
	}
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
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
Entity entities[MAXPLAYERS+1];
int frame;

//Handle dhook_CTFWeaponBase_SecondaryAttack;


public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	SDKHook(iClient, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
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


	SetConVarString(cvar_ref_tf_fireball_airblast_recharge_penalty, "0.5");	// Reverting this to live TF2 values for now
	SetConVarString(cvar_ref_tf_fireball_burn_duration, "3");
	SetConVarString(cvar_ref_tf_fireball_burning_bonus, "2");
	SetConVarString(cvar_ref_tf_fireball_damage, "37.5");
	SetConVarString(cvar_ref_tf_fireball_radius, "17.5");


	SetConVarString(cvar_ref_tf_airblast_cray_power, "400");
	SetConVarString(cvar_ref_tf_airblast_cray_reflect_coeff, "1");
	
	// This detects when we touch a cabinet
	HookEvent("post_inventory_application", OnGameEvent, EventHookMode_Post);
	
	//Handle game_config = LoadGameConfigFile("Ech0");
	
	//dhook_CTFWeaponBase_SecondaryAttack = DHookCreateFromConf(game_config, "CTFWeaponBase::SecondaryAttack");
	
	AddNormalSoundHook(OnSoundNormal);		// Use this to detect sounds
}


	// -={ Resets variables on death }=-

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast) {
	//int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int victim = event.GetInt("victim_entindex");
	//int customKill = event.GetInt("customkill");
	
	// Enforcer
	for (int i = 1; i <= MaxClients; i++) {		// Remove mark when the Spy dies
		if (IsClientInGame(i) && IsPlayerAlive(i)) {
			if (players[i].iEnforcer_Mark == victim) {
				players[i].iEnforcer_Mark = 0;
				TF2_RemoveCondition(i, TFCond_MarkedForDeath);
			}
		}
	}
	
	if (players[victim].iEnforcer_Mark > 0) {		// Enforcer speed boost on mark kill
		TF2_AddCondition(players[victim].iEnforcer_Mark, TFCond_SpeedBuffAlly, 5.0, 0);
		players[victim].iEnforcer_Mark = 0;
	}

	return Plugin_Continue;
}

	// -={ Resets variables on death }=-

Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {
	int iClient;
	
	if (StrEqual(name, "post_inventory_application")) {
		iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(iClient)) {
			players[iClient].fBurningHealthLoss = 0.0;		// Restore health lost from Afterburn
			int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
			SetEntProp(iClient, Prop_Send, "m_iHealth", iMaxHealth);
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
			
			// Modify our weapon attributes
			AttributeChanges(iClient, iPrimary, iSecondary, iMelee, iWatch);
		}
	}
	return Plugin_Continue;
}

public Action AttributeChanges(int iClient, int iPrimary, int iSecondary, int iMelee, int iWatch) {
	/*int iPrimaryIndex = -1;
	if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

	int iSecondaryIndex = -1;
	if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

	int iMeleeIndex = -1;
	if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	int iWatchIndex = -1;
	if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");*/
	
	TF2Attrib_RemoveByName(iClient, "hidden primary max ammo bonus");
	TF2Attrib_RemoveByName(iClient, "hidden secondary max ammo penalty");
	TF2Attrib_RemoveByName(iClient, "move speed bonus");
	TF2Attrib_RemoveByName(iClient, "max health additive bonus");
	TF2Attrib_RemoveByName(iClient, "max health additive penalty");
	TF2Attrib_RemoveByName(iClient, "clip size penalty");
	
	switch (TF2_GetPlayerClass(iClient)) {
		
		// Soldier
		case TFClass_Soldier: {
			TF2Attrib_SetByName(iClient, "rocket jump damage reduction", 0.8);
		}

		// Pyro
		case TFClass_Pyro: {
			TF2Attrib_SetByName(iClient, "max health additive bonus", 50.0);
			TF2Attrib_SetByName(iPrimary, "flame ammopersec increased", 1.333333);
			TF2Attrib_SetByName(iPrimary, "flame_drag", 8.5);
			TF2Attrib_SetByName(iPrimary, "flame_speed", 2450.0);
			TF2Attrib_SetByName(iPrimary, "flame_up_speed", 50.0);
			TF2Attrib_SetByName(iPrimary, "flame_lifetime", 0.6);
		}

		// Heavy
		case TFClass_Heavy: {
			TF2Attrib_SetByName(iClient, "move speed bonus", 1.0389610);
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			TF2Attrib_SetByName(iClient, "hidden primary max ammo bonus", 0.6);
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 120, _, primaryAmmo);
		}
		
		// Engineer
		case TFClass_Engineer: {
			TF2Attrib_SetByName(iClient, "build rate bonus", 0.4);
			TF2Attrib_SetByName(iClient, "engineer sentry build rate multiplier", 0.4);
		}
		
		// Medic
		case TFClass_Medic: {
			TF2Attrib_SetByName(iClient, "clip size penalty", 0.625);
			TF2Attrib_SetByName(iClient, "heal rate penalty", 0.75);
			TF2Attrib_SetByName(iClient, "overheal decay penalty", 0.333333);
			TF2Attrib_SetByName(iPrimary, "override projectile type", 9.0);
			SetEntProp(iPrimary, Prop_Send, "m_iClip1", 25);
		}

		// Sniper
		case TFClass_Sniper: {
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			TF2Attrib_SetByName(iClient, "hidden primary max ammo bonus", 0.4);
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 10, _, primaryAmmo);
			TF2Attrib_SetByName(iPrimary, "sniper fires tracer HIDDEN", 1.0);
		}
	}
	return Plugin_Handled;
}

public void OnGameFrame() {
	frame++;
	
	if (frame % 99 == 0) {	// Run every 1.5 seconds or so
	
		// Armed sticky visuals
		for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
			if (!IsValidEntity(iEnt)) continue;
			
			char class[64];
			GetEntityClassname(iEnt, class, sizeof(class));
			if (!StrEqual(class, "tf_projectile_pipe_remote")) continue;
			float vecGrenadePos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecGrenadePos);
			
			//int team = GetEntProp(iEnt, Prop_Send, "m_iTeamNum");
			//CreateParticle(iEnt, "arm_muzzleflash_flare", 0.15, _, _, _, _, _, 10.0);	// 0.15 s duration; 10 HU size
			/*if (team == 2) {		// Red
				CreateParticle(iEnt, "drg_cow_explosion_flashup", 0.15, _, _, _, _, _, 1.0);	// 0.15 s duration; 10 HU size
			}
			else if (team == 3) {
				CreateParticle(iEnt, "drg_cow_explosion_flashup_blue", 0.15, _, _, _, _, _, 1.0);
			}*/
			
			for (int iNearbyPlayer = 1; iNearbyPlayer <= MaxClients; iNearbyPlayer++) {
				if (!IsClientInGame(iNearbyPlayer) || !IsPlayerAlive(iNearbyPlayer)) continue;
				
				float vecNearbyPlayerPos[3];
				GetClientEyePosition(iNearbyPlayer, vecNearbyPlayerPos);
				float fDistance = GetVectorDistance(vecGrenadePos, vecNearbyPlayerPos);
				if (fDistance > 350.0) continue;
				
				int iTeam = GetEntProp(iEnt, Prop_Send, "m_iTeamNum");	// 2 == RED; 3 == BLU
				int iPitch = (iTeam == 2 ? 50 : 150); 
				EmitSoundToClient(iNearbyPlayer, "misc/rd_finale_beep01.wav", _, _, _, _, RemapValClamped(fDistance, 0.0, 350.0, 0.15, 0.05), iPitch); 	// This is a naval mine sort of sound; perfect
			}
		}
	}
	
	for (int iClient = 1; iClient <= MaxClients; iClient++) {		// Caps Afterburn at 6 and handles Temperature
		if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient)) continue;
			
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		int iPrimaryIndex = -1;
		if (iPrimary >= 0) {
			iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
		}
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int iSecondaryIndex = -1;
		if (iSecondary >= 0) {
			iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		}
		int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
		int iMeleeIndex = -1;
		if (iMelee >= 0) {
			iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
		}
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");		// Retrieve the active weapon
		
		// Global
		// Afterburn
		float fBurn = TF2Util_GetPlayerBurnDuration(iClient);
		
		if (fBurn > 6.0) TF2Util_SetPlayerBurnDuration(iClient, 6.0);
		
		if (fBurn > 0.0) {
			players[iClient].fBurningHealthLoss += 0.015;
			if (players[iClient].fBurningHealthLoss > 12.0) {
				players[iClient].fBurningHealthLoss = 12.0;
			}
		}
		else {
			players[iClient].fBurningHealthLoss -= 0.015;
			if (players[iClient].fBurningHealthLoss < 0.0) {
				players[iClient].fBurningHealthLoss = 0.0;
			}
		}
		if (TF2_GetPlayerClass(iClient) == TFClass_Pyro) {
			players[iClient].fBurningHealthLoss = 0.0;
		}

		int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
		//int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
		int iMaxHealth;
		switch (TF2_GetPlayerClass(iClient)) {
			// TODO: Make this take unlocks into account
			case TFClass_Scout, TFClass_Engineer, TFClass_Sniper, TFClass_Spy: {
				iMaxHealth = 125;
			}
			case TFClass_Medic: {
				iMaxHealth = 150;
			}
			case TFClass_DemoMan, TFClass_Pyro: {
				iMaxHealth = 175;
			}
			case TFClass_Soldier: {
				iMaxHealth = 200;
			}
			case TFClass_Heavy: {
				iMaxHealth = 300;
			}
		}
		int fHealthProportion = iHealth / iMaxHealth;
		
		//TF2Attrib_AddCustomPlayerAttribute(iClient, "max health additive penalty", -(iMaxHealth * 0.083333) * players[iClient].fBurningHealthLoss);
		iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);		// Redefine this later on after we update max health
		if (fHealthProportion < iHealth / iMaxHealth) {
			SetEntProp(iClient, Prop_Send, "m_iHealth", fHealthProportion * iMaxHealth);
		}
		
		// Natascha tractor beam effect
		if (players[iClient].fVacuumRampup > 0.0) {
			players[iClient].fVacuumRampup -= 0.015;
		}
		
		// Heal bolt regen
		if (players[iClient].fRegenTimer > 0.0) {
			if (frame % 8 == 0) {		// Healing 3 health per 8 frames is approximately 25
				TF2Util_TakeHealth(iClient, 3.0);
				players[iClient].fRegenTimer -= 0.12;
			}
		}
		
		// Crit heals
		if (players[iClient].fLastDmgTrack < 15.0) {
			players[iClient].fLastDmgTrack += 0.015;
		}
		if (players[iClient].fLastDmgTrack > 10.0) {
			TF2Attrib_SetByName(iClient, "health from healers increased", RemapValClamped(players[iClient].fLastDmgTrack, 10.0, 15.0, 1.0, 1.5));
		}
		else {
			TF2Attrib_RemoveByName(iClient, "health from healers increased");
		}
		
		// Enforcer mark
		if (!TF2_IsPlayerInCondition(iClient, TFCond_MarkedForDeath)) {		// Remove Enforcer mark when the Mark-for-Death debuff expires
			players[iClient].iEnforcer_Mark = 0;
		}
		
		// Panic Attack
		if (iSecondaryIndex == 1153) {				
			if (iActive == iSecondary) {
				players[iClient].fPAReload = 1.0;
			}
			else {
				players[iClient].fPAReload -= 0.015;
				
				if (players[iClient].fPAReload <= 0.0) {
					AutoreloadPA(iClient);
				}
			}
		}
		else if (iPrimaryIndex == 1153) {				
			if (iActive == iPrimary) {
				players[iClient].fPAReload = 1.0;
			}
			else {
				players[iClient].fPAReload -= 0.015;
				
				if (players[iClient].fPAReload <= 0.0) {
					AutoreloadPAPrim(iClient);
				}
			}
		}
		
		switch (TF2_GetPlayerClass(iClient)) {
	
			// Scout
			case TFClass_Scout: {
				// Atomizer
				if (iMeleeIndex != 450) continue;
				
				int airdash_value = GetEntProp(iClient, Prop_Send, "m_iAirDash");
				if (airdash_value > 0) {		// Did we double jump this frame?
					players[iClient].iAirdash_Count++;		// Count the double jump
					if (players[iClient].iAirdash_Count >= 1) {
						EmitSoundToAll("misc/banana_slip.wav", iClient, SNDCHAN_AUTO, 30, (SND_CHANGEVOL|SND_CHANGEPITCH), 1.0, 100);
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
			
			// Soldier
			case TFClass_Soldier: {
				
				// Mantreads
				if (iSecondaryIndex != 444) continue;
				
				float vecVel[3];
				if (players[iClient].bSlam == true) {
					GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);
					vecVel[2] -= 12.0;		// Effectively doubles our gravity
					TeleportEntity(iClient , _, _, vecVel);
					if (players[iClient].fSpeedometer > vecVel[2]) {
						players[iClient].fSpeedometer = vecVel[2];
					}
					TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, 4.0, 0);
				}
				if (!(GetEntityFlags(iClient) & FL_ONGROUND || GetEntityFlags(iClient) & FL_INWATER)) continue;
				
				players[iClient].bSlam = false;
				players[iClient].fTreadsTimer = 0.0;
				if (players[iClient].fSpeedometer < 0.0) {
					
					// Create a cosmetic explosion
					int iExplode = CreateEntityByName("env_explosion");
					
					DispatchKeyValue(iExplode, "fireballsprite", "sprites/splodesprite.vmt");
					DispatchKeyValue(iExplode, "iMagnitude", "0");
					DispatchKeyValue(iExplode, "iRadiusOverride", "200");
					DispatchKeyValue(iExplode, "rendermode", "5");
					DispatchKeyValue(iExplode, "spawnflags", "2");
					
					DispatchSpawn(iExplode);
					ActivateEntity(iExplode);
					
					float vecSoldierPos[3];
					GetClientEyePosition(iClient, vecSoldierPos);
					TeleportEntity(iExplode, vecSoldierPos, NULL_VECTOR, NULL_VECTOR);

					AcceptEntityInput(iExplode, "Explode");
					AcceptEntityInput(iExplode, "Kill");
					
					SetEntPropEnt(iExplode, Prop_Data, "m_hOwnerEntity", iClient);
					
					for (int iTarget = 1 ; iTarget <= MaxClients ; iTarget++) {
						if (!IsValidClient(iTarget)) continue;
						float vecTargetPos[3];
						EmitAmbientSound("weapons/explode2.wav", vecSoldierPos, iClient, SNDLEVEL_TRAIN, _, 0.35);
						GetClientEyePosition(iClient, vecSoldierPos);
						GetClientEyePosition(iTarget, vecTargetPos);
						
						float fDist = GetVectorDistance(vecSoldierPos, vecTargetPos);
						if (!(fDist <= 218.0 && (TF2_GetClientTeam(iClient) != TF2_GetClientTeam(iTarget) || iClient != iTarget))) continue;
						
						Handle hndl = TR_TraceRayFilterEx(vecSoldierPos, vecTargetPos, MASK_SOLID, RayType_EndPoint, PlayerTraceFilter, iClient);
						if (TR_DidHit(hndl) == false || IsValidClient(TR_GetEntityIndex(hndl))) {
							float fDamage = RemapValClamped(fDist, 70.0, 218.0, 1.0, 0.5) * RemapValClamped(players[iClient].fSpeedometer, -650.0, -3500.0, 40.0, 240.0);		// Damage scales with distance and falling speed

							int type = DMG_BLAST;
							float vecBlast[3], vecVelVictim[3];
							vecBlast[2] = RemapValClamped(players[iClient].fSpeedometer, -650.0, -3500.0, 150.0, 600.0);
							GetEntPropVector(iTarget, Prop_Data, "m_vecVelocity", vecVelVictim);		// Retrieve existing velocity
							AddVectors(vecVelVictim, vecBlast, vecVelVictim);
							
							TeleportEntity(iTarget , _, _, vecVelVictim);
							SDKHooks_TakeDamage(iTarget, iSecondary, iClient, fDamage, type, -1, vecBlast, vecSoldierPos, false);
						}
						delete hndl;
					}
					players[iClient].fSpeedometer = 0.0;
					TF2_RemoveCondition(iClient, TFCond_SpeedBuffAlly);
					TF2Attrib_RemoveByName(iSecondary, "damage force reduction");
					TF2Attrib_RemoveByName(iSecondary, "airblast vulnerability multiplier");
					TF2Attrib_RemoveByName(iSecondary, "increased air control");
				}
			}
			
			// Pyro
			case TFClass_Pyro: {
				// Airblast jump chaining prevention
				float vecVel[3];
				GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
				if (vecVel[2] == 0 && (GetEntityFlags(iClient) & FL_ONGROUND)) {		// Are we grounded?
					players[iClient].AirblastJumpCD = true;
				}
				
				/* *Flamethrower weaponstates*
					0 = Idle
					1 = Start firing
					2 = Firing
					3 = Airblasting
				*/
				
				// Phlogistinator
				int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
				if (iPrimaryIndex == 594 && (weaponState == 1 || weaponState == 2)) {		// Are we firing the Phlog?
					
					int Ammo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, Ammo);		// Only fire the beam on frames where the ammo changes
					if (ammoCount == (players[iClient].iPhlog_Ammo - 1)) {		// We update iPhlog_Ammo after this check, so clip will always be 1 lower on frames in which we fire a shot
						
						float vecPos[3], vecAng[3];
						
						GetClientEyePosition(iClient, vecPos);
						GetClientEyeAngles(iClient, vecAng);
						
						GetAngleVectors(vecAng, vecAng, NULL_VECTOR, NULL_VECTOR);
						ScaleVector(vecAng, 512.0);		// Scales this vector 512 HU out
						AddVectors(vecPos, vecAng, vecAng);		// Add this vector to the position vector so the game can aim it better
						
						TR_TraceRayFilter(vecPos, vecAng, MASK_SOLID, RayType_EndPoint, TraceFilter_ExcludeSingle, iClient);		// Create a trace that starts at us and ends 512 HU forward
						
						int iBeamColour[4];		// Colour of the beam
						if (TF2_GetClientTeam(iClient) == TFTeam_Red) {
							iBeamColour[0] = 255;
							iBeamColour[1] = 0;
							iBeamColour[2] = 0;
							iBeamColour[3] = 200;
						}
						else if (TF2_GetClientTeam(iClient) == TFTeam_Blue) {
							iBeamColour[0] = 0;
							iBeamColour[1] = 255;
							iBeamColour[2] = 0;
							iBeamColour[3] = 200;
						}
						vecPos[2] -= 12.0;
						TE_SetupBeamPoints(vecPos, vecAng, g_modelLaser, g_modelHalo, 0, 1, 0.1, 2.0, 2.0, 1, 1.0, iBeamColour, 1);	// Create a beam visual
						
						if (TR_DidHit()) {
							int iEntity = TR_GetEntityIndex();		// This is the ID of the thing we hit
							
							if (iEntity >= 1 && iEntity <= MaxClients && GetClientTeam(iEntity) != GetClientTeam(iClient)) {		// Did we hit an enemy?
								//PrintToChatAll("Hit");
								
								float vecVictim[3], fDmgMod;
								GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
								float fDistance = GetVectorDistance(vecPos, vecVictim, false);		// Distance calculation
								fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our distance multiplier
								// TODO: knockback equation
								SDKHooks_TakeDamage(iEntity, iPrimary, iClient, (7.5 * fDmgMod), DMG_SHOCK, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage (credited to the Phlog)
							}
						}
					}
					players[iClient].iPhlog_Ammo = ammoCount;
				}
				
				// Pressure
				char class[64];
				GetEntityClassname(iPrimary, class, sizeof(class));
				
				/*if (primaryIndex == 30474 || primaryIndex == 741) {		// Cap Napalmer pressure to 1 tank
					players[iClient].fPressure += 0.01;	// 1.5 seconds repressurisation time
					if (players[iClient].fPressure > 1.0) {
						players[iClient].fPressure = 1.0;
						TF2Attrib_SetByDefIndex(iPrimary, 255, 1.33);		// Increased push force when pressurised (to live TF2 value)
					}
					else {
						TF2Attrib_SetByDefIndex(iPrimary, 255, 1.125);
					}
				}*/

				if (StrEqual(class, "tf_weapon_flamethrower")) {		// Cap other Flamethrowers' pressure to 2 tanks
					if (players[iClient].fPressureCD > 0.0) {		// This value starts high and goes down
						players[iClient].fPressureCD -= 0.015;
					}
					else {
						players[iClient].fPressureCD = 0.0;
					}
					if (players[iClient].fPressure < 2.0) {
						if (players[iClient].fPressureCD <= 0.0) {
							players[iClient].fPressure += 0.03;		// Takes 0.5 sec to refil each charge
						}
					}
					else {
						players[iClient].fPressure = 2.0;
					}
					
					if (players[iClient].fPressure < 1.0) {		// Disable Airblast when not pressurised
						TF2Attrib_SetByDefIndex(iSecondary, 356, 1.0);
					}
					else {
						TF2Attrib_SetByDefIndex(iSecondary, 356, 0.0);
					}
				}
				else if (StrEqual(class, "tf_weapon_rocketlauncher_fireball")) {
					if (players[iClient].fPressureCD > 0.0) {
						players[iClient].fPressureCD -= 0.015;
					}
					if (players[iClient].fPressure < 1.0) {
						if (players[iClient].fPressureCD <= 0.0) {
							players[iClient].fPressure += 0.03;
						}
					}
					else {
						players[iClient].fPressure = 1.0;
					}
				}
				
				if ((iPrimaryIndex != 594) && (iPrimaryIndex != 1178)) {
					SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 1, "Pressure: %.2f", players[iClient].fPressure);
				}
				
				if (TF2_IsPlayerInCondition(iClient, TFCond_RocketPack)) {
					//PrintToChatAll("Rocketpack");
					TF2Attrib_SetByDefIndex(iSecondary, 610, 3.0);
					TF2Attrib_SetByDefIndex(iSecondary, 780, 1.5);
				}
				else {
					//PrintToChatAll("Rockets off");
					TF2Attrib_SetByDefIndex(iSecondary, 610, 1.0);
					TF2Attrib_SetByDefIndex(iSecondary, 780, 1.0);
				}
			}
			
			// Heavy
			// Counteracts the L&W nerf by dynamically adjusting damage and accuracy; handles Natascha speed
			case TFClass_Heavy: {
				
				players[iClient].fFlare_Cooldown -= 0.015;
				
				//float fDmgMult = 1.0;		// Default values -- for stock, and in case of emergency
				//float fAccMult = 0.8;
				
				/*switch(iPrimaryIndex) {		// Determine unique damage and accuracy multipliers for the unlocks
					case 424: {		// Tomislav
						//fDmgMult = 1.0;
						fAccMult = 0.6;
					}
					case 41: {		// Natascha
						//fDmgMult = 1.0;
						fAccMult = 1.0;
					}
					case 811, 832: {		// Huo-Long Heater
						//fDmgMult = 2.4074;
						fAccMult = 1.0;
					}
					case 312: {		// Brass Beast
						//fDmgMult = 1.02;
						fAccMult = 1.0;
					}
				}*/
				
				int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
				int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
				int sequence = GetEntProp(view, Prop_Send, "m_nSequence");		// We use viewmodel animation as an additional check for being unrevved for Natascha
				float cycle = GetEntPropFloat(view, Prop_Data, "m_flCycle");
				
				/* *Minigun weaponstates*
					0 = Idle
					1 = Revving up
					2 = Firing
					3 = Revved but not firing
				*/
				
				if (weaponState == 1) {		// Are we revving up?
					players[iClient].fRev = 1.005;		// This is our rev meter; it's a measure of how close we are to being free of the L&W nerf
				}
				
				else if ((weaponState == 2 || weaponState == 3) && players[iClient].fRev > 0.0) {		// If we're revved but the rev meter isn't empty...
					players[iClient].fRev = players[iClient].fRev - 0.015;		// It takes us 67 frames (1 second) to fully deplete the rev meter
					int time = RoundFloat(players[iClient].fRev * 1000);
					if (time%90 == 0) {		// Only adjust the damage every so often
						float factor = 1.0 + time/990.0;		// We increase damage and accuracy over time proportional to the rev meter
						if (iPrimaryIndex == 424) {		// Tomislav
							TF2Attrib_SetByDefIndex(iPrimary, 106, 0.6 * 1.0/factor);		// Spread bonus
						}
						//TF2Attrib_SetByDefIndex(iPrimary, 2, fDmgMult * 1.0 * factor);		// Damage bonus
					}
				}
				
				else if (weaponState == 0 && sequence == 23) {		// Are we unrevving?
					if(cycle < 0.6) {
						SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + 0.8);
					}
					float speed = 1.66;
					SetEntPropFloat(view, Prop_Send, "m_flPlaybackRate", speed); //speed up animation
					TF2Attrib_AddCustomPlayerAttribute(iClient, "switch from wep deploy time decreased", 0.25, 0.2);		// Temporary faster Minigun holster
					//TF2Attrib_SetByDefIndex(iPrimary, 3, 0.33)
					
				}
				
				else if (weaponState == 2 && (iPrimaryIndex == 811 || iPrimaryIndex == 832)) {		// Are we revved up with the HLH?
					if (players[iClient].fFlare_Cooldown > 0.0) {		// If we shouldn't be allowed to fire yet...
						SetEntProp(iPrimary, Prop_Send, "m_iWeaponState", 3);		// Set us to idle
					}
				}
			}
			
			// Medic
			case TFClass_Medic: {
				if (iPrimaryIndex == 17 || iPrimaryIndex == 204 || iPrimaryIndex == 36 || iPrimaryIndex == 412) {	// Exclude the Crossbow
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int iClip = GetEntData(iPrimary, iAmmoTable, 4);		// We can detect shots by checking ammo changes
					if (iClip == (players[iClient].iSyringe_Ammo - 1)) {		// We update iSyringe_Ammo after this check, so iClip will always be 1 lower on frames in which we fire a shot
						float vecAng[3];
						GetClientEyeAngles(iClient, vecAng);
						Syringe_PrimaryAttack(iClient, iPrimary, vecAng);
					}
					players[iClient].iSyringe_Ammo = iClip;
					
					// Syringe autoreload
					if (players[iClient].iEquipped != iActive) {			// Weapon swap
						CreateTimer(1.6, AutoreloadSyringe, iClient);
					}
					players[iClient].iEquipped = iActive;
				}
			}
		}
	}
}


	// -={ Preps Airblast jump and backpack reloads }=-

public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!IsClientInGame(iClient) || !IsPlayerAlive(iClient)) return Plugin_Continue;

	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int primaryIndex = -1;
	if(iPrimary >= 0) primaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
	int iSecondaryIndex = -1;
	if(iSecondary >= 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
	
	int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	//int iMeleeIndex = -1;
	//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	//int iClientFlags = GetEntityFlags(iClient);
	
	switch (TF2_GetPlayerClass(iClient)) {
	
		// Soldier
		case TFClass_Soldier: {
			if (!(buttons & IN_JUMP)) return Plugin_Continue;
			if (iSecondaryIndex != 444) return Plugin_Continue;		// Mantreads
			
			if (players[iClient].fTreadsTimer < 0.8) {
				players[iClient].fTreadsTimer += 0.015;
			}
			else {
				players[iClient].bSlam = true;
				TF2Attrib_SetByName(iSecondary, "damage force reduction", 0.25);
				TF2Attrib_SetByName(iSecondary, "airblast vulnerability multiplier", 0.25);
				TF2Attrib_SetByName(iSecondary, "increased air control", 2.0);
			}
		}
		
		// Pyro
		case TFClass_Pyro: {

			char class[64];
			GetEntityClassname(iPrimary, class, sizeof(class));
			
			if (!(StrEqual(class, "tf_weapon_flamethrower") || (StrEqual(class, "tf_weapon_rocketlauncher_fireball"))) || players[iClient].fPressureCD > 0.0) return Plugin_Continue;
			if (!(buttons & IN_ATTACK2)) return Plugin_Continue;
			
			if (buttons & IN_ATTACK && players[iClient].fPressure >= 2.0) {	// Flame Burst
				players[iClient].fPressure -= 2.0;
				players[iClient].fPressureCD = 0.75;
				FlameBurst(iClient);
			}
			else if (players[iClient].fPressure >= 1.0) {	// Regular Airblast
				players[iClient].fPressure -= 1.0;
				players[iClient].fPressureCD = 0.75;
				if (primaryIndex == 1178)	AirblastJump(iClient);	// Dragon's Fury
			}
			else {
				buttons &= ~IN_ATTACK2;		// Disable Airblast if we don't have a Pressure charge
			}
		}
		
		// Heavy
		case TFClass_Heavy: {
			// Minigun holster while spun
			if (iPrimary == -1 || iActive != iPrimary || weapon <= 0) return Plugin_Continue;
			
			if (weapon == iSecondary) {
				bool bReady = true;
				char classname[64];
				GetEntityClassname(iSecondary, classname, 64);
				if (StrContains(classname, "lunchbox") != -1) {		// Are we holding a non-Lunchbox (i.e. a Shotgun)?
					int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					int ammo = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, secondaryAmmo);
					if (ammo == 0) bReady = false;		// Don't let us swap to the Shotgun if it's out of ammo
				}
				if (bReady) {
					SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() - 1.0);
					ClientCommand(iClient, "slot2");
				}
			}
			else if (weapon == iMelee) {
				SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() - 1.0);
				ClientCommand(iClient, "slot3");
			}
		}
		
		// Medic
		case TFClass_Medic: {
			
			char class[64];
			GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
			
			/*if (StrEqual(class, "tf_weapon_syringegun_medic")) {	
				if (buttons & IN_ATTACK2) {
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");		
					int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve loaded ammo
					
					if (clip == 25) {
						SetEntData(iPrimary, iAmmoTable, 0, 4, true);		// Consume all loaded ammo
						HealSyringeFire(iClient, iPrimary);
					}
				}
			}*/
		}
		
		// Sniper
		case TFClass_Sniper: {
			
			// Huntsman passive reload
			if (iPrimary < 0 || iActive != iPrimary) return Plugin_Continue;
			
			if (!(primaryIndex == 56 || primaryIndex == 1005 || primaryIndex == 1092)) return Plugin_Continue;
			
			int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
			int iClip = GetEntData(iPrimary, iAmmoTable, 4);
			
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			int iReserveAmmo = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
			
			if (iClip == 0 && iReserveAmmo > 0 && weapon != 0 && weapon != iPrimary) {		// weapon is the weapon we swap to; check if we're swapping to something other than the bow
				SetEntProp(iClient, Prop_Data, "m_iAmmo", iReserveAmmo - 1 , _, primaryAmmo);
				SetEntData(iPrimary, iAmmoTable, 1, 4, true);
			}
		}
	}
	
	return Plugin_Continue;
}

void FlameBurst(int iClient) {
	//PrintToChatAll("Flame Burst");
	float vecAng[3], vecPos[3], offset[3], vecProjVel[3];
	GetClientEyeAngles(iClient, vecAng);		// Identify where we're looking
	GetClientEyePosition(iClient, vecPos);

	//int iFireball = CreateEntityByName("tf_projectile_balloffire");
	int iFireball = CreateEntityByName("tf_projectile_energy_ball");
	int iFireballVisual = CreateEntityByName("tf_projectile_balloffire");
	
	if (iFireball != -1) {
		int team = GetClientTeam(iClient);
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		
		offset[0] = (15.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		offset[1] = (-6.0 * Cosine(DegToRad(vecAng[1])));
		offset[2] = -10.0;
		
		vecPos[0] += offset[0];
		vecPos[1] += offset[1];
		vecPos[2] += offset[2];
		
		SetEntPropEnt(iFireball, Prop_Send, "m_hOwnerEntity", iClient);	// Attacker
		SetEntPropEnt(iFireball, Prop_Send, "m_hLauncher", iPrimary);	// Weapon
		SetEntProp(iFireball, Prop_Data, "m_iTeamNum", team);		// Team
		SetEntProp(iFireball, Prop_Data, "m_CollisionGroup", 24);		// Collision
		SetEntProp(iFireball, Prop_Data, "m_usSolidFlags", 0);
		SetEntPropFloat(iFireball, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iFireball, Prop_Send, "m_flModelScale", 1.0);
		
		DispatchSpawn(iFireball);
		
		vecProjVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 3000.0;
		vecProjVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 3000.0;
		vecProjVel[2] = Sine(DegToRad(vecAng[0])) * -3000.0;

		//PrintToServer("Spawning at: %.2f %.2f %.2f", vecPos[0], vecPos[1], vecPos[2]);
		TeleportEntity(iFireball, vecPos, vecAng, vecProjVel);			// Apply position and velocity to the projectile
	}
	if (iFireballVisual != -1) {
		int team = GetClientTeam(iClient);
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		
		offset[0] = (15.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		offset[1] = (-6.0 * Cosine(DegToRad(vecAng[1])));
		offset[2] = -10.0;
		
		vecPos[0] += offset[0];
		vecPos[1] += offset[1];
		vecPos[2] += offset[2];
		
		SetEntPropEnt(iFireballVisual, Prop_Send, "m_hOwnerEntity", iClient);	// Attacker
		SetEntPropEnt(iFireballVisual, Prop_Send, "m_hLauncher", iPrimary);	// Weapon
		SetEntProp(iFireballVisual, Prop_Data, "m_iTeamNum", team);		// Team
		SetEntProp(iFireballVisual, Prop_Data, "m_CollisionGroup", 24);		// Collision
		SetEntProp(iFireballVisual, Prop_Data, "m_usSolidFlags", 0);
		SetEntPropFloat(iFireballVisual, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iFireballVisual, Prop_Send, "m_flModelScale", 1.0);
		
		DispatchSpawn(iFireballVisual);
		
		vecProjVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 3000.0;
		vecProjVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 3000.0;
		vecProjVel[2] = Sine(DegToRad(vecAng[0])) * -3000.0;

		//PrintToServer("Spawning at: %.2f %.2f %.2f", vecPos[0], vecPos[1], vecPos[2]);
		TeleportEntity(iFireballVisual, vecPos, vecAng, vecProjVel);			// Apply position and velocity to the projectile
	}
	
	AirblastJump(iClient);
}

void AirblastJump(int iClient) {
	if (!(GetEntityFlags(iClient) & FL_ONGROUND)) {
		float vecAngle[3], vecVel[3], fRedirect, fBuffer, vecBuffer[3];
		GetClientEyeAngles(iClient, vecAngle);		// Identify where we're looking
		GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
		
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
		float fForce = 250.0 + (fRedirect / 2);		// Add half of our redirected falling speed to this
		vecForce[0] *= fForce;
		vecForce[1] *= fForce;
		vecForce[2] *= fForce;
		
		vecForce[2] += 25.0;		// Some fixed upward force to make the jump feel beter
		AddVectors(vecVel, vecForce, vecForce);		// Add the Airblast push force to our velocity
		//AddVectors(vecProjection, vecForce, vecForce); This bit is terrible
		
		TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, vecForce);		// Sets the Pyro's momentum to the appropriate value
	}
}

public Action AutoreloadSyringe(Handle timer, int iClient) {
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	//if(iPrimary != -1) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	char class[64];
	GetEntityClassname(iPrimary, class, sizeof(class));
	
	if (StrEqual(class, "tf_weapon_syringegun_medic")) {		// If we have a Syringe Gun equipped
		int iClipMax = 25;
		/*switch(iPrimaryIndex) {
			case 36: {
				iClipMax = 40;
			}
		}*/
		
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int iClip = GetEntData(iPrimary, iAmmoTable, 4);
		int ammoSubtract = iClipMax - iClip;
		
		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int iReserveAmmo = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
		
		if (iClip < iClipMax && iReserveAmmo > 0) {
			if (iReserveAmmo < iClipMax) {
				ammoSubtract = iReserveAmmo;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", iReserveAmmo - ammoSubtract, _, primaryAmmo);
			SetEntData(iPrimary, iAmmoTable, iClipMax, 4, true);
		}
	}
	return Plugin_Handled;
}

public void Syringe_PrimaryAttack(int iClient, int iPrimary, float vecAng[3]) {
	int iSyringe = CreateEntityByName("tf_projectile_syringe");
	
	if (iSyringe != -1) {
		int team = GetClientTeam(iClient);
		float vecPos[3], vecVel[3], offset[3];
		
		GetClientEyePosition(iClient, vecPos);
		
		offset[0] = (15.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		offset[1] = (-6.0 * Cosine(DegToRad(vecAng[1])));
		offset[2] = -10.0;
		
		vecPos[0] += offset[0];
		vecPos[1] += offset[1];
		vecPos[2] += offset[2];

		if (isKritzed(iClient)) EmitAmbientSound("weapons/syringegun_shoot_crit.wav", vecPos, iClient);
		else EmitAmbientSound("weapons/syringegun_shoot.wav", vecPos, iClient);
		
		SetEntPropEnt(iSyringe, Prop_Send, "m_hOwnerEntity", iClient);
		SetEntPropEnt(iSyringe, Prop_Send, "m_hLauncher", iPrimary);
		SetEntProp(iSyringe, Prop_Data, "m_iTeamNum", team);
		SetEntProp(iSyringe, Prop_Send, "m_iTeamNum", team);
		SetEntProp(iSyringe, Prop_Data, "m_CollisionGroup", 24);
		SetEntProp(iSyringe, Prop_Data, "m_usSolidFlags", 0);
		SetEntProp(iSyringe, Prop_Data, "m_nSkin", team - 2);
		SetEntProp(iSyringe, Prop_Send, "m_nSkin", team - 2);
		SetEntPropVector(iSyringe, Prop_Data, "m_angRotation", vecAng);	
		SetEntityModel(iSyringe, "models/weapons/w_models/w_syringe_proj.mdl");
		SetEntPropFloat(iSyringe, Prop_Data, "m_flGravity", 0.3);
		SetEntPropFloat(iSyringe, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iSyringe, Prop_Send, "m_flModelScale", 1.5);
		
		DispatchSpawn(iSyringe);
		
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 1500.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 1500.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -1500.0;
		
		// Calculate minor leftward velocity to help us aim better
		float leftVel[3];
		leftVel[0] = -Sine(DegToRad(vecAng[1])) * 0.015;
		leftVel[1] = Cosine(DegToRad(vecAng[1])) * 0.015;
		leftVel[2] = 0.0;  // No change in the vertical direction

		vecVel[0] += leftVel[0];
		vecVel[1] += leftVel[1];

		TeleportEntity(iSyringe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
}

public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			// Natascha
			if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 41) {

				float vecAttacker[3], vecVictim[3], vecVelVictim[3];
				GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);
				GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);
				GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vecVelVictim);		// Gets defender initial velocity
				float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
				
				if (fDistance < 750.0) {
					float fForce = damage * 12.0 * RemapValClamped(players[victim].fVacuumRampup, 0.0, 1.0, 1.0, 2.0);	// Max knockback mult of 2x
					
					if (TF2_GetPlayerClass(victim) == TFClass_Heavy) {
						fForce *= 0.5;
					}
					
					players[victim].fVacuumRampup += 0.175;	// 1.5 sec to max ramp-up
					
				    float vecDir[3];
					MakeVectorFromPoints(vecVictim, vecAttacker, vecDir); // vecDir = attacker - victim
					NormalizeVector(vecDir, vecDir);                      // Make it a unit vector

					ScaleVector(vecDir, fForce);                // vecForce = vecDir * fForce
					AddVectors(vecVelVictim, vecDir, vecVelVictim);

					TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vecVelVictim); // Apply force
				}
			}
		}
	}
	
	if (victim >= 1 && victim <= MaxClients) {
		players[victim].fLastDmgTrack = 0.0;
	}
}


	// -={ Calculates damage }=-

Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& weapon, float damage_force[3], float damage_position[3], int damage_custom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
	
		if (victim != attacker) {
		
			float vecAttacker[3];
			float vecVictim[3];
			GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
			GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
			float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
			float fDmgMod = 1.0;
			
			if (weapon < 0) {
				// Thermal Thruster stomp
				if (damage_type & DMG_FALL && TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
					damage *= (5.0 / 3.0);
				}
			}
			
			if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
				GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
				
				// Explosives
				if (StrEqual(class, "tf_weapon_grenadelauncher")) {
					//float vecExplosive[3];
					//GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", vecExplosive);		// Gets projectile position
					
					//float fDistExplosive = GetVectorDistance(vecExplosive, vecVictim, false);
					//PrintToChatAll("Initial damage : %f", damage);
					float fDmgQuadraticMult = RemapValClamped(damage, 60.0, 30.0, 1.0, 0.0) * RemapValClamped(damage, 60.0, 30.0, 1.0, 0.0);
					fDmgQuadraticMult = RemapValClamped(fDmgQuadraticMult, 1.0, 0.0, 1.0, 0.5);
					//PrintToChatAll("Quadratic : %f", fDmgQuadraticMult);
					damage *= RemapValClamped(damage, 60.0, 30.0, 1.0, 1.9) * fDmgQuadraticMult;
				}
				if (StrEqual(class, "tf_weapon_rocketlauncher")) {
					//PrintToChatAll("Initial damage : %f", damage);
					float DmgFrac, DmgFracMult;
					
					if (fDistance > 512.0) {
						DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
					}
					else {
						DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);
					}
					
					DmgFrac = damage / DmgFracMult;
					
					float fDmgQuadraticMult = RemapValClamped(DmgFrac, 90.0, 45.0, 1.0, 0.0) * RemapValClamped(DmgFrac, 90.0, 45.0, 1.0, 0.0);
					fDmgQuadraticMult = RemapValClamped(fDmgQuadraticMult, 1.0, 0.0, 1.0, 0.5);
					//PrintToChatAll("Quadratic : %f", fDmgQuadraticMult);
					damage *= RemapValClamped(DmgFrac, 90.0, 45.0, 1.0, 1.9) * fDmgQuadraticMult;
				}
				if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
					//PrintToChatAll("Initial damage : %f", damage);
					float DmgFrac, DmgFracMult;
					
					if (fDistance > 512.0) {
						DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
					}
					else {
						DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.80);
					}
					
					DmgFrac = damage / DmgFracMult;
					
					float fDmgQuadraticMult = RemapValClamped(DmgFrac, 120.0, 60.0, 1.0, 0.0) * RemapValClamped(DmgFrac, 120.0, 60.0, 1.0, 0.0);
					fDmgQuadraticMult = RemapValClamped(fDmgQuadraticMult, 1.0, 0.0, 1.0, 0.5);
					//PrintToChatAll("Quadratic : %f", fDmgQuadraticMult);
					damage *= RemapValClamped(DmgFrac, 120.0, 60.0, 1.0, 1.9) * fDmgQuadraticMult;
				}
				
				// Scout
				// Scattergun
				if (StrEqual(class, "tf_weapon_scattergun")) {
					damage /= 1.5;
				}
				
				// Back Scatter
				if (StrEqual(class, "tf_weapon_scattergun") && GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 1103) {
					float vecVictimFacing[3], vecDirection[3];
					MakeVectorFromPoints(vecAttacker, vecVictim, vecDirection);		// Calculate direction we are aiming in
					
					GetClientEyeAngles(victim, vecVictimFacing);
					GetAngleVectors(vecVictimFacing, vecVictimFacing, NULL_VECTOR, NULL_VECTOR);
					
					float dotProduct = GetVectorDotProduct(vecDirection, vecVictimFacing);
					bool isBehind = dotProduct > 0.0;		// 180 degrees back angle
					
					if (isBehind) {
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.001, 0);
						damage *= 1.35;
						//PrintToChatAll("Backstab");
					}
				}
				// Bat
				else if (StrEqual(class, "tf_weapon_bat")) {
					damage *= 1.1428571;
				}

				// Soldier
				if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 414) {
					// Liberty Launcher no ramp-up-fall-off
					if (!(damage_type & DMG_CRIT)) {
						if (fDistance < 512.0) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Generates a proportion from 1.25 to 1.0 depending on distance (from 0 to 512 HU)
						}
					}
					damage = damage / fDmgMod;		// Removes ramp-up multiplier
					return Plugin_Changed;
				}
				// Shovel
				else if (StrEqual(class, "tf_weapon_shovel")) {
					damage *= 1.230769;
				}
				
				// Pyro
				// Flamethrower rebuild
				else if(StrEqual(class, "tf_weapon_flamethrower") && (damage_type & DMG_IGNITE) && !(damage_type & DMG_BLAST)) {
					damage = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 11.25, 7.5);
					players[victim].fBurningHealthLoss += 0.6;

					//crit damage multipliers
					if (damage_type & DMG_CRIT) {
						if (isMiniKritzed(attacker, victim) && !isKritzed(attacker)) {
							damage *= 1.35;
						}
						else {
							damage *= 3.0;
						}
					}

					damage_type &= ~DMG_USEDISTANCEMOD;

					if(damage_type & DMG_SONIC) {
						damage_type &= ~DMG_SONIC;
						damage = 0.01;
					}
				}
				
				// Heavy
				// Reduce base damage to compensate for extra bullets
				if (StrEqual(class, "tf_weapon_minigun")) {
					damage *= 0.222222;		// 36 to 32
					
					if (players[attacker].fRev > 0.0) {		// Undoes the damage component of the L&W nerf
						fDmgMod = RemapValClamped(players[attacker].fRev, 0.0, 1.0, 1.0, 2.0);
						damage *= fDmgMod;
					}
				}
				
				// Natascha
				if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 41) {
					damage_type |= DMG_PREVENT_PHYSICS_FORCE;		// Disable base knockback
				}
				
				// Brass Beast resistance
				if (TF2_GetPlayerClass(victim) == TFClass_Heavy) {
					int iPrimary = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Primary, true);
					if (GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex") == 312) {
						//PrintToChatAll("Brass Beast");
						int weaponState = GetEntProp(iPrimary, Prop_Send, "m_iWeaponState");
						
						if (weaponState == 2 || weaponState == 3) {		// Revved
							//PrintToChatAll("revved");
							float vecVictimFacing[3], vecDirection[3];
							
							MakeVectorFromPoints(vecAttacker, vecVictim, vecDirection);		// Calculate direction from us to the attacker and compare that to our aim vector
							GetClientEyeAngles(victim, vecVictimFacing);
							GetAngleVectors(vecVictimFacing, vecVictimFacing, NULL_VECTOR, NULL_VECTOR);
							
							float dotProduct = GetVectorDotProduct(vecDirection, vecVictimFacing);
							//PrintToChatAll("dotproduct: %f", dotProduct);
							
							if (dotProduct < -0.707) {
								
								//PrintToChatAll("Blocked");
								damage *= 0.8;
							}
						}
					}
				}
				
				// HLH Damage
				if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 811 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 832) {		// Do we have the HLH equipped?
					/*if (TF2Util_GetPlayerBurnDuration(victim) > 0 && !(TF2_IsPlayerInCondition(attacker, TFCond_Kritzkrieged) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnFirstBlood) 
						|| TF2_IsPlayerInCondition(attacker, TFCond_CritOnWin) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnFlagCapture) || TF2_IsPlayerInCondition(attacker, TFCond_CritOnKill) 
						|| TF2_IsPlayerInCondition(attacker, TFCond_CritOnDamage))) {		// If we're shooting a burning person but not supposed to be dealing Crits...
						damage_type &= ~DMG_CRIT;		// ...Remove the Crits
						if (TF2_IsPlayerInCondition(victim, TFCond_Jarated) || TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim, TFCond_MarkedForDeathSilent)
							|| TF2_IsPlayerInCondition(attacker, TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(attacker, TFCond_Buffed) || TF2_IsPlayerInCondition(attacker, TFCond_CritCola)) {		// But, if we're suppose doing Mini-Crits...
							TF2_AddCondition(victim,TFCond_MarkedForDeathSilent, 0.015);		// Apply Mini-Crits via Mark-for-Death
						}
					}*/

					/*if (!(damage_type & DMG_CRIT)) {
						if (fDistance < 512.0) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Generates a proportion from 0.5 to 1.0 depending on distance (from 1024 to 1536 HU)
						}
						else {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
					}*/
					//damage = 60.0 * fDmgMod;
					damage *= 35.0 * fDmgMod;
					
					if (isKritzed(attacker)) {
						damage = 210.0;
					}
					
					//damage_type = (damage_type & ~DMG_IGNITE);
					return Plugin_Changed;
				}
				
				// Fists
				else if (StrEqual(class, "tf_weapon_fists")) {
					damage *= 1.230769;
				}
				
				// Medic
				// Syringe Gun
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {
					
					damage_type |= DMG_BULLET;
					if (!isKritzed(attacker)) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up/fall-off multiplier (+/- 50%)
						if (isMiniKritzed(attacker, victim) && fDistance > 512.0) {
							fDmgMod = 1.0;
						}
					}
					else {
						fDmgMod = 3.0;
						damage_type |= DMG_CRIT;
					}
					damage = 5.0 * fDmgMod;
					//PrintToChatAll("damage: %f", damage);
				}
				
				// Sniper
				// Sniper Rifle
				else if (StrEqual(class, "tf_weapon_sniperrifle")) {
					if (fDistance > 1000.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 1024.0, 1556.0, 1.0, 0.5);		// Generates a proportion from 0.5 to 1.0 depending on distance (from 1024 to 1536 HU)

						damage *= fDmgMod;

						return Plugin_Changed;
					}
				}
				
				// SMG
				else if (StrEqual(class, "tf_weapon_smg")) {
					damage *= 1.125;
				}
				
				// Huntsman damage fall-off
				else if (StrEqual(class, "tf_weapon_compound_bow")) {
					if (damage_type & DMG_CRIT != 0) {
						fDmgMod = SimpleSplineRemapValClamped(damage, 150.0, 360.0, 1.2, 0.833333);		// Scale up low-charge arrow damage and reduce max damage to 100
						if (!isKritzed(attacker)) {
							damage *= 0.833333;	// 2.5x headshot mult
						}
					}
					else {
						fDmgMod = SimpleSplineRemapValClamped(damage, 50.0, 120.0, 1.2, 0.833333);
					}
					
					damage *= fDmgMod;
					
					if (fDistance > 1000.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 1024.0, 1556.0, 1.0, 0.5);		// Generates a proportion from 0.5 to 1.0 depending on distance (from 1024 to 1536 HU)

						damage *= fDmgMod;
						/*if (fDistance > 1500.0 && damage_type & DMG_CRIT != 0) {		// Removes headshot Crits after 1200 HU
							damage_type = (damage_type & ~DMG_CRIT);
							damage /= 3;
						}*/
						

						return Plugin_Changed;
					}
				}
				
				// Spy
				// Revolver
				else if (StrEqual(class, "tf_weapon_revolver")) {
					damage *= 1.125;
				}
				// Enforcer
				if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 460) {
					
					float vecAttackerAng[3], vecVictimAng[3];		// Stores the shooter and victim's facing
					GetClientEyeAngles(attacker, vecAttackerAng);
					GetClientEyeAngles(victim, vecVictimAng);
					NormalizeVector(vecAttackerAng, vecAttackerAng);
					NormalizeVector(vecVictimAng, vecVictimAng);
					
					PrintToChatAll("dotproduct: %f", GetVectorDotProduct(vecAttackerAng, vecVictimAng));
					
					if (GetVectorDotProduct(vecAttackerAng, vecVictimAng) > 0.0 && TF2_IsPlayerInCondition(attacker, TFCond_Disguised)) {		// Are we disguised and behind the victim?
						if (fDistance < 512.0001) {		// Are we close?
							TF2_AddCondition(victim, TFCond_MarkedForDeath, 5.0);
							players[victim].iEnforcer_Mark = attacker;		// Record the person that marks us so we can buff them when we die
							//PrintToChatAll("marker: %i marked %i", players[victim].iEnforcer_Mark, victim);
						}
					}
					return Plugin_Changed;
				}
			}
		}
		else {
			// Soldier
			if (TF2_GetPlayerClass(victim) == TFClass_Soldier) {
				if (damage_type & DMG_BLAST) {
					damage /= 1.2;		// Raise resistance 40% -> 50%
				}
			}
			
			// Pyro
			else if (TF2_GetPlayerClass(victim) == TFClass_Pyro) {
				GetEntityClassname(inflictor, class, sizeof(class));
				if (StrEqual(class, "tf_projectile_pipe"))  {		// Reduce damage taken from pipe reflects
					float vecVictim[3], vecPipe[3];
					GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);
					GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", vecPipe);
					float fDistance = GetVectorDistance(vecPipe, vecVictim, false);
					damage = SimpleSplineRemapValClamped(fDistance, 0.0, 144.0, 45.0, 22.5);	// Pipes do normal damage, plus 25% self damage resistance
				}
				else if (StrEqual(class, "tf_projectile_energy_ball"))  {
					damage = 0.0;
				}
			}
			
			// Heavy
			else if (TF2_GetPlayerClass(victim) == TFClass_Heavy) {
				if (weapon > 0) {
					// HLH self-damage 2x multiplier
					if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 811 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 832) {
						//PrintToChatAll("damage: %f", damage);
						damage *= 9.75;
					}
				}
			}
		}
	}
	
	return Plugin_Changed;
}

Action BuildingDamage (int building, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3]) {
	char class[64];
	
	if (building >= 1 && IsValidEdict(building) && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {
			GetEntityClassname(weapon, class, sizeof(class));
			//int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			int Level = GetEntProp(building, Prop_Send,"m_iUpgradeLevel");
			
			// Scout
			// Bat
			if (StrEqual(class, "tf_weapon_bat")) {
				damage *= 1.1428571;
			}

			// Soldier
			// Shovel
			else if (StrEqual(class, "tf_weapon_shovel")) {
				damage *= 1.230769;
			}
			
			// Pyro
			// Flamethrower
			else if (StrEqual(class, "tf_weapon_flamethrower")) {
				damage = 12.0;
			}

			// Flare Gun
			else if (StrEqual(class, "tf_weapon_flaregun")) {
				damage *= 2.0;
			}
			
			// Heavy
			// Minigun
			if (StrEqual(class, "tf_weapon_minigun")) {
				damage *= 0.222222;
				
				if (Level == 2) {
					damage *= 1.17;
				}
				else if (Level == 3) {
					damage *= 1.25;
				}
			}
			// Huo-Long Heater
			if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 811 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 832) {
				//damage = 60.0;
				damage *= 35.0;
			}
			// Fists
			else if (StrEqual(class, "tf_weapon_fists")) {
				damage *= 1.230769;
			}
			
			// Medic
			// Syringe Gun (bug fix)
			else if (StrEqual(class, "tf_weapon_syringegun_medic")) {
				damage *= 0.5;
			}
			
			// Sniper
			// SMG
			else if (StrEqual(class, "tf_weapon_smg")) {
				damage *= 1.125;
			}
			
			// Spy
			// Revolver
			else if (StrEqual(class, "tf_weapon_revolver")) {
				damage *= 1.125;
			}
		}
	}
	
	return Plugin_Changed;
}


	// -={ Panic Attack passive autoreload }=-

public Action AutoreloadPAPrim(int iClient) {
	
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int iPrimaryIndex = -1;
	if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	char class[64];
	GetEntityClassname(iPrimary, class, sizeof(class));
	
	if (iPrimaryIndex == 1153) {
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		
		int iClipMax = 3;
		
		int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our pistol
		
		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < iClipMax && ammoCount > 0) {
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - 1, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iPrimary, iAmmoTable, clip + 1, 4, true);		// Add loaded ammo
			
			if (clip + 1 < iClipMax) {
				players[iClient].fPAReload = 0.5;
			}
			else {
				EmitSoundToClient(iClient, "weapons/widow_maker_pump_action_back.wav");
			}
		}
	}
	return Plugin_Handled;
}

public Action AutoreloadPA(int iClient) {
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);		// Retrieve the secondary weapon
	int iSecondaryIndex = -1;
	if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
	
	char class[64];
	GetEntityClassname(iSecondary, class, sizeof(class));		// Retrieve the weapon
	
	if (iSecondaryIndex == 1153) {		// If we have a pistol equipped
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		
		int iClipMax = 3;
		
		int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our pistol
		
		int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < iClipMax && ammoCount > 0) {
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - 1, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iSecondary, iAmmoTable, clip + 1, 4, true);		// Add loaded ammo
			
			if (clip + 1 < iClipMax) {
				players[iClient].fPAReload = 0.5;
			}
			else {
				EmitSoundToClient(iClient, "weapons/widow_maker_pump_action_back.wav");
			}
		}
	}
	return Plugin_Handled;
}


	// -={ Sets HLH projectiles to fire from a specific spot, and destroys them on a timer; handles Huntsman hitreg }=-

public void OnEntityCreated(int iEnt, const char[] classname) {
	if (IsValidEdict(iEnt)) {
		if (StrEqual(classname,"obj_sentrygun") || StrEqual(classname,"obj_dispenser") || StrEqual(classname,"obj_teleporter")) {
			//SDKHook(iEnt, SDKHook_SetTransmit, BuildingThink);
			SDKHook(iEnt, SDKHook_OnTakeDamage, BuildingDamage);
		}
		
		if(StrEqual(classname, "tf_projectile_energy_ball")) {
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
			SDKHook(iEnt, SDKHook_SpawnPost, ProjectleSpawn);
		}
		
		else if(StrEqual(classname,"tf_flame_manager")) {
			//SDKHook(iEnt, SDKHook_Touch, FlameTouch);
		}
		
		if(StrEqual(classname,"tf_projectile_flare")) {
			SDKHook(iEnt, SDKHook_SpawnPost, FlareSpawn);
		}
		
		if(StrEqual(classname,"tf_projectile_rocket")) {
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
			SDKHook(iEnt, SDKHook_SpawnPost, FlareSpawn);
		}
		
		/*else if(StrEqual(classname, "tf_projectile_balloffire")) {
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}*/
		
		else if (StrEqual(classname, "tf_projectile_pipe_remote")) {	// Make sticky hitboxes larger
			float maxs[3], mins[3];
			SetEntProp(iEnt, Prop_Send, "m_triggerBloat", 8);
			maxs[0] = 4.0; maxs[1] = 4.0; maxs[2] = 4.0;
			mins[0] = (0.0 - maxs[0]); mins[1] = (0.0 - maxs[1]); mins[2] = (0.0 - maxs[2]);
			SetEntPropVector(iEnt, Prop_Send, "m_vecMaxs", maxs);
			SetEntPropVector(iEnt, Prop_Send, "m_vecMins", mins);
			SDKHook(iEnt, SDKHook_SpawnPost, BombSpawn);
		}
		
		else if(StrEqual(classname, "tf_projectile_syringe")) {
			SDKHook(iEnt, SDKHook_SpawnPost, needleSpawn);
		}

		else if(StrEqual(classname, "tf_projectile_arrow")) {
			SDKHook(iEnt, SDKHook_SpawnPost, HealBoltSpawn);
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}
	}
}

/*MRESReturn DHookCallback_CTFWeaponBase_SecondaryAttack(int entity) {
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Primary, true);
	
	char class[64];
	GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_syringegun_medic")) {	
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");		
		int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve loaded ammo
		
		if (clip == 25) {
			SetEntData(iPrimary, iAmmoTable, 0, 4, true);		// Consume all loaded ammo
			HealSyringeFire(owner, iPrimary);
		}
	}
	return MRES_Ignored;
}*/

Action HealSyringeFire(int iClient, int iPrimary) {
	int iSyringe = CreateEntityByName("tf_projectile_arrow");
	
	if (iSyringe != -1) {
		int team = GetClientTeam(iClient);
		
		float vecAng[3], vecPos[3], vecVel[3], offset[3];
		
		GetClientEyePosition(iClient, vecPos);
		GetClientEyeAngles(iClient, vecAng);
		
		offset[0] = (15.0 * Sine(DegToRad(vecAng[1])));		// We already have the eye angles from the function call
		offset[1] = (-6.0 * Cosine(DegToRad(vecAng[1])));
		offset[2] = -10.0;
		
		vecPos[0] += offset[0];
		vecPos[1] += offset[1];
		vecPos[2] += offset[2];

		if (isKritzed(iClient)) EmitAmbientSound("weapons/crusaders_crossbow_shoot_crit.wav", vecPos, iClient);
		else EmitAmbientSound("weapons/crusaders_crossbow_shoot.wav", vecPos, iClient);
		
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
		//SetEntPropFloat(iSyringe, Prop_Send, "m_flModelScale", 3.0);
		
		DispatchSpawn(iSyringe);
		
		// Calculates forward velocity
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 2400.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 2400.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -2400.0;
		
		// Calculate minor leftward velocity to help us aim better
		float leftVel[3];
		leftVel[0] = -Sine(DegToRad(vecAng[1])) * 0.015;
		leftVel[1] = Cosine(DegToRad(vecAng[1])) * 0.015;
		leftVel[2] = 0.0;  // No change in the vertical direction

		vecVel[0] += leftVel[0];
		vecVel[1] += leftVel[1];

		TeleportEntity(iSyringe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
	
	return Plugin_Handled;
}

Action ProjectileTouch(int iProjectile, int other) {
	char class[64];
	GetEntityClassname(iProjectile, class, sizeof(class));
	
	if (StrEqual(class, "tf_projectile_rocket")) {
		if (other != 0) return Plugin_Handled;		// Detect ground hits
		
		int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");
		float vecRocketPos[3];
		GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecRocketPos);

		for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
			if (!IsValidEntity(iEnt)) continue;
			
			GetEntityClassname(iEnt, class, sizeof(class));
			if (!StrEqual(class, "tf_projectile_pipe_remote")) continue;
			
			int iStickyTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
			if (iStickyTeam == iProjTeam) continue;
			
			float vecStickyPos[3];
			GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecStickyPos);

			float fBlastRadius = 144.0;
			if (GetVectorDistance(vecRocketPos, vecStickyPos) > fBlastRadius) continue;
			
			float fDamage = 90.0;
			fDamage *= SimpleSplineRemapValClamped(GetVectorDistance(vecRocketPos, vecStickyPos), 0.0, fBlastRadius, 1.0, 0.5);
			entities[other].fHealth -= fDamage;
			if (entities[other].fHealth < 0.0) AcceptEntityInput(iEnt, "Kill");
		}
	}

	else if (StrEqual(class, "tf_projectile_energy_ball")) {
		if (other == 0) {		// Detect entity hits
			if (!IsValidClient(other))  return Plugin_Handled;
			
			int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");
			int iEnemyTeam = GetEntProp(other, Prop_Data, "m_iTeamNum");
			if (iProjTeam == iEnemyTeam) return Plugin_Handled;
			
			int owner = GetEntPropEnt(iProjectile, Prop_Send, "m_hOwnerEntity");
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Primary, true);
			
			//PrintToChatAll("Hit");
			if (TF2Util_GetPlayerBurnDuration(other) > 0.0 > 0.0) {
				SDKHooks_TakeDamage(other, iProjectile, owner, 50.0, DMG_IGNITE|DMG_BURN, iPrimary, NULL_VECTOR, NULL_VECTOR, false);
			}
			else {
				SDKHooks_TakeDamage(other, iProjectile, owner, 25.0, DMG_IGNITE|DMG_BURN, iPrimary, NULL_VECTOR, NULL_VECTOR, false);
			}
		}
		
		else {		// Detect ground hits
		
			int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");
			float vecRocketPos[3];
			GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecRocketPos);

			for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
				if (!IsValidEntity(iEnt)) continue;
				
				GetEntityClassname(iEnt, class, sizeof(class));
				if (!StrEqual(class, "tf_projectile_pipe_remote")) continue;
				
				int iStickyTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
				if (iStickyTeam == iProjTeam) continue;
				
				float vecStickyPos[3];
				GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecStickyPos);

				if (GetVectorDistance(vecRocketPos, vecStickyPos) <= 48.2) {
					AcceptEntityInput(iEnt, "Kill");
				}
			}
		}
	}
	
	else if (StrEqual(class, "tf_projectile_arrow")) {
		if (other != 0) {		// If we hit an entity
			//PrintToChatAll("Bolt contact");
		}
	}
	return Plugin_Handled;
}

void ProjectleSpawn(int entity) {
	CreateTimer(0.16, KillProj, entity);		// The projectile will travel ~500 HU in this time
}

Action KillProj(Handle timer, int entity) {
	if(IsValidEdict(entity)) {
		int team = GetEntProp(entity, Prop_Data, "m_iTeamNum");
		if (team == 3) {
			CreateParticle(entity, "drg_cow_explosion_flashup_blue", 1.0 , _, _, _, _, _, _, false, false);
		}
		else if (team == 2) {
			CreateParticle(entity, "drg_cow_explosion_flashup", 1.0 , _, _, _, _, _, _, false, false);
		}
		
		AcceptEntityInput(entity,"KillHierarchy");
	}
	return Plugin_Continue;
}

void BombSpawn(int entity) {
	entities[entity].fHealth = 70.0;
}

Action FlareSpawn(int entity) {
	char class[64];
	int owner;
	GetEntityClassname(entity, class, sizeof(class));
	if (StrEqual(class, "tf_projectile_rocket")) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if (TF2_GetPlayerClass(owner) == TFClass_Heavy) {
			
			/*if (players[owner].fFlare_Cooldown > 0.0) {		// If we shouldn't be allowed to fire yet...
				AcceptEntityInput(entity, "KillHierarchy");		// Instantly delete the flare
				
				return Plugin_Handled;
			}*/
			
			float vecPos[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecPos);
			
			EmitSoundToClient(owner, "weapons/flare_detonator_explode.wav");
			//RequestFrame(FlareVel, entity);		// It doesn't like it when we try to modify velocity on this frame, so we do it on the next one
			
			vecPos[2] -= 10.0;		// Make the flare appear 20 HU down so it's fired out of the gun rather than the Heavy's face
			float vel[3];
			GetEntPropVector(entity, Prop_Data, "m_vecVelocity", vel);
			vel[2] += 800.0;

			TeleportEntity(entity, vecPos, NULL_VECTOR, vel);
			players[owner].fFlare_Cooldown = 0.5;
			
			int primary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Primary, true);
			SetEntPropEnt(entity, Prop_Send, "m_hLauncher", primary);

			CreateTimer(0.6, KillFlare, entity);		// The projectile will travel about 1000 HU in this time
			
			if (0.5 > GetEntPropFloat(primary, Prop_Data, "m_flNextPrimaryAttack")) {		// If our next attack would be before the intended firing interval of the weapon, cancel it; prevents tapfire exploit
				SetEntPropFloat(primary, Prop_Data, "m_flNextPrimaryAttack", 0.5);
			}
			
			int CreatedEntityRef = EntIndexToEntRef(entity);
			
			AttrPackDrop[FreeDataPack] = new DataPack();
			WritePackCell(AttrPackDrop[FreeDataPack], CreatedEntityRef);
			//WritePackCell(AttrPackDrop[FreeDataPack], RocketLaunchValue);
			//WritePackCell(AttrPackDrop[FreeDataPack], RocketDropValue);
			WritePackCell(AttrPackDrop[FreeDataPack], 2.50);
			WritePackCell(AttrPackDrop[FreeDataPack], 1.00);
			// Store the created entity reference associated with the data pack
			DataPackEntRefNumber[FreeDataPack] = CreatedEntityRef;

			// The game doesn't like it when we execute the function immediately, presumably the velocity stuff doesn't start until the next frame?
			//RequestFrame(RocketLaunch, AttrPackDrop[FreeDataPack]);
		}
	}
	
	return Plugin_Continue;
}

public void RocketLaunch(DataPack AttrEntPack)
{
	// You normally don't need to do this when the DataPack has just been created, but it doesn't hurt to have this here and it saves me doing something stupid down the line
	ResetPack(AttrEntPack);
	int RocketEnt = EntRefToEntIndex(ReadPackCell(AttrEntPack));
	int RocketLaunchValue = ReadPackCell(AttrEntPack);
	int RocketDropValue = ReadPackCell(AttrEntPack);
	if (IsValidEntity(RocketEnt))
	{
		float RocketAngle[3];
		float RocketVelocity[3];

		GetEntPropVector(RocketEnt, Prop_Data, "m_angRotation", RocketAngle);
		GetEntPropVector(RocketEnt, Prop_Data, "m_vecAbsVelocity", RocketVelocity);

		RocketVelocity[2] = RocketVelocity[2] + (RocketLaunchValue);
		
		GetVectorAngles(RocketVelocity, RocketAngle);
		TeleportEntity(RocketEnt, NULL_VECTOR, RocketAngle, RocketVelocity);
	}
	else
	{
		// If the rocket somehow has disappeared off the face of the earth before we were even able to calculate drop, kill the data pack, otherwise memory leaks go brrrrrr
		CloseHandle(AttrEntPack);
	}
	if (RocketDropValue != 0)
	{
		// Creates a timer for the next frame, supposedly this is a lot more reliable and consistent compared to RequestFrame, which previous code iterations used.
		float FrameTimeLength = GetGameFrameTime();
		CreateTimer(FrameTimeLength, RocketDrop, AttrEntPack);
	}
}

public Action RocketDrop(Handle timer, DataPack AttrEntPack)
{
	ResetPack(AttrEntPack);
	int RocketEnt = EntRefToEntIndex(ReadPackCell(AttrEntPack));
	ReadPackCell(AttrEntPack);
	int RocketDropValue = ReadPackCell(AttrEntPack);
	if (IsValidEntity(RocketEnt))
	{
		float RocketAngle[3];
		float RocketVelocity[3];

		GetEntPropVector(RocketEnt, Prop_Data, "m_angRotation", RocketAngle);
		GetEntPropVector(RocketEnt, Prop_Data, "m_vecAbsVelocity", RocketVelocity);

		RocketVelocity[2] = RocketVelocity[2] - (RocketDropValue / 10);

		GetVectorAngles(RocketVelocity, RocketAngle);
		TeleportEntity(RocketEnt, NULL_VECTOR, RocketAngle, RocketVelocity);

		float FrameTimeLength = GetGameFrameTime();
		CreateTimer(FrameTimeLength, RocketDrop, AttrEntPack);
	}
	else
	{
		CloseHandle(AttrEntPack);
	}
	return Plugin_Continue;
}

/*void FlareVel(int entity) {
	float vecVel[3]; 
	GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vecVel);		// Gets flare velocity
	
	vecVel[2] += 80.0;

	TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, vecVel);
}*/

Action KillFlare(Handle timer, int flare) {
	if(IsValidEdict(flare)) {
		CreateParticle(flare, "arm_muzzleflash_flare", 0.15, _, _, _, _, _, 10.0);		// Displays particle on natural flare death (0.15 s duration, 10 HU size)
		AcceptEntityInput(flare, "KillHierarchy");
	}
	return Plugin_Continue;
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
		case 17, 204, 36, 412: {
			int owner = GetEntPropEnt(Syringe, Prop_Send, "m_hOwnerEntity");
			if (IsValidClient(owner)) {
				if (other != owner && other >= 1 && other <= MaxClients) {
					TFTeam team = TF2_GetClientTeam(other);
					if (TF2_GetClientTeam(owner) != team) {		// Hitting enemies
					
						int damage_type = DMG_BULLET | DMG_USE_HITLOCATIONS;
						SDKHooks_TakeDamage(other, owner, owner, 1.0, damage_type, weapon,_,_, false);		// Do this to ensure we get hit markers
					}
				}
			}
			else if (other == 0) {		// Impact world
				CreateParticle(Syringe, "impact_metal", 1.0,_,_,_,_,_,_,false);
			}
		}
	}
	return Plugin_Continue;
}


void HealBoltSpawn(int entity) {
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
	
	SDKHook(entity, SDKHook_StartTouch, HealBoltTouch);
}

Action HealBoltTouch(int Syringe, int other) {
	int weapon = GetEntPropEnt(Syringe, Prop_Send, "m_hLauncher");
	int wepIndex = -1;
	if (weapon != -1) wepIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	switch(wepIndex) {
		case 17, 204, 36, 412: {
			int owner = GetEntPropEnt(Syringe, Prop_Send, "m_hOwnerEntity");
			if (IsValidClient(owner)) {
				if (other != owner && other >= 1 && other <= MaxClients) {
					TFTeam team = TF2_GetClientTeam(other);
					if (TF2_GetClientTeam(owner) != team) {		// Hitting enemies
					
						int damage_type = DMG_BULLET | DMG_USE_HITLOCATIONS;
						SDKHooks_TakeDamage(other, owner, owner, 20.0, damage_type, weapon,_,_, false);		// Do this to ensure we get hit markers
					}
					else {		// Hitting teammates
						//PrintToChatAll("Contact");
						int iHealth = GetEntProp(other, Prop_Send, "m_iHealth");
						int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, other);
						if (iHealth < iMaxHealth) {		// If the teammate is below max health
							
							float vecVictim[3], vecPos[3];
							GetClientEyePosition(owner, vecPos);		// Gets shooter position
							GetEntPropVector(other, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
							float fDistance = GetVectorDistance(vecPos, vecVictim, false);		// Distance calculation
							
							float healing = RemapValClamped(fDistance, 0.0, 1024.0, 25.0, 50.0);
						
							if (iHealth > iMaxHealth - healing) {		// Heal us to full
								SetEntProp(other, Prop_Send, "m_iHealth", iMaxHealth);
							} 
							else {
								TF2Util_TakeHealth(other, healing);
							}
							
							// Apply regen buff
							players[other].fRegenTimer = 2.0;

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
			}
			else if (other == 0) {		// Impact world
				CreateParticle(Syringe, "impact_metal", 1.0,_,_,_,_,_,_,false);
			}
		}
	}
	return Plugin_Continue;
}

Action OnSoundNormal(int clients[MAXPLAYERS], int& clients_num, char sample[PLATFORM_MAX_PATH], int& entity, int& channel,float& volume, int& level, int& pitch, int& flags, char soundentry[PLATFORM_MAX_PATH], int& seed) {
	if (StrContains(sample, "player/weapons/dragon_gun_motor_loop") == 0) return Plugin_Stop;
	return Plugin_Continue;
}



	// ==={{ Do not touch anything below this point }}===
	
	// -={ Displays particles (taken from ShSilver) }=-

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


	// -={ Identifies sources of (Mini-)Crits (taken from ShSilver) }=-

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
	if(victim!=-1)
	{
		if (TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeathSilent))
			result = true;
	}
	if (TF2_IsPlayerInCondition(client,TFCond_CritMmmph) || TF2_IsPlayerInCondition(client,TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(client,TFCond_Buffed) || TF2_IsPlayerInCondition(client,TFCond_CritCola))
		result = true;
	return result;
}


stock bool IsValidClient(int iClient) {
	if (iClient <= 0 || iClient > MaxClients) return false;
	if (!IsClientInGame(iClient)) return false;
	return true;
}


	// -={ Handles data filtering when performing traces (taken from Bakugo) }=-

bool TraceFilter_ExcludeSingle(int entity, int contentsmask, any data) {
	return (entity != data);
}

bool PlayerTraceFilter(int entity, int contentsMask, any data)
{
	if(entity == data)
		return (false);
	if(IsValidClient(entity))
		return (false);
	return (true);
}

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