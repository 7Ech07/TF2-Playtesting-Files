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


	// -={ Modifies attributes without needing to go through another plugin }=-
public Action TF2Items_OnGiveNamedItem(int iClient, char[] class, int index, Handle& item) {
	Handle item1;

	if (StrEqual(class, "tf_weapon_bat") || StrEqual(class, "tf_weapon_bat_fish") || 
	StrEqual(class, "tf_weapon_bat_wood") || StrEqual(class, "tf_weapon_bat_giftwrap") || 
	StrEqual(class, "saxxy") || StrEqual(class, "tf_weapon_shovel") || 
	StrEqual(class, "tf_weapon_katana") || StrEqual(class, "tf_weapon_fireaxe") ||
	StrEqual(class, "tf_weapon_breakable_sign") || StrEqual(class, "tf_weapon_slap") ||
	StrEqual(class, "tf_weapon_sword") || StrEqual(class, "tf_weapon_stickbomb") || 
	StrEqual(class, "tf_weapon_bottle") || StrEqual(class, "tf_weapon_fists") || 
	StrEqual(class, "tf_weapon_robot_arm") || StrEqual(class, "tf_weapon_wrench") ||
	StrEqual(class, "tf_weapon_bonesaw") || StrEqual(class, "tf_weapon_club") ||
	StrEqual(class, "tf_weapon_knife")) {	// All Melees
		item1 = TF2Items_CreateItem(0);
		TF2Items_SetFlags(item1, (OVERRIDE_ATTRIBUTES|PRESERVE_ATTRIBUTES));
		TF2Items_SetNumAttributes(item1, 1);
		TF2Items_SetAttribute(item1, 0, 178, 0.1); // Increased melee draw speed
	}
}