#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <tf2>
#include <dhooks>
#include <tf2_stocks>
#include <tf2items>
#include <tf2utils>

#pragma semicolon 1
#pragma newdecls required

#pragma semicolon 1
#include <sourcemod>


/*Handle cvar_ref_tf_flame_dmg_mode_dist;	
Handle cvar_ref_tf_flamethrower_boxsize;
//Handle cvar_ref_tf_flamethrower_burst_zvelocity;
//Handle cvar_ref_tf_flamethrower_burstammo;
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
Handle cvar_ref_tf_airblast_cray_reflect_coeff;*/

enum struct Player {
	bool AirblastJumpCD;
	//bool ParticleCD;
	//int iTempLevel; 
}

Player players[MAXPLAYERS+1];


/*public void OnClientPutInServer (int iClient)
{
	SDKHook(iClient, SDKHook_OnTakeDamageAlive, OnTakeDamage);
}


	// -={ Accesses the dev only Flanethrower cvars }=-

public void OnPluginStart() {
	cvar_ref_tf_flame_dmg_mode_dist = FindConVar("tf_flame_dmg_mode_dist");
	cvar_ref_tf_flamethrower_boxsize = FindConVar("tf_flamethrower_boxsize");
	//cvar_ref_tf_flamethrower_burst_zvelocity = FindConVar("_tf_flamethrower_burst_zvelocity");
	//cvar_ref_tf_flamethrower_burstammo = FindConVar("tf_flamethrower_burstammo");
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
		//TF2Items_SetAttribute(item1, 7, 256, 1.04125); // mult airblast refire time (0.66s; 82.5% duration)
	}
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}*/


	// -={ Iterates every frame }=-
	
	// Somethhing in here might be broken

public void OnGameFrame() {
	
	/*SetConVarString(cvar_ref_tf_flame_dmg_mode_dist, "0.0");
	SetConVarString(cvar_ref_tf_flamethrower_boxsize, "12.0");
	//SetConVarString(cvar_ref_tf_flamethrower_burst_zvelocity, "350");
	//SetConVarString(cvar_ref_tf_flamethrower_burstammo, "0.0");
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
	SetConVarString(cvar_ref_tf_airblast_cray_reflect_coeff, "1");*/
	
	
	for (int i = 1; i <= MaxClients; i++) {		// Caps Afterburn at 8 and handles Temperature
		if (IsClientInGame(i) && IsPlayerAlive(i)) {
			/*float fBurn = TF2Util_GetPlayerBurnDuration(i);
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
			}*/
			
			float vecVel[3];
			GetEntPropVector(i, Prop_Data, "m_vecVelocity", vecVel);		// Retrieve existing velocity
			if (vecVel[2] == 0 && (GetEntityFlags(i) & FL_ONGROUND)) {		// Are we grounded?
				players[i].AirblastJumpCD = true;
			}
			else {
			}
		}
	}
}


	// -={ Preps Airblast jump }=-

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2]) {
	if (client >= 1 && client <= MaxClients) {
		if (TF2_GetPlayerClass(client) == TFClass_Pyro) {

			int iPrimary = TF2Util_GetPlayerLoadoutEntity(client, TFWeaponSlot_Primary, true);		// Retrieve the primary weapon
			char class[64];
			GetEntityClassname(iPrimary, class, sizeof(class));		// Retrieve the weapon
			
			if (StrEqual(class, "tf_weapon_flamethrower")) {		// Are we holding an Airblast-capable weapon?
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
			else if (StrEqual(class, "tf_weapon_rocketlauncher_fireball")) {		// Are we holding the Dragon's Fury?
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
	}
	
	return Plugin_Continue;
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


	// -={ Generates a unit vector in the direction we're looking }=-
	// For future references: C++ uses radians for trig functions

/*float GetUnitVector(float vecAngle[3]) {
	float vecUnit[3];
	vecUnit[0] = Cosine(vecAngle[0] * 0.01745329) * Cosine(vecAngle[2] * 0.01745329);		// We are facing straight down the X axis when pitch and yaw are both 0; Cos(0) is 1
	vecUnit[1] = Sine(vecAngle[0] * 0.01745329) * Cosine(vecAngle[2] * 0.01745329);		// We are facing straight down the Y axis when pitch is 0 and yaw is 90
	vecUnit[2] = Sine(vecAngle[2] * 0.01745329); 	// We are facing straight up the Z axis when pitch is 90 (yaw is irrelevant)

	return vecUnit;
}*/


	// -={ Calculates damage }=-

/*Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damage_type, int& weapon, float damage_force[3], float damage_position[3], int damage_custom) {
	char class[64];
	
	if (victim >= 1 && victim <= MaxClients && attacker >= 1 && attacker <= MaxClients) {		// Ensures we only go through damage dealt by other players
		if (weapon > 0) {		// Prevents us attempting to process data from e.g. Sentry Guns and causing errors
			GetEntityClassname(weapon, class, sizeof(class));		// Retrieve the weapon
			
			if(StrEqual(class, "tf_weapon_flamethrower") && (damage_type & DMG_IGNITE) && !(damage_type & DMG_BLAST)) {
				//recreate flamethrower damage scaling, code inpsired by NotnHeavy
				//base damage plus any bonus
				/*Address bonus = TF2Attrib_GetByDefIndex(weapon, 2);
				float value = bonus == Address_Null ? 1.0 : TF2Attrib_GetValue(bonus);*//*
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
		}
	}
	
	return Plugin_Continue;
}


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
}*/