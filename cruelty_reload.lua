-- cruelty_reload.lua
-- 路径：garrysmod/lua/autorun/cruelty_reload.lua

-- ========== 服务器端：处理补弹请求 ==========
if SERVER then
    util.AddNetworkString("CrueltyReload_Refill")

    net.Receive("CrueltyReload_Refill", function(len, ply)
        if not IsValid(ply) or not ply:Alive() then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then return end

        local maxClip = wep:GetMaxClip1()
        if not maxClip or maxClip <= 0 then return end

        local clip = wep:Clip1()
        local need = maxClip - clip
        if need <= 0 then return end

        -- 无限弹药武器直接补满，不动备弹
        local ammoType = wep:GetPrimaryAmmoType()
        if ammoType == -1 then
            wep:SetClip1(maxClip)
            return
        end

        local reserve = ply:GetAmmoCount(ammoType)
        if reserve <= 0 then return end

        local toLoad = math.min(need, reserve)
        ply:SetAmmo(reserve - toLoad, ammoType)  -- 扣备弹
        wep:SetClip1(clip + toLoad)                   -- 补弹匣
    end)

    return
end

-- ========== 客户端 ==========
local reloading = false
local a_y = 0
local b_y = 0
local origin_y = 0
local lockedAngles = nil
local refilled = false
local Mouse_y = 0
local RightP=true

-- ========== 可调参数 ==========
local MOUSE_SENS       = 0.5
local PULL_STRENGTH    = 8.0
local PULL_STRENGTH_2    = 16.0
local LINE_A_START     = 0.2
local LINE_B_POS       = 0.8
local VIEWMODEL_OFFSET = 20
local HUD_X_RATIO      = 0.75
local LINE_WIDTH       = 220
-- ==============================

local function StartReload()
    reloading = true
    local scrH = ScrH()
    origin_y = scrH * LINE_A_START
    a_y = origin_y
    b_y = scrH * LINE_B_POS
    lockedAngles = LocalPlayer():EyeAngles()
    refilled = false
	Mouse_y = 0
end

local function EndReloadState()
    reloading = false
    lockedAngles = nil
end

local function RequestRefill()
    net.Start("CrueltyReload_Refill")
    net.SendToServer()
end

hook.Add("CreateMove", "CrueltyReload_CreateMove", function(cmd)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        if reloading then EndReloadState() end
        return
    end

    local buttons = cmd:GetButtons()
    local rightHeld = bit.band(buttons, IN_ATTACK2) ~= 0
    local leftDown  = bit.band(buttons, IN_ATTACK)  ~= 0

    -- 松开右键后重新武装
    if not rightHeld then
        RightP = true
    end

    -- 换弹中按左键 → 打断，并解除武装（必须松开右键再按才能再次换弹）
    if reloading and leftDown then
        EndReloadState()
        a_y = origin_y
        RightP = false
    end

    -- 满足条件才启动换弹
    if not reloading and rightHeld and RightP then
        StartReload()
        RightP = false
    end

    -- 换弹中右键松开 → 结束
    if reloading and not rightHeld then
        EndReloadState()
    end

    -- 换弹中：锁定视角、收集鼠标增量
    if reloading then
        Mouse_y = cmd:GetMouseY()   -- 必须在清零之前取
        cmd:SetMouseX(0)
        cmd:SetMouseY(0)
        if lockedAngles then
            cmd:SetViewAngles(lockedAngles)
        end
    end

    -- 始终封锁右键攻击
    cmd:SetButtons(bit.band(buttons, bit.bnot(IN_ATTACK2)))
	
end)
hook.Add("CalcViewModelView", "CrueltyReload_VM", function(wp, vm, oldPos,oldAng,pos,ang)
    local delta=(a_y-origin_y)*0.02
    local offset=ang:Up()*-delta
    local finalPos=pos+offset
    return finalPos,ang
end)

hook.Add("HUDPaint", "CrueltyReload_HUD", function()
    if a_y-origin_y<=5 and not reloading then
		return
	end
    local scrW, scrH = ScrW(), ScrH()
    local centerX = scrW * HUD_X_RATIO
    local halfW = LINE_WIDTH / 2
    local thickness = 2

    -- 贯穿屏幕的竖线
    surface.SetDrawColor(0, 255, 0, 255)
    surface.DrawRect(centerX - thickness / 2, 0, thickness, scrH)

    -- b 线（目标）
    surface.SetDrawColor(0, 255, 0, 255)
    surface.DrawRect(centerX - halfW, b_y, LINE_WIDTH, thickness)

    -- a 线（当前）
    surface.SetDrawColor(255, 50, 50, 255)
    surface.DrawRect(centerX - halfW, a_y, LINE_WIDTH, thickness)

	surface.SetTextPos(centerX, b_y)
	surface.SetTextColor(0, 255, 0, 255)
	surface.DrawText("RELOAD",false)
end)

hook.Add("Think", "CrueltyReload_Think", function()
	
	local dt = FrameTime()
    if reloading then
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then
            EndReloadState()
        end
		a_y = a_y + Mouse_y * MOUSE_SENS
    end
	local dist = a_y - origin_y
	local push=PULL_STRENGTH
	if not reloading then
		push=PULL_STRENGTH_2
	end
	a_y = a_y - dist * push * dt

	a_y = math.Clamp(a_y, 0, ScrH())

	if a_y >= b_y then
		if not refilled then
			RequestRefill()
			refilled = true
			surface.PlaySound("weapons/shotgun/shotgun_reload1.wav")
		end
	else
		refilled = false
	end
end)
