#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
//#include <tf2items>
#include <tf2utils>
#include <tf2attributes>

#pragma newdecls required

public Plugin myinfo =
{
	name = "Czin's Team Synergy 2 Balancemod",
	author = "Ech0",
	description = "Contains weapon rebalances from Czin's document",
	version = "2.0.8",
	url = ""
};


	// ==={{ Initialisation and stuff }}==

enum struct Player {
	// Multi-class
	float fTHREAT;		// THREAT
	float fTHREAT_Timer;	// Timer for when our THREAT should start decreasing
	float fHeal_Penalty;		// Tracks how long after taking damage we restore our incoming healing to normal
	float fHeal_Penalty_Timer;		// Tracks how much damage we take so the heal penalty can be applied
	float fAfterburn;		// Tracks Afterburn max health debuff
	float fAfterburn_DMG_tick;	// Imposes a 1.0 sec cooldown on taking damage from Afterburn
	float fPA_Accuracy;		// Tracks the Panic Attack's accuracy
	float fTempLevel;		// Tracks damage taken from the Huo-Long Heater
	float fBaseball_Debuff_Timer;	// Tracks Sandman debuff
	float fShocked;	// Tracks Neon Annihilator debuff
	int iEquipped;		// Tracks the equipped weapon's index in order to determine when it changes
	int iMilk_Cooldown;		// Blocks repeated healing ticks from Mad Milk
	int iJarated;		// Tracks the ID of the person who Jarates us so we can give them our TRHEAT
	int iLastButtons;		// Tracks the buttons we had held down last frame
	bool bMilk_Wetness;		// Stores whether or not we're sill supposed to be wet after recieving healing from Milk
	
	// Scout
	float fAirjump;		// Tracks damage taken while airborne
	bool bCac;		// Tracks status of the Crit-a-Cola buff
	bool bBonk;		// Tracks status of the Bonk buff
	float fCleaver;	// Tracks recharge state of the Flying Guillotine
	
	// Soldier
	bool bSlam;		// Stores whether we're in the slam state
	int iBazooka_Ammo;		// Tracks ammo loaded into the Bazooka so that in conjunction with the below variable, we can detect frames where we load in a rocket
	int iBazooka_Clip;		// Tracks how many rockets are loaded into our Bazooka so we can store this in the rockets and modify their blast radius at the time of impact
	float fBazooka_Load_Timer;	// Counts down after we load the Bazooka so that the entire barrage is properly given the correct amount of blast radius reduction
	float fBuff_Banner;		// Timer on the Buff Banner effect
	float fMantreads_OOC_Timer;		// Tracks how long we've been out of combat for deciding when to apply the Mantreads speed buff
	
	// Pyro
	int iAmmo;	// Tracks ammo for the purpose of making the hitscan beam
	float fAxe_Cooldown;		// Axtinguisher cooldown
	
	// Demoman
	bool bCharge_Crit_Prepped;		// Stores when we're ready to deal a charge Mini-Crit
	bool bIsDemoknight;		// Stores if we are a full Demoknight (excluding Tide Turner) for the purposes of slowing THREAT decay

	// Heavy
	float fRev;		// Tracks how long we've been revved for the purposes of undoing the L&W nerf
	float fSpeed;		// Tracks how long we've been firing for the purposes of modifying Heavy's speed and reverting the JI buff
	float fLunchbox_Cooldown;		// Track our lunchbox cooldown so we can revert any gains from healthpack pickups
	float fTomislavDrainDelay;		// Tracks how long until we drain a unit of ammo from the Tomislav while revved
	bool bSteak_Buff;		// Tracks the Buffalo Steak buff
	
	// Engineer
	bool bMini;		// Stores whether we've swapped to the Mini-Sentry PDA
	bool bSentryBuilt;		// Stores whether or not we already have a Sentry, built to help us interpret EventObjectBuilt
	
	// Medic
	int iSyringe_Ammo;		// Tracks loaded syringes for the purposes of determining when we fire a shot
	//float fAmputator_heal_tick_timer;	// Tracks how long until a heal instance during the Amputator's taunt
	
	// Sniper
	int iHeadshot_Frame;		// Identifies frames where we land a headshot
	int iHeads;		// Tracks heads on the Shahanshah
	float fFocus_Timer;	// Tracks Focus duration on the Heatmaker so we can display a timer on the HUD
	float fHealth_Regen_Timer;	// Tracks time between health regen ticks
	
	// Spy
	float fHitscan_Accuracy;		// Tracks dynamic accuracy on the revolver
	float fDamage_Recieved_Enforcer;		// Tracks damage we recieve with the Enforcer equipped that counts towards breaking our cloak or disguise
	float fYER_Disguise_Remove_Timer;		// Tracks how long we have Spy sprint active with the YER out
	float fYER_Cooldown;		// Explosion YER cooldown
	int iHitscan_Ammo;			// Tracks ammo change on the revolver so we can determine when a shot is fired (for the purposes of dynamic accuracy)
	float fCloak_Timer;			// Tracks how long we've been cloaked (so we can disable cloak drain during the cloaking animation)
}

enum struct Entity {
	// Rockets
	int iBazooka_Clip;		// Stores how much to reduce our blast radius by, as determined by the number of rockets in our barrage
	
	// Stickies
	bool bTrap;		// Stores whether a sticky has existed long enough to become a trap
	float fHealth;		// Tracks the health of Demo's bombs
	
	// Buildings
	float fConstruction_Health;		// Tracks the amount of health a building is *supposed* to have during its construction animation
	int iDispMetal;	// Stores the Metal in our Dispenser
}

int frame;		// Tracks frames


Player players[MAXPLAYERS+1];
Entity entities[2048];

float g_buildingHeal[2048];

//Handle g_hSDKFinishBuilding;
Handle g_SDKCallWeaponSwitch;
Handle g_detour_CalculateMaxSpeed;
Handle dhook_CTFWeaponBase_SecondaryAttack;
//Handle g_hCanHolster;
//Handle g_SDKCallMinigunWindDown;

DynamicHook g_hDHookItemIterateAttribute;
int g_iCEconItem_m_Item;
int g_iCEconItemView_m_bOnlyIterateItemViewAttributes;

Handle cvar_ref_tf_boost_drain_time;
Handle cvar_ref_tf_use_fixed_weaponspreads;
Handle cvar_ref_tf_fall_damage_disablespread;
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

Handle cvar_tf_parachute_maxspeed_xy;
Handle cvar_tf_parachute_maxspeed_onfire_z;
Handle cvar_tf_parachute_aircontrol;


public void OnPluginStart() {
    // =========================
    // ConVars
    // =========================

	cvar_ref_tf_boost_drain_time = FindConVar("tf_boost_drain_time");
	cvar_ref_tf_use_fixed_weaponspreads = FindConVar("tf_use_fixed_weaponspreads");
	cvar_ref_tf_fall_damage_disablespread = FindConVar("tf_fall_damage_disablespread");
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

	cvar_tf_parachute_maxspeed_xy = FindConVar("tf_parachute_maxspeed_xy");
	cvar_tf_parachute_maxspeed_onfire_z = FindConVar("tf_parachute_maxspeed_onfire_z");
	cvar_tf_parachute_aircontrol = FindConVar("tf_parachute_aircontrol");

	SetConVarString(cvar_ref_tf_boost_drain_time, "5.0");
	SetConVarString(cvar_ref_tf_use_fixed_weaponspreads, "0");
	SetConVarString(cvar_ref_tf_fall_damage_disablespread, "1");
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

	SetConVarString(cvar_tf_parachute_maxspeed_xy, "400.0");
	SetConVarString(cvar_tf_parachute_maxspeed_onfire_z, "-50.0");
	SetConVarString(cvar_tf_parachute_aircontrol, "0.5");

    // =========================
    // Commands + Events
    // =========================

    RegConsoleCmd("pda", Command_PDA, "Sile's Team Synergy 2 Mini-mod - Swap between regular and Mini-Sentry");

    HookEvent("player_spawn", OnGameEvent, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_healed", OnPlayerHealed);
    HookEvent("post_inventory_application", OnGameEvent, EventHookMode_Post);
    HookEvent("item_pickup", OnGameEvent, EventHookMode_Post);
    HookEvent("player_jarated", OnGameEvent, EventHookMode_Post);
    HookEvent("player_builtobject", EventObjectBuilt);
    HookEvent("object_destroyed", EventObjectDestroy);
    HookEvent("object_detonated", EventObjectDetonate);

    // =========================
    // Load Gamedata
    // =========================

    GameData gamedata = new GameData("Ech0");
    if (!gamedata) {
        SetFailState("Failed to load gamedata: Ech0");
    }

    // =========================
    // CEconItemView::IterateAttributes hook
    // =========================

    int iOffset = gamedata.GetOffset("CEconItemView::IterateAttributes");

    if (iOffset == -1) {
        SetFailState("Offset CEconItemView::IterateAttributes not found!");
    }

    g_hDHookItemIterateAttribute = new DynamicHook(
        iOffset,
        HookType_Raw,
        ReturnType_Void,
        ThisPointer_Address
    );

    if (!g_hDHookItemIterateAttribute) {
        SetFailState("Failed to create DynamicHook for IterateAttributes");
    }

    g_hDHookItemIterateAttribute.AddParam(HookParamType_ObjectPtr);

    // =========================
    // SendProp Offsets
    // =========================

    g_iCEconItem_m_Item = FindSendPropInfo("CEconEntity", "m_Item");

    FindSendPropInfo(
        "CEconEntity",
        "m_bOnlyIterateItemViewAttributes",
        _,
        _,
        g_iCEconItemView_m_bOnlyIterateItemViewAttributes
    );

    // =========================
    // Detours
    // =========================

    g_detour_CalculateMaxSpeed =
        DHookCreateFromConf(gamedata, "CTFPlayer::TeamFortress_CalculateMaxSpeed");

    if (!g_detour_CalculateMaxSpeed) {
        SetFailState("Failed to create detour for CalculateMaxSpeed");
    }

    if (!DHookEnableDetour(g_detour_CalculateMaxSpeed, false, Detour_CalculateMaxSpeed)) {
        SetFailState("Failed to enable CalculateMaxSpeed detour");
    }

    dhook_CTFWeaponBase_SecondaryAttack =
        DHookCreateFromConf(gamedata, "CTFWeaponBase::SecondaryAttack");

    if (!dhook_CTFWeaponBase_SecondaryAttack) {
        SetFailState("Failed to create SecondaryAttack detour");
    }
	
	/*g_hCanHolster =
		DHookCreateFromConf(gamedata, "CTFMinigun::CanHolster");
		
	if (!g_hCanHolster) {
        SetFailState("Failed to create detour for CanHolster");
    }
	
	if (!DHookEnableDetour(g_hCanHolster, false, Detour_CanHolster)) {
        SetFailState("Failed to enable CanHolster detour");
    }
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Signature, "CTFMinigun::WindDown()");
	g_SDKCallMinigunWindDown = EndPrepSDKCall();*/

    delete gamedata;
}



Action Command_PDA(int iClient, int args) {
	if (iClient > 0) {
		if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
			if (players[iClient].bMini == true) {
				// Disable
				//int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
				//int meleeIndex = -1;
				//if(iMelee != -1) meleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
				TF2Attrib_AddCustomPlayerAttribute(iClient, "engineer sentry build rate multiplier", 0.5);
				players[iClient].bMini = false;
			}
			else {
				// Enable
				//int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
				//int meleeIndex = -1;
				//if(iMelee != -1) meleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
				TF2Attrib_AddCustomPlayerAttribute(iClient, "engineer sentry build rate multiplier", 2.5);
				players[iClient].bMini = true;
			}
		}
	}
	
	return Plugin_Handled;
}


public MRESReturn Detour_CalculateMaxSpeed(int self, Handle ret, Handle params) {
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(self, TFWeaponSlot_Secondary, true);
	int iSecondaryIndex = -1;
	if (iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
	
	if (iSecondaryIndex != 411) {		// Keep enabled for Quick-Fix
		if (DHookGetParam(params, 1)) {		// Medic speed matching activation is stored in a Boolean; this code always switches it to false
			DHookSetReturn(ret, 0.0);
			return MRES_Override;
		}
	}

    return MRES_Ignored;
}

/*public MRESReturn Detour_CanHolster(int pThis, Handle ret) {
    //if (!IsValidEntity(pThis)) return MRES_Ignored;
	
    DHookSetReturn(ret, true);
    return MRES_Supercede;
}*/


public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	SDKHook(iClient, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
	SDKHook(iClient, SDKHook_WeaponSwitch, WeaponSwitch);
	SDKHook(iClient, SDKHook_WeaponCanSwitchTo, OnClientWeaponCanSwitchTo);
	SDKHook(iClient, SDKHook_TraceAttack, TraceAttack);
}

public void OnMapStart() {
	PrecacheSound("weapons/explode2.wav", true);
	PrecacheSound("player/recharged.wav", true);
	PrecacheSound("weapons/dispenser_heal.wav", true);
	PrecacheSound("weapons/jar_explode.wav", true);
	PrecacheSound("weapons/pipe_bomb1.wav", true);
	PrecacheSound("weapons/syringegun_shoot.wav", true);
	PrecacheSound("weapons/syringegun_shoot_crit.wav", true);
	PrecacheSound("weapons/drg_pomson_drain_01.wav", true);
	
	PrecacheModel("models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl",true);
	PrecacheModel("models/weapons/w_models/w_syringe_proj.mdl",true);
}

	// -={ Resets variables on death }=-

Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {	
	if (StrEqual(name, "player_spawn")) {
		int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsPlayerAlive(iClient)) {
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int iMeleeIndex = -1;
			if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			players[iClient].fTHREAT = 0.0;
			players[iClient].fTHREAT_Timer = 0.0;
			players[iClient].fHeal_Penalty = -10.0;
			players[iClient].fAfterburn = 0.0;
			
			players[iClient].iAmmo = 0;
			
			players[iClient].iSyringe_Ammo = 0;
			
			players[iClient].iHeadshot_Frame = 0;
			
			players[iClient].fHitscan_Accuracy = 0.0;
			players[iClient].iHitscan_Ammo = 0;
			players[iClient].fCloak_Timer = 0.0;
			
			// Prevents incorrect ammo distrubition when swapping from one Pistol-wielder to the other
			// Handles buggy Shortstop reserves on spawn
			if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
				char class[64];
				
				GetEntityClassname(iPrimary, class, sizeof(class));
				if (StrEqual(class, "tf_weapon_handgun_scout_primary")) {		// Shortstop
					int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 24, _, iPrimaryAmmo);
				}
				
				GetEntityClassname(iSecondary, class, sizeof(class));
				if (StrEqual(class, "tf_weapon_pistol") || StrEqual(class, "tf_weapon_pistol_scout")) {
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, iSecondaryAmmo);
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 1.0);	
				}
			}

			else if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
				char class[64];
				GetEntityClassname(iSecondary, class, sizeof(class));	
				if (StrEqual(class, "tf_weapon_pistol")) {
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, iSecondaryAmmo);
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.18);
				}
			}
			
			// Syncs Demo's ammo count between launchers
			else if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
				int AmmoOffset = 0, ClipOffset = 0;
				if (iSecondary > 0) {
					if (iSecondaryIndex == 265) {		// Sticky Jumper
						AmmoOffset += 6;
					}
					if (iSecondaryIndex == 131 || iSecondaryIndex == 406 || iSecondaryIndex == 1144 || iSecondaryIndex == 1099) {	// Shields
						AmmoOffset -= 8;
					}
				}
				if (iMelee > 0) {
					if (iMeleeIndex == 404) {		// Persian Persuader
						AmmoOffset = -18;		// Ignore everything else and lower reserves to 6
					}
				}
				
				if (iPrimary > 0) {
					if (iPrimaryIndex == 308) {		// Loch-n-Load
						ClipOffset -= 2;
					}
				}
				if (iSecondary > 0) {
					if (iSecondaryIndex == 131 || iSecondaryIndex == 406 || iSecondaryIndex == 1144 || iSecondaryIndex == 1099 || iSecondaryIndex == 265) {		// Sticky Jumper, Shields
						ClipOffset = RoundToFloor((-6 + ClipOffset) * 0.33);
					}
				}
				
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				
				if (iPrimaryIndex != 1101 && iPrimaryIndex != 405 && iPrimaryIndex != 608) {		// Make sure we actually have a launcher in this slot
					int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");		// Reserve ammo
					SetEntData(iPrimary, iAmmoTable, 6 + ClipOffset, 4, true);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 24 + AmmoOffset, _, iPrimaryAmmo);
					TF2Attrib_SetByName(iPrimary, "clip size penalty HIDDEN", (6.0 + ClipOffset) / 4.0);		// Clip size
					TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", (24.0 + AmmoOffset) / 16.0);		// Reserves
				}
				if (iSecondaryIndex != 131 && iSecondaryIndex != 406 && iSecondaryIndex != 1099 && iSecondaryIndex != 1144) {
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntData(iSecondary, iAmmoTable, 6 + ClipOffset, 4, true);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 24 + AmmoOffset, _, iSecondaryAmmo);
					TF2Attrib_SetByName(iSecondary, "clip size penalty HIDDEN", (6.0 + ClipOffset) / 8.0);
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", (24.0 + AmmoOffset) / 24.0);
				}
			}
			
			// Apply increased melee range to swords when boots are equipped
			if (iSecondaryIndex == 444 || iPrimaryIndex == 405 || iPrimaryIndex == 608) {
				char class[64];
				GetEntityClassname(iMelee, class, 64);
				if (StrEqual(class,"tf_weapon_katana") || StrEqual(class, "tf_weapon_sword")) {
					TF2Attrib_SetByDefIndex(iMelee, 264, 1.6);		// melee range multiplier (increased to 72 HU)
				}
			}
			else {
				TF2Attrib_SetByDefIndex(iMelee, 264, 1.0);
			}
			
			// Fix for Bushwacka range
			if (iMeleeIndex == 232) {
				TF2Attrib_SetByDefIndex(iMelee, 264, 1.6);
			}
		}
	}
	
	else if (StrEqual(name, "post_inventory_application")) {
		int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(iClient)) {
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			//int iMeleeIndex = -1;
			//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSapper = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Building, true);
			
			// Modify our weapon attributes
			AttributeChanges(iClient, iPrimary, iSecondary, iMelee, iSapper);
			
			// Reset variables and trigger on-spawn effects
			players[iClient].fAfterburn = 0.0;		// Restore health lost from Afterburn
			int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
			SetEntProp(iClient, Prop_Send, "m_iHealth", iMaxHealth);
			
			if (iPrimaryIndex == 441) {		// Cow Mangler
				SetEntPropFloat(iPrimary, Prop_Send, "m_flEnergy", 25.0);		// Fill energy
			}
			if (iSecondaryIndex == 444) {		// Mantreads
				players[iClient].fMantreads_OOC_Timer = 5.0;
			}
			
			if (TF2_GetPlayerClass(iClient) == TFClass_Pyro) {
				players[iClient].fAxe_Cooldown = 20.0;
			}
			
			if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
				players[iClient].fYER_Cooldown = 20.0;
			}
		}
	}
	
	else if (StrEqual(name, "item_pickup")) {
		int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(iClient)) {
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			//int iSecondaryIndex = -1;
			//if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int iMeleeIndex = -1;
			if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
		
			char class[64];
			GetEventString(event, "item", class, sizeof(class));
			
			//PrintToChatAll("We've picked something up! It's a %s", class);
			
			if (StrContains(class, "healthkit_medium") == 0) {
				//PrintToChatAll("Medium");
			}
			
			if (iMeleeIndex == 38 || iMeleeIndex == 457 || iMeleeIndex == 1000) {		// Axtinguisher
				if (StrContains(class, "ammopack_medium") == 0 || StrContains(class, "ammopack_small") == 0 || StrContains(class, "tf_ammo_pack") == 0) {
					players[iClient].fAxe_Cooldown += 10.0;
				}
				else if (StrContains(class, "ammopack_full") == 0) {
					players[iClient].fAxe_Cooldown = 20.0;
				}
			}
			
			if (iMeleeIndex == 225 || iMeleeIndex == 574) {		// Your Eternal Reward
				if (StrContains(class, "ammopack_medium") == 0 || StrContains(class, "ammopack_small") == 0 || StrContains(class, "tf_ammo_pack") == 0) {
					players[iClient].fAxe_Cooldown += 10.0;
				}
				else if (StrContains(class, "ammopack_full") == 0) {
					players[iClient].fAxe_Cooldown = 20.0;
				}
			}
			
			if (StrContains(class, "healthkit_small") == 0) {
				if (TF2_IsPlayerInCondition(iClient, TFCond_Bleeding)) {
					
				}
				else if (iMeleeIndex == 326) {		// Double the extra healing for Back Scratcher
					int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
					int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
					int newHealth = RoundFloat(iHealth + iMaxHealth * 0.1);
					if (newHealth > iMaxHealth) {
						newHealth = iMaxHealth;
					}
					SetEntProp(iClient, Prop_Send, "m_iHealth", newHealth);
					//CreateTimer(0.4, HealPopup, iClient, newHealth);
				}
				else {
					int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
					int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
					int newHealth = RoundFloat(iHealth + iMaxHealth * 0.05);
					if (newHealth > iMaxHealth) {
						newHealth = iMaxHealth;
					}
					SetEntProp(iClient, Prop_Send, "m_iHealth", newHealth);
					//CreateTimer(0.4, HealPopup, iClient, newHealth);
				}
				
			}
			else if (StrContains(class, "ammopack_small") == 0) {
				if (IsValidClient(iClient)) {
				
					if (iPrimary != -1) {
						int PrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
						int PrimaryAmmoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, PrimaryAmmo);
						
						GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
						// Scatterguns (excluding Back Scatter)
						if (StrEqual(class, "tf_weapon_scattergun") && iPrimaryIndex != 1103) {
							if (PrimaryAmmoCount < 14) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 6, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 20, _, PrimaryAmmo);
							}
						}
						// Back Scatter
						else if (iPrimaryIndex == 1103) {
							if (PrimaryAmmoCount < 7) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 3, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 10, _, PrimaryAmmo);
							}
						}
						// Flamethrowers, Syringe Guns (excluding Blutsauger)
						else if (StrEqual(class, "tf_weapon_flamethrower") || (StrEqual(class, "tf_weapon_syringegun_medic") && iPrimaryIndex != 36)) {
							if (PrimaryAmmoCount < 140) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 60, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 200, _, PrimaryAmmo);
							}
						}
						// Miniguns
						else if (StrEqual(class, "tf_weapon_minigun")) {
							if (PrimaryAmmoCount < 115) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 35, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 150, _, PrimaryAmmo);
							}
						}
						// Grenade Launchers
						else if (StrEqual(class, "tf_weapon_grenadelauncher")) {
							if (PrimaryAmmoCount < 17) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 7, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 24, _, PrimaryAmmo);
							}
						}
						// Engie Shotgun
						else if (StrEqual(class, "tf_weapon_shotgun_primary")) {
							if (PrimaryAmmoCount < 26) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", PrimaryAmmoCount + 10, _, PrimaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, PrimaryAmmo);
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
							if (SecondaryAmmoCount < 26) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 10, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, SecondaryAmmo);
							}
						}
						// Sticky Launchers
						else if (StrEqual(class, "tf_weapon_pipebomblauncher")) {
							if (SecondaryAmmoCount < 17) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 7, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 24, _, SecondaryAmmo);
							}
						}
						// Shotguns
						else if (StrEqual(class, "tf_weapon_shotgun") || StrEqual(class, "tf_weapon_shotgun_hwg") || StrEqual(class, "tf_weapon_shotgun_pyro") || StrEqual(class, "tf_weapon_shotgun_soldier")) {
							if (SecondaryAmmoCount < 26) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 10, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 36, _, SecondaryAmmo);
							}
						}
						// SMG
						else if (StrEqual(class, "tf_weapon_smg")) {
							if (SecondaryAmmoCount < 52) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 23, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 75, _, SecondaryAmmo);
							}
						}
						// Revolver
						else if (StrEqual(class, "tf_weapon_revolver")) {
							if (SecondaryAmmoCount < 13) {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", SecondaryAmmoCount + 5, _, SecondaryAmmo);
							}
							else {
								SetEntProp(iClient, Prop_Data, "m_iAmmo", 18, _, SecondaryAmmo);
							}
						}
					}

					// Metal
					int iMetal = GetEntData(iClient, FindDataMapInfo(iClient, "m_iAmmo") + (3 * 4), 4);
					if (iMetal < 140) {
						SetEntData(iClient, FindDataMapInfo(iClient, "m_iAmmo") + (3 * 4), iMetal + 50, 4);
					}
					else {
						SetEntData(iClient, FindDataMapInfo(iClient, "m_iAmmo") + (3 * 4), 200, 4);
					}
					
					// Cloak
					float fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
					SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak + 30.0);	// This number is out of 100
				}
			}
		}
	}
	else if (StrEqual(name, "player_jarated")) {
		int iAttacker = GetClientOfUserId(GetEventInt(event, "thrower_entindex"));
		int iVictim = GetClientOfUserId(GetEventInt(event, "victim_entindex"));
		players[iVictim].iJarated = iAttacker;		// Record the ID of the person that Jarates us
	}
	return Plugin_Continue;
}

