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


enum struct Player {
	float fRev;		// Tracks how long we've been revved for the purposes of undoing the L&W nerf
	float fSpeed;		// Tracks how long we've been revved for the purposes of undoing the L&W nerf
}

Player players[MAXPLAYERS+1];

	// -={ Modifies attributes without needing to go through another plugin }=-

public Action TF2Items_OnGiveNamedItem(int iClient, char[] class, int index, Handle& item) {
	Handle item1;
	// Heavy
	if (StrEqual(class, "tf_weapon_minigun")) {	// All Miniguns
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 5);
		TF2Items_SetAttribute(item1, 0, 1, 0.85); // damage penalty (15%)
		TF2Items_SetAttribute(item1, 1, 106, 0.8); // weapon spread bonus (20%)
		TF2Items_SetAttribute(item1, 2, 125, -50.0); // max health additive penalty (20%)
		TF2Items_SetAttribute(item1, 3, 45, 0.75); // bullets per shot bonus (-25%)
		TF2Items_SetAttribute(item1, 4, 75, 1.6); // speed
		TF2Items_SetAttribute(item1, 5, 37, 0.7); // ammo (-30%)
	}
	
	if (item1 != null) {
		item = item1;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}


	// -={ Iterates every frame }=-

public void OnGameFrame() {	
	for (int iClient = 1; iClient <= MaxClients; iClient++) {		// Caps Afterburn at 6 and handles Temperature
		if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
			
			int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);
			//PrintToChatAll("fRev: %f", players[iClient].fRev);
			//PrintToChatAll("fSpeed: %f", players[iClient].fSpeed);
			// Heavy
			// Counteracts the L&W nerf by dynamically adjusting damage and accuracy
			if (TF2_GetPlayerClass(iClient) == TFClass_Heavy) {
			
				float fDmgMult = 1.0;		// Default values -- for stock, and in case of emergency
				float fAccMult = 0.8;
				
				int weaponState = GetEntProp(primary, Prop_Send, "m_iWeaponState");
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
						TF2Attrib_SetByDefIndex(primary, 106, fAccMult * 1.0/factor);		// Spread bonus
						TF2Attrib_SetByDefIndex(primary, 2, fDmgMult * 1.0 * factor);		// Damage bonus
					}
				}
				
				else if (weaponState == 0 && sequence == 23) {		// Are we unrevving?
					if(cycle < 0.6) {
						SetEntPropFloat(primary, Prop_Send, "m_flTimeWeaponIdle", GetGameTime() + 0.8);
					}
					float speed = 1.66;
					SetEntPropFloat(view, Prop_Send, "m_flPlaybackRate", speed); //speed up animation
					TF2Attrib_AddCustomPlayerAttribute(iClient, "switch from wep deploy time decreased", 0.25, 0.2);		// Temporary faster Minigun holster
					//TF2Attrib_SetByDefIndex(primary, 3, 0.33)
				}
				
				if ((weaponState == 2) && players[iClient].fSpeed > 0.0) {		// If we're firing but the speed meter isn't empty...
					players[iClient].fSpeed = players[iClient].fSpeed - 0.015;		// It takes us 67 frames (1 second) to fully deplete the rev meter
				}
				
				else {
					players[iClient].fSpeed = players[iClient].fSpeed + 0.015;
					if (players[iClient].fSpeed > 1.005) {
						players[iClient].fSpeed = 1.005;
					}
				}
				
				//TF2Attrib_SetByDefIndex(primary, 75, RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 0.75, 0.925));		// Speed while deployed
				TF2Attrib_SetByDefIndex(primary, 106, RemapValClamped(players[iClient].fRev, 0.0, 1.005, 1.2, 0.8));		// spread bonus
				TF2Attrib_SetByDefIndex(primary, 2, RemapValClamped(players[iClient].fRev, 0.0, 1.005, 2.0, 1.0));		// damage bonus
				TF2Attrib_AddCustomPlayerAttribute(iClient, "aiming movespeed increased", RemapValClamped(players[iClient].fSpeed, 0.0, 1.005, 0.5, 1.0));	// Speed
			}
		}
	}
}


public Action OnPlayerRunCmd(int iClient, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient)) {
		
		TFClassType tfClientClass = TF2_GetPlayerClass(iClient);
		float position[3];
		GetEntPropVector(iClient, Prop_Send, "m_vecOrigin", position);
		int primary = TF2Util_GetPlayerLoadoutEntity(iClient, TFWeaponSlot_Primary, true);

	
		switch(tfClientClass)
		{
			case TFClass_Heavy:	
			{
				//allow holster in minigun spindown
				if(primary != -1)
				{
					int weaponState = GetEntProp(primary, Prop_Send, "m_iWeaponState");
					int view = GetEntPropEnt(iClient, Prop_Send, "m_hViewModel");
					int sequence = GetEntProp(view, Prop_Send, "m_nSequence");
					float cycle = GetEntPropFloat(view, Prop_Data, "m_flCycle");
					if(sequence == 23 && weaponState == 0)
					{
						int done = GetEntProp(view, Prop_Data, "m_bSequenceFinished");
						if (done == 0) SetEntProp(view, Prop_Data, "m_bSequenceFinished", true, .size = 1);

						float idle = 0.0;
						// if(primaryIndex == 298) idle = 1.0;
						if(cycle < 0.2 && idle > 0) //set idle time faster
						{
							SetEntPropFloat(primary, Prop_Send, "m_flTimeWeaponIdle",GetGameTime()+idle);
						}
					}
					
					return Plugin_Changed;
				}
			}
		}
	}
	return Plugin_Continue;
}