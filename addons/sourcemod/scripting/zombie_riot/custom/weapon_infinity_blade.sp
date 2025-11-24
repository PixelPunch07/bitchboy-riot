#pragma semicolon 1
#pragma newdecls required

// Cooldowns
static float f_InfinityBladeDashCooldown[MAXPLAYERS+1];
static float f_InfinityBladeRocketCooldown[MAXPLAYERS+1];

// HUD
static float f_InfinityBladeHudDelay[MAXPLAYERS+1];

// Sounds
static const char g_DashSounds[][] = 
{
	"player/taunt_yeti_standee_demo_start.wav"
};

static const char g_RocketSounds[][] = 
{
	"weapons/cow_mangler_explosion_charge_04.wav"
};

static bool Precached_InfinityBlade;

public void InfinityBlade_MapStart()
{
	Precached_InfinityBlade = false;
	Zero(f_InfinityBladeDashCooldown);
	Zero(f_InfinityBladeRocketCooldown);
	Zero(f_InfinityBladeHudDelay);
}

void InfinityBlade_Precache()
{
	if(!Precached_InfinityBlade)
	{
		PrecacheSoundArray(g_DashSounds);
		PrecacheSoundArray(g_RocketSounds);
		PrecacheSound("weapons/physcannon/energy_sing_explosion2.wav");
		Precached_InfinityBlade = true;
	}
}

// Called when weapon equipped
public void InfinityBlade_OnEquip(int client, int weapon)
{
	InfinityBlade_Precache();
	InfinityBlade_DisplayHud(client);
}

// On melee hit - apply vulnerability
public void InfinityBlade_OnHit(int attacker, int victim, float &damage, int weapon)
{
	if(!IsValidEntity(weapon))
		return;
	
	int pap = RoundFloat(Attributes_Get(weapon, 868, 0.0));
	
	// Base vulnerability on all PaP levels
	float vulnerability = 0.10; // 10% base
	
	if(pap >= 2)
		vulnerability = 0.15; // 15% at PaP 2+
		
	if(pap >= 3)
		vulnerability = 0.20; // 20% at PaP 3+
	
	// Apply vulnerability for 5 seconds
	IncreaseEntityDamageTakenBy(victim, vulnerability, 5.0, true);
	
	// Visual feedback
	if(victim <= MaxClients)
	{
		SetDefaultHudPosition(attacker);
		SetGlobalTransTarget(attacker);
		ShowSyncHudText(attacker, SyncHud_Notifaction, "Vulnerability Applied: +%.0f%%", vulnerability * 100.0);
	}
}

// M2 Attack - Dash (PaP 1+)
public void InfinityBlade_Attack2(int client, int weapon, bool crit, int slot)
{
	if(!IsValidEntity(weapon))
		return;
		
	int pap = RoundFloat(Attributes_Get(weapon, 868, 0.0));
	
	if(pap < 1)
	{
		ClientCommand(client, "playgamesound items/medshotno1.wav");
		SetDefaultHudPosition(client);
		SetGlobalTransTarget(client);
		ShowSyncHudText(client, SyncHud_Notifaction, "Need PaP Level 1 to use Dash!");
		return;
	}
	
	float GameTime = GetGameTime();
	
	if(f_InfinityBladeDashCooldown[client] > GameTime)
	{
		float Ability_CD = f_InfinityBladeDashCooldown[client] - GameTime;
		ClientCommand(client, "playgamesound items/medshotno1.wav");
		SetDefaultHudPosition(client);
		SetGlobalTransTarget(client);
		ShowSyncHudText(client, SyncHud_Notifaction, "Dash on cooldown: %.1fs", Ability_CD);
		return;
	}
	
	// Find target
	int target = GetClosestTarget(client, true, _, false, _, _, _, true, .UseVectorDistance = true);
	
	if(!IsValidEntity(target))
	{
		ClientCommand(client, "playgamesound items/medshotno1.wav");
		SetDefaultHudPosition(client);
		SetGlobalTransTarget(client);
		ShowSyncHudText(client, SyncHud_Notifaction, "No target found!");
		return;
	}
	
	// Get positions
	float clientPos[3], targetPos[3];
	GetClientAbsOrigin(client, clientPos);
	WorldSpaceCenter(target, targetPos);
	
	float distance = GetVectorDistance(clientPos, targetPos);
	
	if(distance > 1000.0)
	{
		ClientCommand(client, "playgamesound items/medshotno1.wav");
		SetDefaultHudPosition(client);
		SetGlobalTransTarget(client);
		ShowSyncHudText(client, SyncHud_Notifaction, "Target too far away!");
		return;
	}
	
	// Set cooldown
	f_InfinityBladeDashCooldown[client] = GameTime + 30.0;
	
	// Calculate dash velocity
	float vecAngles[3];
	MakeVectorFromPoints(clientPos, targetPos, vecAngles);
	GetVectorAngles(vecAngles, vecAngles);
	
	float velocity[3];
	GetAngleVectors(vecAngles, velocity, NULL_VECTOR, NULL_VECTOR);
	ScaleVector(velocity, 800.0);
	velocity[2] = 300.0; // Add upward boost
	
	// Dash towards target
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	TF2_AddCondition(client, TFCond_SpeedBuffAlly, 0.5);
	
	// Visual and sound effects
	EmitSoundToAll(g_DashSounds[GetRandomInt(0, sizeof(g_DashSounds) - 1)], client, SNDCHAN_AUTO, NORMAL_ZOMBIE_SOUNDLEVEL, _, 0.8);
	
	int particle = ParticleEffectAt(clientPos, "scout_dodge_blue", 1.0);
	TeleportEntity(particle, clientPos, NULL_VECTOR, NULL_VECTOR);
	
	// Deal damage and knockback when reaching target
	DataPack pack;
	CreateDataTimer(0.3, InfinityBlade_DashImpact, pack);
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(EntIndexToEntRef(target));
	pack.WriteCell(EntIndexToEntRef(weapon));
	
	Rogue_OnAbilityUse(client, weapon);
	InfinityBlade_DisplayHud(client);
}