public Action AttributeChanges(int iClient, int iPrimary, int iSecondary, int iMelee, int iSapper) {
	int iPrimaryIndex = -1;
	if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

	int iSecondaryIndex = -1;
	if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

	int iMeleeIndex = -1;
	if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	int iSapperIndex = -1;
	if(iSapper > 0) iSapperIndex = GetEntProp(iSapper, Prop_Send, "m_iItemDefinitionIndex");
	
	TF2Attrib_RemoveByName(iClient, "hidden primary max ammo bonus");
	TF2Attrib_RemoveByName(iClient, "hidden secondary max ammo penalty");
	TF2Attrib_RemoveByName(iClient, "move speed bonus");
	TF2Attrib_RemoveByName(iClient, "fire rate bonus");
	TF2Attrib_RemoveByName(iClient, "fire rate penalty");
	TF2Attrib_RemoveByName(iClient, "clip size bonus");
	if(iPrimary > 0) {
		TF2Attrib_RemoveByName(iPrimary, "weapon spread bonus");
		TF2Attrib_RemoveByName(iClient, "hidden primary max ammo bonus");
	}
	
	switch (TF2_GetPlayerClass(iClient)) {
		
		// Scout
		case TFClass_Scout: {
			TF2Attrib_SetByName(iClient, "hidden primary max ammo bonus", 0.625); // reduced to 20
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 20, _, primaryAmmo);
			TF2Attrib_SetByName(iClient, "increase player capture value", -1.0);
			int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
		
			switch (iPrimaryIndex) {
				case 1103: {	// Back Scatter v3
					TF2Attrib_SetByName(iPrimary, "maxammo primary reduced", 0.5); // 10 shells
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 10, _, primaryAmmo);
					TF2Attrib_SetByName(iPrimary, "clip size bonus", 1.67); // also 10 shells
					TF2Attrib_SetByName(iPrimary, "spread penalty", 1.2);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 10);
				}
				case 772: {	// Baby Face's Blaster v1
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.67);
				}
				case 45, 1078: {	// Force-A-Nature
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.33);
					TF2Attrib_SetByName(iPrimary, "fire rate bonus", 0.6);
					TF2Attrib_SetByName(iPrimary, "reload time decreased", 0.988); // reduced to ~1.13 sec
					TF2Attrib_SetByName(iPrimary, "scattergun no reload single", 1.0);
					TF2Attrib_RemoveByName(iPrimary, "scattergun has knockback");	// without this, the weapon still applies the stun when fired in mid-air
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 2);
				}
				case 448: {	// Soda Popper v2
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.33);
					TF2Attrib_SetByName(iPrimary, "fire rate bonus", 0.67);
					TF2Attrib_SetByName(iPrimary, "reload time decreased", 0.79); // reduced to ~1.33 sec
					TF2Attrib_SetByName(iPrimary, "scattergun no reload single", 1.0);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 2);
				}
				case 220: {	// Shortstop
					TF2Attrib_SetByName(iPrimary, "reload time increased hidden", 1.35); // lowered to 35% from 50%
					TF2Attrib_SetByName(iPrimary, "damage force increase hidden", 1.4);
					TF2Attrib_SetByName(iPrimary, "airblast vulnerability multiplier hidden", 1.4);
				}
			}
			
			switch (iSecondaryIndex) {
				case 449: {	// Winger
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.67);
					TF2Attrib_SetByName(iSecondary, "increased jump height from weapon", 1.25);
					TF2Attrib_SetByName(iSecondary, "cancel falling damage", 1.0);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 12);
				}
				case 773: {	// Pretty Boy's Pocket Pistol
					if (iPrimaryIndex == 1103) {	// Back Scatter has reduced ammo
						TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.277777); // 10 shells
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 10, _, secondaryAmmo);
					}
					else {
						TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.555555); // 20 shells
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 20, _, secondaryAmmo);
					}
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 12);
				}
				case 812, 833: {	// Flying Guillotine
					TF2Attrib_SetByName(iSecondary, "effect bar recharge rate increased", 0.8); // 8 seconds
				}
				case 222: {	// Mad Milk
					TF2Attrib_SetByName(iSecondary, "effect bar recharge rate increased", 0.75); // 15 seconds
					TF2Attrib_SetByName(iSecondary, "item_meter_resupply_denied", 1.0);
				}
				case 46, 1145: {	// Bonk v1
					TF2Attrib_SetByName(iSecondary, "item_meter_resupply_denied", 0.67);
				}
				case 163: {	// Crit-a-Cola v2
					TF2Attrib_SetByName(iSecondary, "item_meter_resupply_denied", 0.67);
					TF2Attrib_SetByName(iSecondary, "lunchbox adds minicrits", 2.0);
				}
			}
			
			switch (iMeleeIndex) {
				case 450: {	// Atomizer
					TF2Attrib_SetByName(iMelee, "air dash count", 1.0);
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
					//TF2Attrib_SetByName(iMelee, "fire rate penalty", 1.5);
				}
				case 325: {	// Boston Basher
					TF2Attrib_SetByName(iMelee, "damage bonus", 1.25);
					TF2Attrib_SetByName(iMelee, "bleeding duration", 5.0);
					TF2Attrib_SetByName(iMelee, "hit self on miss", 1.0);
				}
				case 317: {	// Candy Cane
					TF2Attrib_SetByName(iMelee, "Max health additive penalty", -15.0);
				}
				case 349: {	// Sun-on-a-Stick
					TF2Attrib_SetByName(iMelee, "dmg taken from fire reduced on active", 0.5);
				}
				case 355: {	// Fan O'War
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
				}
			}
		}
	
		// Soldier
		case TFClass_Soldier: {
			TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", 0.6); // reduced to 12
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 12, _, primaryAmmo);
		
			switch (iPrimaryIndex) {
				case 228, 1085: {	// Black Box
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.75);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 3);
				}
				case 127: {	// Direct Hit
					TF2Attrib_SetByName(iPrimary, "damage bonus", 1.25);
					TF2Attrib_SetByName(iPrimary, "blast radius decreased", 0.5);
					TF2Attrib_SetByName(iPrimary, "Projectile speed increased", 1.8);
					TF2Attrib_SetByName(iPrimary, "mod mini-crit airborne", 1.0);
				}
				case 414: {	// Liberty Launcher
					TF2Attrib_SetByName(iPrimary, "damage penalty", 0.85);
					TF2Attrib_SetByName(iPrimary, "rocket jump damage reduction", 0.85);
					TF2Attrib_SetByName(iPrimary, "projectile speed increased", 1.4);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 4);	// Fixes a bug where it sometimes spawns with a fifth shot
				}
				case 730: {	// Beggar's Bazooka
					TF2Attrib_SetByName(iPrimary, "fire rate bonus", 0.3);
					TF2Attrib_SetByName(iPrimary, "auto fires full clip", 1.0);
					TF2Attrib_SetByName(iPrimary, "can overload", 1.0);
					TF2Attrib_SetByName(iPrimary, "dmg penalty vs buildings", 0.75);
					TF2Attrib_SetByName(iPrimary, "clip size penalty HIDDEN", 0.75);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 0);
				}
				case 1104: {	// Air Strike
					TF2Attrib_SetByName(iPrimary, "maxammo primary reduced", 0.67);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 8, _, primaryAmmo);
					TF2Attrib_SetByName(iPrimary, "rocketjump attackrate bonus", 0.35);
					TF2Attrib_SetByName(iPrimary, "mini rockets", 1.0);
					TF2Attrib_SetByName(iPrimary, "clipsize increase on kill", 4.0);
				}
				case 441: {	// Cow Mangler 5000
					TF2Attrib_SetByName(iPrimary, "clip size bonus upgrade", 1.25);
					SetEntPropFloat(iPrimary, Prop_Send, "m_flEnergy", 20.0);		// Fill energy
				}
				case 237: {	// Rocket Jumper
					TF2Attrib_SetByName(iPrimary, "damage penalty", 0.0);
					TF2Attrib_SetByName(iPrimary, "no self blast dmg", 2.0);
					TF2Attrib_SetByName(iPrimary, "cannot pick up intelligence", 1.0);
				}
			}
			
			switch (iSecondaryIndex) {
				case 415: {	// Reserve Shooter
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.67);
					TF2Attrib_SetByName(iSecondary, "mod mini-crit airborne", 1.0);
					TF2Attrib_SetByName(iSecondary, "weapon spread bonus", 0.6);
					TF2Attrib_SetByName(iSecondary, "fire rate penalty", 1.2);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 4);
				}
				case 1153: {	// Panic Attack
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.67);
					TF2Attrib_SetByName(iSecondary, "single wep deploy time decreased", 0.5);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 4);
				}
				case 129, 1001: {	// Buff Banner
					TF2Attrib_SetByName(iSecondary, "increase buff duration HIDDEN", 0.4);
					TF2Attrib_SetByName(iSecondary, "mod soldier buff type", 1.0);
				}
				case 133: {	// Gunboats
					TF2Attrib_SetByName(iSecondary, "rocket jump damage reduction", 0.5);
				}
				case 444: {	// Mantreads
					TF2Attrib_SetByName(iSecondary, "boots falling stomp", 1.0);
				}
				case 1101: {	// B.A.S.E. Jumper
					TF2Attrib_SetByName(iSecondary, "parachute attribute", 1.0);
					TF2Attrib_SetByName(iSecondary, "mod soldier buff type", 4.0);
				}
			}
		
			switch (iMeleeIndex) {
				case 416: {		// Market Gardener
					TF2Attrib_SetByName(iMelee, "mod crit while airborne", 1.0);
				}
				case 775: {	// Escape Plan
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
				}
				case 357: {		// Half-Zatoichi
					TF2Attrib_SetByName(iMelee, "heal on kill", 85.0);
				}
				case 447: {		// Disciplinary Action
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
					TF2Attrib_SetByName(iMelee, "melee bounds multiplier", 1.3);
				}
			}
		}
	
		// Pyro
		case TFClass_Pyro: {
			TF2Attrib_SetByName(iPrimary, "damage bonus HIDDEN", 0.0);
			TF2Attrib_SetByName(iPrimary, "flame ammopersec increased", 1.333333);
			TF2Attrib_SetByName(iPrimary, "flame_speed", 2300.0);
			TF2Attrib_SetByName(iPrimary, "flame_lifetime", 0.13);
			TF2Attrib_SetByName(iPrimary, "weapon burn dmg reduced", 0.25);
			int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					
			switch (iPrimaryIndex) {
				/*if (StrEqual(class, "tf_weapon_flamethrower")) {		// All Flamethrowers
					TF2Attrib_SetByName(iPrimary, "damage bonus HIDDEN", 0.0);
					TF2Attrib_SetByName(iPrimary, "flame ammopersec increased", 1.333333);
					TF2Attrib_SetByName(iPrimary, "flame_speed", 2300.0);
					TF2Attrib_SetByName(iPrimary, "flame_lifetime", 0.13);
					TF2Attrib_SetByName(iPrimary, "weapon burn dmg reduced", 0.25);
				}*/
				case 40, 1146: {		// Backburner
					TF2Attrib_SetByName(iPrimary, "damage bonus HIDDEN", 0.0);
					TF2Attrib_SetByName(iPrimary, "flame ammopersec increased", 1.333333);
					TF2Attrib_SetByName(iPrimary, "flame_speed", 2300.0);
					TF2Attrib_SetByName(iPrimary, "flame_lifetime", 0.13);
					TF2Attrib_SetByName(iPrimary, "weapon burn dmg reduced", 0.25);
					TF2Attrib_SetByName(iPrimary, "max health additive bonus", 25.0);
					TF2Attrib_SetByName(iPrimary, "airblast cost increased", 2.0);
				}
				case 215: {		// Degreaser
					TF2Attrib_SetByName(iPrimary, "damage bonus HIDDEN", 0.0);
					TF2Attrib_SetByName(iPrimary, "flame ammopersec increased", 1.333333);
					TF2Attrib_SetByName(iPrimary, "flame_speed", 2300.0);
					TF2Attrib_SetByName(iPrimary, "flame_lifetime", 0.13);
					TF2Attrib_SetByName(iPrimary, "weapon burn dmg reduced", 0.25);
					TF2Attrib_SetByName(iPrimary, "maxammo primary reduced", 0.5);
					int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 12, _, primaryAmmo);
					TF2Attrib_SetByName(iPrimary, "deploy time decreased", 0.5);
				}
				case 1178: {	// Dragon's Fury
					TF2Attrib_SetByName(iPrimary, "item_meter_charge_type", 1.0);
					TF2Attrib_SetByName(iPrimary, "item_meter_charge_rate", 0.7);
					TF2Attrib_SetByName(iPrimary, "meter_label", 0.7);
					TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", 0.2);
					TF2Attrib_SetByName(iPrimary, "airblast cost scale hidden", 0.25);
					TF2Attrib_SetByName(iPrimary, "airblast cost scale hidden", 0.25);
				}
			}
			
			switch (iSecondaryIndex) {
				case 415: {	// Reserve Shooter
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.67);
					TF2Attrib_SetByName(iSecondary, "mod mini-crit airborne", 1.0);
					TF2Attrib_SetByName(iSecondary, "weapon spread bonus", 0.6);
					TF2Attrib_SetByName(iSecondary, "fire rate penalty", 1.2);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 4);
				}
				case 1153: {	// Panic Attack
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.67);
					TF2Attrib_SetByName(iSecondary, "single wep deploy time decreased", 0.5);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 4);
				}
				case 39, 1081: {	// Flare Gun
					TF2Attrib_SetByName(iSecondary, "faster reload rate", 0.6);
					TF2Attrib_SetByName(iSecondary, "crits_become_minicrits", 1.0);
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.5);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 16, _, secondaryAmmo);
				}
				case 351: {	// Detonator
					TF2Attrib_SetByName(iSecondary, "faster reload rate", 0.75);
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.75);
					TF2Attrib_SetByName(iSecondary, "crits_become_minicrits", 1.0);
					TF2Attrib_SetByName(iSecondary, "lunchbox adds minicrits", 1.0);
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.5);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 16, _, secondaryAmmo);
				}
				case 740: {	// Scorch Shot
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.54);
					TF2Attrib_SetByName(iSecondary, "mod flaregun fires pellets with knockback", 3.0);
					TF2Attrib_SetByName(iSecondary, "self dmg push force decreased", 0.65);
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.5);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 16, _, secondaryAmmo);
				}
			}
			
			switch (iMeleeIndex) {
				case 38, 457, 1000: {	// Axtinguisher
					TF2Attrib_SetByName(iMelee, "minicrit vs burning player", 1.0);
				}
				case 214: {	// Powerjack
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
					TF2Attrib_SetByName(iMelee, "move speed bonus", 1.15);
				}
				case 326: {	// Back Scratcher
					TF2Attrib_SetByName(iMelee, "health from packs increased", 2.0);
					TF2Attrib_SetByName(iMelee, "health from healers reduced", 0.25);
				}
				case 348: {	// Sharpened Volcano Fragment
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.6);
					TF2Attrib_SetByName(iMelee, "Set DamageType Ignite", 1.0);
				}
				case 813, 834: {	// Neon Annihilator
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.6);
					TF2Attrib_SetByName(iMelee, "ragdolls plasma effect", 1.0);
					TF2Attrib_SetByName(iMelee, "crit vs wet players", 1.0);
				}
				case 1181: {	// Hot Hand
					TF2Attrib_SetByName(iMelee, "speed_boost_on_hit_enemy", 1.0);
				}
			}
		}
	
		// Demoman
		case TFClass_DemoMan: {
			TF2Attrib_SetByName(iClient, "stickybomb charge rate", 0.5);
			TF2Attrib_SetByName(iClient, "mult charge turn control", 3.0);
			players[iClient].bIsDemoknight = false;
			
			switch (iPrimaryIndex) {
				case 308: {	// Loch-n-Load
					TF2Attrib_SetByName(iPrimary, "grenade no bounce", 1.0);
					TF2Attrib_SetByName(iPrimary, "projectile speed increased", 1.25);
				}
				case 996: {	// Loose Cannon
					TF2Attrib_SetByName(iPrimary, "projectile speed increased", 1.5);
					//TF2Items_SetAttribute(item1, 1, 127, 1.0); // sticky air burst mode
				}
				case 405: {	// Ali Baba's Wee Booties
					TF2Attrib_SetByName(iPrimary, "move speed bonus", 1.10);
					TF2Attrib_SetByName(iPrimary, "mult charge turn control", 3.0);
				}
				case 608: {	// Bootlegger (different item to the Booties)
					TF2Attrib_SetByName(iPrimary, "max health additive bonus", 25.0);
					TF2Attrib_SetByName(iPrimary, "mult charge turn control", 3.0);
				}
				case 1101: {	// B.A.S.E. Jumper
					TF2Attrib_SetByName(iPrimary, "parachute attribute", 1.0);
					TF2Attrib_SetByName(iPrimary, "mod soldier buff type", 4.0);
				}
			}
			
			switch (iSecondaryIndex) {
				case 130: {	// Scottish Resistance
					TF2Attrib_SetByName(iSecondary, "sticky detonate mode", 1.0);
				}
				case 1150: {	// Quickiebomb Launcher
					TF2Attrib_SetByName(iSecondary, "dmg penalty vs buildings", 0.9);
					TF2Attrib_SetByName(iSecondary, "stickybomb charge rate", 0.5);
					TF2Attrib_SetByName(iSecondary, "sticky arm time bonus", -0.2);
				}
				case 265: {	// Sticky Jumper
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.0);
					TF2Attrib_SetByName(iSecondary, "no self blast dmg", 2.0);
					TF2Attrib_SetByName(iSecondary, "cannot pick up intelligence", 1.0);
					TF2Attrib_SetByName(iSecondary, "override projectile type", 14.0);
					TF2Attrib_SetByName(iSecondary, "max pipebombs decreased", -6.0);
				}
				case 131, 1144: {	// Chargin' Targe
					TF2Attrib_SetByName(iSecondary, "max health additive bonus", 35.0);
					TF2Attrib_SetByName(iSecondary, "charge recharge rate increased", 1.2);
					if (iPrimaryIndex == 405 || iPrimaryIndex == 608) players[iClient].bIsDemoknight = true;
				}
				case 406: {	// Splendid Screen
					TF2Attrib_SetByName(iSecondary, "max health additive bonus", 15.0);
					TF2Attrib_SetByName(iSecondary, "charge recharge rate increased", 2.4);
					if (iPrimaryIndex == 405 || iPrimaryIndex == 608) players[iClient].bIsDemoknight = true;
				}
				case 1099: {	// Tide Turner
					TF2Attrib_SetByName(iSecondary, "lose demo charge on damage when charging", 1.0);
					TF2Attrib_SetByName(iSecondary, "charge recharge rate increased", 1.2);
					TF2Attrib_SetByName(iSecondary, "full charge turn control", 50.0);
				}
			}
			
			switch (iMeleeIndex) {
				case 404: {		// Persian Persuader
					TF2Attrib_SetByName(iMelee, "ammo gives charge", 1.0);
					TF2Attrib_SetByName(iMelee, "charge meter on hit", 0.2);
				}
				case 327: {		// Claidheamh Mor
					TF2Attrib_SetByName(iMelee, "kill refills meter", 75.0);
					TF2Attrib_SetByName(iMelee, "charge time increased", 0.5);
				}
				case 357: {		// Half-Zatoichi
					TF2Attrib_SetByName(iMelee, "heal on kill", 85.0);
				}
			}
		}
	
		// Heavy
		case TFClass_Heavy: {
			TF2Attrib_SetByName(iPrimary, "max health additive penalty", -50.0);
			TF2Attrib_SetByName(iClient, "move speed bonus", 1.043478);
			TF2Attrib_SetByName(iClient, "aiming movespeed increased", 1.57);
			TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", 0.75);
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 150, _, primaryAmmo);
			TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.5);
			int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 16, _, secondaryAmmo);
			TF2Attrib_SetByName(iPrimary, "bullets per shot bonus", 0.75);
			TF2Attrib_SetByName(iPrimary, "weapon spread bonus", 0.7);
		
			switch (iPrimaryIndex) {
				case 41: {	// Natascha
					TF2Attrib_SetByName(iPrimary, "projectile penetration", 1.25);
					TF2Attrib_SetByName(iPrimary, "override projectile type", 8.0);
					TF2Attrib_SetByName(iPrimary, "centerfire projectile", 1.0);
				}
				case 424: {	// Tomislav
					TF2Attrib_SetByName(iPrimary, "minigun no spin sounds", 1.0);
					TF2Attrib_SetByName(iPrimary, "fire rate penalty", 1.15);
					TF2Attrib_SetByName(iPrimary, "damage bonus", 1.2);
					TF2Attrib_SetByName(iPrimary, "minigun spinup time decreased", 0.8);
					TF2Attrib_SetByName(iPrimary, "damage bonus", 1.2);
				}
				case 312: {	// Brass Beast
					TF2Attrib_SetByName(iPrimary, "minigun spinup time increased", 1.25);
					TF2Attrib_SetByName(iPrimary, "bullets per shot bonus", 1.0);
					TF2Attrib_SetByName(iPrimary, "max health additive penalty", -25.0);
				}
				case 811, 832: {	// Huo-Long Heater
					TF2Attrib_SetByName(iPrimary, "ring of fire while aiming", 12.0);
				}
			}
			
			switch (iSecondaryIndex) {
				case 425: {	// Family Business
					TF2Attrib_SetByName(iSecondary, "weapon spread bonus", 0.672);
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.75);
				}
				case 1153: {	// Panic Attack
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.67);
					TF2Attrib_SetByName(iSecondary, "single wep deploy time decreased", 0.5);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 4);
				}
				case 42, 863, 1002: {	// Sandvich
					TF2Attrib_SetByName(iSecondary, "lunchbox healing decreased", 0.84);
					TF2Attrib_SetByName(iSecondary, "item_meter_charge_rate", 20.0);
					TF2Attrib_SetByName(iSecondary, "item_meter_charge_type", 1.0);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 1, _, secondaryAmmo);
				}
				case 311: {	// Buffalo Steak Sandvich
					TF2Attrib_SetByName(iSecondary, "kill eater score type", 50.0);
					TF2Attrib_SetByName(iSecondary, "lunchbox adds minicrits", 2.0);
					TF2Attrib_SetByName(iSecondary, "energy buff dmg taken multiplier", 1.0);
					TF2Attrib_SetByName(iSecondary, "item_meter_charge_rate", 30.0);
					TF2Attrib_SetByName(iSecondary, "item_meter_charge_type", 1.0);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 1, _, secondaryAmmo);
				}
			}
			
			switch (iMeleeIndex) {
				case 43: {	// Killing Gloves of Boxing
					TF2Attrib_SetByName(iMelee, "critboost on kill", 5.0);
				}
				case 239, 1084: {	// Gloves of Running Urgently
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
					TF2Attrib_SetByName(iMelee, "move speed bonus", 1.2);
					TF2Attrib_SetByName(iMelee, "provide on active", 1.0);
				}
				case 310: {	// Warrior's Spirit
					TF2Attrib_SetByName(iMelee, "heal on hit for slowfire", 25.0);
					TF2Attrib_SetByName(iMelee, "honorbound", 1.0);
					TF2Attrib_SetByName(iMelee, "heal on kill", 125.0);
				}
				case 331: {	// Fists of Steel
					TF2Attrib_SetByName(iMelee, "dmg from melee increased", 2.0);
				}
				case 426: {	// Eviction Notice
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.6);
					TF2Attrib_SetByName(iMelee, "fire rate bonus", 0.6);
					TF2Attrib_SetByName(iMelee, "speed_boost_on_hit", 3.0);
				}
			}
		}
		
		// Engineer
		case TFClass_Engineer: {
			TF2Attrib_SetByName(iClient, "engy building health bonus", 0.9);
			TF2Attrib_SetByName(iClient, "build rate bonus", 0.5);
			TF2Attrib_SetByName(iClient, "engineer sentry build rate multiplier", 0.5);
			TF2Attrib_SetByName(iClient, "upgrade rate decrease", 1.6);
			TF2Attrib_SetByName(iPrimary, "weapon spread bonus", 0.6);
			
			switch (iPrimaryIndex) {
				case 527: {	// Widowmaker
					TF2Attrib_SetByName(iPrimary, "mod ammo per shot", 35.0);
					TF2Attrib_SetByName(iPrimary, "mod use metal ammo type", 1.0);
					TF2Attrib_SetByName(iPrimary, "mod no reload DISPLAY ONLY", 1.0);
					TF2Attrib_SetByName(iPrimary, "mod max primary clip override", -1.0);
					TF2Attrib_SetByName(iPrimary, "add onhit addammo", 100.0);
				}
			}
			
			switch (iMeleeIndex) {
				case 329: {	// Jag
					TF2Attrib_SetByName(iMelee, "upgrade rate decrease", 0.5);
				}
				case 142: {	// Gunslinger
					TF2Attrib_SetByName(iMelee, "build rate bonus", 1.5);
					TF2Attrib_SetByName(iMelee, "gunslinger punch combo", 1.0);
					TF2Attrib_SetByName(iMelee, "max health additive bonus", 25.0);
				}
			}
		}
		
		// Medic
		case TFClass_Medic: {
			TF2Attrib_SetByName(iClient, "clip size bonus", 1.25);
			SetEntProp(iPrimary, Prop_Send, "m_iClip1", 50);
			TF2Attrib_SetByName(iClient, "hidden primary max ammo bonus", 1.333333);
			TF2Attrib_SetByName(iClient, "ubercharge rate penalty", 0.0);
			TF2Attrib_SetByName(iPrimary, "override projectile type", 9.0);
			
			switch (iPrimaryIndex) {
				case 36: {	// Blutsauger
					TF2Attrib_SetByName(iPrimary, "maxammo primary reduced", 0.6);
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.8);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 40);
					TF2Attrib_SetByName(iPrimary, "heal on hit for rapidfire", 3.0);
				}
				case 412: {	// Overdose
					TF2Attrib_SetByName(iPrimary, "damage penalty", 0.7);
				}
				case 305: {	// Crusader's Crossbow
					TF2Attrib_SetByName(iPrimary, "fire rate penalty", 1.2);
				}
			}
			
			switch (iSecondaryIndex) {
				case 35: {	// Kritzkrieg
					TF2Attrib_SetByName(iSecondary, "medigun charge is crit boost", 1.0);
					TF2Attrib_SetByName(iSecondary, "special taunt", 1.0);
				}
				case 411: {	// Quick-Fix
					TF2Attrib_SetByName(iSecondary, "medigun charge is megaheal", 2.0);
					TF2Attrib_SetByName(iSecondary, "lunchbox adds minicrits", 2.0);
					TF2Attrib_SetByName(iSecondary, "heal rate bonus", 1.4);
				}
				case 998: {	// Vaccinator
					TF2Attrib_SetByName(iSecondary, "medigun charge is resists", 3.0);	// disables resistance swapping
					TF2Attrib_SetByName(iSecondary, "overheal fill rate reduced", 0.34);
				}
			}
			
			switch (iMeleeIndex) {
				case 37, 1003: {	// Ubersaw
					TF2Attrib_SetByName(iMelee, "add uber charge on hit", 0.3);
				}
				case 413: {	// Solemn Vow v2
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.75);
					TF2Attrib_SetByName(iMelee, "mod see enemy health", 1.0);
				}
				case 173: {	// Vita-saw v2
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.7);
					TF2Attrib_SetByName(iMelee, "move speed bonus resource level", 1.2);
					TF2Attrib_SetByName(iMelee, "speed_boost_on_hit", 2.5);
				}
				case 304: {	// Amputator
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
					TF2Attrib_SetByName(iMelee, "enables aoe heal", 1.0);
				}
			}
		}
		
		// Sniper
		case TFClass_Sniper: {
			TF2Attrib_SetByName(iClient, "hidden primary max ammo bonus", 0.6);
			TF2Attrib_SetByName(iClient, "aiming movespeed increased", 1.851851);
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 15, _, primaryAmmo);
			
			switch (iPrimaryIndex) {
				case 526, 30665: {	// Machina
					TF2Attrib_SetByName(iPrimary, "damage bonus", 1.15);
					TF2Attrib_SetByName(iPrimary, "sniper only fire zoomed", 1.0);
					TF2Attrib_SetByName(iPrimary, "sniper fires tracer", 1.0);
					TF2Attrib_SetByName(iPrimary, "lunchbox adds minicrits", 2.0);
					TF2Attrib_SetByName(iPrimary, "projectile penetration", 1.0);
				}
				case 230: {	// Sydney Sleeper v3
					TF2Attrib_SetByName(iPrimary, "faster reload rate", 0.67);
					TF2Attrib_SetByName(iPrimary, "SRifle Charge rate decreased", 0.0);
				}
				case 752: {	// Hitman's Heatmaker v2
					TF2Attrib_SetByName(iPrimary, "damage penalty on bodyshot", 0.75);
				}
				case 1098: {	// Classic
					TF2Attrib_SetByName(iPrimary, "crit on hard hit", 1.0);
					TF2Attrib_SetByName(iPrimary, "sniper no headshot without full charge", 1.0);
					TF2Attrib_SetByName(iPrimary, "sniper crit no scope", 1.0);
					TF2Attrib_SetByName(iPrimary, "sniper fires tracer HIDDEN", 1.0);
					TF2Attrib_SetByName(iPrimary, "lunchbox adds minicrits", 3.0);
					TF2Attrib_SetByName(iPrimary, "SRifle Charge rate decreased", 0.75);
				}
				case 402: {	// Bazaar Bargain
					TF2Attrib_SetByName(iPrimary, "sniper charge per sec", 1.5);	// The Bargain's downside is hardcoded so I have to do this instead
					TF2Attrib_SetByName(iPrimary, "maxammo primary reduced", 0.5);
				}
				case 56, 1005, 1092: {	// Huntsman
					TF2Attrib_SetByName(iPrimary, "faster reload rate", 0.75);
					TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", 0.533333);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 8, _, primaryAmmo);
				}
			}
			
			switch (iSecondaryIndex) {
				case 751: {	// Cleaner's Carbine v2
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.75);
					TF2Attrib_SetByName(iSecondary, "maxammo secondary reduced", 0.4);
				}
				case 58, 1105, 1083: {	// Jarate v1.2
					TF2Attrib_SetByName(iSecondary, "item_meter_resupply_denied", 1.0);
				}
				case 231: {	// Darwin's Danger Shield
					TF2Attrib_SetByName(iSecondary, "max health additive bonus", 25.0);
					TF2Attrib_SetByName(iSecondary, "aiming no flinch", 1.0);
				}
			}
			
			switch (iMeleeIndex) {
				case 232: {	// Bushwacka
					TF2Attrib_SetByName(iMelee, "melee range multiplier", 1.5);
					TF2Attrib_SetByName(iMelee, "hit self on miss", 1.0);
				}
				case 401: {	// Shahanshah
					TF2Attrib_SetByName(iMelee, "fire rate penalty", 1.35);
				}
				case 171: {	// Tribalman's Shiv
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.5);
					TF2Attrib_SetByName(iMelee, "bleeding duration", 6.0);
				}
			}
		}
		
		// Spy
		case TFClass_Spy: {
			TF2Attrib_SetByName(iClient, "sapper damage penalty", 0.88);
			TF2Attrib_SetByName(iClient, "maxammo secondary reduced", 0.75);
			TF2Attrib_SetByName(iClient, "reload time increased", 1.191527);
			
			switch (iSecondaryIndex) {
				case 61, 1006: {	// Ambassador
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.55);
					TF2Attrib_SetByName(iSecondary, "maxammo secondary reduced", 0.67);
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 12, _, iSecondaryAmmo);
				}
				case 224: {	// L'Etranger
					TF2Attrib_SetByName(iSecondary, "add cloak on hit", 25.0);
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.5);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 3);
				}
				case 460: {	// Enforcer
					TF2Attrib_SetByName(iSecondary, "fire rate penalty", 1.2);
				}
			}
			
			switch (iMeleeIndex) {
				case 461: {	// Big Earner
					TF2Attrib_SetByName(iMelee, "add cloak on kill", 30.0);
					TF2Attrib_SetByName(iMelee, "speed_boost_on_kill", 3.0);
					TF2Attrib_SetByName(iMelee, "health from healers reduced", 0.5);
					TF2Attrib_SetByName(iMelee, "health from packs increased", 0.5);
				}
				case 225, 574: {	// Your Eternal Reward
					TF2Attrib_SetByName(iMelee, "disguise on backstab", 1.0);
					TF2Attrib_SetByName(iMelee, "silent killer", 1.0);
					TF2Attrib_SetByName(iMelee, "lunchbox adds minicrits", 1.0);
				}
				case 356: {	// Conniver's Kunai
					TF2Attrib_SetByName(iMelee, "max health additive penalty", -55.0);
				}
			}
			
			switch (iSapperIndex) {
				case 810, 831: {	// Red-Tape Recorder
					TF2Attrib_SetByName(iClient, "sapper damage penalty", 0.5);
					TF2Attrib_SetByName(iClient, "sapper health bonus", 1.5);
				}
			}
			
			/*else if (index == 60) {	// Cloak and Dagger
				item1 = TF2Items_CreateItem(0);
				TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
				TF2Items_SetNumAttributes(item1, 2);
				TF2Items_SetAttribute(item1, 0, 89, 0.86666); // cloak consume rate decreased (duration increased from 6.5 to 7.5)
				TF2Items_SetAttribute(item1, 1, 729, 1.0); // ReducedCloakFromAmmo (nil)
			}*/
		}
	}
	
	return Plugin_Handled;
}

