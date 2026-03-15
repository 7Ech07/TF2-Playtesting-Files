#pragma semicolon 1
#include <sourcemod>

#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2utils>
#include <tf2attributes>

#include <tf_ontakedamage>

#pragma newdecls required

public Plugin myinfo =
{
	name = "NotSoda's Yet Another Balancemod",
	author = "Ech0",
	description = "Contains some weapon changes from not_soda's document",
	version = "1.0.0",
	url = "https://docs.google.com/document/d/1CoRwkTyjMT_zRLQskJpMtxZ-D5a-jcvRGOfXzWfcn7Q/edit?tab=t.0#heading=h.j7op7vjkjl6u"
};

	// ==={{ Initialisation and stuff }}==

enum struct Player {
	// Multi-class
	float fHealth_Regen;		// Tracks how long after taking or dealing damage we start to regenerate health
	float fHealth_Regen_Timer;	// Tracks time between health regen ticks
	//int iLastButtons;		// Tracks the buttons we had held down last frame
	
	// Demoman
	int iLoadout;		// Stores our primary and secondary index when we have the Eyelander, so we can detect when it changes and reset our Heads
	bool bCharge_Crit_Prepped;	// Stores when the melee should be able to Crit during a shield charge

	// Medic
	int iSyringe_Ammo;		// Tracks loaded syringes for the purposes of determining when we fire a shot
	bool bMedic;		// Used to disable Medic's health regen
	
	// Sniper
	int iHeadshot_Frame;		// Identifies frames where we land a headshot
	float fRazorback_Health;		// Stores the health of our Razorback
}

Player players[MAXPLAYERS+1];
float g_meterPri[MAXPLAYERS+1];

int offs_CTFPlayer_iClass;

DynamicHook g_hDHookItemIterateAttribute;
int g_iCEconItem_m_Item;
int g_iCEconItemView_m_bOnlyIterateItemViewAttributes;

Handle g_detour_CalculateMaxSpeed;
Handle dtRegenThink;

Handle cvar_ref_tf_use_fixed_weaponspreads;
Handle cvar_ref_tf_fall_damage_disablespread;

Handle cvar_ref_tf_fireball_airblast_recharge_penalty;
Handle cvar_ref_tf_fireball_burn_duration;
Handle cvar_ref_tf_fireball_burning_bonus;

public void OnPluginStart() {
	cvar_ref_tf_fireball_airblast_recharge_penalty = FindConVar("tf_fireball_airblast_recharge_penalty");
	cvar_ref_tf_fireball_burn_duration = FindConVar("tf_fireball_burn_duration");
	cvar_ref_tf_fireball_burning_bonus = FindConVar("tf_fireball_burning_bonus");
	cvar_ref_tf_use_fixed_weaponspreads = FindConVar("tf_use_fixed_weaponspreads");
	cvar_ref_tf_fall_damage_disablespread = FindConVar("tf_fall_damage_disablespread");

	SetConVarString(cvar_ref_tf_use_fixed_weaponspreads, "1");
	SetConVarString(cvar_ref_tf_fall_damage_disablespread, "1");
	SetConVarString(cvar_ref_tf_fireball_airblast_recharge_penalty, "1.0");
	SetConVarString(cvar_ref_tf_fireball_burn_duration, "4");
	SetConVarString(cvar_ref_tf_fireball_burning_bonus, "1");
	
    Handle hConfig = new GameData("Ech0");

    int iOffset = GameConfGetOffset(hConfig, "CEconItemView::IterateAttributes");
    g_hDHookItemIterateAttribute = new DynamicHook(iOffset, HookType_Raw, ReturnType_Void, ThisPointer_Address);
    if (g_hDHookItemIterateAttribute == null)
    {
        SetFailState("Failed to create hook CEconItemView::IterateAttributes offset from SF2 gamedata!");
    }
    g_hDHookItemIterateAttribute.AddParam(HookParamType_ObjectPtr);

    g_iCEconItem_m_Item = FindSendPropInfo("CEconEntity", "m_Item");
    FindSendPropInfo("CEconEntity", "m_bOnlyIterateItemViewAttributes", _, _, g_iCEconItemView_m_bOnlyIterateItemViewAttributes);
	
	// Dhook to disable Medic speed matching
    g_detour_CalculateMaxSpeed = DHookCreateFromConf(hConfig, "CTFPlayer::TeamFortress_CalculateMaxSpeed");
	if (g_detour_CalculateMaxSpeed == INVALID_HANDLE) {
		LogError("Failed to create detour for CTFPlayer::TeamFortress_CalculateMaxSpeed");
		return;
	}	
    if (!DHookEnableDetour(g_detour_CalculateMaxSpeed, false, Detour_CalculateMaxSpeed)) {		// False signifies a pre- hook
        SetFailState("Failed to enable detour on CTFPlayer::TeamFortress_CalculateMaxSpeed");
    }
    
	dtRegenThink = DHookCreateFromConf(hConfig, "CTFPlayer::RegenThink()");
	if (dtRegenThink == INVALID_HANDLE) {
		LogError("Failed to create detour for CTFPlayer::RegenThink");
		return;
	}	
    if (!DHookEnableDetour(dtRegenThink, false, OnPlayerRegenThinkPre)) {
        SetFailState("Failed to enable detour on CTFPlayer::RegenThink");
    }
    if (!DHookEnableDetour(dtRegenThink, true, OnPlayerRegenThinkPost)) {
        SetFailState("Failed to enable detour on CTFPlayer::RegenThink");
    }
	
	offs_CTFPlayer_iClass = FindSendPropInfo("CTFPlayer", "m_iClass");
	
    delete hConfig;
	
	HookEvent("player_spawn", OnGameEvent, EventHookMode_Post);
	HookEvent("post_inventory_application", OnGameEvent, EventHookMode_Post);		// This detects when we touch a cabinet
	HookEvent("player_death", Event_PlayerDeath);
	
	AddCommandListener(PlayerListener, "eureka_teleport");
}

public void OnClientPutInServer (int iClient) {
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
	SDKHook(iClient, SDKHook_OnTakeDamageAlivePost, OnTakeDamagePost);
	//SDKHook(iClient, SDKHook_TraceAttack, TraceAttack);
}

public void OnMapStart() {
	PrecacheSound("weapons/discipline_device_power_down.wav", true);
	PrecacheSound("weapons/syringegun_shoot.wav", true);
	PrecacheSound("weapons/syringegun_shoot_crit.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_back.wav", true);
	PrecacheSound("weapons/widow_maker_pump_action_forward.wav", true);
}

//public void OnEntityCreate(int iEntity, const char[] sClassname)
// OR (As long you have a method to detect the weapon/hat/medal/etc... entity)
public void TF2Items_OnGiveNamedItem_Post(int iClient, char[] sClassname, int iItemDefIndex, int iLevel, int iQuality, int iEntity) {
	Address pCEconItemView = GetEntityAddress(iEntity) + view_as<Address>(g_iCEconItem_m_Item);
	g_hDHookItemIterateAttribute.HookRaw(Hook_Pre, pCEconItemView, CEconItemView_IterateAttributes);
	g_hDHookItemIterateAttribute.HookRaw(Hook_Post, pCEconItemView, CEconItemView_IterateAttributes_Post);
}

static MRESReturn CEconItemView_IterateAttributes(Address pThis, DHookParam hParams) {
    StoreToAddress(pThis + view_as<Address>(g_iCEconItemView_m_bOnlyIterateItemViewAttributes), true, NumberType_Int8, false);
    return MRES_Ignored;
}

static MRESReturn CEconItemView_IterateAttributes_Post(Address pThis, DHookParam hParams) {
    StoreToAddress(pThis + view_as<Address>(g_iCEconItemView_m_bOnlyIterateItemViewAttributes), false, NumberType_Int8, false);
    return MRES_Ignored;
}

Action OnGameEvent(Event event, const char[] name, bool dontbroadcast) {	
	if (StrEqual(name, "player_spawn")) {
		
	}
	
	else if (StrEqual(name, "post_inventory_application")) {
		int iClient = GetClientOfUserId(GetEventInt(event, "userid"));
		if (IsValidClient(iClient)) {
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			//int iPrimaryIndex = -1;
			//if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

			int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
			//int iSecondaryIndex = -1;
			//if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

			int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
			//int iMeleeIndex = -1;
			//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
			
			// Modify our weapon attributes
			AttributeChanges(iClient, iPrimary, iSecondary, iMelee, iWatch);
		}
	}
	return Plugin_Continue;
}

