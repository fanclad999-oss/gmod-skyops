---
name: skyops-missions-ui
description: SkyOps mission format, briefing/HUD mockups and the mission-module ↔ core API split (UI/missions thread)
metadata:
  type: project
  modified: 2026-10-23T22:51:39.337Z
---

Part of [[gmod-lvs-coop-project]]. UI/missions thread (2026-10-23) owns: briefing screen, data-driven missions, DCS-like HUD distinct from stock LVS.

- Mockups canvas (briefing / pilot HUD / debrief): https://claude.ai/artifact/6V1QXTdYF8gdqCnTR9wV6M. Look: dark #0d1114, amber accent #f2a93b, green HUD #7dff9a, threat red #ff6b5e, fonts Rajdhani + JetBrains Mono, Russian UI.
- Mission format spec + 4 examples: /mnt/project-files/skyops-missions/ (MISSION_FORMAT.md, missions/*.lua). Missions reference named map anchors (lua/skyops/maps/kirovskoe.lua), not raw InfMap coords.
- Objective types: reach, destroy, recon, land, protect, survive; `after` chains, `optional`.
- Mission module owns net msgs skyops_brief/slot/ready/obj/debrief. Asked core thread for SkyOps.Spawn.{AirDefense,Convoy,AIFlight,PlayerJet}, hook SkyOps.UnitKilled, SkyOps.Map.Anchor — confirmed by core thread 2026-10-23. Missions use core roles (su34, tornado_ids, f14a, su25sm3; s75, tor_m1, roland, aaa), not LVS classes; no ZU-23 (use "aaa").
- Repo fanclad999-oss/gmod-skyops. PR #1 (branch claude/missions-ui, 2026-10-23): mission engine, briefing/debrief Derma, pilot HUD (ru for su34/su25sm3, nato for tornado/f14a), RWR, WSO MFD. Unit conversion lives in SkyOps.Conv (core owns SkyOps.Units = kill tracking). Docs: docs/missions.md, docs/ui.md. User wants HUD "as realistic as possible" per real aircraft. Not yet tested in-game.
- Loadouts (2026-10-23): missions declare `loadouts = { tags = {...}, default = <core loadout id> }`; briefing has < > picker for the flight pilot (net skyops_loadout), ids come from core SkyOps.Registry.GetLoadouts(role). SEAD Su-34 default = 34 (Х-31П, anti-radiation). Tornado/F-14 packs have no ARM. Map scale: SkyOps.HU_TO_M (Kirovskoe 40 u/m). Fonts enlarged + convar skyops_ui_scale after user said briefing text too small.
- Install: changed files are staged in /mnt/project-files/skyops-install/ and written to user's PC addons\skyops via device_commit_files (folder already granted).
- 2026-10-24: core sh_airfield.lua registers real airfield_main/airfield_apron (world pos, no chunk). maps/sh_kirovskoe.lua now lays other todo anchors out as km offsets (east,north) from airfield_main via a 2 s timer. Ground start: flights line up forward along runway. start.alt = m above terrain. On-screen SAM markers ui/cl_threats.lua (net skyops_unitdown hides killed groups); weapon descriptions ui/cl_weapon_info.lua. User asked about a pylon-by-pylon loadout builder: feasible but big, offered separate thread, awaiting answer.