public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast) {
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (!IsValidClient(attacker)) return Plugin_Handled;
	if (TF2_GetPlayerClass(attacker) != TFClass_Scout) return Plugin_Handled;
	
	int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
	int iMeleeIndex = -1;
	if (iMelee >= 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	if (iMeleeIndex != 317) return Plugin_Handled;		// Candy Cane
	
	TF2Util_TakeHealth(attacker, 40.0);
	Event event2 = CreateEvent("player_healonhit");
	if (event2) {
		event2.SetInt("amount", 40);
		event2.SetInt("entindex", attacker);
		
		event2.FireToClient(attacker);
		delete event2;
	}
	return Plugin_Continue;
}

public void TF2Items_OnGiveNamedItem_Post(int iClient, char[] sClassname, int iItemDefIndex, int iLevel, int iQuality, int iEntity)
{
	Address pCEconItemView = GetEntityAddress(iEntity) + view_as<Address>(g_iCEconItem_m_Item);
	g_hDHookItemIterateAttribute.HookRaw(Hook_Pre, pCEconItemView, CEconItemView_IterateAttributes);
	g_hDHookItemIterateAttribute.HookRaw(Hook_Post, pCEconItemView, CEconItemView_IterateAttributes_Post);
}

static MRESReturn CEconItemView_IterateAttributes(Address pThis, DHookParam hParams)
{
    StoreToAddress(pThis + view_as<Address>(g_iCEconItemView_m_bOnlyIterateItemViewAttributes), true, NumberType_Int8, false);
    return MRES_Ignored;
}

static MRESReturn CEconItemView_IterateAttributes_Post(Address pThis, DHookParam hParams)
{
    StoreToAddress(pThis + view_as<Address>(g_iCEconItemView_m_bOnlyIterateItemViewAttributes), false, NumberType_Int8, false);
    return MRES_Ignored;
} 
	// -={ Iterates every frame }=-

public void OnGameFrame() {
	
	frame++;
	
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
			
			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			int iMeleeIndex = -1;
			if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			//int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
			//int iWatchIndex = -1;
			//if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");			
			
			// Global and multi-class
			{
				//THREAT
				if (players[iClient].fTHREAT_Timer > 0.0) {
					players[iClient].fTHREAT_Timer -= 0.75;		// If we're not doing more than 50 DPS, this value will decrease
					if (players[iClient].fTHREAT_Timer > 500.0) {
						players[iClient].fTHREAT_Timer = 500.0;
					}
				}
				
				if (players[iClient].fTHREAT > 0.0 && TF2_IsPlayerInCondition(iClient, TFCond_Jarated)) {
					if (players[iClient].fTHREAT > 1.5) {
						players[iClient].fTHREAT -= 1.5;		// Equivalent of removing 100 THREAT per second
						players[players[iClient].iJarated].fTHREAT += 1.5;		// Adds the THREAT to the guy that threw the Jarate
					}				
					else {
						players[players[iClient].iJarated].fTHREAT += players[iClient].fTHREAT;
						players[iClient].fTHREAT = 0.0;
					}
				}
				if (players[iClient].fTHREAT > 0.0 && players[iClient].fTHREAT_Timer <= 0.0) {
					players[iClient].fTHREAT -= 0.75;		// Equivalent of removing 50 THREAT per second
				}
				if(players[iClient].fTHREAT < 0.0) {
					players[iClient].fTHREAT = 0.0;
				}
				
				// Displays THREAT
				SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
				ShowHudText(iClient, 1, "THREAT: %.0f", players[iClient].fTHREAT);
				
				if (iActive > 0) {
					if (iPrimary == iActive && iPrimaryIndex != 448) {		// Disable on Soda Popper so we can display HYPE
						// Define gold as the target colour (max THREAT)
						//int R2 = 255, G2 = 215, B2 = 0; // Gold colour
						int R2 = 255, G2 = 190, B2 = 0; // RED Gold colour
						int team = GetEntProp(iClient, Prop_Send, "m_iTeamNum");
						if (team == 3) {
							R2 = 190, G2 = 165, B2 = 50; // BLU Gold colour
						}

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
							SetEntityRenderColor(iActive, R, G, B, 255); // Set alpha to 255 (full visibility)
						}
					}
					else {
						// Define pink as the target colour (max Hype)
						int R2 = 255, G2 = 105, B2 = 180; // RED Gold colour

						// Ensure RemapValClamped is defined and returns a valid float
						float hype = GetEntPropFloat(iClient, Prop_Send,"m_flHypeMeter");
						float HypeScale = RemapValClamped(hype, 0.0, 100.0, 0.0, 1.0);
						if (HypeScale < 0.0 || HypeScale > 1.0) {
							HypeScale = 0.0; // Clamp to valid range if out-of-bounds
						}

						// Use the fixed baseline colour
						int R1 = 255, G1 = 255, B1 = 255; 

						// Interpolate RGB channels based on HypeScale
						int R = R1 + RoundToZero((R2 - R1) * HypeScale);
						int G = G1 + RoundToZero((G2 - G1) * HypeScale);
						int B = B1 + RoundToZero((B2 - B1) * HypeScale);

						// Check if the new colour differs from the current one to prevent redundant updates
						int currentR = 0, currentG = 0, currentB = 0, currentA = 255; // Initialise variables
						GetEntityRenderColor(iActive, currentR, currentG, currentB, currentA);

						if (currentR != R || currentG != G || currentB != B) {
							// Apply the interpolated colour to the weapon
							SetEntityRenderColor(iActive, R, G, B, 255); // Set alpha to 255 (full visibility)
						}
					}
				}

				// In-combat healing penalty
				if (players[iClient].fHeal_Penalty_Timer > 20.0) {
					players[iClient].fHeal_Penalty = 5.0;
					if (!TF2_IsPlayerInCondition(iClient, TFCond_Bleeding)) {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.5);
					}
					players[iClient].fHeal_Penalty_Timer = 20.0;
				}
				else if (players[iClient].fHeal_Penalty_Timer > 0.0) {
					players[iClient].fHeal_Penalty_Timer -= 0.15;
				}
				if (players[iClient].fHeal_Penalty > -10.0) {
					players[iClient].fHeal_Penalty -= 0.015;
				}
				if (players[iClient].fHeal_Penalty > 0.0) {
					if (frame % 33 == 0 && !(TF2_IsPlayerInCondition(iClient, TFCond_Disguised) || TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)))  {		// Trigger this every 33 frames (half-second)
						CreateParticle(iClient, "blood_impact_red_01", 2.0, _, _, _, _, 40.0);
					}
					if (TF2_IsPlayerInCondition(iClient, TFCond_Bleeding)) {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.0);
					}
					else {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.5);
						if (iMeleeIndex == 326) {		// Back Scratcher
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.125);
						}
						else {
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.5);
						}
					}
				}
				else {
					if (TF2_IsPlayerInCondition(iClient, TFCond_Bleeding)) {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.0);
					}
					else {
						if (iMeleeIndex == 326) {		// Back Scratcher
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.25);
						}
						else {
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 1.0);
						}
					}
				}


				// Afterburn
				//int MaxHP = GetEntProp(iClient, Prop_Send, "m_iMaxHealth");
				if (TF2Util_GetPlayerBurnDuration(iClient) > 8.0) {
					TF2Util_SetPlayerBurnDuration(iClient, 8.0);
				}
				if (TF2Util_GetPlayerBurnDuration(iClient) > 0.0) {
					players[iClient].fAfterburn += 0.015;
					if (players[iClient].fAfterburn > 6.0) {
						players[iClient].fAfterburn = 6.0;
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
				
				/*if (players[iClient].fAfterburn_DMG_tick > 0.0) {
					players[iClient].fAfterburn_DMG_tick -= 0.015;
				}
				if (iHealth < 30) {
					players[iClient].fAfterburn_DMG_tick = 1.0;
				}*/
				
				if (players[iClient].fTempLevel > 0.0) {
					players[iClient].fTempLevel -= 0.015;
				}
				
				// Mad Milk removal
				if (TF2_IsPlayerInCondition(iClient, TFCond_Milked)) {
					TF2_RemoveCondition(iClient, TFCond_Milked);
				}
				
				// Sandman debuff
				if (players[iClient].fBaseball_Debuff_Timer > 0.0) {
					players[iClient].fBaseball_Debuff_Timer -= 0.015;
				}
				
				// Neon Annihilator debuff
				if (players[iClient].fShocked > 0.0) {
					players[iClient].fShocked -= 0.015;
					TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.0);
					TF2Attrib_AddCustomPlayerAttribute(iClient, "mod weapon blocks healing", 1.0);
				}
				else {
					TF2Attrib_RemoveByName(iClient, "mod weapon blocks healing");
					if (!TF2_IsPlayerInCondition(iClient, TFCond_Bleeding)) {
						TF2Attrib_RemoveByName(iClient, "health from healers reduced");
					}
				}
				
				// Jarate duration nerf
				if (TF2_IsPlayerInCondition(iClient, TFCond_Jarated)) {
					if (TF2Util_GetPlayerConditionDuration(iClient, TFCond_Jarated) > 8.0)
					TF2Util_SetPlayerConditionDuration(iClient, TFCond_Jarated, 8.0);
				}
				
				// Panic Attack
				if (iActiveIndex != 1153) {
					players[iClient].fPA_Accuracy = 1.3;
				}
				else if (players[iClient].fPA_Accuracy > 0.0) {
					players[iClient].fPA_Accuracy -= 0.015;
				}
				
				if (iActiveIndex == 1153) {		// Scale Panic Attack accuracy up over 1.3 seconds
					if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
						TF2Attrib_SetByDefIndex(iActive, 106, 0.6 * RemapValClamped(players[iClient].fPA_Accuracy, 1.3, 0.0, 1.2, 1.0));		// Spread bonus
					}
					else {
						TF2Attrib_SetByDefIndex(iActive, 106, RemapValClamped(players[iClient].fPA_Accuracy, 1.3, 0.0, 1.2, 1.0));		// Spread bonus
					}
				}
				
				// Half-Zatoichi
				if (iActiveIndex == 357) {
					if (iHealth <= 100) {		// Disable holster if we don't have enough health to offset Honourbound
						TF2_AddCondition(iClient, TFCond_RestrictToMelee, 0.02, 0);		// Buffalo Steak strip to melee debuff
					}
				}
			}
			
			// Scout
			if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
				// Double jump nerf
				if (!TF2_IsPlayerInCondition(iClient, TFCond_CritHype)) {		// Despite the name, this is the regular Hype effect
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
					
					else if (!(GetEntityFlags(iClient) & FL_ONGROUND)) {
						ShowHudText(iClient, 2, "Damage taken: %.0f", players[iClient].fAirjump);
					}
					
					else {
						ShowHudText(iClient, 2, "");		// By having a message with nothing in it, we make the other messages load in faster
					}
					
					if (iPrimaryIndex == 448) {		// Passive Soda Popper Hype build
						float hype = GetEntPropFloat(iClient, Prop_Send,"m_flHypeMeter");
						if (hype < 100.0) {
							SetEntPropFloat(iClient, Prop_Send, "m_flHypeMeter", hype + 0.075);
						}
					}
				}
				// Soda Popper effect
				else {
					int JumpCount = GetEntProp(iClient, Prop_Send, "m_iAirDash");
					if (players[iClient].fAirjump > 50.0 && JumpCount < 5) {
						SetEntProp(iClient, Prop_Send, "m_iAirDash", JumpCount + 1);		// Remove one jump
						(players[iClient].fAirjump > 50.0);
					}
					
					SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 2, "Jumps remaining: %.0f", RemapValClamped(JumpCount + 0.0, 0.0, 5.0, 5.0, 0.0));
				}
				
				// Display particle effects from Bonk
				if (players[iClient].bBonk == true) {
					// TODO: find better particle effect
					float ang[3];
					GetEntPropVector(iClient, Prop_Data, "m_angRotation", ang);
					ang[0] = DegToRad(ang[0]); ang[1] = DegToRad(ang[1]); ang[2] = DegToRad(ang[2]);
					if (GetClientTeam(iClient) == 3) {
						CreateParticle(iClient,"medic_healradius_blue_buffed",1.0,ang[0],ang[1],_,_,_,_,_,false);
					}
					else {
						CreateParticle(iClient,"medic_healradius_red_buffed",1.0,ang[0],ang[1],_,_,_,_,_,false);
					}
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
				
				// Shortstop secondary ammo
				char class[64], class2[64];
				GetEntityClassname(iPrimary, class, sizeof(class));
				GetEntityClassname(iSecondary, class2, sizeof(class2));
				if (StrEqual(class, "tf_weapon_handgun_scout_primary") && (StrEqual(class2, "tf_weapon_pistol") || StrEqual(class2, "tf_weapon_handgun_scout_secondary")  || StrEqual(class2, "tf_weapon_pistol_scout"))) {	// Shortstop + Pistol
					int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");		// Reserve ammo
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					int iPrimaryReserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, iPrimaryAmmo);
					int iSecondaryReserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, iSecondaryAmmo);
					
					if (iActive == iPrimary) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", iPrimaryReserves, _, iSecondaryAmmo);
					}
					
					else if (iActive == iSecondary) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", iSecondaryReserves, _, iPrimaryAmmo);
					}
				}
				
				// Crit-a-Cola v2 buff
				if (players[iClient].bCac == true) {
					players[iClient].fTHREAT += 1.136;
					players[iClient].fTHREAT_Timer += 1.623;
					if (players[iClient].fTHREAT > 1000.0) {
						players[iClient].fTHREAT = 1000.0;
					}
				}
				
				// Winger reduced gravity
				if (iSecondaryIndex == 449 && iSecondary == iActive) {
					if ((GetEntityFlags(iClient) & FL_ONGROUND) != 0) continue;
					float vecVel[3];
					GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);
					if (vecVel[2] > 0.0) continue;
					vecVel[2] += 3.0;		// Lower gravity 33%
					TeleportEntity(iClient , _, _, vecVel);
				}
				
				// Syncs ammo between weapons when the Pocket Pistol is equipped
				if (iSecondaryIndex == 773) {
					int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					int iPrimaryReserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, iPrimaryAmmo);
					int iSecondaryReserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, iSecondaryAmmo);
					
					if (iActive == iPrimary) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", iPrimaryReserves, _, iSecondaryAmmo);
					}
					
					else if (iActive == iSecondary) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", iSecondaryReserves, _, iPrimaryAmmo);
					}
				}
				
				// Flying Guillotine disable long-range recharge
				if (iSecondaryIndex == 812 || iSecondaryIndex == 833) {
					float fRegen = GetEntPropFloat(iSecondary, Prop_Send, "m_flEffectBarRegenTime");
					if (fRegen != players[iClient].fCleaver && fRegen != 0.0) {
						if (fRegen > players[iClient].fCleaver) players[iClient].fCleaver = fRegen;
						if (fRegen < players[iClient].fCleaver) {
							SetEntPropFloat(iSecondary, Prop_Send, "m_flEffectBarRegenTime", players[iClient].fCleaver);
							SetEntPropFloat(iSecondary, Prop_Send, "m_flLastFireTime", players[iClient].fCleaver - 4.0);
						}
					}
				}
				
				// Sun-on-a-Stick while on fire
				if (iMeleeIndex == 349) {
					if (TF2Util_GetPlayerBurnDuration(iClient) > 5.36) {
						TF2Util_SetPlayerBurnDuration(iClient, 5.36);
					}
					
					if (TF2Util_GetPlayerBurnDuration(iClient) <= 0.0) continue;
					TF2_AddCondition(iClient, TFCond_RestrictToMelee, 0.02, 0);
				}
				
				// Bonk v1 buff
				/*if (players[iClient].bBonk == true) {
					TF2Attrib_AddCustomPlayerAttribute(iClient, "damage force reduction", 0.4);
				}
				else {
					TF2Attrib_RemoveByName(iClient, "damage force reduction");
				}*/
			}
			
			// Soldier
			else if (TF2_GetPlayerClass(iClient) == TFClass_Soldier) {
				// Gunboats airborne splash radius penalty
				if (iSecondaryIndex == 133) {
					if (TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping)) {
						if (iPrimaryIndex == 127) {		// Direct Hit
							TF2Attrib_SetByDefIndex(iPrimary, 100, 0.333333); // blast radius decreased (reduced 50%)
						}
						else {
							TF2Attrib_SetByDefIndex(iPrimary, 100, 0.67);
						}
						float ang[3];
						GetEntPropVector(iClient, Prop_Data, "m_angRotation", ang);
						ang[0] = DegToRad(ang[0]); ang[1] = DegToRad(ang[1]); ang[2] = DegToRad(ang[2]);
						CreateParticle(iClient,"flaming_slap",1.0,ang[0],ang[1],_,_,_,_,_,false);		// Attaches a particle to the Soldier
						
					}
				}
				// Mantreads
				if (iSecondaryIndex == 444) {
					players[iClient].fMantreads_OOC_Timer += 0.015;
					if (players[iClient].fMantreads_OOC_Timer > 5.0) {
						TF2Attrib_SetByDefIndex(iSecondary, 107, 1.25);	// move speed bonus
					}
					else {
						TF2Attrib_RemoveByDefIndex(iSecondary, 107);
					}
				}
				// Air Strike
				if (iPrimaryIndex == 1104) {
					if (TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping)) {
						TF2Attrib_SetByDefIndex(iPrimary, 100, 1.25);	// blast radius (25%; cancels out rapid fire attribute)
						TF2Attrib_SetByDefIndex(iPrimary, 411, 2.0);	// projectile spread angle penalty (2 deg)
					}
					else {
						TF2Attrib_RemoveByDefIndex(iPrimary, 100);
						TF2Attrib_RemoveByDefIndex(iPrimary, 411);
					}
				}
				// Bazooka
				if (iPrimaryIndex == 730) {
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int iClip = GetEntData(iPrimary, iAmmoTable, 4);		// Loaded ammo of our launchers
					if (iClip > players[iClient].iBazooka_Ammo) {
						players[iClient].iBazooka_Clip = iClip;
						players[iClient].fBazooka_Load_Timer = 1.5;
					}
					
					if (players[iClient].fBazooka_Load_Timer > 0.0) {
						players[iClient].fBazooka_Load_Timer -= 0.015;
					}
					else {
						players[iClient].iBazooka_Clip = 0;
					}
					
					players[iClient].iBazooka_Ammo = iClip;
				}
				
				// Banner effects
				if (players[iClient].fBuff_Banner > 0.0) {
					players[iClient].fBuff_Banner -= 0.015;
					
					for (int iTarget = 1 ; iTarget <= MaxClients ; iTarget++) {
						if (IsValidClient(iTarget)) {
							float vecTargetPos[3], vecSoldierPos[3];
							GetClientEyePosition(iClient, vecSoldierPos);
							GetClientEyePosition(iTarget, vecTargetPos);
							
							float fDist = GetVectorDistance(vecSoldierPos, vecTargetPos);		// Store distance
							if (fDist <= 200.0 && TF2_GetClientTeam(iClient) == TF2_GetClientTeam(iTarget)) {
								Handle hndl = TR_TraceRayFilterEx(vecSoldierPos, vecTargetPos, MASK_SOLID, RayType_EndPoint, PlayerTraceFilter, iClient);
								if (TR_DidHit(hndl) == false || IsValidClient(TR_GetEntityIndex(hndl))) {
									players[iTarget].fTHREAT = 1000.0;
									players[iTarget].fTHREAT_Timer = 500.0;
								}
								delete hndl;
							}
						}
					}
				}
				
				// Buff Banner passive
				if (iSecondaryIndex == 129 || iSecondaryIndex == 1001) {
					if (iPrimaryIndex == 1104) {	// Air Strike exception
						TF2Attrib_AddCustomPlayerAttribute(iClient, "hidden primary max ammo bonus", 1.75);
					}
					else {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "hidden primary max ammo bonus", 1.5);
					}
				}
				else {
					TF2Attrib_RemoveByName(iClient, "hidden primary max ammo bonus");
				}
				
				// Escape Plan speed
				if (iActiveIndex == 775)
				{
					int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
					float fSpeed;

					if (iHealth <= 40) {
						fSpeed = 336.0;
					}
					else if (iHealth <= 60) {
						fSpeed = 312.0;
					}
					else if (iHealth <= 100) {
						fSpeed = 288.0;
					}
					else if (iHealth <= 120) {
						fSpeed = 264.0;
					}
					else {
						fSpeed = 240.0;
					}

					SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", fSpeed);
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
						
						if (iPrimaryIndex == 594) {		// Phlog
						
							DataPack hDataPack = new DataPack();		// Write this to a datapack so we can send it to another function
							hDataPack.WriteCell(iClient);
							hDataPack.WriteFloatArray(vecPos, 3);
							hDataPack.WriteFloatArray(vecAng, 3);

							CreateTimer(0.15, FlameBeam, hDataPack);
						}
						else {
						
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
														
														if (isBehind && !isKritzed(iClient)) {
															TF2_AddCondition(iEntity, TFCond_MarkedForDeathSilent, 0.015);
														}
													}
													
													float fDamage = 10.0 * fDmgMod * fDmgModTHREAT;
			
													int iDamagetype = DMG_IGNITE|DMG_USE_HITLOCATIONS;

													if (isKritzed(iClient)) {
														fDamage = 10.0;
														iDamagetype |= DMG_CRIT;
													}
													if (players[iEntity].bBonk == true) {
														//PrintToChatAll("damage before: %f", fDamage);
														fDamage -= 6.0;
														//PrintToChatAll("damage after: %f", fDamage);
														if (fDamage < 0) {
															fDamage = 0.0;
														}
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
													if (players[iClient].fBaseball_Debuff_Timer <= 0.0) {
														players[iClient].fTHREAT_Timer += fDamage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
													}
												}
												
												else if (StrEqual(class,"obj_sentrygun") || StrEqual(class,"obj_teleporter") || StrEqual(class,"obj_dispenser")) {		// Buildings
													float fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 450.0, 1.5, 1.0);		// Gives us our distance multiplier
													float fDmgModTHREAT = RemapValClamped(fDistance, 0.0, 450.0, 0.0, 0.5) * players[iClient].fTHREAT / 1000 + 1;
													
													float fDamage = 10.0 * fDmgMod * fDmgModTHREAT;
													int iDamagetype = DMG_IGNITE;
													
													SDKHooks_TakeDamage(iEntity, iPrimary, iClient, fDamage, iDamagetype, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage
												}
												
												else if (StrEqual(class, "tf_projectile_pipe_remote") || StrEqual(class, "tf_projectile_pipe")) {		// Handles Demo bomb destruction on hit
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
					}
					players[iClient].iAmmo = ammoCount;
				}
				
				// Axtinguisher
				if (iMeleeIndex == 38 || iMeleeIndex == 457 || iMeleeIndex == 1000) {
					SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 2, "Axe: %.0f%%", 5.0 * players[iClient].fAxe_Cooldown);
					
					if (players[iClient].fAxe_Cooldown < 20.0) {
						players[iClient].fAxe_Cooldown += 0.015;
					}
					else {
						players[iClient].fAxe_Cooldown = 20.0;
					}
				}
			}				
			
			// Demoman
			else if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
				// Make sure we have no Demoknight stuff equipped
				if (!(iPrimaryIndex == 1101 || iPrimaryIndex == 405 || iPrimaryIndex == 608 || iSecondaryIndex == 131 || iSecondaryIndex == 406 || iSecondaryIndex == 1099 || iSecondaryIndex == 1144)) {

					// Ensures both launchers share the same pool of ammo
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int iClipGrenade = GetEntData(iPrimary, iAmmoTable, 4);
					int iClipSticky = GetEntData(iSecondary, iAmmoTable, 4);
					
					int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
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
				
				// Trigger Mini-Crits after 0.9 sec charging
				float fCharge = GetEntPropFloat(iClient, Prop_Send, "m_flChargeMeter");
				if (fCharge <= 40.0  && TF2_IsPlayerInCondition(iClient, TFCond_Charging) && iActive == iMelee) {
					players[iClient].bCharge_Crit_Prepped = true;
					TF2Attrib_SetByDefIndex(iMelee, 264, 2.666);		// Increase rage to 128 HU
				}
				else if (players[iClient].bCharge_Crit_Prepped == true) {
					CreateTimer(0.3, RemoveChargeCrit, iClient);
				}
			}
			
			// Heavy
			else if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
				
				//float fCharge = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
				//PrintToChatAll("Charge: %f", fCharge);
			
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
				if (weaponState == 1) {	
					players[iClient].fRev = 1.005;		// This is our rev meter; it's a measure of how close we are to being free of the L&W nerf
				}
				
				else if ((weaponState == 2 || weaponState == 3) && players[iClient].fRev > 0.0) {		// If we're revved (or firing) but the rev meter isn't empty...
					players[iClient].fRev = players[iClient].fRev - 0.015;		// It takes us 67 frames (1 second) to fully deplete the rev meter
				}
				
				// Fast holster when unrevving
				else if (weaponState == 0 && sequence == 23) {	
					if (iPrimaryIndex != 312) {
						int bDone = GetEntProp(view, Prop_Data, "m_bSequenceFinished");
						if (bDone == 0) SetEntProp(view, Prop_Data, "m_bSequenceFinished", true, .size = 1);

						if(cycle < 0.2) {		//set idle time faster
							SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle",GetGameTime() + 1.0);
						}
						float fAnimSpeed = 2.0;
						SetEntPropFloat(view, Prop_Send, "m_flPlaybackRate", fAnimSpeed);		//speed up animation
					}
				}
				
				// Adjust damage, accuracy and movement speed dynamically as we shoot
				if (iPrimaryIndex != 312) {
					if (weaponState == 2) {
						if (players[iClient].fSpeed > 0.0) {		// If we're firing but the speed meter isn't empty...
							players[iClient].fSpeed = players[iClient].fSpeed - 0.015;		// It takes us 67 frames (1 second) to fully deplete the meter
						}
					}
					
					else {	// While we're not firing...
						if (players[iClient].fSpeed < 1.005) {
							players[iClient].fSpeed = players[iClient].fSpeed + 0.015;
						}
						else {
							players[iClient].fSpeed = 1.005;		// Clamp
						}
					}
				}
				
				// Brass Beast (slow while revved)
				else {
					if (weaponState == 2 || weaponState == 3) {
						if (players[iClient].fSpeed > 0.0) {
							players[iClient].fSpeed = players[iClient].fSpeed - 0.015;
						}
					}
					else {
						if (players[iClient].fSpeed < 1.005) {
							players[iClient].fSpeed = players[iClient].fSpeed + 0.015;
						}
					}
				}
				
				// Tomislav ammo drain while revved
				if (iPrimaryIndex == 424 && weaponState == 3) {	
					if (players[iClient].fTomislavDrainDelay > 0.0) {
						players[iClient].fTomislavDrainDelay -= 0.015;
					}
					else {
						players[iClient].fTomislavDrainDelay = 0.2;
						
						int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
						int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
						SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - 1, _, primaryAmmo);
					}
				}
				
				float DmgBase;
				DmgBase = 1.0;
				
				int time = RoundFloat(players[iClient].fRev * 1000);		// Time slowly decreases
				if (time % 100 == 0) {		// Only trigger an update every 0.1 sec
					float factor = 1.0 + time / 1000.0;		// This value continuously decreases from ~2 to 1 over time
					TF2Attrib_SetByDefIndex(iPrimary, 106, 0.8 / factor);		// Spread bonus
					TF2Attrib_SetByDefIndex(iPrimary, 2, DmgBase * factor);		// Damage bonus (33% damage penalty inversely proportional to speed)
				}
				
				if (iPrimaryIndex == 312) {		// Brass Beast
					TF2Attrib_SetByDefIndex(iPrimary, 54, RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 0.510, 1.0));
				}
				else {
					TF2Attrib_SetByDefIndex(iPrimary, 54, RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 0.583, 1.0));
				}
				
				// Huo-Long Heater
				if (iPrimaryIndex == 811 || iPrimaryIndex == 832) {
					int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
					int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
					float fFiringSpeedMult = RemapValClamped((iHealth / iMaxHealth) * 1.0, 1.0 , 0.0, 1.2, 0.6);
					TF2Attrib_SetByName(iMelee, "fire rate bonus", fFiringSpeedMult);
				}
				
				char class[64];
				GetEntityClassname(iSecondary, class,64);
				if (StrEqual(class,"tf_weapon_lunchbox")) {
					//PrintToChatAll("%f", players[iClient].fLunchbox_Cooldown);
					//PrintToChatAll("Bar %f", GetEntPropFloat(iSecondary, Prop_Send, "m_flItemChargeMeter"));
					//PrintToChatAll("Playerbar %f", GetEntPropFloat(iClient, Prop_Send, "m_flItemChargeMeter"));
					//PrintToChatAll("Nextattack %f", GetEntPropFloat(iSecondary, Prop_Send, "m_flNextPrimaryAttack"));
					//PrintToChatAll("Energy %f", GetEntPropFloat(iSecondary, Prop_Send, "m_flEnergy"));
					//PrintToChatAll("Lastattack %f", GetEntPropFloat(iSecondary, Prop_Send, "m_flLastFireTime"));
					//SetEntPropFloat(iSecondary, Prop_Send, "m_flEffectBarRegenTime");
					//if (GetEntPropFloat(iSecondary, Prop_Send, "m_flEffectBarRegenTime") > players[iClient].fLunchbox_Cooldown + 10.0) {
					//	SetEntPropFloat(iSecondary, Prop_Send, "m_flEffectBarRegenTime", players[iClient].fLunchbox_Cooldown);
					//}
					players[iClient].fLunchbox_Cooldown = GetEntPropFloat(iSecondary, Prop_Send, "m_flEffectBarRegenTime");
				}
				
				// Steak Sandvich
				if (players[iClient].bSteak_Buff == true) {
					TF2Attrib_SetByName(iSecondary, "move speed bonus", 1.2);
				}
				
				// Fists of Steel prevent suicide
				if (iActiveIndex == 331) {
					int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
					if (iHealth <= 125) {
						TF2_AddCondition(iClient, TFCond_RestrictToMelee, 0.02, 0);		// Buffalo Steak strip to melee debuff
					}
				}
			}
			
			// Engineer
			else if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
				// Display PDA
				SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
				if (players[iClient].bMini == true) {
					ShowHudText(iClient, 2, "PDA: Mini-Sentry");
				}
				else {
					ShowHudText(iClient, 2, "PDA: Standard");
				}
				
				// Pistol autoreload
				if (players[iClient].iEquipped != iActive && players[iClient].iEquipped == iSecondary) {			// Weapon swap off Pistol
					CreateTimer(1.005, AutoreloadPistol, iClient);
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
				
				// Syringe autoreload
				if (players[iClient].iEquipped != iActive) {			// Weapon swap
					CreateTimer(1.6, AutoreloadSyringe, iClient);
				}
				
				// Passive Uber build (0.625%/sec base)
				float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
				if (fUber < 1.0 && !(TF2_IsPlayerInCondition(iClient, TFCond_Ubercharged) || TF2_IsPlayerInCondition(iClient, TFCond_Kritzkrieged) || TF2_IsPlayerInCondition(iClient, TFCond_MegaHeal))) {	// Disble this when Ubered
					if (iMeleeIndex == 413) continue;	// Solemn Vow
					if (iSecondaryIndex == 35) {		// Kritzkreig
						fUber += 0.00009328 * 1.25 * 0.5;
					}
					else if (iSecondaryIndex == 998) {		// Vaccinator
						fUber += 0.00009328 * 3.0 * 0.5;
					}
					else {
						fUber += 0.00009328 * 0.5;		// This is being added every *tick*
					}
					SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber);
				}
				
				// Amputator taunt heal
				/*if (TF2_IsPlayerInCondition(iClient, TFCond_Taunting)) {
					if (iActiveIndex == 304 && GetEntProp(iClient, Prop_Send, "m_nActiveTauntSlot") == -1 && GetEntProp(iClient, Prop_Send, "m_bAllowMoveDuringTaunt") == 0) {
						players[iClient].fAmputator_heal_tick_timer += 0.015;
						if (players[iClient].fAmputator_heal_tick_timer >= 1.0) {
						
							players[iClient].fAmputator_heal_tick_timer = 0.0;
							// TODO: change range to correct value
							for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
								if (!IsValidClient(iEnt)) continue;
								
								int iPatientTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
								int iMedicTeam = GetEntProp(iClient, Prop_Data, "m_iTeamNum");
								if (iPatientTeam == iMedicTeam) continue;
								
								float vecPatientPos[3], vecMedicPos[3], vecDistance;
								GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecPatientPos);
								GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", vecMedicPos);
								vecDistance = GetVectorDistance(vecPatientPos, vecMedicPos);
								if (vecDistance > 450.0) continue;
								
								float fHealing = 26.25;
								fHealing *= RemapValClamped(vecDistance, 0.0, 450.0, 1.0, 0.5);
								
								TF2Util_TakeHealth(iEnt, fHealing);
								Event event = CreateEvent("player_healonhit");
								if (event) {
									event.SetInt("amount", RoundFloat(fHealing));
									event.SetInt("entindex", iEnt);
									
									event.FireToClient(iEnt);
									delete event;
								}
								
								if (fUber < 1.0) {
									if (iSecondaryIndex == 35) {		// Kritzkreig
										fUber += fHealing * 1.25 * 0.75;
									}
									else if (iSecondaryIndex == 998) {		// Vaccinator
										fUber += fHealing * 3.0 * 0.75;
									}
									else {
										fUber += fHealing * 0.75;		// 25% less Uber build from the taunt
									}
									SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber);
								}
							}
						}
					}
				}*/
				
				// Vita-saw
				if (iActiveIndex == 173) {
					if (frame % 67 != 0) continue;
					int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", (ammoCount > 20 ? ammoCount - 20 : 0), _, primaryAmmo);
				}
			}
			
			// Sniper
			else if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
				char class[64];
				
				GetEntityClassname(iActive, class,64);
				// Sniper Rifle
				if (StrEqual(class,"tf_weapon_sniperrifle") || StrEqual(class,"tf_weapon_sniperrifle_decap") || StrEqual(class,"tf_weapon_sniperrifle_classic")) {
					float fCharge = GetEntPropFloat(iPrimary, Prop_Send, "m_flChargedDamage");
					TF2Attrib_SetByDefIndex(iActive, 54, RemapValClamped(fCharge, 0.0, 150.0, 1.0, 0.6));			// Lower movement speed as the weapon charges
				}
				
				// Hitman's Heatmaker
				if (iPrimaryIndex == 752) {
					SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
					if (players[iClient].fFocus_Timer > 0.0) {
						ShowHudText(iClient, 2, "Focused: %.1f", players[iClient].fFocus_Timer);
						players[iClient].fFocus_Timer -= 0.015;
					}
					else if (players[iClient].fFocus_Timer < 0.0) {
						TF2Attrib_RemoveByName(iClient, "fire rate bonus HIDDEN");
						TF2Attrib_RemoveByName(iClient, "sniper fires tracer HIDDEN");
						players[iClient].fFocus_Timer = 0.0;
					}
					
					else {
						ShowHudText(iClient, 2, "");
					}
				}
				
				GetEntityClassname(iSecondary, class,64);
				// Cleaner's Carbine v2
				if (StrEqual(class, "tf_weapon_charged_smg")) {
					int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
					int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					
					int clip = GetEntData(iSecondary, iAmmoTable, 4);
					int reserves = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
					
					if (reserves > 0) {
						SetEntProp(iClient, Prop_Data, "m_iAmmo", 0, _, primaryAmmo);
						SetEntData(iSecondary, iAmmoTable, (clip + 2 * reserves > 40) ? 40 : (clip + 2 * reserves), 4, true);		// Transfer reserves into clip
					}
					
					if (clip < 15) {
						if (players[iClient].fFocus_Timer > 0.0) {
							TF2Attrib_SetByName(iSecondary, "fire rate bonus HIDDEN", 0.4355);
							//TF2Attrib_SetByDefIndex(iSecondary, 6, 0.4355);		// Fire rate bonus
						}
						else {
							TF2Attrib_SetByName(iSecondary, "fire rate bonus HIDDEN", 0.65);
							//TF2Attrib_SetByDefIndex(iSecondary, 6, 0.65);
						}
					}
					else {
						TF2Attrib_RemoveByName(iSecondary, "fire rate bonus HIDDEN");
						//TF2Attrib_SetByDefIndex(iSecondary, 6, 1.0);
					}
				}
				// Razorback
				if (StrEqual(class, "tf_wearable_razorback") && (iSecondaryIndex == 57)) {
					if (iActive == iMelee) {
						TF2Attrib_AddCustomPlayerAttribute(iSecondary, "move speed bonus", 1.07);	
					}
					else {
						TF2Attrib_RemoveByName(iSecondary, "move speed bonus");	
					}
				}
				// Cozy Camper
				if (StrEqual(class, "tf_wearable") && (iSecondaryIndex == 642)) {
					if (GetEntityFlags(iClient) & FL_DUCKING) {
						TF2Attrib_AddCustomPlayerAttribute(iClient, "damage force reduction", 0.5);
						TF2Attrib_AddCustomPlayerAttribute(iClient, "move speed penalty", 0.001);
						TF2Attrib_AddCustomPlayerAttribute(iClient, "aiming movespeed increased", 0.001);
						
						if (players[iClient].fHealth_Regen_Timer < 1.0) {
							players[iClient].fHealth_Regen_Timer += 0.015;
						}
						else {
							players[iClient].fHealth_Regen_Timer = 0.0;
							TriggerHealing(iClient);
						}
					}
					else {
						TF2Attrib_RemoveByName(iClient, "damage force reduction");
						TF2Attrib_RemoveByName(iClient, "move speed penalty");
						TF2Attrib_RemoveByName(iClient, "aiming movespeed increased");
					}
				}
				
				// Shahanshah
				if (iMeleeIndex == 401) {
					int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
					int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
					if (iHealth < iMaxHealth / 2) TF2Attrib_SetByName(iMelee, "fire rate penalty", 0.65);
					else TF2Attrib_SetByName(iMelee, "fire rate penalty", 1.35);
				}
			}
			
			// Spy
			else if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
				// Spy sprint
				if (TF2_IsPlayerInCondition(iClient, TFCond_Disguised) && !TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
					if (iActive != iSecondary && iActiveIndex != 27 && iMeleeIndex != 461) {		// Are we holding something other than the revolver or Disguise Kit? (and disable for Big Earner)
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
					if (iMeleeIndex == 461) {		// Reduced healing on wearer
						if (TF2_IsPlayerInCondition(iClient, TFCond_Disguised)) {
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.5);
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from packs increased", 0.5);
						}
						else {
							TF2Attrib_AddCustomPlayerAttribute(iClient, "health from packs increased", 1.0);
						}
					}
				}
				
				float fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
				
				// Determines when we're in the cloaking animation
				if (TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
					players[iClient].fCloak_Timer += 0.015;
					if (players[iClient].fCloak_Timer > 1.0) {
						players[iClient].fCloak_Timer = 1.0;
						//SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak + 5.0);
					}
					else {
						SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", fCloak + 0.149254);		// This is how much cloak we normally drain per frame
					}
				}
				else {
					players[iClient].fCloak_Timer = 0.0;
				}
				
				// Enforcer
				if (iSecondaryIndex == 460) {
					if (players[iClient].fDamage_Recieved_Enforcer > 50.0) {
						if (TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
							TF2_RemoveCondition(iClient, TFCond_Cloaked);
							players[iClient].fDamage_Recieved_Enforcer = 0.0;
							EmitSoundToClient(iClient, "weapons/drg_pomson_drain_01.wav");
						}
						
						else if (TF2_IsPlayerInCondition(iClient, TFCond_Disguised)) {
							TF2_RemoveCondition(iClient, TFCond_Disguised);
							players[iClient].fDamage_Recieved_Enforcer = 0.0;
							EmitSoundToClient(iClient, "weapons/drg_pomson_drain_01.wav");
						}
					}
					else {
						players[iClient].fDamage_Recieved_Enforcer -= 0.75;		// Drains the meter in ~1 second
					}
					if (players[iClient].fDamage_Recieved_Enforcer < 0.0) {
						players[iClient].fDamage_Recieved_Enforcer = 0.0;
					}
				}
				
				// Your Eternal Reward
				/*if (iMeleeIndex == 225 || iMeleeIndex == 574) {
					if (iActive != iSecondary) {
						if (players[iClient].fYER_Disguise_Remove_Timer > 1.5) {
							if (TF2_IsPlayerInCondition(iClient, TFCond_Disguised) && !TF2_IsPlayerInCondition(iClient, TFCond_Cloaked)) {
								TF2_RemoveCondition(iClient, TFCond_Disguised);
								players[iClient].fYER_Disguise_Remove_Timer = 0.0;
								EmitSoundToClient(iClient, "weapons/drg_pomson_drain_01.wav");
							}
						}
						else {
							players[iClient].fYER_Disguise_Remove_Timer += 0.015;
							SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
							ShowHudText(iClient, 2, "Disguise drops in: %.0f%%", 1.5 - players[iClient].fYER_Disguise_Remove_Timer);
						}
					}
					else {
						players[iClient].fYER_Disguise_Remove_Timer = 0.0;
					}
				}*/
		
				if (iMeleeIndex == 225 || iMeleeIndex == 574) {
					SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 2, "Knife: %.0f%%", 5.0 * players[iClient].fYER_Cooldown);
					
					if (players[iClient].fYER_Cooldown < 20.0) {
						players[iClient].fYER_Cooldown += 0.015;
					}
					else {
						players[iClient].fYER_Cooldown = 20.0;
					}
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
			
			// Update this every frame, after everything else
			players[iClient].iEquipped = iActive;
		}
	}
}