public Action AttributeChanges(int iClient, int iPrimary, int iSecondary, int iMelee, int iWatch) {
	int iPrimaryIndex = -1;
	if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");

	int iSecondaryIndex = -1;
	if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");

	int iMeleeIndex = -1;
	if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	int iWatchIndex = -1;
	if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
	
	TF2Attrib_RemoveByName(iClient, "hidden primary max ammo bonus");
	TF2Attrib_RemoveByName(iClient, "hidden secondary max ammo penalty");
	TF2Attrib_RemoveByName(iClient, "move speed bonus");
	TF2Attrib_RemoveByName(iClient, "max health additive bonus");
	TF2Attrib_RemoveByName(iClient, "max health additive penalty");
	TF2Attrib_RemoveByName(iClient, "clip size penalty");
	
	switch (TF2_GetPlayerClass(iClient)) {
		
		// Scout
		case TFClass_Scout: {
			switch (iPrimaryIndex) {
				case 45, 1078: {	// Force-A-Nature
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.33);
					TF2Attrib_SetByName(iPrimary, "fire rate bonus", 0.5);
					TF2Attrib_SetByName(iPrimary, "scattergun no reload single", 1.0);
				}
			}
			
			switch (iSecondaryIndex) {
				case 163: {	// Crit-a-Cola
					TF2Attrib_SetByName(iSecondary, "lunchbox adds minicrits", 2.0);
					TF2Attrib_SetByName(iSecondary, "mod_mark_attacker_for_death", 5.0);
				}
				case 812, 833: {	// Flying Guillotine
					TF2Attrib_SetByName(iSecondary, "effect bar recharge rate increased", 1.6); // 10 seconds
				}
			}
			
			switch (iMeleeIndex) {
				case 44: {	// Sandman
					TF2Attrib_SetByName(iMelee, "mod bat launches balls", 1.0);
					TF2Attrib_SetByName(iMelee, "increased jump height", 0.85);
				}
			}
		}
	
		// Soldier
		case TFClass_Soldier: {
			TF2Attrib_SetByName(iMelee, "mod crit while airborne", 1.0);
			TF2Attrib_RemoveByName(iPrimary, "reload time decreased");
			
			switch (iPrimaryIndex) {
				case 127: {	// Direct Hit
					TF2Attrib_SetByName(iPrimary, "Blast radius decreased", 0.3);
					TF2Attrib_SetByName(iPrimary, "Projectile speed increased", 1.8);
					TF2Attrib_SetByName(iPrimary, "damage bonus", 1.25);
					TF2Attrib_SetByName(iPrimary, "mod mini-crit airborne", 1.0);
				}
			}
			
			switch (iSecondaryIndex) {
				case 129, 1001: {	// Buff Banner
					TF2Attrib_SetByName(iPrimary, "reload time decreased", 0.85);
				}
				case 133: {	// Gunboats
					TF2Attrib_SetByName(iSecondary, "max health additive penalty", -25.0);
					TF2Attrib_SetByName(iSecondary, "rocket jump damage reduction", 0.5);
				}
			}
		
			switch (iMeleeIndex) {
				case 128: {	// Equalizer v2
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.6);
					TF2Attrib_SetByName(iMelee, "reduced_healing_from_medics", 0.0);
				}
			}
		}
	
		// Pyro
		case TFClass_Pyro: {
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
			TF2Attrib_SetByName(iPrimary, "flame ammopersec increased", 1.333333);
			TF2Attrib_SetByName(iPrimary, "flame_drag", 8.5);
			TF2Attrib_SetByName(iPrimary, "flame_speed", 2450.0);
			TF2Attrib_SetByName(iPrimary, "flame_up_speed", 50.0);
			TF2Attrib_SetByName(iPrimary, "flame_lifetime", 0.6);
			TF2Attrib_SetByName(iPrimary, "extinguish restores health", 20.0);
			TF2Attrib_SetByName(iMelee, "speed_boost_on_kill", 3.0);
			
			switch (iPrimaryIndex) {
				case 40, 1146: {	// Backburner
					TF2Attrib_SetByName(iPrimary, "mod flamethrower back crit", 1.0);
				}
				case 1178: {	// Dragon's Fury
					TF2Attrib_SetByName(iPrimary, "item_meter_charge_type", 1.0);
					TF2Attrib_SetByName(iPrimary, "item_meter_charge_rate", 0.8);
					TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", 0.2);
					TF2Attrib_SetByName(iPrimary, "airblast cost scale hidden", 0.25);
					TF2Attrib_SetByName(iPrimary, "dragons fury neutral properties", 1.0);
					TF2Attrib_SetByName(iPrimary, "extinguish restores health", 20.0);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 40, _, primaryAmmo);
				}
			}
			
			switch (iSecondaryIndex) {
				case 39, 1081: {	// Flare Gun
					TF2Attrib_SetByName(iSecondary, "hidden secondary max ammo penalty", 0.5);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 16, _, secondaryAmmo);
					TF2Attrib_SetByName(iSecondary, "afterburn duration penalty", 0.4);
				}
			}
			
			switch (iMeleeIndex) {
				case 38, 457, 1000: {	// Axtinguisher
					TF2Attrib_SetByName(iMelee, "minicrit vs burning player", 1.0);
					TF2Attrib_SetByName(iMelee, "dmg penalty vs nonburning", 0.67);
					TF2Attrib_SetByName(iMelee, "single wep holster time increased", 1.5);
					TF2Attrib_RemoveByName(iMelee, "speed_boost_on_kill");
				}
			}
		}
	
		// Demoman
		case TFClass_DemoMan: {
			TF2Attrib_SetByName(iClient, "mult charge turn control", 2.0);
			
			switch (iPrimaryIndex) {
				case 308: {	// Loch-n-Load
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.75);
					TF2Attrib_SetByName(iPrimary, "sticky air burst mode", 2.0);
					TF2Attrib_SetByName(iPrimary, "Projectile speed increased", 1.4);
					TF2Attrib_SetByName(iPrimary, "grenade no spin", 1.0);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 3);
				}
				case 1151: {	// Iron Bomber
					TF2Attrib_SetByName(iPrimary, "grenade no bounce", 1.0);
					TF2Attrib_SetByName(iPrimary, "Blast radius decreased", 0.6);
					//TF2Attrib_SetByName(iPrimary, "custom projectile model", "models/workshop/weapons/c_models/c_quadball/w_quadball_grenade.mdl");
				}
				case 996: {	// Loose Cannon
					//TF2Attrib_SetByName(iPrimary, "projectile speed increased", 1.5);
					//TF2Items_SetAttribute(item1, 1, 127, 1.0); // sticky air burst mode
				}
				case 405, 608: {	// Ali Baba's Wee Booties
					TF2Attrib_SetByName(iPrimary, "move speed bonus", 1.10);
					TF2Attrib_SetByName(iPrimary, "mult charge turn control", 2.0);
					TF2Attrib_SetByName(iClient, "charge recharge rate increased", 1.25);
				}
			}
			
			switch (iSecondaryIndex) {
				case 131, 1144: {	// Chargin' Targe
					TF2Attrib_SetByName(iSecondary, "dmg from ranged reduced", 65.0);
					TF2Attrib_SetByName(iSecondary, "airblast vulnerability multiplier", 0.25);
					TF2Attrib_SetByName(iSecondary, "damage force reduction", 0.25);
				}
			}
			
			switch (iMeleeIndex) {
				case 132, 266, 482, 1082: {	// Eyelander
					TF2Attrib_SetByName(iMelee, "is_a_sword", 72.0);
					TF2Attrib_SetByName(iMelee, "max health additive penalty", -25.0);
					TF2Attrib_SetByName(iMelee, "decapitate type", 1.0);
					TF2Attrib_SetByName(iMelee, "kill eater kill type", 6.0);
					
					if (players[iClient].iLoadout != iPrimaryIndex + iSecondaryIndex) SetEntProp(iClient, Prop_Send, "m_iDecapitations", 0);
					players[iClient].iLoadout = iPrimaryIndex + iSecondaryIndex;
					
					int heads = GetEntProp(iClient, Prop_Send, "m_iDecapitations");
					DataPack pack = new DataPack();
					pack.Reset();
					pack.WriteCell(iClient);
					pack.WriteCell(heads);
					pack.WriteCell(0);
					RequestFrame(updateHeads, pack);
				}
				case 172: {	// Scotsman's Skullcutter
					TF2Attrib_SetByName(iMelee, "is_a_sword", 72.0);
					TF2Attrib_SetByName(iMelee, "damage bonus", 1.2);
					TF2Attrib_SetByName(iMelee, "minicritboost on kill", 4.0);
				}
			}
		}
	
		// Heavy
		case TFClass_Heavy: {
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			TF2Attrib_SetByName(iClient, "aiming movespeed increased", 1.04054);	// 50% penalty, rather than 53%
			TF2Attrib_SetByName(iClient, "hidden primary max ammo bonus", 0.75);
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 150, _, primaryAmmo);
			TF2Attrib_SetByName(iMelee, "fire rate bonus", 0.75);
		
			switch (iPrimaryIndex) {
				case 41: {	// Natascha
					TF2Attrib_SetByName(iPrimary, "provide on active", 1.0);
					TF2Attrib_SetByName(iPrimary, "health on radius damage", 2.0);
					TF2Attrib_SetByName(iPrimary, "heal on kill", 20.0);
					TF2Attrib_SetByName(iPrimary, "damage penalty", 0.75);
					TF2Attrib_SetByName(iPrimary, "health from healers reduced", 0.5);
				}
			}
			
			switch (iSecondaryIndex) {
				case 42, 863, 1002: {	// Sandvich
					TF2Attrib_SetByName(iSecondary, "lunchbox healing decreased", 0.67);
				}
			}
			
			switch (iMeleeIndex) {
				case 43: {	// Killing Gloves of Boxing
					TF2Attrib_SetByName(iMelee, "critboost on kill", 5.0);
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.75);
				}
			}
		}
	
		// Engineer
		case TFClass_Engineer: {
			TF2Attrib_SetByName(iClient, "build rate bonus", 0.5);
			TF2Attrib_SetByName(iClient, "engineer sentry build rate multiplier", 0.5);
			
			switch (iPrimaryIndex) {
				case 141, 1004: {	// Frontier Justice
					TF2Attrib_SetByName(iPrimary, "mod sentry killed revenge", 1.0);
					TF2Attrib_SetByName(iPrimary, "lose revenge crits on death DISPLAY ONLY", 0.5);
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.5);
				}
				case 527: {	// Widowmaker
					TF2Attrib_SetByName(iPrimary, "damage bonus bullet vs sentry target", 1.1);
					TF2Attrib_SetByName(iPrimary, "mod ammo per shot", 30.0);
					TF2Attrib_SetByName(iPrimary, "mod use metal ammo type", 1.0);
					TF2Attrib_SetByName(iPrimary, "mod no reload DISPLAY ONLY", 1.0);
					TF2Attrib_SetByName(iPrimary, "mod max primary clip override", -1.0);
					TF2Attrib_SetByName(iPrimary, "add onhit addammo", 100.0);
				}
			}
			
			switch (iMeleeIndex) {
				case 155: {	// Southern Hospitality
					TF2Attrib_SetByName(iMelee, "engy disposable sentries", 1.0);
					TF2Attrib_SetByName(iMelee, "Repair rate decreased", 0.75);
				}
				case 142: {	// Gunslinger
					TF2Attrib_SetByName(iMelee, "gunslinger punch combo", 1.0);
					TF2Attrib_SetByName(iMelee, "mod wrench builds minisentry", 1.0);
					TF2Attrib_SetByName(iMelee, "max health additive bonus", 1.0);
					TF2Attrib_SetByName(iMelee, "engineer sentry build rate multiplier", 1.0);
				}
				case 329: {	// Jag
					TF2Attrib_SetByName(iMelee, "Construction rate increased", 1.3);
					TF2Attrib_SetByName(iMelee, "fire rate bonus", 0.85);
					TF2Attrib_SetByName(iMelee, "Repair rate decreased", 0.6);
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.75);
					TF2Attrib_SetByName(iMelee, "dmg penalty vs buildings", 0.67);
				}
				case 589: {	// Eureka Effect
					TF2Attrib_SetByName(iMelee, "alt fire teleport to spawn", 1.0);
					TF2Attrib_SetByName(iMelee, "special taunt", 1.0);
					TF2Attrib_SetByName(iMelee, "Construction rate decreased", 0.5);
					TF2Attrib_SetByName(iMelee, "metal_pickup_decreased", 0.8);
					TF2Attrib_SetByName(iMelee, "mod teleporter cost", 0.5);
				}
			}
		}
	
		// Medic
		case TFClass_Medic: {
			TF2Attrib_SetByName(iClient, "clip size penalty", 0.625);
			TF2Attrib_SetByName(iPrimary, "override projectile type", 9.0);
			SetEntProp(iPrimary, Prop_Send, "m_iClip1", 25);
			
			switch (iPrimaryIndex) {
				case 36: {	// Blutsauger
					TF2Attrib_SetByName(iPrimary, "clip size penalty", 0.6);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 15);
				}
			}
			
			switch (iSecondaryIndex) {
				case 35: {	// Kritzkreig
					TF2Attrib_SetByName(iSecondary, "medigun charge is crit boost", 1.0);
					TF2Attrib_SetByName(iSecondary, "ubercharge rate bonusd", 1.25);
				}
				case 411: {	// Quick-Fix
					TF2Attrib_SetByName(iSecondary, "lunchbox adds minicrits", 2.0);
					TF2Attrib_SetByName(iSecondary, "heal rate bonus", 1.25);
					TF2Attrib_SetByName(iSecondary, "medigun charge is megaheal", 2.0);
					TF2Attrib_SetByName(iSecondary, "overheal penalty", 0.0);
				}
			}
			
			switch (iMeleeIndex) {
				case 37, 1003: {	// Ubersaw
					TF2Attrib_SetByName(iMelee, "add uber charge on hit", 0.2);
				}
			}
		}
	
		// Sniper
		case TFClass_Sniper: {
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			TF2Attrib_SetByName(iClient, "max health additive bonus", 25.0);
			TF2Attrib_SetByName(iClient, "sniper charge per sec", 2.0);
			int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
			SetEntProp(iClient, Prop_Data, "m_iAmmo", 25 , _, primaryAmmo);
			SetEntData(iPrimary, iAmmoTable, 4, 4, true);
			
			switch (iPrimaryIndex) {
				case 56, 1005: {	// Huntsman
					TF2Attrib_SetByName(iPrimary, "faster reload rate", 0.4);
					TF2Attrib_SetByName(iPrimary, "speed_boost_on_hit", 3.0);
					TF2Attrib_SetByName(iPrimary, "hidden primary max ammo bonus", 0.5);
					SetEntProp(iClient, Prop_Data, "m_iAmmo", 12, _, primaryAmmo);
					SetEntProp(iPrimary, Prop_Send, "m_iClip1", 1);
				}
			}
			
			switch (iSecondaryIndex) {
				case 58, 1083: {	// Jarate
					TF2Attrib_SetByName(iSecondary, "jarate description", 1.0);
					TF2Attrib_SetByName(iSecondary, "effect bar recharge rate increased", 2.0); // 40 seconds
					TF2Attrib_SetByName(iSecondary, "item_meter_resupply_denied", 1.0);
					TF2Attrib_SetByName(iSecondary, "extinguish reduces cooldown", 0.8);
				}
				case 57: {	// Razorback
					TF2Attrib_SetByName(iSecondary, "item_meter_charge_type", 1.0);
					TF2Attrib_SetByName(iSecondary, "item_meter_charge_rate", 30.0);
					TF2Attrib_SetByName(iSecondary, "move speed penalty", 0.9);
					
					SetEntProp(iSecondary, Prop_Data, "m_fEffects", 129);	// 129 = intact
					players[iClient].fRazorback_Health = 25.0;
				}
			}
			
			switch (iMeleeIndex) {
				case 171: {	// Tribalman's Shiv
					TF2Attrib_SetByName(iMelee, "bleeding duration", 6.0);
					TF2Attrib_SetByName(iMelee, "damage penalty", 0.75);
				}
			}
		}
	
		// Spy
		case TFClass_Spy: {
			TF2Attrib_SetByName(iClient, "max health additive bonus", 25.0);
			TF2Attrib_SetByName(iClient, "cloak consume rate decreased", 0.833333);	// 12 seconds
			
			switch (iSecondaryIndex) {
				case 61, 1006: {	// Ambassador
					TF2Attrib_SetByName(iSecondary, "Reload time increased", 1.35);
					TF2Attrib_SetByName(iSecondary, "clip size penalty", 0.5);
					SetEntProp(iSecondary, Prop_Send, "m_iClip1", 3);
				}
				case 224: {	// L'Etranger
					TF2Attrib_SetByName(iSecondary, "add cloak on hit", 0.25);
					TF2Attrib_SetByName(iSecondary, "damage penalty", 0.8);
				}
			}

			switch (iMeleeIndex) {
				case 225, 574: {	// Your Eternal Reward
					TF2Attrib_SetByName(iMelee, "disguise on backstab", 1.0);
					TF2Attrib_SetByName(iMelee, "silent killer", 1.0);
					TF2Attrib_SetByName(iMelee, "lunchbox adds minicrits", 1.0);
				}
			}
			
			switch (iWatchIndex) {
				case 60: {	// Cloak and Dagger
					TF2Attrib_SetByName(iWatch, "set cloak is movement based", 2.0);
					TF2Attrib_SetByName(iWatch, "mult cloak meter regen rate", 2.5);
					TF2Attrib_SetByName(iWatch, "ReducedCloakFromAmmo", 0.5);
				}
			}
		}
	}
	
	int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
	GetEntProp(iClient, Prop_Send, "m_iHealth", iMaxHealth);
	
	return Plugin_Handled;
}


