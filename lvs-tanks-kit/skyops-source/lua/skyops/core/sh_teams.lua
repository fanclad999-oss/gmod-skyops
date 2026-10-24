-- Sides. All SW vehicles ship with ENT.AITEAM = 2, so the side is set per spawn.

SkyOps.Teams = {
	BLUE = 1, -- players
	RED = 2,  -- enemy air defense and aircraft
}

-- Map scale. Source's own scale is 1 u = 1.905 cm, but the Kirovskoe map is
-- built at 40 u per metre (KIR.S), and its distances are what players see.
-- InfMap's autorun ("!!inf_init.lua") runs before ours, so KIR is set by now.
local UNITS_PER_M = ( KIR and KIR.S ) or ( 1 / 0.01905 )
SkyOps.M_TO_HU = UNITS_PER_M
SkyOps.HU_TO_M = 1 / UNITS_PER_M