public Action RemoveMilk(Handle timer, int iClient) {
	players[iClient].bMilk_Wetness = false;
	return Plugin_Handled;
}

public Action RemoveCaC(Handle timer, int iClient) {
	players[iClient].bCac = false;
	return Plugin_Handled;
}

public Action RemoveBonk(Handle timer, int iClient) {
	players[iClient].bBonk = false;
	TF2Attrib_RemoveByName(iClient, "damage force reduction");
	return Plugin_Handled;
}

public Action RemoveSteak(Handle timer, int iClient) {
	players[iClient].bSteak_Buff = false;
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
	TF2Attrib_RemoveByName(iSecondary, "move speed bonus");
	return Plugin_Handled;
}

public Action FlameBeam(Handle timer, DataPack data) {

	// Extract the variables from the DataPack
	data.Reset();
	int iClient = data.ReadCell();
	float vecPos[3];
	data.ReadFloatArray(vecPos, sizeof(vecPos)); // Correctly read into vecPos array
	GetClientEyePosition(iClient, vecPos);

	float vecAng[3];
	data.ReadFloatArray(vecAng, sizeof(vecAng)); // Correctly read into vecAng array
	
	int iEntity;
	float vecEnd[3];
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int iPrimaryIndex = -1;
	if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
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
							
							float fDamage = 10.0 * fDmgMod * fDmgModTHREAT;
							
							if (iPrimaryIndex == 215) {
								fDamage = 9.0 * fDmgMod * fDmgModTHREAT;
							}
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
							if (players[iClient].fBaseball_Debuff_Timer <= 0.0) {
								players[iClient].fTHREAT_Timer += fDamage;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
							}
						}
						
						else if (StrEqual(class,"obj_sentrygun") || StrEqual(class,"obj_teleporter") || StrEqual(class,"obj_dispenser")) {		// Buildings
							float fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 450.0, 1.5, 1.0);		// Gives us our distance multiplier
							float fDmgModTHREAT = RemapValClamped(fDistance, 0.0, 450.0, 0.0, 0.5) * players[iClient].fTHREAT / 1000 + 1;
							
							float fDamage = 10.0 * fDmgMod * fDmgModTHREAT;
							int iDamagetype = DMG_IGNITE;
							
							SDKHooks_TakeDamage(iEntity, iPrimary, iClient, fDamage, iDamagetype, iPrimary, NULL_VECTOR, vecVictim);		// Deal damage
						}
						
						else if (StrEqual(class, "tf_projectile_pipe_remote") || StrEqual(class, "tf_projectile_pipe")) {		// Handles sticky destruction on hit
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
	return Plugin_Handled;
}