public Action Event_PlayerDeath(Event event, const char[] cName, bool dontBroadcast) {
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (!IsValidClient(attacker)) return Plugin_Continue;

	int iWeaponIndex = event.GetInt("weapon_def_index");
	/*int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
	int iPrimaryIndex = -1;
	if (iPrimary >= 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
	int iSecondaryIndex = -1;
	if (iSecondary >= 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
	int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
	int iMeleeIndex = -1;
	if (iMelee >= 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");*/

	// Blutsauger heal on patient kills
	for (int iOther = 1 ; iOther <= MaxClients ; iOther++) {
		if (!IsValidClient(iOther)) continue;
		int iWeapon = GetEntPropEnt(iOther, Prop_Data, "m_hActiveWeapon");
		if (iWeapon < 0) continue;
		char classname[64];
		GetEntityClassname(iWeapon, classname, sizeof(classname));
		if (!StrEqual(classname, "tf_weapon_medigun")) continue;

		int iPatient = GetEntPropEnt(iWeapon, Prop_Send, "m_hHealingTarget");
		if (iPatient != attacker) continue;
		
		int iMedicPrimary = TF2Util_GetPlayerLoadoutEntity(iOther, TFWeaponSlot_Primary, true);
		int iMedicPrimaryIndex = -1;
		if (iMedicPrimary >= 0) iMedicPrimaryIndex = GetEntProp(iMedicPrimary, Prop_Send, "m_iItemDefinitionIndex");
		
		if (iMedicPrimaryIndex == 36) {
			TF2Util_TakeHealth(iOther, 30.0);
			Event eventHeal = CreateEvent("player_healonhit");
			if (eventHeal) {
				eventHeal.SetInt("amount", 30);
				eventHeal.SetInt("entindex", iOther);
				
				eventHeal.FireToClient(iOther);
				delete eventHeal;
			}
		}
	}

	// Eyelander heads remove health bonus
	if (TFClass_DemoMan == TF2_GetPlayerClass(attacker) && (iWeaponIndex == 132 || iWeaponIndex == 266 || iWeaponIndex == 482 || iWeaponIndex == 1082)) {
		int heads = GetEntProp(attacker, Prop_Send, "m_iDecapitations");
		DataPack pack = new DataPack();
		pack.Reset();
		pack.WriteCell(attacker);
		pack.WriteCell(heads);
		pack.WriteCell(0);
		RequestFrame(updateHeads, pack);
	}

	// Your Eternal Reward cloak drain
	if (TFClass_Spy == TF2_GetPlayerClass(attacker) && (iWeaponIndex == 225 || iWeaponIndex == 574)) {
		float fCloak;
		fCloak = GetEntPropFloat(attacker, Prop_Send, "m_flCloakMeter");
		SetEntPropFloat(attacker, Prop_Send, "m_flCloakMeter", fCloak > 50.0 ? fCloak - 50.0 : 0.0);		// Subtract 20 cloak per shot
	}
	
	return Plugin_Continue;
}

