---
name: gmod-lvs-coop-project
description: Goal, tech findings and plan for the GMod co-op jet addon (LVS + Ryunocchi planes + InfMap)
metadata:
  type: project
  modified: 2026-10-23T21:36:04.293Z
---

User (Александр, writes Russian, reply in Russian) wants a GMod addon (working name SkyOps) for DCS-like co-op: 2 players in one LVS jet (pilot + WSO), long missions, AI air defense (SAM/AAA/enemy fighters), on Infinite Map with bots following across chunks. Visuals last.

Findings (2026-10-23):
- LVS source: github.com/SpaxscE/lvs_base. Has AddPassengerSeat, AddWeapon(data, PodID), lvs_missile (SetTarget etc.), LVS:SendMissileAlert, flares, SetAI/RunAI/GetAITEAM, hooks LVS.PlayerEnteredVehicle / OnVehicleDestroyed / UpdateRelationship.
- InfMap1 (meetric1, gm_infinite) detours GetPos/SetPos/traces; NPC/NextBot NOT supported -> build bots as scripted ents/LVS AI, not NPCs. InfMap2 (zff.dev/googer/infmap2) successor, maps via lua/infmap2/<map>/main.lua, docs TODO. LVS+InfMap compatibility unverified = step 0 spike.
- Ryunocchi planes are separate Workshop addons; patch by class name, don't redistribute.
- Plan doc: https://claude.ai/artifact/YPh7nS6b8BnWYKvfa1y7df
- Claude can't run GMod; user tests in-game. No GitHub repo yet (asked user to create one).

Addons from user (2026-10-23), all by Ryuunosuke (akasaka_ryuu) except map:
- Map: 3819959079 Kirovskoe (Khrestivka) 1:1 InfMap, needs InfMap1 base 2905327911.
- Planes: 3489256708 Tornado IDS (2 seats), 3408992578 F-14A (pilot+RIO), 3319073025 Su-34 (2 seats), 3261220817 Su-25SM3 (1 seat).
- SAM: 3470355913 S-75 (P-12, SNR-75, launcher), 3291755974 TOR-M1 (4 seats), 3488791956 FlaRakPz I Roland.
- Deps: LVS Framework 2912816023, Planes Pack 2912826012, Military Pack, Tanks Pack, SW Bombs V3 3127790930 + Russian/USA/French content.
- Steam pages for ALL 8 show "removed for violating guidelines"; on user's PC (C:\Program Files (x86)\Steam\steamapps\workshop\content\4000) only map, InfMap, LVS framework, planes pack, SW Bombs are present; Ryuunosuke items not there. Asked user where he has them.

Update 2026-10-23 22:05: all addons now installed on user PC. Repo fanclad999-oss/gmod-skyops (public, saved to project); skeleton pushed to main. Real classes + quirks in repo docs/addons.md (sw_su34, sw_tornado, sw_f14a, sw_su25sm3, sw_snr75/sw_s75/sw_p12, sw_torm1, sw_9k33m3, sw_flarakpz1). Missiles are SW Bombs sw_base_rocket_v3 (.target), not lvs_missile. Layout agreed with missions/UI thread: core thread owns addon.json, autorun loader, lua/skyops/core/*; missions thread owns lua/skyops/{mission,ui,missions,maps}/*. User asked for "максимально реальный" aircraft behaviour.

Step 0 result (2026-10-23 22:30, log in user's garrysmod\data\skyops\compat_log.txt): InfMap chunk transitions clean for LVS. Problems + fixes (PR #2): stock LVS AI target range 60000u and only chases targets in front -> SkyOps AI brain (sv_ai_flight); Ryuunosuke SeekerDist tiny (Su-34 20000u=380m) -> sv_realism sets real ranges; SAM has no AI -> sv_sam brain; InfMap terrain = infmap_* entities, not brushes (MASK_SOLID_BRUSHONLY misses it). Device folders granted: workshop content\4000, garrysmod\addons, garrysmod\data. Deploy builds to garrysmod\addons\skyops via device_commit_files from /mnt/project-files/skyops-build/skyops.

2026-10-23 22:50: Test 2 OK: SkyOps AI chaser follows across chunks and fires. KEY: Kirovskoe map scale is 40 u/m (KIR.S), not 52.49; chunk = 500 m; ground height = KIR.MeshHeight(x,y) (colliders kir_collider stream only near moving ents). Source physenv MaxVelocity 4000 u/s capped all jets+missiles -> raised to 50000. Loadouts: ent:SetLoadout(n) rebuilds weapons; registry core/sh_loadouts.lua. Su-34 loadout 34 Kh-31 -> ARM via core/sv_arm.lua. No ARM models for Tornado/F-14.

2026-10-24 00:30: InfMap1 traces are clipped to the start chunk and hit real map bounds after ~16000 u -> long LOS uses KIR.MeshHeight ray-march (sv_radar). Ryuunosuke SAM radar weapon OnThink resets IsLocked every tick without gunner, and OnTick cuts missile guidance when not locked -> sv_sam overrides SetIsLocked/SetClosestEnt per instance on AI sites. Big on-screen SAM markers requested by user -> handed to missions thread (ui/).