public Action RemoveChargeCrit(Handle timer, int iClient) {
	players[iClient].bCharge_Crit_Prepped = false;
	int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	char class[64];
	GetEntityClassname(iMelee, class, 64);
	if (StrEqual(class,"tf_weapon_katana") || StrEqual(class, "tf_weapon_sword")) {
		TF2Attrib_SetByDefIndex(iMelee, 264, 1.6);		// melee range multiplier (increased to 72 HU)
	}
	else {
		TF2Attrib_SetByDefIndex(iMelee, 264, 1.0);
	}
	return Plugin_Handled;
}

public Action TriggerHealing(int iClient) {
	int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
	int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
	if (iHealth >= iMaxHealth) return Plugin_Continue;
	
	float fHealing = RemapValClamped(players[iClient].fHeal_Penalty, -10.0, 5.0, 10.0, 4.0);
	int iHealing = RoundToFloor(fHealing);
	if (iHealing <= 0) return Plugin_Continue;
	
	TF2Util_TakeHealth(iClient, float(iHealing));
	Event event = CreateEvent("player_healonhit");
	if (event) {
		event.SetInt("amount", iHealing);
		event.SetInt("entindex", iClient);
		
		event.FireToClient(iClient);
		delete event;
	}
	
	return Plugin_Handled;
}

bool SingleTargetTraceFilter(int entity, int contentsMask, any data) {
	if(entity != data)
		return (false);
	return (true);
}

public void TF2_OnConditionAdded(int iClient, TFCond condition) {
	
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	//int iPrimaryIndex = -1;
	//if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	// Bleeding heal penalty
	if (condition == TFCond_Bleeding) {
		TF2Attrib_AddCustomPlayerAttribute(iClient, "health from healers reduced", 0.0);
		TF2Attrib_AddCustomPlayerAttribute(iClient, "health from packs increased", 0.0);
	}

	// Disable charge crits
	else if (condition == TFCond_CritDemoCharge) {
		TF2_RemoveCondition(iClient, TFCond_CritDemoCharge);
	}
	
	// Vaccinator Uber
	else if (condition == TFCond_UberBulletResist) {
		TF2_RemoveCondition(iClient, TFCond_UberBulletResist);
		TF2_RemoveCondition(iClient, TFCond_SmallBulletResist);
		players[iClient].fTHREAT = 1000.0;
		players[iClient].fTHREAT_Timer = 500.0;
		
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int iSecondaryIndex = -1;
		if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		if (iSecondaryIndex == 998) {		// Vaccinator (assume this is the Medic providing the effect)
			SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", 0.0);	// Reset the Uber bar
		}
	}
	
	// Crit-a-Cola and Bonk
	if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
		if (condition == TFCond_CritCola) {
			TF2_RemoveCondition(iClient, TFCond_CritCola);
			players[iClient].bCac = true;
			CreateTimer(8.0, RemoveCaC, iClient);
		}
		else if (condition == TFCond_Bonked) {
			TF2_RemoveCondition(iClient, TFCond_Bonked);
			TF2Attrib_AddCustomPlayerAttribute(iClient, "damage force reduction", 0.4);
			players[iClient].bBonk = true;
			CreateTimer(8.0, RemoveBonk, iClient);
		}
	}

	// Buff Banner TODO add Battalions
	if (TF2_GetPlayerClass(iClient) == TFClass_Soldier) {
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int iSecondaryIndex = -1;
		if (iSecondary != -1) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		
		if (condition == TFCond_Buffed && (iSecondaryIndex == 129 || iSecondaryIndex == 1001)) {
			TF2_RemoveCondition(iClient, TFCond_Buffed);
			players[iClient].fBuff_Banner = 4.0;
		}
	}
	
	// Re-enables Flare Gun Crits when Crit boosted
	else if (TF2_GetPlayerClass(iClient) == TFClass_Pyro) {
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		char class[64];
		GetEntityClassname(iSecondary, class, sizeof(class));
		if (StrEqual(class, "tf_weapon_flaregun")) {		// We disable Flare Gun Crits with the Cow Mangler Crit disable attributes
			if (isKritzed(iClient)) {		// Disable this attribute when we actually should be Critting
				TF2Attrib_SetByDefIndex(iSecondary, 869, 0.0);
			}
			else {
				TF2Attrib_SetByDefIndex(iSecondary, 869, 1.0);
			}
		}
	}
	// Re-enables charge melee Crits when Crit boosted
	else if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan) {
		int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
		if (isKritzed(iClient)) {		// Disable this attribute when we actually should be Critting
			TF2Attrib_SetByDefIndex(iMelee, 869, 0.0);
		}
		else {
			TF2Attrib_SetByDefIndex(iMelee, 869, 1.0);
		}
	}
	// Modify Steak buff
	else if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
		if (condition == TFCond_CritCola) {
			TF2_RemoveCondition(iClient, TFCond_CritCola);
			TF2_RemoveCondition(iClient, TFCond_RestrictToMelee);
			players[iClient].bSteak_Buff = true;
			CreateTimer(15.0, RemoveSteak, iClient);
		}
	}
	// Re-enables Huntsman Crits when Crit boosted
	else if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
		char class[64];
		GetEntityClassname(iPrimary, class, sizeof(class));
		if (StrEqual(class, "tf_weapon_compound_bow")) {
			if (isKritzed(iClient)) {		// Disable this attribute when we actually should be Critting
				TF2Attrib_SetByDefIndex(iPrimary, 869, 0.0);
			}
			else {
				TF2Attrib_SetByDefIndex(iPrimary, 869, 1.0);
			}
		}
	}
}

public void TF2_OnConditionRemoved(int iClient, TFCond condition) {
	//int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	//int iMeleeIndex = -1;
	//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");

	if (condition == TFCond_Bleeding) {
		TF2Attrib_RemoveByName(iClient, "health from packs increased");
		TF2Attrib_RemoveByName(iClient, "health from healers reduced");
	}
	
	if (TF2_GetPlayerClass(iClient) == TFClass_Pyro) {
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		char class[64];
		GetEntityClassname(iSecondary, class, sizeof(class));
		if (StrEqual(class, "tf_weapon_flaregun")) {
			if (!isKritzed(iClient)) {
				TF2Attrib_SetByDefIndex(iSecondary, 869, 1.0);
			}
		}
	}
	else if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		int iSecondaryIndex = -1;
		if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		if (iSecondaryIndex == 61 || iSecondaryIndex == 1006) {
			if (!isKritzed(iClient)) {
				TF2Attrib_SetByDefIndex(iSecondary, 869, 1.0);
			}
		}
	}
}

public void OnEntityCreated(int iEnt, const char[] classname) {
	if (IsValidEdict(iEnt)) {
		
		if (StrEqual(classname,"item_healthkit_medium")) {
			HookSingleEntityOutput(iEnt, "OnPlayerTouch", Output_OnPlayerTouch, true);
		}
		
		if (StrEqual(classname,"obj_sentrygun") || StrEqual(classname,"obj_dispenser") || StrEqual(classname,"obj_teleporter")) {
			entities[iEnt].fConstruction_Health = 0.0;
			SDKHook(iEnt, SDKHook_SetTransmit, BuildingThink);
			SDKHook(iEnt, SDKHook_OnTakeDamage, BuildingDamage);
		}
		
		else if(StrEqual(classname, "tf_weapon_handgun_scout_primary")) {
			//DHookEntity(dhook_CTFWeaponBase_SecondaryAttack, false, iEnt, _, DHookCallback_CTFWeaponBase_SecondaryAttack);
		}
		
		else if(StrEqual(classname, "tf_projectile_rocket")) {
			SDKHook(iEnt, SDKHook_SpawnPost, RocketSpawn);
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}
		
		else if(StrEqual(classname, "tf_projectile_energy_ball")) {
			SDKHook(iEnt, SDKHook_SpawnPost, OrbSpawn);
		}

		else if(StrEqual(classname, "tf_weapon_particle_cannon")) {
			//DHookEntity(dhook_CTFWeaponBase_SecondaryAttack, false, iEnt, _, DHookCallback_CTFWeaponBase_SecondaryAttack);
			SDKHook(iEnt, SDKHook_StartTouch, ProjectileTouch);
		}
		
		else if(StrEqual(classname, "tf_projectile_balloffire")) {
			SDKHook(iEnt, SDKHook_SpawnPost, fireballSpawn);
		}
		
		else if(StrEqual(classname,"tf_projectile_pipe")) {
			SDKHook(iEnt, SDKHook_SpawnPost, BombSpawn);
			SDKHook(iEnt, SDKHook_Think, PipeSet);
		}

		else if(StrEqual(classname,"tf_projectile_pipe_remote")) {
			entities[iEnt].bTrap = false;
			SDKHook(iEnt, SDKHook_SpawnPost, BombSpawn);
			CreateTimer(5.0, TrapSet, iEnt);		// This function swaps the sticky from rocket-style ramp-up to fixed damage
		}
		
		else if(StrEqual(classname, "tf_projectile_syringe")) {
			SDKHook(iEnt, SDKHook_SpawnPost, needleSpawn);
		}

		else if(StrEqual(classname, "tf_projectile_arrow")) {
			SDKHook(iEnt, SDKHook_SpawnPost, arrowSpawn);
		}
	}
}

public void OnEntityDestroyed(int entity) {
	if (!IsValidEntity(entity) || !IsValidEdict(entity)) return;
	
	char class[64];
	GetEntityClassname(entity, class, sizeof(class));
	if (StrEqual(class, "tf_projectile_jar_milk")) {		// Mad Milk
		MilkExplosion(entity);
	}
	
	else if (StrEqual(class, "tf_projectile_jar")) {		// Jarate
		PissExplosion(entity);
	}
}

public void MilkExplosion(int entity) {
	int iProjTeam = GetEntProp(entity, Prop_Data, "m_iTeamNum");
	float vecRocketPos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecRocketPos);
	
	for (int iTarget = 1; iTarget < MaxClients; iTarget++) {
		if (!IsValidClient(iTarget)) continue;
		if (GetEntProp(iTarget, Prop_Send, "m_iTeamNum") != iProjTeam) continue;
		
		float vecTargetPos[3];
		GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);

		if (GetVectorDistance(vecRocketPos, vecTargetPos) <= 200.0) {
			TF2Util_TakeHealth(iTarget, 75.0);
			players[iTarget].bMilk_Wetness = true;
			CreateTimer(10.0, RemoveMilk, iTarget);
			Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
			if (event && players[iTarget].iMilk_Cooldown == 0) {
				event.SetInt("amount", 75);
				event.SetInt("entindex", iTarget);
				
				event.FireToClient(iTarget);
				delete event;
			}
		}
	}
}

public void PissExplosion(int entity) {
	//int iOwner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	//if (!IsValidClient(iOwner)) return;
	int iProjTeam = GetEntProp(entity, Prop_Data, "m_iTeamNum");
	float vecRocketPos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", vecRocketPos);
	
	for (int iTarget = 1; iTarget <= MaxClients; iTarget++) {
		if (!IsValidClient(iTarget)) continue;
		if (GetEntProp(iTarget, Prop_Send, "m_iTeamNum") == iProjTeam) continue;
		
		float vecTargetPos[3];
		GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);
		float fDistance = GetVectorDistance(vecRocketPos, vecTargetPos);
		
		if (fDistance <= 200.0) {
			float fDamage = SimpleSplineRemapValClamped(fDistance, 0.0, 200.0, 50.0, 25.0);
			int iDamagetype = DMG_BLAST;
			//int iSecondary = TF2Util_GetPlayerLoadoutEntity(iOwner, TFWeaponSlot_Secondary, true);
			//SDKHooks_TakeDamage(iTarget, iSecondary, iOwner, fDamage, iDamagetype, iSecondary, NULL_VECTOR, NULL_VECTOR);
			SDKHooks_TakeDamage(iTarget, iTarget, iTarget, fDamage, iDamagetype, _, NULL_VECTOR, NULL_VECTOR);
		}
	}
}

void Output_OnPlayerTouch(const char[] output, int iEnt, int iCollector, float delay) {
	if (!IsValidClient(iCollector) || !IsValidEntity(iEnt)) return;
	
	int iThrower = GetEntPropEnt(iEnt, Prop_Send, "m_hOwnerEntity");
	if (iCollector == iThrower) return;
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iThrower, TFWeaponSlot_Secondary, true);
	float fCharge = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
	
	TF2Util_TakeHealth(iThrower, SimpleSplineRemapValClamped(fCharge, 0.0, 100.0, 0.0, 125.0));
	
	AcceptEntityInput(iEnt, "Kill");	
}

	// -={ Disable the Cow Mangler secondary fire entirely }=-

/*MRESReturn DHookCallback_CTFWeaponBase_SecondaryAttack(int entity) {
	return MRES_Supercede;
}*/

	// -={ Sniper Rifle headshot hit registration and various effects that trigger on certain hitscan hits }=-

Action TraceAttack(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& ammo_type, int hitbox, int hitgroup) {
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {
		if (hitgroup == 1 && (TF2_GetPlayerClass(attacker) == TFClass_Heavy || TF2_GetPlayerClass(attacker) == TFClass_Sniper || TF2_GetPlayerClass(attacker) == TFClass_Spy)) {		// Hitgroup 1 is the head
			players[attacker].iHeadshot_Frame = GetGameTickCount();		// We store headshot status in a variable for the next function to read
		}
		
		// Demoman disable charge full crits
		if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
			if (damage_type & DMG_SLASH) {
				if (players[attacker].bCharge_Crit_Prepped == false) {
					if (!isKritzed(attacker)) {
						damage_type &= ~DMG_CRIT;
					}
				}
				else {
					if (!isKritzed(attacker)) {
						damage_type &= ~DMG_CRIT;
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015);
					}
				}
			}
		}
		
		// Spy stun on Uber
		if (TF2_GetPlayerClass(attacker) == TFClass_Spy) {
			int iActive = GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon");
			int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
			if (iActive != iMelee) return Plugin_Continue;
			float vecPos[3], vecVictim[3], vecVictimFacing[3], vecDirection[3];
			GetClientEyePosition(attacker, vecPos); 
			GetClientEyePosition(victim, vecVictim);
			
			MakeVectorFromPoints(vecPos, vecVictim, vecDirection);		// Calculate direction we are aiming in
			GetClientEyeAngles(victim, vecVictimFacing);
			GetAngleVectors(vecVictimFacing, vecVictimFacing, NULL_VECTOR, NULL_VECTOR);
			
			float dotProduct = GetVectorDotProduct(vecDirection, vecVictimFacing);
			bool isBehind = dotProduct > 0.707;		// 90 degrees back angle
			
			// Uber stun
			if (TF2_IsPlayerInCondition(victim, TFCond_Ubercharged)) {
				if (isBehind) {
					TF2_StunPlayer(victim, 5.0, 0.0, TF_STUNFLAG_BONKSTUCK, attacker);
				}
			}
			
			// Your Eternal Reward explosion
			int iMeleeIndex = -1;
			if (iMelee != -1) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			if (iMeleeIndex == 225 || iMeleeIndex == 574) {
				YERExplosion(attacker, iMelee, isBehind);
				players[attacker].fYER_Cooldown = 0.0;
				ForceSwitchFromMeleeWeapon(attacker);
			}
		}
	}
	return Plugin_Continue;
}

public Action YERExplosion(int iClient, int iWeapon, bool bBackstab) {
	for (int iTarget = 1 ; iTarget <= MaxClients ; iTarget++) {		// The player being damaged
		if (IsValidClient(iTarget)) {
			float vecTargetPos[3], vecSpyPos[3];
			GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);
			GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", vecSpyPos);
			vecTargetPos[2] += 5.0;
			vecSpyPos[2] += 5.0;
			CreateParticle(iClient, "ExplosionCore_MidAir", 2.0);
			EmitAmbientSound("weapons/pipe_bomb1.wav", vecSpyPos, iClient);
			
			float fRadius = (bBackstab ? 288.0 : 144.0);	// Backstabs deal Crit damage in double the radius
			
			float fDist = GetVectorDistance(vecSpyPos, vecTargetPos);		// Store distance
			if (fDist <= fRadius && (TF2_GetClientTeam(iClient) != TF2_GetClientTeam(iTarget) || iClient == iTarget)) {
				Handle hndl = TR_TraceRayFilterEx(vecSpyPos, vecTargetPos, MASK_SOLID, RayType_EndPoint, PlayerTraceFilter, iClient);
				if (TR_DidHit(hndl) == false || IsValidClient(TR_GetEntityIndex(hndl))) {
					float damage = RemapValClamped(fDist, 0.0, fRadius, 60.0, 30.0);
					if (bBackstab) damage *= 3.0;
					
					int type = DMG_BLAST;
					if (iClient == iTarget) {
						damage == 100.0;
					}
					SDKHooks_TakeDamage(iTarget, iClient, iClient, damage, type, iWeapon, NULL_VECTOR, vecSpyPos, false);
				}
				delete hndl;
			}
		}
	}
	
	return Plugin_Handled;
}

	// -={ Handles everything that happens on weapon switch }=-
	