public void TF2_OnConditionAdded(int iClient, TFCond condition) {
	
	//int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	//int iPrimaryIndex = -1;
	//if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	// No capture Crits
	if (condition == TFCond_CritOnFlagCapture) {
		TF2_RemoveCondition(iClient, TFCond_CritOnFlagCapture);
	}
	// No slowing effects from anything
	else if (condition == TFCond_Dazed) {
		TF2_RemoveCondition(iClient, TFCond_Dazed);
	}
	
	if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
		int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
		int iWatchIndex = -1;
		if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
	
		// Dead Ringer
		if (condition == TFCond_Cloaked && iWatchIndex == 59) {
			TF2_AddCondition(iClient, TFCond_Stealthed, 1.0);
			TF2_AddCondition(iClient, TFCond_Disguising, 1.0);
			TF2Attrib_AddCustomPlayerAttribute(iClient, "move speed bonus", 1.2);
			CreateSmoke(iClient);
		}
	}
}

public void TF2_OnConditionRemoved(int iClient, TFCond condition) {
	//int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	//int iMeleeIndex = -1;
	//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
	int iWatchIndex = -1;
	if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
	
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
		
		// Dead Ringer
		if (condition == TFCond_Cloaked && iWatchIndex == 59) {
			SetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter", 0.0);
			TF2Attrib_RemoveByName(iClient, "move speed bonus");
			SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 320.0);
		}
	}
}

public void OnEntityCreated(int iEnt, const char[] classname) {
	if (!IsValidEdict(iEnt)) return;
	
	if (StrEqual(classname, "tf_projectile_pipe")) {
		SDKHook(iEnt, SDKHook_Think, PipeSet);
	}
	
	if (StrEqual(classname, "obj_sentrygun") || StrEqual(classname, "obj_dispenser") || StrEqual(classname, "obj_teleporter")) {
		SDKHook(iEnt, SDKHook_OnTakeDamage, BuildingDamage);
		CreateTimer(0.01, BuildingHealthBuff, iEnt);
	}
	
	else if(StrEqual(classname, "tf_projectile_syringe")) {
		SDKHook(iEnt, SDKHook_SpawnPost, needleSpawn);
	}
}

public void OnGameFrame() {
	for (int iClient = 1; iClient <= MaxClients; iClient++) {
		if (!(IsClientInGame(iClient) && IsPlayerAlive(iClient))) continue;
	
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
		//int iMeleeIndex = -1;
		//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
		
		// Health regen (Blutsauger disables)
		if (players[iClient].fHealth_Regen < 25.0 && iPrimaryIndex != 36) players[iClient].fHealth_Regen += 0.015;
		if (players[iClient].fHealth_Regen_Timer < 1.0) {
			players[iClient].fHealth_Regen_Timer += 0.015;
		}
		else {
			players[iClient].fHealth_Regen_Timer = 0.0;
			TriggerHealing(iClient);
		}
		
		// Cap overheal at 125%
		int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
		int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
		if (iHealth > RoundToFloor(iMaxHealth * 1.25)) SetEntProp(iClient, Prop_Send, "m_iHealth", RoundToFloor(iMaxHealth * 1.25));
		
		// Cap Afterburn at 5 seconds
		if (TF2Util_GetPlayerBurnDuration(iClient) > 5.0) {
			TF2Util_SetPlayerBurnDuration(iClient, 5.0);
		}
		
		if (TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping) && (GetEntityFlags(iClient) & FL_ONGROUND)) {
			TF2_RemoveCondition(iClient, TFCond_BlastJumping);
		}
		
		switch (TF2_GetPlayerClass(iClient)) {
			
			// Soldier
			case TFClass_Soldier: {
				// Equalizer
				if (iHealth < iMaxHealth / 2.0 && iActiveIndex == 128) {
					TF2_AddCondition(iClient, TFCond_CritOnFirstBlood, 0.5);
				}
			}
			
			// Demoman
			case TFClass_DemoMan: {
				// Trigger Mini-Crits after 0.9 sec charging
				float fCharge = GetEntPropFloat(iClient, Prop_Send, "m_flChargeMeter");
				if (fCharge <= 40.0  && TF2_IsPlayerInCondition(iClient, TFCond_Charging) && iActive == iMelee) {
					players[iClient].bCharge_Crit_Prepped = true;
				}
				else if (players[iClient].bCharge_Crit_Prepped == true) {
					CreateTimer(0.3, RemoveChargeCrit, iClient);
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
				}
			}
			
			// Sniper
			case TFClass_Sniper: {
				// Huntsman movement speed
				if (iActive == iPrimary && (iPrimaryIndex == 56 || iPrimaryIndex == 1005)) {
					if (TF2_IsPlayerInCondition(iClient, TFCond_SpeedBuffAlly)) SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 405.0);
					else SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 300.0);
				}
				
				// Sniper Rifle reload
				if (iPrimaryIndex != 56 && iPrimaryIndex != 1005 && iPrimaryIndex != 1092) {		// Do not trigger on Huntsman
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int reload = GetEntProp(iPrimary, Prop_Send, "m_iReloadMode");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					float cycle = GetEntPropFloat(view, Prop_Data, "m_flCycle");
					if (sequence == 29 || sequence == 28) {
						if (cycle >= 1.0) SetEntProp(view, Prop_Send, "m_nSequence", 30);
					}

					if (reload != 0) {
						float reloadSpeed = 0.8;
						float clientPos[3];
						GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", clientPos);

						int relSeq = 51;		// This used to be 41
						float altRel = 0.875;
						
						SetEntPropFloat (view, Prop_Send, "m_flPlaybackRate", (altRel*2.0) / reloadSpeed);
						
						if (TF2_IsPlayerInCondition(iClient, TFCond_Slowed)) {		// Are we scoped?
							TF2_RemoveCondition(iClient, TFCond_Slowed);
						}
						if (TF2_IsPlayerInCondition(iClient, TFCond_Zoomed)) {
							TF2_RemoveCondition(iClient, TFCond_Zoomed);
						}
						
						if (reload == 1) {
							if (sequence != relSeq) SetEntProp(view, Prop_Send, "m_nSequence",relSeq);
							SetEntPropFloat(view, Prop_Data, "m_flCycle", g_meterPri[iClient]); //1004
							SetEntDataFloat(view, 1004, g_meterPri[iClient], true); //1004
							if (g_meterPri[iClient] / reloadSpeed > 0.1) {
								EmitSoundToClient(iClient, "weapons/widow_maker_pump_action_forward.wav");
								SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 2);
							}
						}
						else if (reload == 2) {
							if(sequence != relSeq) SetEntProp(view, Prop_Send, "m_nSequence",relSeq);
							SetEntPropFloat(view, Prop_Data, "m_flCycle",g_meterPri[iClient]); //1004
							SetEntDataFloat(view, 1004,g_meterPri[iClient], true); //1004
							if(g_meterPri[iClient] / reloadSpeed > 0.4) {
								EmitSoundToClient(iClient, "weapons/revolver_reload_cylinder_arm.wav");
								SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 3);
							}
						}
						else if (reload == 3) {
							if(sequence != relSeq) SetEntProp(view, Prop_Send, "m_nSequence",relSeq);
							SetEntPropFloat(view, Prop_Data, "m_flCycle",g_meterPri[iClient]); //1004
							SetEntDataFloat(view, 1004,g_meterPri[iClient], true); //1004
							if(g_meterPri[iClient] / reloadSpeed > 0.8) {
								EmitSoundToClient(iClient, "weapons/widow_maker_pump_action_back.wav");
								SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 4);
							}
						}
						g_meterPri[iClient] += 1.0 / 66;
					}
					
					int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
					int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
					
					SetHudTextParams(-0.1, -0.16, 0.5, 255, 255, 255, 255);
					ShowHudText(iClient, 1, "Reserves: %i", ammoCount);
				}
				
				// Razorback
				if (iSecondaryIndex == 57) {
					SetHudTextParams(-0.1, -0.23, 0.5, 255, 255, 255, 255);
					if (players[iClient].fRazorback_Health > 0.0) {
						ShowHudText(iClient, 2, "Shield: %.0f%%", players[iClient].fRazorback_Health * 4.0);
					}
					else ShowHudText(iClient, 2, "Shield Broken!");
				}
			}
		}
	}
}