public Action InfinityBlade_DashImpact(Handle timer, DataPack pack)
{
	pack.Reset();
	int client = GetClientOfUserId(pack.ReadCell());
	int target = EntRefToEntIndex(pack.ReadCell());
	int weapon = EntRefToEntIndex(pack.ReadCell());
	
	if(!IsValidClient(client) || !IsValidEntity(target) || !IsValidEntity(weapon))
		return Plugin_Stop;
	
	if(!IsPlayerAlive(client))
		return Plugin_Stop;
	
	float clientPos[3], targetPos[3];
	GetClientAbsOrigin(client, clientPos);
	WorldSpaceCenter(target, targetPos);
	
	float distance = GetVectorDistance(clientPos, targetPos);
	
	// Only apply if we're close enough
	if(distance < 200.0)
	{
		int pap = RoundFloat(Attributes_Get(weapon, 868, 0.0));
		
		float damage = 150.0;
		if(pap >= 2)
			damage = 200.0;
		if(pap >= 3)
			damage = 250.0;
		
		// Apply damage
		SDKHooks_TakeDamage(target, client, client, damage, DMG_CLUB, weapon, NULL_VECTOR, targetPos);
		
		// Apply strong knockback
		Custom_Knockback(client, target, 600.0, true, true);
		
		if(target <= MaxClients)
		{
			TF2_AddCondition(target, TFCond_LostFooting, 0.5);
			TF2_AddCondition(target, TFCond_AirCurrent, 0.5);
		}
		
		// Impact effects
		EmitSoundToAll("weapons/physcannon/energy_sing_explosion2.wav", client, SNDCHAN_STATIC, NORMAL_ZOMBIE_SOUNDLEVEL, _, 0.8);
		ParticleEffectAt(targetPos, "explosions_MA_bomb_orange", 1.0);
	}
	
	return Plugin_Stop;
}