public Action WeaponSwitch(int iClient, int weapon) {
	
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		//int iActiveIndex = -1;
		//if(iActive > 0) iActiveIndex = GetEntProp(iActive, Prop_Send, "m_iItemDefinitionIndex");
		
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		//int iPrimaryIndex = -1;
		//if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
		
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		//int iSecondaryIndex = -1;
		//if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		
		int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
		int iMeleeIndex = -1;
		if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");

		// Half-Zatoichi
		if (iMeleeIndex == 357 && iActive == iMelee) {
			int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
			int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
			if (sequence != 8 && GetEntProp(iClient, Prop_Send, "m_iKillCountSinceLastDeploy") == 0.0) {
				SDKHooks_TakeDamage(iClient, iClient, iClient, 100.0, (DMG_SLASH|DMG_PREVENT_PHYSICS_FORCE), weapon, _, _, false);
			}
		}
		
		// Pain Train
		if (iMeleeIndex == 154 && weapon == iMelee) {
			int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
			int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
			if (sequence != 8 && GetEntProp(iClient, Prop_Send, "m_iKillCountSinceLastDeploy") == 0.0) {
				int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
				SDKHooks_TakeDamage(iClient, iClient, iClient, iMaxHealth * 0.25, (DMG_SLASH|DMG_PREVENT_PHYSICS_FORCE), iMelee, _, _, false);
			}
		}

		// Soldier
		if (TF2_GetPlayerClass(iClient) == TFClass_Soldier) {
			// Equalizer holster
			if (iActive == iMelee && (iMeleeIndex == 128)) {
				players[iClient].fTHREAT_Timer = 0.0;
			}
			// Escape Plan deploy
			else if (weapon == iMelee && iMeleeIndex == 775) {
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(iPrimary, iAmmoTable, 0, 4, true);
			}
		}
		
		// Heavy
		if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
			// Fists of Steel
			if (iMeleeIndex == 331) {
				if (iActive == iMelee) {
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					if (sequence != 8) {
						SDKHooks_TakeDamage(iClient, iClient, iClient, 125.0, (DMG_SLASH|DMG_PREVENT_PHYSICS_FORCE), iMelee, _, _, false);
					}
				}
				else if (weapon == iMelee) {
					SDKHooks_TakeDamage(iClient, iClient, iClient, -126.0, (DMG_SLASH|DMG_PREVENT_PHYSICS_FORCE), iMelee, _, _, false);	// Raise this number by 1 because otherwise it restores the wrong amount of health for some reason
				}
			}
		}

		// Medic
		if (TF2_GetPlayerClass(iClient) == TFClass_Medic) {
			// Ubersaw holster
			if (iActive == iMelee && (iMeleeIndex == 37 || iMeleeIndex == 1003)) {
				int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
				int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
				if (sequence != 8 && GetEntProp(iClient, Prop_Send, "m_iKillCountSinceLastDeploy") == 0.0) {
					float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
					if (fUber < 0.15) {
						SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", 0.0);
					}
					else {
						SetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel", fUber - 0.15);
					}
					EmitSoundToClient(iClient, "weapons/drg_pomson_drain_01.wav");
				}
			}
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
			
			bool bIsAttackFullCrit = false;
			
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
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			/*int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");*/
			
			int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
			int iMeleeIndex = -1;
			if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			int iVictimSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			int iVictimSecondaryIndex = -1;
			if(iVictimSecondary > 0) iVictimSecondaryIndex = GetEntProp(iVictimSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iVictimWatch = TF2Util_GetPlayerLoadoutEntity(victim, 6, true);
			int iVictimWatchIndex = -1;
			if(iVictimWatch > 0) iVictimWatchIndex = GetEntProp(iVictimWatch, Prop_Send, "m_iItemDefinitionIndex");
			
			// -== Victims ==-
			{
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
				
				// Bonk v1 buff
				if (players[victim].bBonk == true) {
					//PrintToChatAll("damage before: %f", damage);
					damage -= 6.0;
					//PrintToChatAll("damage after: %f", damage);
					if (damage < 0) {
						damage = 0.0;
					}
				}
				
				// Half-Zatoichi detect hits
				if (iWeaponIndex == 357) {
					if (GetEntProp(attacker, Prop_Send, "m_iKillCountSinceLastDeploy") != 1) {
						SetEntProp(attacker, Prop_Send, "m_iKillCountSinceLastDeploy", 1);
					}
				}
				
				// Razorback no block backstabs
				if (iVictimSecondaryIndex == 57 && damagecustom == TF_CUSTOM_BACKSTAB && damage == 0.0) {
					damage = 999.0;
				}
				
				// Cloak and Dagger no resistance
				if (TF2_IsPlayerInCondition(victim, TFCond_Cloaked) && iVictimWatchIndex == 60) {
					damage /= 0.8;
				}
			}
			
			// -== Attackers ==-
			// Pain Train
			if (iWeaponIndex == 154) {
				damage *= 1.25;
			}
			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if ((StrEqual(class, "tf_weapon_scattergun") || StrEqual(class, "tf_weapon_soda_popper") || StrEqual(class, "tf_weapon_pep_brawler_blaster")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Scale the ramp-up down to 150%
				}
				
				// Baby-Face's Blaster
				if (StrEqual(class, "tf_weapon_pep_brawler_blaster")) {	// TODO: put in ontakedamagepost
					if (fDmgMod * damage >= 30) {
						TF2_AddCondition(attacker, TFCond_SpeedBuffAlly, 2.5);
					}
				}
				
				// Flying Guillotine
				if (iWeaponIndex == 812 || iWeaponIndex == 833) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 0.75, 1.25);		// 25% ramp-up/fall-off
					TF2_RemoveCondition(victim, TFCond_Bleeding);
					if (!TF2_IsPlayerInCondition(victim, TFCond_Bleeding)) {
						// TODO: Make this not strip other bleeds
						RemoveBleed(victim);
					}
				}
				
				// Bat
				if (weapon == iMelee) {
					damage *= 1.1428571;	// 40 base damage
				}
				
				// Sandman
				else if (iWeaponIndex == 44) {
					if (attacker != inflictor) {
						damage *= 5 / 3;	// 25 damage
					}
				}
				
				// Boston Basher
				if (iWeaponIndex == 325) {
					if (TF2_IsPlayerInCondition(victim, TFCond_Bleeding)) {
						damage *= 1.35;
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015);		// Mini-Crits on Bleeding players
					}
				}
				
				// Sun-on-a-Stick
				if (iWeaponIndex == 349) {
					if (TF2Util_GetPlayerBurnDuration(attacker) > 0.0) {
						damage *= 1.4;
					}
				}
			}

			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if (weapon == iPrimary) {
					damage *= 0.888888;		// 80 base damage
				}
				if ((StrEqual(class, "tf_weapon_rocketlauncher") || StrEqual(class, "tf_weapon_rocketlauncher_airstrike") || (StrEqual(class, "tf_weapon_particle_cannon")) && damage_type & DMG_BLAST) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.6) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 140%
					if (iPrimaryIndex == 127) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 120%
					}
				}
				else	if (iPrimaryIndex == 414 && fDistance > 512.0) {		// Liberty Launcher
					fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Remove fall-off
				}
				if (iPrimaryIndex == 730) {		// Beggar's Bazooka
					if (entities[inflictor].iBazooka_Clip > 0) {
						
						// TODO: make this neater
						float DmgFrac, DmgFracMult;
						if (fDistance > 512.0) {
							DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
						else {
							DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.6);
						}
						DmgFrac = damage / DmgFracMult;
						
						if (entities[inflictor].iBazooka_Clip == 2) {
							if (DmgFrac < 48) {
								damage = 0.0;
							}
							else {
								damage *= SimpleSplineRemapValClamped(DmgFrac, 80.0, 48.0, 1.0, 0.833333);
							}
						}
						else if (entities[inflictor].iBazooka_Clip == 3) {
							if (DmgFrac < 56) {
								damage = 0.0;
							}
							else {
								damage *= SimpleSplineRemapValClamped(DmgFrac, 80.0, 56.0, 1.0, 0.714286);
							}
						}
					}
				}
				if (StrEqual(class, "tf_weapon_particle_cannon") && damage_type & DMG_BLAST && fDistance > 512.0) {		// Increase Cow Mangler fall-off
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				}
				
				if (weapon == iMelee) {
					damage *= 1.230769;		// 80 base damage
					
					if (iMelee == 416) {		// Market Gardener
						if (!(damage_type & DMG_CRIT)) {		// Less damage on non-Crits
							damage /= 2.0;
						}
						if (TF2_IsPlayerInCondition(victim, TFCond_BlastJumping)) {
							damage *= 0.8;		// Reduced damage on blast jumpers
						}
					}
				}
			}
			
			// Pyro
			if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				// Disables damage from fire particles
				if (StrEqual(class, "tf_weapon_flamethrower") && (damage_type & DMG_IGNITE) && !(damage_type & DMG_BLAST)) {
					if (damage_type & DMG_USE_HITLOCATIONS) {
						damage_type &= ~DMG_USE_HITLOCATIONS;
					}
					else {
						damage = 0.0;
					}
				}
				
				// Flare Guns
				else if (StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge")) {
					if (damage_type & DMG_BULLET) {
						damage *= 1.833333;
						if (fDistance < 512.0) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our ramp-up multiplier
						}
					}
				}
				
				// Scorch Shot
				if (!(damage_type & DMG_HALF_FALLOFF) && !(damage_type & DMG_BURN)) {
					TF2_RemoveCondition(victim, TFCond_Dazed);
					TF2_AddCondition(victim, TFCond_ImmuneToPushback, 0.015, attacker);
				}
				
				// Axtinguisher
				if (iWeaponIndex == 38 || iWeaponIndex == 457 || iWeaponIndex == 1000) {
					if (damage >= GetEntProp(victim, Prop_Send, "m_iHealth") && TF2Util_GetPlayerBurnDuration(victim) > 0.0) {
						TF2_AddCondition(attacker, TFCond_SpeedBuffAlly, 3.0);
					}
				}
				// Sharpened Volcano Fragment
				if (iWeaponIndex == 348) {
					if (TF2Util_GetPlayerBurnDuration(victim) <= 0.0) {
						damage *= 3.0;
						damage_type |= DMG_CRIT;
						bIsAttackFullCrit = true;
					}
				}
				// Neon Annihilator
				if (iWeaponIndex == 813 || iWeaponIndex == 834) {
					players[victim].fShocked = 6.0;
					if (players[victim].bMilk_Wetness == true) {
						damage *= 3.0;
						damage_type |= DMG_CRIT;
						bIsAttackFullCrit = true;
					}
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				// Stickies
				if (StrEqual(class, "tf_weapon_pipebomblauncher") && entities[inflictor].bTrap == false) {		// Only do this for recent stickies
					damage *= (5.0 / 6.0);
					// Quickiebomb Launcher consistant damage with distance
					if (iWeaponIndex == 1150) {
						if (fDistance < 512.0) {
							fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);
						}
						else {
							fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
					}
					else {
						if (fDistance < 512.0) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.7) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Scale the ramp-up up to 140%
						}
						else {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Scale the fall-off up to 75%
						}
					}
				}
				else if (iWeaponIndex == 131 || iWeaponIndex == 406 || iWeaponIndex == 1144 || iWeaponIndex == 1099) {
					float meter = GetEntPropFloat(attacker, Prop_Send,"m_flChargeMeter");
					damage = 60.0;
					fDmgMod = SimpleSplineRemapValClamped(meter, 40.0, 100.0, 1.0, 0.68);		// Base damage increased 50 -> 60; min damage increased 16 -> 30
					damage *= fDmgMod;
					if (iWeaponIndex == 1099) {		// Restore 50% meter on Tide Turner bash						
						DataPack pack = new DataPack();
						pack.Reset();
						pack.WriteCell(attacker);
						RequestFrame(updateShield, pack);
					}
				}
				
				// Remove shield bash Crit
				else if (weapon == iMelee) {
					if (players[attacker].bCharge_Crit_Prepped == true) {
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015);
					}
					/*else if (!isKritzed(attacker) & !isMiniKritzed(attacker, victim)) {
						
					}*/
				}
				
				// Loose Cannon
				if (iWeaponIndex == 996) {
					RequestFrame(CannonKnockback, victim);
				}
				
				// Shield bash no knockback and long-range Mini-Crit
				if (iWeaponIndex == 131 || iWeaponIndex == 406 || iWeaponIndex == 1099 || iWeaponIndex == 1144) {
					damage_type |= DMG_PREVENT_PHYSICS_FORCE;
					float fCharge = GetEntPropFloat(attacker, Prop_Send, "m_flChargeMeter");
					if (fCharge <= 40.0) {
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015);
						damage *= 1.35;
					}
				}
			}

			// Heavy
			if (TF2_GetPlayerClass(attacker) == TFClass_Heavy) {
				// Natascha
				if (iWeaponIndex == 41) {
					damage = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 21.0, 7.0);
					
					if (damage_type & DMG_CRIT != 0) {
						if (isKritzed(attacker)) damage = 42.0;
						else if (isMiniKritzed(attacker, victim)) {
							if (fDistance < 512.0) damage *= 1.35;
							else damage = 21.0 * 1.35;
						}
						else damage *= 2.0;
					}
				}
				
				if (StrEqual(class, "tf_weapon_minigun")) {
					damage *= SimpleSplineRemapValClamped(players[attacker].fSpeed, 0.0, 1.005, 1.0, 0.666);		// Scale damage up from -33% to base as we fire
				}
				
				else if (StrEqual(class, "tf_weapon_shotgun_hwg") || StrEqual(class, "tf_weapon_shotgun")) {
					damage *= 1.1;
				}
				
				// Family Business
				if (iWeaponIndex == 425) {
					if (players[attacker].iHeadshot_Frame == GetGameTickCount()) {
						damage *= 1.35;
						TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015, 0);
					}
				}
				
				if (weapon == iMelee) {
					damage *= 1.230769;		// 80 base damage
				}
				if (iWeaponIndex == 310) {		// Detect Warrior's Spirit hits
					if (GetEntProp(attacker, Prop_Send, "m_iKillCountSinceLastDeploy") != 1) {
						SetEntProp(attacker, Prop_Send, "m_iKillCountSinceLastDeploy", 1);
					}
				}
			}
			
			// Medic
			if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {
					
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
					if (iWeaponIndex == 412) {		// Overdose
						damage = 7.0;
					}
					else {
						damage = 10.0;
					}
				}
				else if (iWeaponIndex == 37 || iWeaponIndex == 1003) {		// Detect Ubersaw hits
					if (GetEntProp(attacker, Prop_Send, "m_iKillCountSinceLastDeploy") != 1) {
						SetEntProp(attacker, Prop_Send, "m_iKillCountSinceLastDeploy", 1);
					}
				}
			}
			
			// Sniper
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
				// Rifle custom ramp-up/fall-off and Mini-Crit headshot damage
				if (StrEqual(class, "tf_weapon_sniperrifle") || StrEqual(class, "tf_weapon_sniperrifle_decap") || StrEqual(class, "tf_weapon_sniperrifle_classic")) {
					
					//PrintToChatAll("headshot frame: %i", players[attacker].iHeadshot_Frame);
					//PrintToChatAll("game frame: %i", GetGameTickCount());
					
					damage = 45.0;		// We're overwriting the Rifle charge behaviour so we manually set the baseline damage here
					if (iWeaponIndex == 526) {		// Machina damage bonus
						damage *= 1.15;
					}
					float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
					fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 1.75);		// Apply up to 75% bonus damage depending on charge
					damage *= fDmgMod;
					
					if (isKritzed(attacker)) {
						damage *= 3;
					}
					
					/*if (iWeaponIndex == 230) {		// Sydney Sleeper
						if (TF2_IsPlayerInCondition(victim, TFCond_Jarated)) {
							damage *= 1.35;
						}
						TF2_AddCondition(victim, TFCond_Jarated, RemapValClamped(fCharge, 0.0, 150.0, 2.0, 6.0));		// 2-6 sec duration
						players[victim].iJarated = attacker;		// Record the ID of the victim to steal their THREAT
						if (fDistance < 512.0) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up multiplier
						}
					}*/
					
					else if (players[attacker].iHeadshot_Frame == GetGameTickCount()) {		// Here we look at headshot status
						if (StrEqual(class, "tf_weapon_sniperrifle_classic")) {
							if (fCharge >= 150.0) {
								damage_type |= DMG_CRIT;		// Apply a Crit
								fDmgMod *= 2.0;
								damagecustom = TF_CUSTOM_HEADSHOT;		// No idea if this does anything, honestly
							}
							else {
								fDmgMod *= 1.35;
								TF2_AddCondition(victim, TFCond_MarkedForDeathSilent, 0.015, 0);
							}
						}
						else {
							damage_type |= DMG_CRIT;		// Apply a Crit
							fDmgMod *= 2.0;
							damagecustom = TF_CUSTOM_HEADSHOT;		// No idea if this does anything, honestly
						}
						
						if (GetEntProp(victim, Prop_Send, "m_iHealth")) {	// Heatmaker headshot
							if (iWeaponIndex == 752) {
								TF2Attrib_AddCustomPlayerAttribute(attacker, "fire rate bonus HIDDEN", 0.75);
								TF2Attrib_AddCustomPlayerAttribute(attacker, "sniper fires tracer HIDDEN", 1.0);
								players[attacker].fFocus_Timer = 5.0;
							}
						}
					}
					
					else if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Gives us our ramp-up multiplier
					}
					
					if (iWeaponIndex == 402) {	// Bazaar Bargain Head damage boost
						int iHeads = GetEntProp(attacker, Prop_Send, "m_iDecapitations");
						damage *= SimpleSplineRemapValClamped(iHeads * 1.0, 0.0, 5.0, 1.0, 1.5);	
					}
				}
				
				// Huntsman
				else if (StrEqual(class, "tf_weapon_compound_bow")) {
					fDmgMod = RemapValClamped(damage, 50.0, 120.0, 1.2, 1.0);		// Scale min damage up to 60
				}
				
				// Tribalman's Shiv
				else if (iWeaponIndex == 171) {
					if (TF2_IsPlayerInCondition(victim, TFCond_Bleeding)) {
						damage_type |= DMG_CRIT;		// Crits on Bleeding players
						damage *= 3.0;
					}
				}
			}
			
			// Spy
			if (TF2_GetPlayerClass(attacker) == TFClass_Spy) {
				if (weapon == iSecondary) {
					damage *= 1.25;
				}
				if ((iWeaponIndex == 61 || iWeaponIndex == 1006) && players[attacker].iHeadshot_Frame == GetGameTickCount() && GetGameTime() - GetEntPropFloat(iSecondary, Prop_Send, "m_flLastFireTime") >= 1.0) {		// Ambassador
					damage_type |= DMG_CRIT;
					damage = 82.5;
				}
				else if (StrEqual(class, "tf_weapon_revolver") && iWeaponIndex != 460 && fDistance < 512.0) {		// Scale non-Enforcer ramp-up down to 120
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
					if (iWeaponIndex == 356) {	// Conniver's Kunai lifesteal
					
						int iVictimHealth = GetEntProp(victim, Prop_Send, "m_iHealth");
						int iHealing = iVictimHealth < 75 ? 75 : iVictimHealth;
						
						SetEntProp(attacker, Prop_Send, "m_iHealth", GetEntProp(attacker, Prop_Send, "m_iHealth") + iHealing);
						Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
						if (event) {
							event.SetInt("amount", iHealing);
							event.SetInt("entindex", attacker);
							
							event.FireToClient(attacker);
							delete event;
						}
					}
				}
			}
			
			damage *= fDmgMod;		// This applies *all* ramp-up/fall-off modifications for all classes
			
			// THREAT modifier
			if (players[attacker].fTHREAT > 0.0 && !isKritzed(attacker) && !bIsAttackFullCrit) {
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
				// Pyro
				(StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge") && damage_type & DMG_BULLET) ||
				// Sniper (bodyshots)
				StrEqual(class, "tf_weapon_sniperrifle")) {		// No fall-off
					if (fDistance < 512.0) {
						fDmgModTHREAT = (1.5/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					else {
						fDmgModTHREAT = 0.5 * players[attacker].fTHREAT/1000 + 1;
					}
				}
				else if (
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher") ||	// +40
				StrEqual(class, "tf_weapon_rocketlauncher_airstrike") ||
				(StrEqual(class, "tf_weapon_particle_cannon") && damage_type & DMG_BLAST) ||
				// Demoman
				(StrEqual(class, "tf_weapon_pipebomblauncher") && iWeaponIndex != 1150)) {
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
				else if (((damage_type & DMG_CLUB || damage_type & DMG_SLASH) || StrEqual(class, "tf_wearable_demoshield")) && !StrEqual(class, "tf_weapon_knife")) {	// Handle melee and shield bash damage (not knives)
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
					else if (iMeleeIndex != 43 && iMeleeIndex != 327 && iMeleeIndex != 329) {		// No THREAT for KGB, Claid or Jag
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
	if (victim >= 1 && victim <= MaxClients && victim == attacker) {		// Self-damage
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			//PrintToChat(victim, "Weapon: %i", iWeaponIndex);
			if (iWeaponIndex == 357) {		// Zatoichi Honourbound damage
				damage *= 2.0;
			}
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			if (iWeaponIndex == 325) {		// Boston Basher
				damage *= 2.0;
				if (!(damage_type & DMG_CLUB)) {
					damage = 0.0;		// Disable Bleed damage
				}
			}
		}
	}
	
	if (victim >= 1 && victim <= MaxClients) {
		// Nullify Afterburn damage
		if (damage_type & DMG_BURN && damage >= 4.0 && damage <= 5.0) {
			if (GetEntProp(victim, Prop_Send, "m_iHealth") <= 1) damage = 0.0;
			else damage = 1.0;
		}
		
		// Nullify Bleed damage (it uses DMG_SLASH for some reason)
		if (damage_type & DMG_SLASH && damage >= 4.0 && damage <= 5.0) {
			damage = 0.0;
		}
	}
	
	/*if (victim >= 1 && victim <= MaxClients) {		// Trigger this on any damage source, but still make sure the victim exists
		if (damage == 1.0 && players[victim].fAfterburn_DMG_tick > 0.0) {
			damage = 0.0;
		}
	}*/

	// Sentry damage
	if (attacker >= 1 && IsValidEdict(attacker) && attacker >= 1 && attacker <= MaxClients) {
		if (IsValidEdict(inflictor) && weapon) {
			GetEntityClassname(inflictor, class, sizeof(class));		// Retrieve the inflictor
			//if (StrEqual(class,"obj_sentrygun")) {		// Handle Sentry bullet damage
			//	ScaleVector(damageForce, 0.5);
			//}
			if (StrEqual(class,"tf_projectile_sentryrocket")) {		// Handle explosive damage from sentry rockets
				float vecAttacker[3];
				float vecVictim[3];
				GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
				float fDmgMod = 1.0;		// Distance mod
				GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets Engineer position
				float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
				fDmgMod = 1 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				damage *= fDmgMod;
			}
			
			if (players[victim].bBonk == true) {
				//PrintToChatAll("damage before: %f", damage);
				damage -= 6.0;
				//PrintToChatAll("damage after: %f", damage);
				if (damage < 0) {
					damage = 0.0;
				}
			}
		}
	}
	
	return Plugin_Changed;
}


public void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damage_type, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients && victim != attacker) {
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));
			int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			
			// Add THREAT
			if (players[attacker].fBaseball_Debuff_Timer <= 0.0) {
				players[attacker].fTHREAT += damage;
				if (players[attacker].fTHREAT > 1000.0) {
					players[attacker].fTHREAT = 1000.0;
				}
				if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
					players[attacker].fTHREAT_Timer += damage * 1.429;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
				}
				else if (players[attacker].bIsDemoknight || TF2_GetPlayerClass(attacker) == TFClass_Medic || TF2_GetPlayerClass(attacker) == TFClass_Sniper || TF2_GetPlayerClass(attacker) == TFClass_Spy) {
					players[attacker].fTHREAT_Timer += damage * 2.0;
				}
				else {
					players[attacker].fTHREAT_Timer += damage;
				}
			}
				
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iVictimSecondary = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Secondary, true);
			int iVictimSecondaryIndex = -1;
			if(iVictimSecondary > 0) iVictimSecondaryIndex = GetEntProp(iVictimSecondary, Prop_Send, "m_iItemDefinitionIndex");

			int iVictimMelee = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Melee, true);
			int iVictimMeleeIndex = -1;
			if(iVictimMelee > 0) iVictimMeleeIndex = GetEntProp(iVictimMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			// -== Victims ==-
			// Scout
			if (TF2_GetPlayerClass(victim) == TFClass_Scout) {
				
				// Double jump disable
				if (!((GetEntityFlags(victim) & FL_ONGROUND) || iVictimSecondaryIndex == 449)) {		// Winger exception
					players[victim].fAirjump += damage;		// Records the damage we take while airborne (resets on landing; handled in OnGameFrame)
				}
				
				// Sandman
				if (attacker != inflictor) {
					if (IsPlayerAlive(victim)) {
					
						int iVictimActive = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
						if (iVictimActive == 44) {
							players[victim].fTHREAT -= 0.5 * damage;
						}
					}
				}
			}
			
			// Soldier
			if (TF2_GetPlayerClass(victim) == TFClass_Soldier) {
				
				if (iVictimSecondaryIndex == 444) {		// Mantreads
					players[victim].fMantreads_OOC_Timer = 0.0;
				}
			}
			
			// Spy
			else if (TF2_GetPlayerClass(victim) == TFClass_Spy) {

				// Enforcer
				if (iVictimSecondaryIndex == 460) {
					if (TF2_IsPlayerInCondition(victim, TFCond_Disguised) || TF2_IsPlayerInCondition(victim, TFCond_Cloaked)) {
						players[victim].fDamage_Recieved_Enforcer += damage;	
					}
				}
			}
			
			// -== Attackers ==-
			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				// Force-A-Nature
				if (iWeaponIndex == 45 || iWeaponIndex == 1078) {

					float vecAttacker[3], vecVictim[3], vecVelVictim[3];
					GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);
					GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);
					GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vecVelVictim);
					float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);
					
					if (fDistance < 750.0 && damage >= 30.0) {
						float fForce = damage * 12.0 * 1.1;	// 1.0x knockback force
						
						if (TF2_GetPlayerClass(victim) == TFClass_Heavy) {
							fForce *= 0.5;
						}
						
						float vecDir[3];
						MakeVectorFromPoints(vecAttacker, vecVictim, vecDir); // vecDir = victim - attacker
						NormalizeVector(vecDir, vecDir);                      // Make it a unit vector

						ScaleVector(vecDir, fForce);                // vecForce = vecDir * fForce
						if (GetEntityFlags(victim) & FL_ONGROUND) {
							if (vecDir[2] < 0.0) {
								vecDir[2] *= -0.25;
							}
						}
						vecDir[2] += 200.0;
						//PrintToChatAll("vecDir1: %f", vecDir[0]);
						//PrintToChatAll("vecDir2: %f", vecDir[1]);
						//PrintToChatAll("vecDir3: %f", vecDir[2]);
						AddVectors(vecVelVictim, vecDir, vecVelVictim);

						TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vecVelVictim); // Apply force
					}
				}
				// Pretty Boy's Pocket Pistol heal on hit
				else if (iWeaponIndex == 773) {
					TF2Util_TakeHealth(attacker, damage * 0.25);
					Event eventHeal = CreateEvent("player_healonhit");
					if (eventHeal) {
						eventHeal.SetInt("amount", RoundFloat(damage * 0.25));
						eventHeal.SetInt("entindex", attacker);
						
						eventHeal.FireToClient(attacker);
						delete eventHeal;
					}
				}
				// Sandman THREAT steal and debuff
				else if (iWeaponIndex == 44) {
					float vecAttacker[3], vecVictim[3], vecVelVictim[3];
					GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);
					GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);
					GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vecVelVictim);
					float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);
					
					float fDrainPercentage = RemapValClamped(fDistance, 0.0, 1024.0, 0.0, 1.0);
					
					float fTHREATSteal = players[victim].fTHREAT * fDrainPercentage;
					players[victim].fTHREAT -= fTHREATSteal;
					players[attacker].fTHREAT += fTHREATSteal;
					players[victim].fBaseball_Debuff_Timer = 2.0 + 6.0 * fTHREATSteal;		// 2-8 sec duration
				}
			}
			
			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if (iWeaponIndex == 228 || iWeaponIndex == 1085) {		// Black Box
					TF2Util_TakeHealth(attacker, damage / 6);
					Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
					if (event) {
						event.SetInt("amount", RoundFloat(damage / 6));
						event.SetInt("entindex", attacker);
						
						event.FireToClient(attacker);
						delete event;
					}
				}
				if (iSecondaryIndex == 444) {		// Mantreads
					players[victim].fMantreads_OOC_Timer = 0.0;
				}
			}
			
			// Pyro
			else if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				// Scorch Shot
				if (iWeaponIndex == 740) {

					float vecFlare[3], vecVictim[3], vecVelVictim[3];
					GetEntPropVector(inflictor, Prop_Send, "m_vecOrigin", vecFlare);
					GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);
					vecVictim[2] -= 40.0;
					GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vecVelVictim);
					//float fDistance = GetVectorDistance(vecFlare, vecVictim, false);
					
					if (damage >= 30.0) {
						float fForce = damage * 12.0 * 3.0;	// 3x knockback force
						
						if (TF2_GetPlayerClass(victim) == TFClass_Heavy) {
							fForce *= 0.5;
						}
						
						float vecDir[3];
						MakeVectorFromPoints(vecFlare, vecVictim, vecDir); // vecDir = victim - flare
						NormalizeVector(vecDir, vecDir);                      // Make it a unit vector

						ScaleVector(vecDir, fForce);                // vecForce = vecDir * fForce
						vecDir[2] += 20.0;
						AddVectors(vecVelVictim, vecDir, vecVelVictim);

						TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vecVelVictim); // Apply force
					}
				}
				
				// Axtinguisher
				if (iWeaponIndex == 38 || iWeaponIndex == 457 || iWeaponIndex == 1000) {
					players[attacker].fAxe_Cooldown = 0.0;
					ForceSwitchFromMeleeWeapon(attacker);
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				// Persian Persuader
				if (iWeaponIndex == 404) {
				
					if (iPrimaryIndex != 1101 && iPrimaryIndex != 405 && iPrimaryIndex != 608) {		// Make sure we actually have a launcher in this slot
						int iPrimaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");		// Reserve ammo
						int iPrimaryReserves = GetEntProp(attacker, Prop_Data, "m_iAmmo", _, iPrimaryAmmo);
						
						if (iPrimaryReserves >= 4) {
							SetEntProp(attacker, Prop_Data, "m_iAmmo", 6, _, iPrimaryAmmo);
						}
						else {
							SetEntProp(attacker, Prop_Data, "m_iAmmo", iPrimaryReserves + 2, _, iPrimaryAmmo);
						}
					}
					
					if (iSecondaryIndex != 131 && iSecondaryIndex != 406 && iSecondaryIndex != 1099 && iSecondaryIndex != 1144) {
						int iSecondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
						int iSecondaryReserves = GetEntProp(attacker, Prop_Data, "m_iAmmo", _, iSecondaryAmmo);
						
						if (iSecondaryReserves >= 4) {
							SetEntProp(attacker, Prop_Data, "m_iAmmo", 6, _, iSecondaryAmmo);
						}
						else {
							SetEntProp(attacker, Prop_Data, "m_iAmmo", iSecondaryReserves + 2, _, iSecondaryAmmo);
						}
					}
				}
				// Loose Cannon
				if (iWeaponIndex == 996) {

					float vecAttacker[3], vecVictim[3], vecVelVictim[3];
					GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);
					GetEntPropVector(victim, Prop_Send, "m_vecOrigin", vecVictim);
					GetEntPropVector(victim, Prop_Data, "m_vecVelocity", vecVelVictim);
					//float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);
					
					if (damage >= 30.0) {
						float fForce = damage * 12.0 * 1.5;	// 1.5x knockback force
						
						if (TF2_GetPlayerClass(victim) == TFClass_Heavy) {
							fForce *= 0.5;
						}
						
						float vecDir[3];
						MakeVectorFromPoints(vecAttacker, vecVictim, vecDir); // vecDir = victim - attacker
						NormalizeVector(vecDir, vecDir);                      // Make it a unit vector

						ScaleVector(vecDir, fForce);                // vecForce = vecDir * fForce
						AddVectors(vecVelVictim, vecDir, vecVelVictim);

						TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, vecVelVictim); // Apply force
					}
				}
			}

			// Heavy
			else if (TF2_GetPlayerClass(attacker) == TFClass_Heavy) {
				// Huo-Long Heater
				if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 811 || GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") == 832) {

					players[victim].fTempLevel += damage;
					if (players[victim].fTempLevel >= 30.0 && TF2Util_GetPlayerBurnDuration(victim) < 4.0) {
						TF2Util_SetPlayerBurnDuration(victim, 4.0);
					}
				}
			}
			
			// Spy
			/*else if (TF2_GetPlayerClass(attacker) == TFClass_Spy) {
				// Your Eternal Reward
				if (iWeaponIndex == 225 || iWeaponIndex == 574) {
					players[attacker].fYER_Cooldown = 0.0;
					ForceSwitchFromMeleeWeapon(attacker);
				}	
			}*/
			
			// Half-Zatoichi
			if (StrEqual(class,"tf_weapon_katana")) {
				TF2Util_TakeHealth(attacker, 15.0);
				Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
				if (event) {
					event.SetInt("amount", 25);
					event.SetInt("entindex", attacker);
					
					event.FireToClient(attacker);
					delete event;
				}
			}
		}
	}
	if (victim >= 1 && victim <= MaxClients) {		// Trigger this on any damage source, but still make sure the victim exists
		// Reduce Medi-Gun healing on victim
		players[victim].fHeal_Penalty_Timer += damage;
		
		/*if (damage == 1.0 && players[victim].fAfterburn_DMG_tick > 0.0) {
			players[victim].fAfterburn_DMG_tick = 0.5;
		}*/
		
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			//int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			if (iSecondaryIndex == 444) {		// Mantreads
				players[victim].fMantreads_OOC_Timer = 0.0;
			}
		}
		//players[victim].fHeal_Penalty = 5.0;
		//TF2Attrib_AddCustomPlayerAttribute(victim, "health from healers reduced", 0.5);
	}
}