public void updateHeads(DataPack pack) {
	pack.Reset();
	int iClient = pack.ReadCell();
	int heads = pack.ReadCell();
	int respawn = pack.ReadCell();
	int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	
	if (heads > 4) heads = 4;
	
	TF2Attrib_SetByName(iClient, "max health additive penalty", RemapValClamped(float(heads), 0.0, 4.0, 0.0, -60.0));
	TF2Attrib_SetByName(iMelee, "fire rate bonus HIDDEN", RemapValClamped(float(heads), 0.0, 4.0, 1.0, 0.6));
	TF2Attrib_SetByName(iMelee, "move speed penalty", RemapValClamped(float(heads), 0.0, 4.0, 1.0, 0.909090));	// Reduce speed to 5% per head (from 8%)
	if (respawn == 1) TF2Util_TakeHealth(iClient, 200.0);
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
		vecVel[0] = Cosine(DegToRad(vecAng[0])) * Cosine(DegToRad(vecAng[1])) * 1600.0;
		vecVel[1] = Cosine(DegToRad(vecAng[0])) * Sine(DegToRad(vecAng[1])) * 1600.0;
		vecVel[2] = Sine(DegToRad(vecAng[0])) * -1600.0;
		
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

public Action TF2_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom, CritType &critType) {
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
			
			int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
			int iPrimaryIndex = -1;
			if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
			/*int iSecondaryIndex = -1;
			if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");*/
			
			int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
			//int iMeleeIndex = -1;
			//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
			
			//int iWatch = TF2Util_GetPlayerLoadoutEntity(victim, 6, true);		// NB: This checks the victim rather than the attacker
			//int iWatchIndex = -1;
			//if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
			
			// -== Victims ==-
			// Sniper
			if (TF2_GetPlayerClass(victim) == TFClass_Sniper) {
				int iVictimSecondary = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Secondary, true);
				int iVictimSecondaryIndex = -1;
				if(iVictimSecondary > 0) iVictimSecondaryIndex = GetEntProp(iVictimSecondary, Prop_Send, "m_iItemDefinitionIndex");
				
				// Razorback
				if (iVictimSecondaryIndex == 57) {
					if (players[victim].fRazorback_Health > 0.0) {
						
						players[victim].fRazorback_Health -= damage;
						damage = 0.0;
						
						if (players[victim].fRazorback_Health <= 0.0) {
							SetEntProp(iVictimSecondary, Prop_Data, "m_fEffects", 161);	// 161 = broken
							TF2_AddCondition(victim, TFCond_SpeedBuffAlly, 5.0);
						}
					}
				}
			}
			
			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				if (weapon == iMelee) {
					damage *= 1.285714;		// 45 base damage
				}
			}
			
			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {
				if (weapon == iMelee) {
					// Equalizer
					if (iWeaponIndex == 128) {
						if (TF2_IsPlayerInCondition(attacker, TFCond_CritOnFirstBlood)) {
							//damage_type |= DMG_CRIT;
							critType = CritType_Crit;
						}
					}
				}
			}
			
			// Pyro
			if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
				if (weapon == iPrimary && inflictor != attacker) {
					// Dragon's Fury
					if (iWeaponIndex == 1178) {
						damage *= 2.6;		// 65 base damage
					}
					else {
						damage *= 1.15;	// 15 base damage (up from 13)
					}
					
					if (iWeaponIndex == 40 || iWeaponIndex == 1146) {		// Backburner
						float vecVictimFacing[3], vecDirection[3];
						MakeVectorFromPoints(vecAttacker, vecVictim, vecDirection);
						
						GetClientEyeAngles(victim, vecVictimFacing);
						GetAngleVectors(vecVictimFacing, vecVictimFacing, NULL_VECTOR, NULL_VECTOR);
						
						float dotProduct = GetVectorDotProduct(vecDirection, vecVictimFacing);
						bool isBehind = dotProduct > 0.707;		// Outside of 90 degree back angle
						
						if (!isBehind && !isKritzed(attacker)) damage *= 0.85;
						
						if (3.0 * damage > GetEntProp(victim, Prop_Send, "m_iHealth") && (isBehind || isKritzed(attacker))) {
							TF2Util_TakeHealth(attacker, 40.0);
							Event event = CreateEvent("player_healonhit");
							if (event) {
								event.SetInt("amount", 40);
								event.SetInt("entindex", attacker);
								
								event.FireToClient(attacker);
								delete event;
							}
						}
					}
				}
				else if (weapon == iSecondary && inflictor != attacker) {
					// Flare Gun
					if (iWeaponIndex == 39 || iWeaponIndex == 1081) {
						if (TF2Util_GetPlayerBurnDuration(victim) > 0.0) critType = CritType_Crit;
					}
				}
				else if (weapon == iMelee) {
					damage *= 1.307692;		// 85 base damage
					
					// Axtinguisher
					if (iWeaponIndex == 38 || iWeaponIndex == 457 || iWeaponIndex == 1000) {
						TF2Util_SetPlayerBurnDuration(victim, 0.0);
					}
				}
				else if (inflictor == attacker) {
					if (!isMiniKritzed(attacker, victim)) {
						damage_type &= ~DMG_CRIT;
						critType = CritType_None;
					}
				}
				if (iPrimaryIndex == 1178 && (!isMiniKritzed(attacker, victim) && !isKritzed(attacker))) {
					if (weapon != iPrimary && weapon != iSecondary && weapon != iMelee) {
						damage_type &= ~DMG_CRIT;
						critType = CritType_None;
					}
				}
			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				if (weapon == iPrimary) {
					// Iron Bomber
					if (iWeaponIndex == 1151) {
						if (fDistance > 512.0) {
							fDmgMod *= SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);	// 20% fall-off
							damage *= fDmgMod;
						}
						
						if (TF2_IsPlayerInCondition(attacker, TFCond_BlastJumping) || TF2_IsPlayerInCondition(attacker, TFCond_Charging)) {
							critType = CritType_MiniCrit;
						}
					}
				}
				else if (weapon == iMelee) {
					if (!isKritzed(attacker) && players[attacker].bCharge_Crit_Prepped == true) {
						if (iPrimaryIndex == 405 || iPrimaryIndex == 608) {
							critType = CritType_Crit;
						}
						else {
							critType = CritType_MiniCrit;
						}
					}
				}
			}

			// Heavy
			if (TF2_GetPlayerClass(attacker) == TFClass_Heavy) {
				if (weapon == iPrimary) {
					// Natascha
					if (iWeaponIndex == 41) {
						TF2Util_TakeHealth(attacker, 2.0);
						Event event = CreateEvent("player_healonhit");		// Inform the user that they have been healed and by how much
						if (event) {
							event.SetInt("amount", 2);
							event.SetInt("entindex", attacker);
							
							event.FireToClient(attacker);
							delete event;
						}
					}
				}
			}
			
			// Medic
			if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
				// Syringe Gun
				if (StrEqual(class, "tf_weapon_syringegun_medic")) {
					
					damage_type |= DMG_BULLET;
					if (!isKritzed(attacker)) {
						if (fDistance > 512.0) fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.5, 0.5);
						else fDmgMod = SimpleSplineRemapValClamped(fDistance, 0.0, 1024.0, 1.2, 0.8);
						if (isMiniKritzed(attacker, victim) && fDistance > 512.0) {
							fDmgMod = 1.0;
							critType = CritType_MiniCrit;
						}
					}
					else {
						fDmgMod = 3.0;
						damage_type |= DMG_CRIT;
						critType = CritType_Crit;
					}
					damage = 7.5 * fDmgMod;
				}
				// Ubersaw
				else if (iWeaponIndex == 37 || iWeaponIndex == 1003) {
					TF2_AddCondition(attacker, TFCond_MarkedForDeathSilent, 2.0);
				}
			}
			
			// Sniper
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
				if (weapon == iPrimary) {
					fDmgMod = 1.0;
					if (iWeaponIndex != 56 && iWeaponIndex != 1092 && iWeaponIndex != 1005) {
						damage = 50.0;	
						float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
						fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 2.0);		// 2x bonus damage from charging
						
						fDmgMod *= RemapValClamped(fDistance, 512.0, 1024.0, 1.0, 0.5);	// 50% fall-off
						damage *= fDmgMod;
					
						if (isKritzed(attacker)) critType = CritType_Crit;
						int hitgroup = GetEntProp(victim, Prop_Data, "m_LastHitGroup");
						if (hitgroup && hitgroup == 1 && fCharge > 0.0) {
							if (!isKritzed(attacker)) damage *= 0.666666;
							critType = CritType_Crit;
						}
					}
					else return Plugin_Continue;
				}
				
				else if (weapon == iSecondary) {
					damage *= 1.875;		// 15 base damage(!)
				}
			}
			
			// Spy
			if (TF2_GetPlayerClass(attacker) == TFClass_Spy) {
				if (weapon == iSecondary) {
					// Ambassador
					if (iWeaponIndex == 61 || iWeaponIndex == 1006) {
						int hitgroup = GetEntProp(victim, Prop_Data, "m_LastHitGroup");
						if (hitgroup && hitgroup == 1) {
							critType = CritType_MiniCrit;
						}
						
						if (players[attacker].iHeadshot_Frame == GetGameTickCount()) {
							critType = CritType_MiniCrit;
						}
					}
				}
			}
			
			if (isKritzed(attacker)) {
				critType = CritType_Crit;
			}
			else if (isMiniKritzed(attacker, victim)) {
				critType = CritType_MiniCrit;
			}
		}
	}
	
	if (victim >= 1 && victim <= MaxClients) {		// Trigger this on any damage source
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(victim, TFWeaponSlot_Secondary, true);
		int iSecondaryIndex = -1;
		if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
		
		if (damage_type & DMG_FALL == DMG_FALL) {
			// Gunboats
			if (iSecondaryIndex == 133) {
				damage *= 0.4;
			}
		}
	}
	
	return Plugin_Changed;
}

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
			
			if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {	// We need to handle the Huntsman separately because the other function breaks the headshot hitreg
				float fDmgMod = 1.0;
				if (damage_type & DMG_CRIT != 0) {
					fDmgMod = SimpleSplineRemapValClamped(damage, 150.0, 360.0, 1.0, 0.833333);	// Reduce max damage to 100
					if (!isKritzed(attacker)) {
						damage *= 0.666666;	
					}
				}
				else {
					fDmgMod = SimpleSplineRemapValClamped(damage, 50.0, 120.0, 1.0, 0.833333);
				}
				
				if (iWeaponIndex == 56 || iWeaponIndex == 1092 || iWeaponIndex == 1005) {
					fDmgMod *= RemapValClamped(fDistance, 512.0, 1024.0, 1.0, 0.5);	// 50% fall-off
					damage *= fDmgMod;
				}
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
			
			// -== Victims ==-
			// Scout
			if (TF2_GetPlayerClass(victim) == TFClass_Scout) {

			}
			
			// Soldier
			if (TF2_GetPlayerClass(victim) == TFClass_Soldier) {
				
			}
			
			// Spy
			else if (TF2_GetPlayerClass(victim) == TFClass_Spy) {

			}
			
			// -== Attackers ==-
			// Scout
			if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
				// Sandman
				if (iWeaponIndex == 44) {
					if (attacker != inflictor) {
						// Play the old stun voicelines
						float vecPos[3];
						GetClientEyePosition(attacker, vecPos);
						int rndact = GetRandomUInt(0, 5);
						switch(rndact) {
							case 0: EmitAmbientSound("vo/scout_stunballhit01.mp3", vecPos, attacker);
							case 1: EmitAmbientSound("vo/scout_stunballhit02.mp3", vecPos, attacker);
							case 2: EmitAmbientSound("vo/scout_stunballhit03.mp3", vecPos, attacker);
							case 3: EmitAmbientSound("vo/scout_stunballhit04.mp3", vecPos, attacker);
							case 4: EmitAmbientSound("vo/scout_stunballhit05.mp3", vecPos, attacker);
							case 5: EmitAmbientSound("vo/scout_stunballhit06.mp3", vecPos, attacker);
							case 6: EmitAmbientSound("vo/scout_stunballhit07.mp3", vecPos, attacker);
							case 7: EmitAmbientSound("vo/scout_stunballhit08.mp3", vecPos, attacker);
							case 8: EmitAmbientSound("vo/scout_stunballhit09.mp3", vecPos, attacker);
							case 9: EmitAmbientSound("vo/scout_stunballhit010.mp3", vecPos, attacker);
							case 10: EmitAmbientSound("vo/scout_stunballhit011.mp3", vecPos, attacker);
							case 11: EmitAmbientSound("vo/scout_stunballhit012.mp3", vecPos, attacker);
							case 12: EmitAmbientSound("vo/scout_stunballhit013.mp3", vecPos, attacker);
							case 13: EmitAmbientSound("vo/scout_stunballhit014.mp3", vecPos, attacker);
							case 14: EmitAmbientSound("vo/scout_stunballhit015.mp3", vecPos, attacker);
							case 15: EmitAmbientSound("vo/scout_stunballhit016.mp3", vecPos, attacker);
						}
						
						TF2Attrib_AddCustomPlayerAttribute(attacker, "move speed bonus", 1.3);
						TF2Attrib_AddCustomPlayerAttribute(attacker, "fire rate bonus", 0.7);
						CreateTimer(5.0, RemoveBaseballBuff, attacker);
					}
				}
			}
			
			// Soldier
			if (TF2_GetPlayerClass(attacker) == TFClass_Soldier) {

			}
			
			// Pyro
			else if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {

			}
			
			// Demoman
			if (TF2_GetPlayerClass(attacker) == TFClass_DemoMan) {
				// Loch-n-Load reload on kill
				if (iWeaponIndex != 308) return;
				if (damage < GetEntProp(victim, Prop_Send, "m_iHealth")) return;
					
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				int iClipMax = 3;				
				int clip = GetEntData(weapon, iAmmoTable, 4);
				int ammoSubtract = iClipMax - clip;
				
				int primaryAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
				int ammoCount = GetEntProp(attacker, Prop_Data, "m_iAmmo", _, primaryAmmo);
				
				if (clip < iClipMax && ammoCount > 0) {
					if (ammoCount < iClipMax) {
						ammoSubtract = ammoCount;
					}
					SetEntProp(attacker, Prop_Data, "m_iAmmo", ammoCount - ammoSubtract, _, primaryAmmo);
					SetEntData(weapon, iAmmoTable, iClipMax, 4, true);
				}
			}
		}
		
		players[attacker].fHealth_Regen = 0.0;
	}
	if (victim >= 1 && victim <= MaxClients) {		// Trigger this on any damage source, but still make sure the victim exists
		// Reset health regen
		players[victim].fHealth_Regen = 0.0;
	}
}