// Fire Homing Rocket (PaP 2+)
public void InfinityBlade_Reload(int client, int weapon, bool crit, int slot)
{
	if(!IsValidEntity(weapon))
		return;
		
	int pap = RoundFloat(Attributes_Get(weapon, 868, 0.0));
	
	if(pap < 2)
	{
		ClientCommand(client, "playgamesound items/medshotno1.wav");
		SetDefaultHudPosition(client);
		SetGlobalTransTarget(client);
		ShowSyncHudText(client, SyncHud_Notifaction, "Need PaP Level 2 to use Homing Rocket!");
		return;
	}
	
	float GameTime = GetGameTime();
	
	if(f_InfinityBladeRocketCooldown[client] > GameTime)
	{
		float Ability_CD = f_InfinityBladeRocketCooldown[client] - GameTime;
		ClientCommand(client, "playgamesound items/medshotno1.wav");
		SetDefaultHudPosition(client);
		SetGlobalTransTarget(client);
		ShowSyncHudText(client, SyncHud_Notifaction, "Rocket on cooldown: %.1fs", Ability_CD);
		return;
	}
	
	// cooldown
	f_InfinityBladeRocketCooldown[client] = GameTime + 45.0;
	
	// Get spawn position
	float clientPos[3], clientAng[3];
	GetClientEyePosition(client, clientPos);
	GetClientEyeAngles(client, clientAng);
	
	// find target for initial direction
	int target = GetClosestTarget(client, true, _, true, _, _, _, true, .UseVectorDistance = true);
	
	float targetPos[3];
	if(IsValidEntity(target))
	{
		WorldSpaceCenter(target, targetPos);
	}
	else
	{
		// Fire forward if no target
		float forwardVec[3];
		GetAngleVectors(clientAng, forwardVec, NULL_VECTOR, NULL_VECTOR);
		targetPos[0] = clientPos[0] + forwardVec[0] * 1000.0;
		targetPos[1] = clientPos[1] + forwardVec[1] * 1000.0;
		targetPos[2] = clientPos[2] + forwardVec[2] * 1000.0;
	}
	
	float damage = 200.0;
	if(pap >= 3)
		damage = 300.0;
	
	// Create rocket projectile
	int projectile = Wand_Projectile_Spawn(client, 1500.0, 10.0, damage, 0, weapon, "raygun_projectile_blue_crit");
	
	if(IsValidEntity(projectile))
	{
		// setup homing
		float ang_Look[3];
		GetEntPropVector(projectile, Prop_Send, "m_angRotation", ang_Look);
		
		Initiate_HomingProjectile(projectile,
			client,
			90.0,			// float lockonAngleMax
			20.0,			// float homingaSec
			false,			// bool LockOnlyOnce
			true,			// bool changeAngles
			ang_Look);		// float AnglesInitiate[3]
		
		SDKUnhook(projectile, SDKHook_StartTouch, Wand_Projectile_Touch);
		SDKHook(projectile, SDKHook_StartTouch, InfinityBlade_Rocket_Touch);
		
		EmitSoundToAll(g_RocketSounds[GetRandomInt(0, sizeof(g_RocketSounds) - 1)], client, SNDCHAN_AUTO, NORMAL_ZOMBIE_SOUNDLEVEL, _, BOSS_ZOMBIE_VOLUME);
	}
	
	Rogue_OnAbilityUse(client, weapon);
	InfinityBlade_DisplayHud(client);
}

public void InfinityBlade_Rocket_Touch(int entity, int target)
{
	if(target > 0 && target < MAXENTITIES)
	{
		int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if(!IsValidEntity(owner))
			owner = 0;
		
		float ProjectileLoc[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", ProjectileLoc);
		float damage = f_WandDamage[entity];
		
		// Explosion with radius
		Explode_Logic_Custom(damage, owner, owner, -1, ProjectileLoc, 200.0, _, _, true);
		
		EmitSoundToAll("weapons/explode1.wav", entity, SNDCHAN_STATIC, NORMAL_ZOMBIE_SOUNDLEVEL, _, 0.8);
		ParticleEffectAt(ProjectileLoc, "ExplosionCore_MidAir", 1.0);
	}
	
	RemoveEntity(entity);
}

static void InfinityBlade_DisplayHud(int client)
{
	float GameTime = GetGameTime();
	
	if(f_InfinityBladeHudDelay[client] > GameTime)
		return;
	
	f_InfinityBladeHudDelay[client] = GameTime + 0.5;
	
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(weapon))
		return;
	
	int pap = RoundFloat(Attributes_Get(weapon, 868, 0.0));
	
	char HUDText[256];
	
	if(pap >= 1)
	{
		if(f_InfinityBladeDashCooldown[client] > GameTime)
		{
			float cd = f_InfinityBladeDashCooldown[client] - GameTime;
			Format(HUDText, sizeof(HUDText), "%sDash: [%.1fs]", HUDText, cd);
		}
		else
		{
			Format(HUDText, sizeof(HUDText), "%sDash: [READY]", HUDText);
		}
	}
	
	if(pap >= 2)
	{
		if(f_InfinityBladeRocketCooldown[client] > GameTime)
		{
			float cd = f_InfinityBladeRocketCooldown[client] - GameTime;
			Format(HUDText, sizeof(HUDText), "%s\nRocket: [%.1fs]", HUDText, cd);
		}
		else
		{
			Format(HUDText, sizeof(HUDText), "%s\nRocket: [READY]", HUDText);
		}
	}
	
	if(strlen(HUDText) > 0)
		PrintHintText(client, "%s", HUDText);
}

// Think hook for HUD updates
public void InfinityBlade_Think(int client)
{
	if(!IsValidClient(client) || !IsPlayerAlive(client))
		return;
	
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if(!IsValidEntity(weapon))
		return;
	
	// check if it's the infinity blade
	if(i_CustomWeaponEquipLogic[weapon] != WEAPON_INFINITY_BLADE)
		return;
	
	InfinityBlade_DisplayHud(client);
}