public Action RemoveBleed(int iClient) {
	if (!(IsValidClient(iClient) && IsPlayerAlive(iClient))) return Plugin_Handled;
	TF2_RemoveCondition(iClient, TFCond_Bleeding);
	return Plugin_Handled;	
}

	// -={ Generates Uber from healing }=-

public Action OnPlayerHealed(Event event, const char[] name, bool dontBroadcast) {
	int iPatient = GetClientOfUserId(event.GetInt("patient"));
	int iHealer = GetClientOfUserId(event.GetInt("healer"));
	int iHealing = event.GetInt("amount");

	if (iPatient >= 1 && iPatient <= MaxClients && iHealer >= 1 && iHealer <= MaxClients && iPatient != iHealer) {
		if (TF2_GetPlayerClass(iHealer) == TFClass_Medic) {
			if (!(TF2_IsPlayerInCondition(iHealer, TFCond_Ubercharged) || TF2_IsPlayerInCondition(iHealer, TFCond_Kritzkrieged) || TF2_IsPlayerInCondition(iHealer, TFCond_MegaHeal))) {
				int iSecondary = TF2Util_GetPlayerLoadoutEntity(iHealer, TFWeaponSlot_Secondary, true);
				int iSecondaryIndex = -1;
				if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
				
				int iActive = GetEntPropEnt(iHealer, Prop_Send, "m_hActiveWeapon");
				int iActiveIndex = -1;
				if(iActive > 0) iActiveIndex = GetEntProp(iActive, Prop_Send, "m_iItemDefinitionIndex");
				
				float fUber = GetEntPropFloat(iSecondary, Prop_Send, "m_flChargeLevel");
				// Amputator healing
				if (iActiveIndex == 304) {
					fUber += iHealing * 0.00125 * 0.75;
				}
				// Ratio changed to 1% per 8 HP
				else if (iSecondaryIndex == 35) {		// Kritzkreig
					fUber += iHealing * 0.00125 * 1.25;		// Add this to our Uber amount (multiply by 0.001 as 1 HP -> 1%, and Uber is stored as a 0 - 1 proportion)
				}
				else if (iSecondaryIndex == 998) {		// Vaccinator
					fUber += 0.00125 * 3.0;
					players[iPatient].fTHREAT += iHealing;
					players[iPatient].fTHREAT_Timer += iHealing;
					if (players[iPatient].fTHREAT > 1000.0) {
						players[iPatient].fTHREAT = 1000.0;
					}
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
	}
	
	//PrintToChatAll("Timer: %f", players[iPatient].fHeal_Penalty);
	
	// Debugging
	/*if (iPatient >= 1 && iPatient <= MaxClients) {
		PrintToChat(iPatient, "Healing: %i", iHealing);
	}*/

	if (iPatient >= 1 && iPatient <= MaxClients && iHealer >= 1 && IsValidEntity(iHealer)) {
		char class[64];
		GetEntityClassname(iHealer, class, 64);
		if (StrEqual(class,"obj_dispenser") && players[iPatient].fHeal_Penalty < -5.0) {
			float BonusHeal;
			BonusHeal = iHealing * RemapValClamped(players[iPatient].fHeal_Penalty, -5.0, -10.0, 1.0, 3.0);
			TF2Util_TakeHealth(iPatient, BonusHeal);
			//PrintToChat(iPatient, "Healing: %i", BonusHeal);
		}
	}

	return Plugin_Continue;
}


public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		
		int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		int iActiveIndex = -1;
		if (iActive > 0) iActiveIndex = GetEntProp(iActive, Prop_Send, "m_iItemDefinitionIndex");
		
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		int iPrimaryIndex = -1;
		if(iPrimary != -1) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
		
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
		//int iSecondaryIndex = -1;
		//if(iSecondary != -1) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		
		int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);

		char class[64];
		GetEntityClassname(iSecondary, class, sizeof(class));
		
		// Scout
		if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
		
			// Force-A-Nature jump
			if ((iPrimaryIndex == 45 || iPrimaryIndex == 1078) && iActive == iPrimary) {
				if (buttons & IN_ATTACK2 && buttons & IN_ATTACK) {
					if (GetEntPropFloat(iPrimary, Prop_Data, "m_flNextPrimaryAttack") < GetGameTime()) {
						
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
						
						vecForce[2] += 50.0;		// Some fixed upward force to make the jump feel beter
						AddVectors(vecVel, vecForce, vecForce);		// Add the Airblast push force to our velocity
						//AddVectors(vecProjection, vecForce, vecForce); This bit is terrible
						
						TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, vecForce);		// Sets the Pyro's momentum to the appropriate value
						
					}
				}
			}
			
			// Shortstop disable shove
			else if (iPrimaryIndex == 220 && iActive == iPrimary) {
				if (buttons & IN_ATTACK2) {
					buttons &= ~IN_ATTACK2;
				}
			}
			
			// Fan O'War
			if (iMelee == iActive && iActiveIndex == 355 && buttons & IN_ATTACK) {
				TeammateWhip(iClient, 2);
			}
		}
		
		// Soldier
		if (TF2_GetPlayerClass(iClient) == TFClass_Soldier) {
			// Mangler disable alt-fire
			if (iPrimaryIndex == 441 && iActive == iPrimary) {
				if (buttons & IN_ATTACK2) {
					buttons &= ~IN_ATTACK2;
				}
			}
			
			// Disciplinary Action
			if (iMelee == iActive && iActiveIndex == 447 && buttons & IN_ATTACK) {
				TeammateWhip(iClient, 2);
			}
		}
		
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
									if (StrEqual(class, "tf_projectile_pipe_remote")) {		// Check if the new entity is a sticky bomb
							
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
		
		// Engineer
		else if (TF2_GetPlayerClass(iClient) == TFClass_Engineer) {
			if (buttons & IN_RELOAD && !(players[iClient].iLastButtons & IN_RELOAD) && ((iActive == iMelee && iActiveIndex != 589) || iActiveIndex == 25 || iActiveIndex == 737 || iActiveIndex == 26)) {		// Swaps PDA
				Command_PDA(iClient, 0);
			}
		}
		
		players[iClient].iLastButtons = buttons;		// Stores buttons for next frame
	}
	return Plugin_Continue;
}

public Action TeammateWhip(int iClient, int iClass) {
	float pos1[3], pos2[3];
	GetClientEyePosition(iClient, pos1);
	GetClientEyeAngles(iClient, pos2);
	GetAngleVectors(pos2, pos2, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(pos2, 82.0);
	AddVectors(pos1, pos2, pos2);
	
	float maxs[3], mins[3];
	
	maxs[0] = 23.0;
	maxs[1] = 23.0;
	maxs[2] = 23.0;
	
	mins[0] = (0.0 - maxs[0]);
	mins[1] = (0.0 - maxs[1]);
	mins[2] = (0.0 - maxs[2]);
	
	TR_TraceHullFilter(pos1, pos2, mins, maxs, MASK_SOLID, TraceFilter_ExcludeSingle, iClient);
	
	if (TR_DidHit()) {
		int iEntity = TR_GetEntityIndex();
		if (iEntity >= 1 && iEntity <= MaxClients && GetClientTeam(iEntity) == GetClientTeam(iClient)) {
			TF2_AddCondition(iEntity, TFCond_SpeedBuffAlly, 2.0);
			if (iClass == 2) TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, 4.0);	// Soldier speeds himself too
		}
	}
	return Plugin_Handled;
}

public Action AutoreloadPistol(Handle timer, int iClient) {
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);		// Retrieve the secondary weapon
	int iSecondaryIndex = -1;
	if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
	
	char class[64];
	GetEntityClassname(iSecondary, class, sizeof(class));		// Retrieve the weapon
	
	if (StrEqual(class, "tf_weapon_pistol") || StrEqual(class, "tf_weapon_pistol_scout") || StrEqual(class, "tf_weapon_handgun_scout_secondary")) {		// If we have a pistol equipped
		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		
		int iClipMax = 12;
		
		int clip = GetEntData(iSecondary, iAmmoTable, 4);		// Retrieve the loaded ammo of our pistol
		int ammoSubtract = iClipMax - clip;		// Don't take away more ammo than is nessesary
		
		int primaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve secondary ammo
		
		if (clip < iClipMax && ammoCount > 0) {
			if (ammoCount < iClipMax) {		// Don't take away more ammo than we actually have
				ammoSubtract = ammoCount;
			}
			SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, primaryAmmo);		// Subtract reserve ammo
			SetEntData(iSecondary, iAmmoTable, iClipMax, 4, true);		// Add loaded ammo
		}
	}
	return Plugin_Handled;
}

public void updateShield(DataPack pack) {		// Recives the datapack from the Tide Turner function and evalutates
	pack.Reset();
	int iClient = pack.ReadCell();
	
	SetEntPropFloat(iClient, Prop_Send, "m_flChargeMeter", 50.0);
}

public Action AutoreloadSyringe(Handle timer, int iClient) {
	if (!(IsValidClient(iClient) && IsPlayerAlive(iClient))) return Plugin_Handled;
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
		leftVel[0] = -Sine(DegToRad(vecAng[1])) * 0.015;
		leftVel[1] = Cosine(DegToRad(vecAng[1])) * 0.015;
		leftVel[2] = 0.0;  // No change in the vertical direction

		vecVel[0] += leftVel[0];
		vecVel[1] += leftVel[1];

		TeleportEntity(iSyringe, vecPos, vecAng, vecVel);			// Apply position and velocity to syringe
	}
}


	// -={ Handles sticky destruction by explosives }=-

Action ProjectileTouch(int iProjectile, int other) {
	char class[64];
	GetEntityClassname(iProjectile, class, sizeof(class));
	
	if (StrEqual(class, "tf_projectile_rocket") || StrEqual(class, "tf_weapon_particle_cannon")) {
		if (other == 0) {		// If we hit the ground
			int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");
			float vecRocketPos[3];
			GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecRocketPos);
			
			for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
                if (!IsValidEntity(iEnt)) continue;

                // Check if the entity is a sticky or grenade
                GetEntityClassname(iEnt, class, sizeof(class));
                if (StrEqual(class, "tf_projectile_pipe_remote") || StrEqual(class, "tf_projectile_pipe")) {
                    int iStickyTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");

                    if (iStickyTeam != iProjTeam) {
                        float vecStickyPos[3];
                        GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecStickyPos);
						
						float fBlastRadius;
						
						switch (entities[iProjectile].iBazooka_Clip) {
							case 1: {
								fBlastRadius = 144.0;
							}
							case 2: {
								fBlastRadius = 115.2;
							}
							case 3: {
								fBlastRadius = 86.4;
							}
							case 0: {
								fBlastRadius = 144.0;
							}
							
						}
						
						if (GetVectorDistance(vecRocketPos, vecStickyPos) > fBlastRadius) continue;
						
						float fDamage = 80.0 * SimpleSplineRemapValClamped(GetVectorDistance(vecRocketPos, vecStickyPos), 0.0, fBlastRadius, 1.0, 0.5);
						entities[other].fHealth -= fDamage;

                        // Check if the sticky is within the appropriate distance for the rocket to do 70 damage
                        /*if (GetVectorDistance(vecRocketPos, vecStickyPos) <= 102.2) {
							AcceptEntityInput(iEnt, "Kill");
						}*/
                    }
                }
			}
		}
	}
	return Plugin_Handled;
}

public void CannonKnockback(int victim) {
	//PrintToChatAll("Cannonball");
	//loose cannon undo stun and strafelock
	TF2_RemoveCondition(victim, TFCond_KnockedIntoAir);
	TF2_RemoveCondition(victim, TFCond_AirCurrent);
	TF2_RemoveCondition(victim, TFCond_Dazed);
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
			
			if (index == 308) {
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
				
				for (int iEnt = 0; iEnt < GetMaxEntities(); iEnt++) {
					if (!IsValidEntity(iEnt)) continue;

					GetEntityClassname(iEnt, class, sizeof(class));
					if (StrEqual(class, "tf_projectile_pipe_remote") || StrEqual(class, "tf_projectile_pipe")) {
						int iStickyTeam = GetEntProp(iEnt, Prop_Data, "m_iTeamNum");
						int iProjTeam = GetEntProp(iProjectile, Prop_Data, "m_iTeamNum");

						if (iStickyTeam != iProjTeam) {
							float vecStickyPos[3];
							GetEntPropVector(iEnt, Prop_Send, "m_vecOrigin", vecStickyPos);

							float fDamage = 40.0 * SimpleSplineRemapValClamped(GetVectorDistance(vecGrenadePos, vecStickyPos), 0.0, 144.0, 1.0, 0.5);
							entities[iEnt].fHealth -= fDamage;
						}
					}
				}
				AcceptEntityInput(iProjectile, "Kill");
			}
		}
	}
	return Plugin_Changed;
}


void RocketSpawn(int iEnt) {
	int iClient = GetEntPropEnt(iEnt, Prop_Send, "m_hOwnerEntity");
	if (players[iClient].iBazooka_Clip > 0) {
		entities[iEnt].iBazooka_Clip = players[iClient].iBazooka_Clip;
	}
}