Action BuildingDamage (int building, int &attacker, int &inflictor, float &damage, int &damage_type, int &weapon, float damageForce[3], float damagePosition[3]) {
	if (weapon == -1) return Plugin_Continue;
	char class[64];
	GetEntityClassname(building, class, sizeof(class));
	
	if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
		GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
		int iWeaponIndex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
		float fDmgMod = 1.0;
		
		int iPrimary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Primary, true);
		/*int iPrimaryIndex = -1;
		if(iPrimary > 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");*/
		
		int iSecondary = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Secondary, true);
		/*int iSecondaryIndex = -1;
		if(iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");*/
		
		int iMelee = TF2Util_GetPlayerLoadoutEntity(attacker, TFWeaponSlot_Melee, true);
		//int iMeleeIndex = -1;
		//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
		
		// Scout
		if (TF2_GetPlayerClass(attacker) == TFClass_Scout) {
			if (weapon == iMelee) {
				damage *= 1.285714;		// 45 base damage
			}
		}
		
		// Pyro
		if (TF2_GetPlayerClass(attacker) == TFClass_Pyro) {
			if (weapon == iPrimary) {
				// Dragon's Fury
				if (iWeaponIndex == 1178) {
					damage *= 2.6;		// 65 base damage
				}
				else {
					damage *= 1.15;		// 15 base damage (up from 13)
				}
			}
			else if (weapon == iMelee) {
				damage *= 1.307692;		// 85 base damage
			}
		}
		
		// Medic
		if (TF2_GetPlayerClass(attacker) == TFClass_Medic) {
			// Syringe Gun
			if (StrEqual(class, "tf_weapon_syringegun_medic")) {
				
				damage_type |= DMG_BULLET;
				damage = 15.0;
			}
		}
		
		// Sniper
		if (TF2_GetPlayerClass(attacker) == TFClass_Sniper) {
			if (weapon == iPrimary) {
				fDmgMod = 1.0;
				if (iWeaponIndex != 56 && iWeaponIndex != 1092 && iWeaponIndex != 1005) {
					damage = 50.0;	
					float fCharge = GetEntPropFloat(weapon, Prop_Send, "m_flChargedDamage");
					fDmgMod = RemapValClamped(fCharge, 0.0, 150.0, 1.0, 2.0);		// 2x bonus damage from charging
					
				}
				damage *= fDmgMod;
			}
			
			else if (weapon == iSecondary) {
				damage *= 1.875;		// 15 base damage(!)
			}
		}
	}
	
	if (StrEqual("obj_sentrygun", class)) {
		int owner = GetEntPropEnt(building, Prop_Send, "m_hBuilder");
		if (owner != -1) {
			
			int iSecondary = TF2Util_GetPlayerLoadoutEntity(owner, TFWeaponSlot_Secondary, true);
			int iSecondaryIndex = -1;
			if (iSecondary > 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
			
			// Wrangler resistance
			if (iSecondaryIndex == 140 || iSecondaryIndex == 1086 || iSecondaryIndex == 30668) {
				int shield = GetEntProp(building, Prop_Send, "m_nShieldLevel");
				
				if (shield > 0) damage *= 2.0;	// 33% resistance
			}
		}
	}
	
	return Plugin_Changed;
}

public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	if (!(IsClientInGame(iClient) & IsPlayerAlive(iClient))) return;
	
	int iActive = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");

	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int iPrimaryIndex = -1;
	if(iPrimary >= 0) iPrimaryIndex = GetEntProp(iPrimary, Prop_Send, "m_iItemDefinitionIndex");
	
	int iSecondary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Secondary, true);
	//int iSecondaryIndex = -1;
	//if (iSecondary >= 0) iSecondaryIndex = GetEntProp(iSecondary, Prop_Send, "m_iItemDefinitionIndex");
	
	int iMelee = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Melee, true);
	//int iMeleeIndex = -1;
	//if(iMelee > 0) iMeleeIndex = GetEntProp(iMelee, Prop_Send, "m_iItemDefinitionIndex");
	
	// Scout
	if (TF2_GetPlayerClass(iClient) == TFClass_Scout) {
	
		// Force-A-Nature jump
		if ((iPrimaryIndex == 45 || iPrimaryIndex == 1078) && iActive == iPrimary) {
			if (buttons & IN_ATTACK && !(TF2_IsPlayerInCondition(iClient, TFCond_BlastJumping)) && !(GetEntityFlags(iClient) & FL_ONGROUND)) {
				if (GetEntPropFloat(iPrimary, Prop_Data, "m_flNextPrimaryAttack") < GetGameTime()) {
					ForceJump(iClient);
				}
			}
		}
	}
	
	// Heavy
	if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
		
		// Minigun holster while spun
		if (iPrimary == -1 || iActive != iPrimary) return;
		if (weapon > 0) {
			if (weapon == iSecondary) {
				bool bReady = true;
				char wep[64];
				GetEntityClassname(iSecondary, wep, 64);
				if (StrContains(wep,"lunchbox") != -1) {		// Are we holding a non-Lunchbox (i.e. a Shotgun)?
					int secondaryAmmo = GetEntProp(iSecondary, Prop_Send, "m_iPrimaryAmmoType");
					int ammo = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, secondaryAmmo);
					if (ammo == 0) {		// Don't let us swap to the Shotgun if it's out of ammo
						bReady = false;
					}
				}
				if (bReady) {
					SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() - 1.0);
					ClientCommand(iClient, "slot2");
				}
			}
			if (weapon == iMelee) {
				SetEntPropFloat(iPrimary, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() - 1.0);
				ClientCommand(iClient, "slot3");
			}
		}
	}
	
	// Sniper
	if (TF2_GetPlayerClass(iClient) == TFClass_Sniper) {
		
		// Huntsman passive reload
		if (iPrimary == -1) return;
		if (iActive != iPrimary) return;
		
		if (iPrimaryIndex == 56 || iPrimaryIndex == 1005 || iPrimaryIndex == 1092) {
		
			int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
			int clip = GetEntData(iPrimary, iAmmoTable, 4);		// Retrieve the loaded ammo of our primary
			
			int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
			int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);		// Retrieve the reserve primary ammo
			
			if (clip == 0 && ammoCount > 0 && weapon != 0 && weapon != iPrimary) {		// weapon is the weapon we swap to; check if we're swapping to something other than the bow
				SetEntProp(iClient, Prop_Data, "m_iAmmo", ammoCount-1 , _, primaryAmmo);		// Subtract reserve ammo
				SetEntData(iPrimary, iAmmoTable, 1, 4, true);		// Add loaded ammo
			}
		}
		
		// Sniper rifle reload
		int reload = GetEntProp(iPrimary, Prop_Send, "m_iReloadMode");
		int viewmodel = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
		int sequence = GetEntProp(viewmodel, Prop_Send, "m_nSequence");

		int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
		int clip = GetEntData(iPrimary, iAmmoTable, 4);

		int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
		int ammoCount = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, primaryAmmo);
		//PrintToChat(iClient, "Clip: %i and Reserves: %i", clip, ammoCount);

		float reloadSpeed = 0.8;
		int maxClip = 4;

		int ReloadAnim = 51;
		float altRel = 0.875;

		if (iActive == iPrimary) {
			
			// Dry fire
			if ((buttons & IN_ATTACK || buttons & IN_ATTACK2) && clip > 0 && ammoCount == 0) {
				SetEntProp(iClient, Prop_Data, "m_iAmmo", 1, _, primaryAmmo);
				RequestFrame(DryFireSniper, iClient);
			}
	
			// Start reloading
			if (((buttons & IN_RELOAD) || clip == 0) && reload == 0 && (sequence == 30 || sequence == 33) && clip < maxClip && ammoCount > 0) {	// Handle reloads
				g_meterPri[iClient] = 0.0;
				SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 1);
				SetEntProp(viewmodel, Prop_Send, "m_nSequence", ReloadAnim);
				SetEntPropFloat(viewmodel, Prop_Send, "m_flPlaybackRate", (2.0 * altRel) / reloadSpeed);
				if (TF2_IsPlayerInCondition(iClient, TFCond_Slowed) && !TF2_IsPlayerInCondition(iClient, TFCond_FocusBuff))
					buttons |= IN_ATTACK2;
			}
			
			// While reloading
			if (reload != 0) {
				if (buttons & IN_ATTACK) {
					if (clip > 0) {
						SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 0);		// Cancel reload to fire a shot
						g_meterPri[iClient] = 0.0;
					}
					else
						buttons &= ~IN_ATTACK;
				}
				if (buttons & IN_ATTACK2 && !TF2_IsPlayerInCondition(iClient, TFCond_FocusBuff)) {
					buttons &= ~IN_ATTACK2;		// Disable scope when out of ammo
					SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 300.0);
				}
				if (g_meterPri[iClient] >= reloadSpeed) {
					//int newClip = ammoCount - maxClip + clip < 0 ? ammoCount + clip : maxClip;
					int newClip = clip + 1;
					//int newAmmo  = ammoCount - maxClip + clip >= 0 ? ammoCount - maxClip + clip : 0;
					int newAmmo  = ammoCount - 1;
					SetEntProp(iClient, Prop_Data, "m_iAmmo", newAmmo , _, primaryAmmo);
					SetEntData(iPrimary, iAmmoTable, newClip, 4, true);
					if (newClip == maxClip) SetEntProp(iPrimary, Prop_Send, "m_iReloadMode", 0);
					SetEntProp(viewmodel, Prop_Send, "m_nSequence", 30);
					g_meterPri[iClient] = 0.0;
				}
			}
			else if (TF2_IsPlayerInCondition(iClient, TFCond_FocusBuff) && clip < maxClip) {
				int newClip = ammoCount - maxClip < 1 ? (ammoCount - maxClip + clip > maxClip ? maxClip : ammoCount - 1 + clip) : maxClip;
				int newAmmo  = ammoCount - maxClip + clip >= 1 ? ammoCount - maxClip + clip : 1;
				SetEntProp(iClient, Prop_Data, "m_iAmmo", newAmmo , _, primaryAmmo);
				SetEntData(iPrimary, iAmmoTable, newClip, 4, true);
			}
			if (buttons & IN_RELOAD) buttons &= ~IN_RELOAD;
			if (buttons & IN_ATTACK3) buttons |= IN_RELOAD;
		}
	}
	
	// Spy
	if (TF2_GetPlayerClass(iClient) == TFClass_Spy) {
		int iWatch = TF2Util_GetPlayerLoadoutEntity(iClient, 6, true);
		int iWatchIndex = -1;
		if(iWatch > 0) iWatchIndex = GetEntProp(iWatch, Prop_Send, "m_iItemDefinitionIndex");
		
		// Dead Ringer
		if (iWatchIndex == 59) {
			float fCloak = GetEntPropFloat(iClient, Prop_Send, "m_flCloakMeter");
			if (buttons & IN_ATTACK2 && !TF2_IsPlayerInCondition(iClient, TFCond_Cloaked) && fCloak < 100.0) {
				buttons &= ~IN_ATTACK2;
			}
		}
	}
}

public Action PlayerListener(int iClient, const char[] command, int argc) {
	char[] args = new char[64];
	GetCmdArg(1, args, 64);

	if (StrEqual(command,"eureka_teleport") && StrEqual(args, "0")) {
		CreateTimer(2.25, EurekaSpeed, iClient);
	}

	return Plugin_Continue;
}