void BombSpawn(int iEnt) {
	entities[iEnt].fHealth = 70.0;
	
	char class[64];
	GetEntityClassname(iEnt, class, sizeof(class));
	
	if (StrEqual(class, "tf_projectile_pipe_remote")) {
		int iOwner = GetEntPropEnt(iEnt, Prop_Data, "m_hOwnerEntity");
		if (IsValidClient(iOwner)) {
		
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iOwner, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if (iSecondary >= 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			if (iSecondaryIndex == 1150) SetEntityModel(iEnt, "models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl");	// Quickiebomb Launcher
		}
	}
}

void OrbSpawn(int iEnt) {
	CreateTimer(1.07421875, KillProj, iEnt);		// The projectile will travel 1024 HU in this time
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

void fireballSpawn(int entity) {
	/*int iClient = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	CreateTimer(0.0, KillProj, entity);
	
	int iRocket = CreateEntityByName("tf_projectile_rocket");
	
	if (iRocket != -1) {
		int team = GetClientTeam(iClient);
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
		float vecPos[3], vecClientAng[3], vecProjVel[3], offset[3];
		
		GetClientEyePosition(iClient, vecPos);
		GetClientEyeAngles(iClient, vecClientAng);
		
		offset[0] = (15.0 * Sine(DegToRad(vecClientAng[1])));
		offset[1] = (-6.0 * Cosine(DegToRad(vecClientAng[1])));
		offset[2] = -10.0;
		
		vecPos[0] += offset[0];
		vecPos[1] += offset[1];
		vecPos[2] += offset[2];

		if (isKritzed(iClient)) EmitAmbientSound("weapons/syringegun_shoot_crit.wav", vecPos, iClient);
		else EmitAmbientSound("weapons/syringegun_shoot.wav", vecPos, iClient);
		
		SetEntPropEnt(iRocket, Prop_Send, "m_hOwnerEntity", iClient);	// Attacker
		SetEntPropEnt(iRocket, Prop_Send, "m_hLauncher", iPrimary);	// Weapon
		SetEntProp(iRocket, Prop_Data, "m_iTeamNum", team);		// Team
		SetEntProp(iRocket, Prop_Data, "m_CollisionGroup", 24);		// Collision
		SetEntProp(iRocket, Prop_Data, "m_usSolidFlags", 0);
		SetEntPropFloat(iRocket, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iRocket, Prop_Send, "m_flModelScale", 1.0);
		
		DispatchSpawn(iRocket);
		
		// Calculates forward velocity
		vecProjVel[0] = Cosine(DegToRad(vecClientAng[0])) * Cosine(DegToRad(vecClientAng[1])) * 2000.0;
		vecProjVel[1] = Cosine(DegToRad(vecClientAng[0])) * Sine(DegToRad(vecClientAng[1])) * 2000.0;
		vecProjVel[2] = Sine(DegToRad(vecClientAng[0])) * -2000.0;

		TeleportEntity(iRocket, vecPos, vecClientAng, vecProjVel);
		CreateTimer(0.3232, KillProj, iRocket);		// The projectile will travel 640 HU in this time
	}*/
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
						else {
							players[owner].fTHREAT_Timer += 1.0;
						}
					}
					else {		// Teammate hit
						if (wepIndex == 412) {		// Overdose
							int iHealth = GetEntProp(other, Prop_Send, "m_iHealth");
							int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, other);
							if (iHealth < iMaxHealth) {		// If the teammate is below max health
								
								float dmgTime = GetEntDataFloat(other, 8968); //m_flLastDamageTime
								float currTime = GetGameTime();
								if (currTime - dmgTime < 15.0) {
									SetEntDataFloat(other, 8968, currTime - 0.5, true);
								}
								if (players[other].fHeal_Penalty > -10.0) {
									players[other].fHeal_Penalty -= 0.5;
								}
								
								float healing;
								if (currTime - dmgTime > 10.0) {
									healing = 2.0;
								}
								if (currTime - dmgTime >= 15.0) {
									healing = 3.0;
								}
								else {
									healing = 1.0;
								}
							
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
								// The ratio is 1% per 16 HP for syringe healing
								if (iSecondaryIndex == 35) {		// Kritzkreig
									fUber += healing * 0.00125 * 1.25 * 0.5;		// Add this to our Uber amount (multiply by 0.001 as 1 HP -> 1%, and Uber is stored as a 0 - 1 proportion)
								}
								if (iSecondaryIndex == 998) {		// Vaccinator
									fUber += healing * 0.00125 * 3.0 * 0.5;
								}
								else {
									fUber += healing * 0.00125 * 0.5;
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
				else if (IsValidEntity(other)) {		// Building damage
					char class[64];
					GetEntityClassname(other, class, sizeof(class));
					if (StrEqual(class,"obj_sentrygun") || StrEqual(class,"obj_dispenser") || StrEqual(class,"obj_teleporter")) {
						int damage_type = DMG_BULLET | DMG_USE_HITLOCATIONS;
						
						float fDistance;
						float vecAttacker[3];
						float vecBuilding[3];
						GetEntPropVector(owner, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
						GetEntPropVector(other, Prop_Send, "m_vecOrigin", vecBuilding);		// Gets building position
						
						float damage = 10.0 * SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);
						SDKHooks_TakeDamage(other, owner, owner, damage, damage_type, weapon,_,_, false);		// Do this to ensure we get hit markers
						
						// Add THREAT
						if (players[owner].fBaseball_Debuff_Timer <= 0.0) {
							players[owner].fTHREAT += 10.0;		// Add THREAT
							if (players[owner].fTHREAT > 1000.0) {
								players[owner].fTHREAT = 1000.0;
							}
							players[owner].fTHREAT_Timer += 10.0;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
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


void arrowSpawn(int iEntity) {
	int iClient = GetEntPropEnt(iEntity, Prop_Send, "m_hOwnerEntity");
	if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
	
		float vecPos[3], vecAng[3], vecVel[3],  offset[3];
		float ang[3];
		GetEntPropVector(iEntity, Prop_Data, "m_angRotation", ang);
		ang[0] = DegToRad(ang[0]); ang[1] = DegToRad(ang[1]); ang[2] = DegToRad(ang[2]);
		
		GetClientEyeAngles(iClient, vecAng);
		GetClientEyePosition(iClient, vecPos);
		
		SetEntPropVector(iEntity, Prop_Data, "m_angRotation", vecAng);		// Orientation of model
		SetEntityModel(iEntity, "models/weapons/w_models/w_syringe_proj.mdl"); // Model
		SetEntPropFloat(iEntity, Prop_Data, "m_flGravity", 0.1);
		SetEntPropFloat(iEntity, Prop_Data, "m_flRadius", 0.3);
		SetEntPropFloat(iEntity, Prop_Send, "m_flModelScale", 0.3);
		
		// Calculates forward velocity
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 2000.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 2000.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -2000.0;

		TeleportEntity(iEntity, _, _, vecVel);			// Apply position and velocity to syringe
	}
}

Action BuildingDamage (int building, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3]) {
	char class[64];
	
	if (building >= 1 && IsValidEdict(building) && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {
			GetEntityClassname(weapon, class, sizeof(class));
			int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
			
			float vecAttacker[3];
			float vecBuilding[3];
			GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets attacker position
			GetEntPropVector(building, Prop_Send, "m_vecOrigin", vecBuilding);		// Gets building position
			float fDistance = GetVectorDistance(vecAttacker, vecBuilding, false);		// Distance calculation
			float fDmgMod = 1.0;		// Distance mod
			float fDmgModTHREAT;	// THREAT mod
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			
			/*int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");*/
			
			int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
			int iMeleeIndex = -1;
			if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			

			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if ((StrEqual(class, "tf_weapon_scattergun") || StrEqual(class, "tf_weapon_soda_popper") || StrEqual(class, "tf_weapon_pep_brawler_blaster")) && fDistance < 512.0) {
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25);		// Scale the ramp-up down to 150%
				}
				if (StrEqual(class, "tf_weapon_pep_brawler_blaster")) {
					if (fDmgMod * damage >= 30) {
						TF2_AddCondition(attacker, TFCond_SpeedBuffAlly, 2.5);
					}
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
				if (iPrimaryIndex == 730) {		// Beggar's Bazooka
					if (entities[inflictor].iBazooka_Clip > 0) {
						
						// TODO: make this neater
						float DmgFrac, DmgFracMult;
						if (fDistance > 512.0) {
							DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
						else {
							DmgFracMult = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.6);
						}
						DmgFrac = damage / DmgFracMult;
						
						if (entities[inflictor].iBazooka_Clip == 2) {
							if (DmgFrac < 48) {
								damage = 0.0;
							}
							else {
								damage *= SimpleSplineRemapValClamped(DmgFrac, 80.0, 48.0, 1.0, 0.833333);
							}
						}
						else if (entities[inflictor].iBazooka_Clip == 3) {
							if (DmgFrac < 56) {
								damage = 0.0;
							}
							else {
								damage *= SimpleSplineRemapValClamped(DmgFrac, 80.0, 56.0, 1.0, 0.714286);
							}
						}
					}
				}			
				if (StrEqual(class, "tf_weapon_particle_cannon")) {
					damage *= 5;
					if (fDistance > 512.0) {		// Increase Cow Mangler fall-off
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.75, 0.25) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
					}
					else {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.6) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75);		// Scale the ramp-up up to 140%
					}
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
					damage *= 1.833333;
					if (fDistance < 512.0) {
						fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our ramp-up/fall-off multiplier
					}
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				if (StrEqual(class, "tf_weapon_pipebomblauncher") && entities[inflictor].bTrap == false) {		// Only do this for recent stickies
					// Quickiebomb Launcher consistant damage with distance
					if (iWeaponIndex == 1150) {
						if (fDistance < 512.0) {
							fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);
						}
						else {
							fDmgMod = 1.0 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						}
					}
					else {
						if (fDistance < 512.0) {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.4, 0.7) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Scale the ramp-up up to 140%
						}
						else {
							fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.25, 0.75) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);		// Scale the fall-off up to 75%
						}
					}
				}
			}

			// Heavy
			if (TF2_GetPlayerClass(attacker) == TFClass_Heavy) {
				// Natascha
				if (iWeaponIndex == 41) {
					damage = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 21.0, 7.0);
				}
				if (StrEqual(class, "tf_weapon_minigun")) {
					fDmgMod = SimpleSplineRemapValClamped(players[attacker].fSpeed, 0.0, 1.005, 1.0, 0.666);		// Scale damage up from -33% to base as we fire
				}
			}
			
			// Medic
			if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {

					if (!(damage_type & DMG_USE_HITLOCATIONS)) {
						damage = 0.0;
					}
					//fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);		// Gives us our ramp-up/fall-off multiplier (+/- 20%)
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
				if (StrEqual(class, "tf_weapon_revolver") && iWeaponIndex != 460 && fDistance < 512.0) {		// Scale ramp-up down to 120
					fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				}
			}
			
			
			damage *= fDmgMod;		// This applies *all* ramp-up/fall-off modifications for all classes
			
			// THREAT modifier
			if (players[attacker].fTHREAT > 0.0) {
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
				// Pyro
				StrEqual(class, "tf_weapon_flaregun") || StrEqual(class, "tf_weapon_flaregun_revenge") ||
				// Sniper (bodyshots)
				StrEqual(class, "tf_weapon_sniperrifle")) {		// No fall-off
					if (fDistance < 512.0) {
						fDmgModTHREAT = (1.5/SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8) -  1) * players[attacker].fTHREAT/1000 + 1;
					}
					else {
						fDmgModTHREAT = 0.5 * players[attacker].fTHREAT/1000 + 1;
					}
				}
				else if (
				// Soldier
				StrEqual(class, "tf_weapon_rocketlauncher") ||	// +40
				StrEqual(class, "tf_weapon_rocketlauncher_airstrike") ||
				StrEqual(class, "tf_weapon_particle_cannon") ||
				// Demoman
				(StrEqual(class, "tf_weapon_pipebomblauncher") && iWeaponIndex != 1150)) {
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
			}
		}
	}
	// Sentry damage to other players
	else if (attacker >= 1 && IsValidEdict(attacker) && attacker >= 1 && attacker <= MaxClients) {
		if (inflictor >= 1 && IsValidEdict(inflictor) && weapon) {
			GetEntityClassname(inflictor, class, sizeof(class));		// Retrieve the inflictor
			if (StrEqual(class,"obj_sentrygun")) {
				
			}
			else if (StrEqual(class,"tf_projectile_sentryrocket")) {		// Handle explosive damage from sentry rockets
				float vecAttacker[3];
				float vecVictim[3];
				GetEntPropVector(building, Prop_Send, "m_vecOrigin", vecVictim);		// Gets defender position
				float fDmgMod = 1.0;		// Distance mod
				GetEntPropVector(attacker, Prop_Send, "m_vecOrigin", vecAttacker);		// Gets Engineer position
				float fDistance = GetVectorDistance(vecAttacker, vecVictim, false);		// Distance calculation
				fDmgMod = 1 / SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
				damage *= fDmgMod;
			}
		}
	}
	
	// THREAT
	if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
		GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
		
		// Add THREAT
		if (players[attacker].fBaseball_Debuff_Timer <= 0.0) {
			players[attacker].fTHREAT += damage;		// Add THREAT
			if (players[attacker].fTHREAT > 1000.0) {
				players[attacker].fTHREAT = 1000.0;
			}
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				players[attacker].fTHREAT_Timer += damage * 1.429;		// Adds damage to the DPS counter we have to exceed to block THREAT drain
			}
			else if (TF2_GetPlayerClass(attacker) == TFClass_Sniper || TF2_GetPlayerClass(attacker) == TFClass_Spy) {
				players[attacker].fTHREAT_Timer += damage * 2.0;
			}
			else {
				players[attacker].fTHREAT_Timer += damage;
			}
			
			// Makes sure that the building properly takes damage during construction
			int seq = GetEntProp(building, Prop_Send, "m_nSequence");
			if (seq == 1) {
				g_buildingHeal[building] -= damage;
			}
		}
	}
	
	return Plugin_Changed;
}


Action BuildingThink(int building, int client) {
	char class[64];
	GetEntityClassname(building, class, 64);
	
	// Adjust Teleporter charge rate
	if (StrEqual(class,"obj_teleporter")) {
		float charge = GetEntPropFloat(building, Prop_Send, "m_flRechargeTime") - GetGameTime();
		if (charge > 0.0) {
			int Level = GetEntProp(building, Prop_Send,"m_iUpgradeLevel");
			if (Level == 1) {
				charge -= 0.00375; // (10 -> 8)
			}
			else if (Level == 2) {
				charge += 0.003; // (5 -> 6)
			}
			else {
				charge += 0.0025; // (3 -> 4)
			}
			SetEntPropFloat(building, Prop_Send, "m_flRechargeTime", charge + GetGameTime());
		}
	}
	
	// update animation speeds for building construction
	/*float rate = RoundToFloor(GetEntPropFloat(building, Prop_Data, "m_flPlaybackRate") * 100) / 100.0;
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
				if (g_hSDKFinishBuilding == INVALID_HANDLE) {
					LogError("g_hSDKFinishBuilding is invalid.");
					return Plugin_Handled;
				}
				SDKCall(g_hSDKFinishBuilding, building);
			}
			entities[building].fConstruction_Health += rate / 4.75;
		}
	}*/
	return Plugin_Continue;
}


	// -={ Deploy Mini-Sentry }=-

public Action EventObjectBuilt(Event bEvent, const char[] name, bool bBroad) {
	int building = GetEventInt(bEvent, "index");
	int owner = GetClientOfUserId(GetEventInt(bEvent, "userid"));
	
	char class[64];
	GetEntityClassname(building, class, sizeof(class));
	if (StrEqual(class, "obj_sentrygun")) {
		if (players[owner].bSentryBuilt == false) {
			players[owner].bSentryBuilt = true;
			if (players[owner].bMini == true) {
				SetEntProp(building, Prop_Send, "m_bMiniBuilding", 1);
				SetEntProp(building, Prop_Send, "m_iMaxHealth", 100);
				SetEntProp(building, Prop_Send, "m_iHealth", 50);
				SetEntPropFloat(building, Prop_Send, "m_flModelScale", 0.75);
				int iMetal = GetEntData(owner, FindDataMapInfo(owner, "m_iAmmo") + (3 * 4), 4);
				SetEntData(owner, FindDataMapInfo(owner, "m_iAmmo") + (3 * 4), iMetal + 55, 4);
			}
			else {
				int iMetal = GetEntData(owner, FindDataMapInfo(owner, "m_iAmmo") + (3 * 4), 4);
				SetEntData(owner, FindDataMapInfo(owner, "m_iAmmo") + (3 * 4), iMetal + 5, 4);
			}
			//PrintToChatAll("Sentry health: %i", GetEntProp(building, Prop_Send, "m_iHealth"));
		}
	}
	
	return Plugin_Continue;
}


	// -={ Detects Sentry death }=-

public Action EventObjectDestroy(Event bEvent, const char[] name, bool bBroad) {
	bool was_building = GetEventBool(bEvent, "was_building");
	int buildType = GetEventInt(bEvent, "objecttype");
	int owner = GetClientOfUserId(GetEventInt(bEvent, "userid"));
	
	// Dispenser = 0
	// Tele = 1
	// Sentry = 2
	
	if (was_building == true) {
		if (buildType == 2) {
			players[owner].bSentryBuilt = false;
		}
	}
	
	return Plugin_Continue;
}


	// -={ Allows for Dispenser self-destruct }=-

public Action EventObjectDetonate(Event bEvent, const char[] name, bool dBroad) {
	int buildType = GetEventInt(bEvent, "objecttype");
	int building = GetEventInt(bEvent, "index");
	int owner = GetClientOfUserId(GetEventInt(bEvent, "userid"));

	// Dispenser = 0
	// Tele = 1
	// Sentry = 2
	
	if (buildType == 0) {
		float vecGrenadePos[3];
		int iMetal;
		GetEntPropVector(building, Prop_Send, "m_vecOrigin", vecGrenadePos);
		iMetal = entities[building].iDispMetal;		// NB: Dispensers can hold 400 Metal
		SetEntProp(building, Prop_Send, "m_iAmmoMetal", 0);

		CreateParticle(building, "ExplosionCore_MidAir", 2.0);
		EmitAmbientSound("weapons/pipe_bomb1.wav", vecGrenadePos, building);
		
		for (int iTarget = 1 ; iTarget <= MaxClients ; iTarget++) {		// The player being damaged by the explosion
			if (IsValidClient(iTarget)) {
				float vecTargetPos[3];
				GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);
				vecTargetPos[2] += 5;
				
				float fDist = GetVectorDistance(vecGrenadePos, vecTargetPos);		// Store distance
				if (fDist <= 148.0 && (TF2_GetClientTeam(owner) != TF2_GetClientTeam(iTarget) || owner == iTarget)) {
					Handle hndl = TR_TraceRayFilterEx(vecGrenadePos, vecTargetPos, MASK_SOLID, RayType_EndPoint, PlayerTraceFilter, building);
					if (TR_DidHit(hndl) == false || IsValidClient(TR_GetEntityIndex(hndl))) {
						float damage = RemapValClamped(fDist, 0.0, 148.0, 87.5, 87.5 / 2) * RemapValClamped(iMetal * 1.0, 0.0, 400.0, 1.0, 1.5);

						int type = DMG_BLAST;
						if (owner == iTarget) {		// Apply self damage resistance and increased push force
							float vel[3], vecBlast[3];
							GetEntPropVector(owner, Prop_Data, "m_vecVelocity", vel);
							
							MakeVectorFromPoints(vecGrenadePos, vecTargetPos, vecBlast);
							NormalizeVector(vecBlast, vecBlast);
							ScaleVector(vecBlast, 400.0);
							
							vel[0] += vecBlast[0]; vel[1] += vecBlast[1]; vel[2] += vecBlast[2];
							
							TeleportEntity(owner, NULL_VECTOR, NULL_VECTOR, vel);
							
							damage *= 0.5;
						}
						SDKHooks_TakeDamage(iTarget, owner, owner, damage, type, -1, NULL_VECTOR, vecGrenadePos, false);
					}
					delete hndl;
				}
			}
		}
	}
	else if (buildType == 2) {
		players[owner].bSentryBuilt = false;
	}

	return Plugin_Continue;
}

public void TrapSet(Handle timer, int iSticky) {
	if (iSticky > 1 && IsValidEdict(iSticky)) {
		entities[iSticky].bTrap = true;
	}
}

Action OnClientWeaponCanSwitchTo(int iClient, int weapon) {
	int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
    
	// Axtinguisher
	if ((TF2_GetPlayerClass(iClient) == TFClass_Pyro) && weapon == iMelee && players[iClient].fAxe_Cooldown < 20.0) {
		int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		if (iWeaponIndex == 38 || iWeaponIndex == 457 || iWeaponIndex == 1000) {
			EmitGameSoundToClient(iClient, "Player.DenyWeaponSelection");
			return Plugin_Handled; // Block switching to melee
		}
	}
	
	// Miniguns
	/*if (TF2_GetPlayerClass(iClient) == TFClass_Heavy && iActive == iPrimary && weapon != iPrimary) {
		char class[64];
		GetEntityClassname(iActive, class, sizeof(class));
		if (StrEqual(class, "tf_weapon_minigun")) {
			int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
			
			SDKCall(g_SDKCallMinigunWindDown, iActive);
			SetEntProp(iActive, Prop_Send, "m_iWeaponState", 0);
			SetEntProp(view, Prop_Send, "m_nSequence", 23);
		}
		return Plugin_Continue;
	}*/

	// Your Eternal Reward
	if ((TF2_GetPlayerClass(iClient) == TFClass_Spy) && weapon == iMelee && players[iClient].fYER_Cooldown < 20.0) {
		int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		if (iWeaponIndex == 225 || iWeaponIndex == 574) {
			EmitGameSoundToClient(iClient, "Player.DenyWeaponSelection");
			return Plugin_Handled; // Block switching to melee
		}
	}

	return Plugin_Continue;
}

void ForceSwitchFromMeleeWeapon(int iClient) {
	int weapon = INVALID_ENT_REFERENCE;
	if (IsValidEntity((weapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Primary))) || IsValidEntity((weapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Secondary))) || IsValidEntity((weapon = GetPlayerWeaponSlot(iClient, TFWeaponSlot_Building)))) {
		SetActiveWeapon(iClient, weapon);
	}
}

void SetActiveWeapon(int iClient, int weapon) {
	int hActiveWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	if (IsValidEntity(hActiveWeapon)) {
		bool bResetParity = !!GetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity");
		SetEntProp(hActiveWeapon, Prop_Send, "m_bResetParity", !bResetParity);
	}
	
	SDKCall(g_SDKCallWeaponSwitch, iClient, weapon, 0);
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
	TF2_IsPlayerInCondition(client,TFCond_CritOnDamage));
}

bool isMiniKritzed(int client,int victim=-1) {
	bool result=false;
	if(victim!=-1) {
		if (TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeathSilent)) {
			result = true;
		}
	}
	if (TF2_IsPlayerInCondition(client,TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(client,TFCond_Buffed)) {
		result = true;
	}
	return result;
}

bool TraceFilter_ExcludeSingle(int entity, int contentsmask, any data) {
	return (entity != data);
}

	// -={ Displays particles (taken from ShSilver) }=-
	
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


	// ==={ Creates temporary entities for displaying particle effects }===
	// ==={ Taken from Nosoop }===
	
enum ParticleAttachment_t {
	PATTACH_ABSORIGIN = 0,
	PATTACH_ABSORIGIN_FOLLOW,
	PATTACH_CUSTOMORIGIN,
	PATTACH_POINT,
	PATTACH_POINT_FOLLOW,
	PATTACH_WORLDORIGIN,
	PATTACH_ROOTBONE_FOLLOW
};
	
stock void TE_SetupTFParticleEffect(const char[] name, const float vecOrigin[3],
		const float vecStart[3] = NULL_VECTOR, const float vecAngles[3] = NULL_VECTOR,
		int entity = -1, ParticleAttachment_t attachType = PATTACH_ABSORIGIN,
		int attachPoint = -1, bool bResetParticles = false) {
	int particleTable, particleIndex;
	
	if ((particleTable = FindStringTable("ParticleEffectNames")) == INVALID_STRING_TABLE) {
		ThrowError("Could not find string table: ParticleEffectNames");
	}
	
	if ((particleIndex = FindStringIndex(particleTable, name)) == INVALID_STRING_INDEX) {
		ThrowError("Could not find particle index: %s", name);
	}
	
	TE_Start("TFParticleEffect");
	TE_WriteFloat("m_vecOrigin[0]", vecOrigin[0]);
	TE_WriteFloat("m_vecOrigin[1]", vecOrigin[1]);
	TE_WriteFloat("m_vecOrigin[2]", vecOrigin[2]);
	TE_WriteFloat("m_vecStart[0]", vecStart[0]);
	TE_WriteFloat("m_vecStart[1]", vecStart[1]);
	TE_WriteFloat("m_vecStart[2]", vecStart[2]);
	TE_WriteVector("m_vecAngles", vecAngles);
	TE_WriteNum("m_iParticleSystemIndex", particleIndex);
	
	if (entity != -1) {
		TE_WriteNum("entindex", entity);
	}
	
	if (attachType != PATTACH_ABSORIGIN) {
		TE_WriteNum("m_iAttachType", view_as<int>(attachType));
	}
	
	if (attachPoint != -1) {
		TE_WriteNum("m_iAttachmentPointIndex", attachPoint);
	}
	
	TE_WriteNum("m_bResetParticles", bResetParticles ? 1 : 0);
}