public Action TriggerHealing(int iClient) {
	int iHealth = GetEntProp(iClient, Prop_Send, "m_iHealth");
	int iMaxHealth = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iMaxHealth", _, iClient);
	if (iHealth >= iMaxHealth) return Plugin_Continue;
	
	int iHealing = RoundToFloor((players[iClient].fHealth_Regen - 5.0) / 4.0 + 1.0);
	int iMedicCount = 0;
	for (int iOther = 1 ; iOther <= MaxClients ; iOther++) {	// Count number of Medics on our team
		if (!IsValidClient(iOther)) continue;
		if (TF2_GetClientTeam(iClient) != TF2_GetClientTeam(iOther)) continue;
		
		if (TF2_GetPlayerClass(iOther) == TFClass_Medic) {
			iMedicCount += 1;
		}
	}
	
	if (iMedicCount > 0) {
		iHealing -= 2 * iMedicCount;
	}
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

public Action ForceJump(int iClient) {
	
	TF2_RemoveCondition(iClient, TFCond_Dazed);
	
	float vecAngle[3], vecVel[3], fRedirect, fBuffer, vecBuffer[3];
	GetClientEyeAngles(iClient, vecAngle);
	GetEntPropVector(iClient, Prop_Data, "m_vecVelocity", vecVel);
	
	float vecForce[3];
	vecForce[0] = -Cosine(vecAngle[1] * 0.01745329) * Cosine(vecAngle[0] * 0.01745329);		// We are facing straight down the X axis when pitch and yaw are both 0; Cos(0) is 1
	vecForce[1] = -Sine(vecAngle[1] * 0.01745329) * Cosine(vecAngle[0] * 0.01745329);		// We are facing straight down the Y axis when pitch is 0 and yaw is 90
	vecForce[2] = Sine(vecAngle[0] * 0.01745329); 	// We are facing straight up the Z axis when pitch is 90 (yaw is irrelevant)
	
	fBuffer = GetVectorDotProduct(vecForce, vecVel) / GetVectorLength(vecVel, false);
	vecBuffer = vecVel;
	ScaleVector(vecBuffer, fBuffer);
	float vecProjection[3];
	vecProjection[0] = -vecBuffer[0];
	vecProjection[1] = -vecBuffer[1];
	vecProjection[2] = -vecBuffer[2];
	
	if (vecVel[2] < 0.0) {
		fRedirect = vecVel[2];		// Stores this momentum for later
		vecVel[2] = 0.0;		// Makes sure we always have at least enough push force to break our fall (unless we aim downwards for some reason)
	}
	
	float fForce = 250.0 + (fRedirect / 2);
	vecForce[0] *= fForce;
	vecForce[1] *= fForce;
	vecForce[2] *= fForce;
	
	vecForce[2] += 75.0;
	AddVectors(vecVel, vecForce, vecForce);
	
	TF2_AddCondition(iClient, TFCond_BlastJumping, 5.0);
	TeleportEntity(iClient, NULL_VECTOR, NULL_VECTOR, vecForce);
	
	return Plugin_Handled;
}

public Action RemoveBaseballBuff(Handle timer, int iClient) {
	TF2Attrib_RemoveByName(iClient, "move speed bonus");
	TF2Attrib_RemoveByName(iClient, "fire rate bonus");
	EmitSoundToClient(iClient, "weapons/discipline_device_power_down.wav");
	SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", 400.0);
	
	return Plugin_Handled;
}

public Action RemoveChargeCrit(Handle timer, int iClient) {
	players[iClient].bCharge_Crit_Prepped = false;
	return Plugin_Handled;
}

public Action BuildingHealthBuff(Handle timer, int iEnt) {
	SetEntProp(iEnt, Prop_Send, "m_iHealth", 75);
	return Plugin_Handled;
}

public Action EurekaSpeed(Handle timer, int iClient) {
	if (!(IsValidClient(iClient) && IsPlayerAlive(iClient))) return Plugin_Handled;
	TF2_AddCondition(iClient, TFCond_SpeedBuffAlly, 5.0);
	return Plugin_Handled;
}

public void DryFireSniper(int iClient) {
	int iPrimary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
	int primaryAmmo = GetEntProp(iPrimary, Prop_Send, "m_iPrimaryAmmoType");
	SetEntProp(iClient, Prop_Data, "m_iAmmo", 0, _, primaryAmmo);
}

public Action CreateSmoke(int iClient) {
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		int SmokeEnt = CreateEntityByName("env_smokestack");
		
		float vecVel[3];
		GetClientAbsOrigin(iClient, vecVel);
	
		char originData[64];
		Format(originData, sizeof(originData), "%f %f %f", vecVel[0], vecVel[1], vecVel[2]);

		if (SmokeEnt) {
			char SName[128];
			Format(SName, sizeof(SName), "Smoke%i", iClient);
			DispatchKeyValue(SmokeEnt,"targetname", SName);
			DispatchKeyValue(SmokeEnt,"Origin", originData);
			DispatchKeyValue(SmokeEnt,"BaseSpread", "60");
			DispatchKeyValue(SmokeEnt,"SpreadSpeed", "80");
			DispatchKeyValue(SmokeEnt,"Speed", "100");
			DispatchKeyValue(SmokeEnt,"StartSize", "200");
			DispatchKeyValue(SmokeEnt,"EndSize", "2");
			DispatchKeyValue(SmokeEnt,"Rate", "60");
			DispatchKeyValue(SmokeEnt,"JetLength", "400");
			DispatchKeyValue(SmokeEnt,"Twist", "40"); 
			DispatchKeyValue(SmokeEnt,"RenderColor", "100 100 100"); //red green blue
			DispatchKeyValue(SmokeEnt,"RenderAmt", "255");
			DispatchKeyValue(SmokeEnt,"SmokeMaterial", "particle/particle_smokegrenade1.vmt");
			
			DispatchSpawn(SmokeEnt);
			AcceptEntityInput(SmokeEnt, "TurnOn");
			
			DataPack pack = new DataPack();
			CreateDataTimer(0.5, Timer_KillSmoke, pack);
			WritePackCell(pack, SmokeEnt);
			
			DataPack pack2 = new DataPack();
			CreateDataTimer(1.5, Timer_StopSmoke, pack2);
			WritePackCell(pack2, SmokeEnt);
		}
	}
	return Plugin_Handled;
}

public Action Timer_KillSmoke(Handle timer, DataPack pack) {
	ResetPack(pack);
	int SmokeEnt = ReadPackCell(pack);
	
	AcceptEntityInput(SmokeEnt, "TurnOff");
	return Plugin_Handled;
}

public Action Timer_StopSmoke(Handle timer, DataPack pack) {
	ResetPack(pack);
	int SmokeEnt = ReadPackCell(pack);
	
	AcceptEntityInput(SmokeEnt, "Kill");
	return Plugin_Handled;
}

Action PipeSet(int iProjectile) {
	char class[64];
	GetEntityClassname(iProjectile, class, sizeof(class));
	
	// Iron Bomber pipes detonating on surface hits
	if (!StrEqual(class, "tf_projectile_pipe")) return Plugin_Continue;
	if (GetEntProp(iProjectile, Prop_Send, "m_bTouched") != 1) return Plugin_Continue;
	
	int weapon = GetEntPropEnt(iProjectile, Prop_Send, "m_hLauncher");
	int owner = GetEntPropEnt(weapon, Prop_Send, "m_hOwnerEntity");
	int index = -1;
	if (weapon != -1) index = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	
	if (index != 1151) return Plugin_Continue;
	
	float vecGrenadePos[3];
	GetEntPropVector(iProjectile, Prop_Send, "m_vecOrigin", vecGrenadePos);

	CreateParticle(iProjectile, "ExplosionCore_MidAir", 2.0);
	EmitAmbientSound("weapons/pipe_bomb1.wav", vecGrenadePos, iProjectile);
	
	for (int iTarget = 1 ; iTarget <= MaxClients ; iTarget++) {		// The player being damaged by the grenade
		if (!IsValidClient(iTarget)) continue;
		float vecTargetPos[3];
		GetEntPropVector(iTarget, Prop_Send, "m_vecOrigin", vecTargetPos);
		vecTargetPos[2] += 5;
		
		float fDist = GetVectorDistance(vecGrenadePos, vecTargetPos);
		if (!(fDist <= 86.4 && (TF2_GetClientTeam(owner) != TF2_GetClientTeam(iTarget) || owner == iTarget))) continue;	// 86.4 HU is the blast radius of this weapon
		
		Handle hndl = TR_TraceRayFilterEx(vecGrenadePos, vecTargetPos, MASK_SOLID, RayType_EndPoint, PlayerTraceFilter, iProjectile);
		if (TR_DidHit(hndl) == false || IsValidClient(TR_GetEntityIndex(hndl))) {
			float damage = RemapValClamped(fDist, 0.0, 86.4, 60.0, 30.0);

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
		delete hndl;
		}
	}
	
	AcceptEntityInput(iProjectile, "Kill");
	return Plugin_Changed;
}

public MRESReturn Detour_CalculateMaxSpeed(int self, Handle ret, Handle params) {
	
	if (DHookGetParam(params, 1)) {		// Medic speed matching activation is stored in a Boolean; this code always switches it to false
		DHookSetReturn(ret, 0.0);
		return MRES_Override;
	}

    return MRES_Ignored;
}

public MRESReturn OnPlayerRegenThinkPre(int iClient) {	// Disables Medic health regen; this is is a terrible idea, but I'm doing it anyway
	if (TF2_GetPlayerClass(iClient) != TFClass_Medic) return MRES_Ignored;
	SetEntData(iClient, offs_CTFPlayer_iClass, view_as<int>(TFClass_Unknown));
	players[iClient].bMedic = true;
	return MRES_Ignored;
}

public MRESReturn OnPlayerRegenThinkPost(int iClient) {
	if (players[iClient].bMedic == true) SetEntData(iClient, offs_CTFPlayer_iClass, view_as<int>(TFClass_Medic));
	players[iClient].bMedic = false;
	return MRES_Ignored;
}

	// Stocks

stock bool IsValidClient(int iClient) {
	if (iClient <= 0 || iClient > MaxClients) return false;
	if (!IsClientInGame(iClient)) return false;
	return true;
}

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
	if(victim!=-1)
	{
		if (TF2_IsPlayerInCondition(victim,TFCond_Jarated) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeath) || TF2_IsPlayerInCondition(victim,TFCond_MarkedForDeathSilent))
			result = true;
	}
	if (TF2_IsPlayerInCondition(client,TFCond_CritMmmph) || TF2_IsPlayerInCondition(client,TFCond_MiniCritOnKill) || TF2_IsPlayerInCondition(client,TFCond_Buffed) || TF2_IsPlayerInCondition(client,TFCond_CritCola))
		result = true;
	return result;
}

int GetRandomUInt(int min, int max) {
	return RoundToFloor(GetURandomFloat() * (max - min + 1)) + min;
}