--[[
  REANIMATE v15 — GardonHub v3
  + HumanoidRootPart (invisible, centre, never rotates)
  + Big sword on G key (mesh 871044141, texture 871044152)
  + Sword slash on Q key — wide horizontal arc, kills + flings nearby
  + Destruct mode E
  + Property watchers + selection lock
  + GRAB attack (T) — mouse-targeted, grabs HRP and kills
  + CAGE attack (Y) — mouse-targeted, 4 beams appear then jail
--]]

local Players = game:GetService("Players")
local RunSvc  = game:GetService("RunService")
local UIS     = game:GetService("UserInputService")
local LP      = Players.LocalPlayer
local PG      = LP:WaitForChild("PlayerGui")
local Cam     = workspace.CurrentCamera

Cam.CameraType = Enum.CameraType.Custom

local S         = 5
local SPEED     = 28
local PUNCH_R   = 24
local STOMP_R   = 40
local SLASH_R   = 35
local PUNCH_CD  = 0.9
local STOMP_CD  = 1.5
local SLASH_CD  = 1.2
local UPDATE_HZ = 24

local SWORD_MESH    = "871044141"
local SWORD_TEX     = "871044152"
local SWORD_SIZE    = Vector3.new(S*0.5, S*3.5, S*0.3)

-- ── F3X ─────────────────────────────────────────────
local function getRemote()
    for _,v in LP:GetDescendants() do
        if v.Name=="SyncAPI" then return v.Parent.SyncAPI.ServerEndpoint end
    end
    for _,v in game.ReplicatedStorage:GetDescendants() do
        if v.Name=="SyncAPI" then return v.Parent.SyncAPI.ServerEndpoint end
    end
    error("Equip F3X first!")
end
local rem=getRemote()
local function f3x(...)
    local args={...}
    local ok,err=pcall(function() rem:InvokeServer(unpack(args)) end)
    if not ok then warn("[REANIMATE] F3X err: "..tostring(err):sub(1,60)) end
end

local f={}
function f.CreatePart(cf)      return f3x("CreatePart","Normal",cf,workspace)          end
function f.SetName(p,n)        f3x("SetName",{p},n)                                    end
function f.SetLocked(p,b)      f3x("SetLocked",{p},b)                                  end
function f.MoveMany(t)         f3x("SyncMove",t)                                        end
function f.Move(p,cf)          f3x("SyncMove",{{Part=p,CFrame=cf}})                    end
function f.Resize(p,sz,cf)     f3x("SyncResize",{{Part=p,CFrame=cf,Size=sz}})          end
function f.Anchor(b,p)         f3x("SyncAnchor",{{Part=p,Anchored=b}})                 end
function f.NoCollide(p)        f3x("SyncCollision",{{Part=p,CanCollide=false}})         end
function f.Color(p,c)          f3x("SyncColor",{{Part=p,Color=c,UnionColoring=false}}) end
function f.Trans(p,t)          f3x("SyncMaterial",{{Part=p,Transparency=t}})           end
function f.Kill(p)             f3x("Remove",{p})                                        end
function f.CreateGroup(items)  return f3x("CreateGroup","Model",workspace,items)        end
function f.AddMesh(p)          f3x("CreateMeshes",{{Part=p}})                           end
function f.SetMesh(p,id)       f3x("SyncMesh",{{Part=p,MeshId="rbxassetid://"..id}})   end
function f.SetTex(p,id)        f3x("SyncMesh",{{Part=p,TextureId="rbxassetid://"..id}}) end
function f.MeshScale(p,s)      f3x("SyncMesh",{{Part=p,Scale=s}})                       end

-- ── Character ────────────────────────────────────────
local char=LP.Character or LP.CharacterAdded:Wait()
for _,n in {"HumanoidRootPart","Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg"} do
    char:WaitForChild(n,10)
end
local hum=char:FindFirstChildOfClass("Humanoid")
local hrp=char.HumanoidRootPart
local oCF=hrp.CFrame

local bc=char:FindFirstChildOfClass("BodyColors")
local fb=Color3.fromRGB(163,162,165)
local COL={
    HRP      = Color3.fromRGB(0,0,0),
    Torso    = bc and bc.TorsoColor3    or fb,
    Head     = bc and bc.HeadColor3     or fb,
    LeftArm  = bc and bc.LeftArmColor3  or fb,
    RightArm = bc and bc.RightArmColor3 or fb,
    LeftLeg  = bc and bc.LeftLegColor3  or fb,
    RightLeg = bc and bc.RightLegColor3 or fb,
}

hum.WalkSpeed=0; hum.JumpPower=0; hum.AutoRotate=false
hum:SetStateEnabled(Enum.HumanoidStateType.Dead,false)
hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
-- Hide locally immediately (client-side, no F3X needed)
for _,p in char:GetDescendants() do
    if p:IsA("BasePart") then p.LocalTransparencyModifier=1 end
end
-- Defer F3X freeze calls — give F3X remote a moment to be ready
task.spawn(function()
    task.wait(0.2)  -- warm-up: F3X needs to register the player first
    f.SetLocked(hrp,false)
    f.Anchor(true,hrp)
    -- Make char parts server-transparent too so others can't see the hidden body
    for _,p in char:GetDescendants() do
        if p:IsA("BasePart") then
            pcall(function() f.Trans(p,1) end)
        end
    end
end)

-- ── Rig defs ─────────────────────────────────────────
local SIZES={
    HRP      = Vector3.new(2*S,2*S,1*S),
    Torso    = Vector3.new(2*S,2*S,1*S),
    Head     = Vector3.new(2*S,1*S,1*S),
    LeftArm  = Vector3.new(1*S,2*S,1*S),
    RightArm = Vector3.new(1*S,2*S,1*S),
    LeftLeg  = Vector3.new(1*S,2*S,1*S),
    RightLeg = Vector3.new(1*S,2*S,1*S),
}
local ORDER={"HRP","Torso","Head","LeftArm","RightArm","LeftLeg","RightLeg"}
local LIMBS={"Torso","Head","LeftArm","RightArm","LeftLeg","RightLeg"}
local rp={}
local rigModel=nil
local rigAlive=false
local rigCollision=false
local watchConns={}
local watchCooldowns={}

local function safeCall(fn,...)
    local ok,err=pcall(fn,...)
    if not ok then warn("[REANIMATE] "..tostring(err):sub(1,80)) end
    return ok
end

local regen  -- forward declare

-- ── Fast part spawn ──────────────────────────────────
local function spawnPartWS(cf)
    local arrived
    local conn=workspace.ChildAdded:Connect(function(c)
        if c:IsA("BasePart") and not arrived then arrived=c end
    end)
    f.CreatePart(cf)
    local deadline=tick()+4
    repeat task.wait(0.02) until arrived or tick()>deadline
    conn:Disconnect()
    return arrived
end

-- ── Property enforcer ────────────────────────────────
local function enforcePart(nm,p)
    if not p or not p.Parent then return end
    local now=tick()
    if watchCooldowns[nm] and now-watchCooldowns[nm]<0.2 then return end
    watchCooldowns[nm]=now
    if p.Color~=COL[nm]       then f.Color(p,COL[nm]) end
    if p.Size~=SIZES[nm]      then f.Resize(p,SIZES[nm],p.CFrame) end
    if p.Transparency~=(nm=="HRP" and 1 or 0) then f.Trans(p,nm=="HRP" and 1 or 0) end
    if not p.Anchored          then f.Anchor(true,p) end
    if not p.Locked            then f.SetLocked(p,true) end
end

local WATCH_PROPS={"Color","Size","Transparency","BrickColor"}
local function watchPart(nm,p)
    if watchConns[nm] then
        for _,c in watchConns[nm] do pcall(function() c:Disconnect() end) end
    end
    watchConns[nm]={}
    if not p then return end
    for _,prop in WATCH_PROPS do
        local ok,conn=pcall(function()
            return p:GetPropertyChangedSignal(prop):Connect(function()
                task.spawn(function() enforcePart(nm,p) end)
            end)
        end)
        if ok and conn then table.insert(watchConns[nm],conn) end
    end
    local anchorConn=p:GetPropertyChangedSignal("Anchored"):Connect(function()
        if p and p.Parent and not p.Anchored then f.Anchor(true,p); f.SetLocked(p,true) end
    end)
    table.insert(watchConns[nm],anchorConn)
    local lockConn=p:GetPropertyChangedSignal("Locked"):Connect(function()
        if p and p.Parent and not p.Locked then f.SetLocked(p,true) end
    end)
    table.insert(watchConns[nm],lockConn)
    table.insert(watchConns[nm],p.AncestryChanged:Connect(function()
        if not p.Parent then
            rp[nm]=nil
            if type(regen)=="function" then task.spawn(regen) end
        end
    end))
end

-- ── Build ─────────────────────────────────────────────
local function buildRig(spawnCF)
    table.clear(rp)
    for nm,conns in watchConns do
        for _,c in conns do pcall(function() c:Disconnect() end) end
    end
    table.clear(watchConns)
    if rigModel and rigModel.Parent then pcall(function() rigModel:Destroy() end) end
    rigModel=nil

    local queue={}
    local qconn=workspace.ChildAdded:Connect(function(c)
        if c:IsA("BasePart") then table.insert(queue,c) end
    end)
    for _=1,#ORDER do f.CreatePart(spawnCF); task.wait(0.03) end
    local deadline=tick()+8
    repeat task.wait(0.02) until #queue>=#ORDER or tick()>deadline
    qconn:Disconnect()
    if #queue<#ORDER then warn("[REANIMATE] only got "..(#queue).."/"..#ORDER.." parts"); return false end

    local spawned={}
    for i,nm in ORDER do
        local p=queue[i]
        if not p then warn("[REANIMATE] missing part slot "..i); return false end
        f.SetName(p,"GR_"..nm); rp[nm]=p; table.insert(spawned,p)
    end
    task.wait(0.05)

    f.CreateGroup(spawned)
    local model
    local mdeadline=tick()+4
    repeat task.wait(0.03)
        for _,c in workspace:GetChildren() do
            if c:IsA("Model") and c:FindFirstChild("GR_Torso") then model=c; break end
        end
    until model or tick()>mdeadline
    if not model then warn("[REANIMATE] no model after group"); return false end
    rigModel=model
    f.SetName(model,"Rig")
    task.wait(0.03)

    model.AncestryChanged:Connect(function()
        if not model.Parent then
            rigAlive=false
            if type(regen)=="function" then task.spawn(regen) end
        end
    end)

    for _,nm in ORDER do rp[nm]=rigModel:FindFirstChild("GR_"..nm) end

    for _,nm in ORDER do if rp[nm] then f.SetLocked(rp[nm],false) end end
    task.wait(0.03)
    local resizeBatch={}
    for _,nm in ORDER do if rp[nm] then table.insert(resizeBatch,{Part=rp[nm],CFrame=spawnCF,Size=SIZES[nm]}) end end
    if #resizeBatch>0 then f3x("SyncResize",resizeBatch) end
    task.wait(0.06)
    local colBatch={}
    for _,nm in ORDER do if rp[nm] then table.insert(colBatch,{Part=rp[nm],CanCollide=rigCollision}) end end
    if #colBatch>0 then f3x("SyncCollision",colBatch) end
    task.wait(0.03)
    local colorBatch={}
    for _,nm in LIMBS do if rp[nm] then table.insert(colorBatch,{Part=rp[nm],Color=COL[nm],UnionColoring=false}) end end
    if #colorBatch>0 then f3x("SyncColor",colorBatch) end
    task.wait(0.03)
    -- Apply material to all limbs
    local matBatch={}
    for _,nm in LIMBS do if rp[nm] then table.insert(matBatch,{Part=rp[nm],Material=rigMaterial}) end end
    if #matBatch>0 then f3x("SyncMaterial",matBatch) end
    task.wait(0.03)
    local anchorBatch={}
    for _,nm in ORDER do if rp[nm] then table.insert(anchorBatch,{Part=rp[nm],Anchored=true}) end end
    if #anchorBatch>0 then f3x("SyncAnchor",anchorBatch) end
    task.wait(0.03)
    if rp["HRP"] then f3x("SyncMaterial",{{Part=rp["HRP"],Transparency=1}}) end
    task.wait(0.02)
    for _,nm in ORDER do if rp[nm] then f.SetLocked(rp[nm],true) end end
    task.wait(0.02)
    for _,nm in ORDER do watchPart(nm,rp[nm]) end

    Cam.CameraSubject=rp["HRP"]
    print("[REANIMATE] Rig built!")
    return true
end

-- ── Giant state ──────────────────────────────────────
local gPos=oCF.Position+Vector3.new(0,S*2,0)
local gYaw=0
local animT=0
local idleT=0
local moving=false
local punchStart=-99; local stompStart=-99; local slashStart=-99
local PUNCH_DUR=0.4; local STOMP_DUR=0.5; local SLASH_DUR=0.7
local destructMode=false
local chaosMode=false
local lastDestructTap=0
local stompOnWalk=false
local lastStepSign=0
local swordEquipped=false
local swordPart=nil
local layingDown=false
local layBlend  =0
local layPoseIdx   =1
local layPoseNext  =2
local layPoseBlend =0
local layPoseTimer =0
local layPoseHoldTime = math.random(22,40)

local function gCF()
    return CFrame.new(gPos)*CFrame.Angles(0,gYaw,0)
end

-- ── Mouse target helper ──────────────────────────────
-- Finds the player closest to where the mouse is pointing in 3D space.
-- Distance doesn't matter — uses angular proximity to camera ray.
-- ── Mouse target helpers ─────────────────────────────
-- Use LP.PlayerGui Mouse object — no raycast, just .Target
local Mouse = LP:GetMouse()

-- Returns the player whose character contains Mouse.Target
local function getMouseTargetPlayer()
    local target = Mouse.Target
    if not target then return nil end
    -- walk up ancestry to find a character model
    local obj = target
    while obj do
        local pl = Players:GetPlayerFromCharacter(obj)
        if pl and pl ~= LP then return pl end
        obj = obj.Parent
    end
    return nil
end

-- Returns the raw BasePart under the mouse (any part, not just players)
local function getMouseTargetPart()
    return Mouse.Target
end

-- ── Sword + slash ────────────────────────────────────
local function getSwordCF(rArmCF)
    local armBottom=rArmCF*CFrame.new(0,-S*0.5,0)
    return armBottom*CFrame.new(0,-SWORD_SIZE.Y*0.5,0)
end

local function getSlashAngles(slashT)
    if slashT<=0 or slashT>=1 then return 0,0,0 end
    local r=math.rad
    local pitch,yaw,roll
    if slashT<0.25 then
        local t=slashT/0.25; pitch=r(-130)*t; yaw=r(50)*t; roll=r(0)
    elseif slashT<0.70 then
        local t=(slashT-0.25)/0.45; local ease=1-(1-t)^2
        pitch=r(-130)+r(200)*ease; yaw=r(50)-r(120)*ease; roll=r(30)*math.sin(t*math.pi)
    else
        local t=(slashT-0.70)/0.30
        pitch=r(70)-r(50)*t; yaw=r(-70)+r(70)*t; roll=0
    end
    return pitch,yaw,roll
end

local slashWaveActive=false
local function fireSlashWave()
    if slashWaveActive then return end
    slashWaveActive=true
    task.spawn(function()
        local rigHRP=rp["HRP"]
        local fwd
        if rigHRP and rigHRP.Parent then fwd=rigHRP.CFrame.LookVector
        else fwd=CFrame.Angles(0,gYaw,0):VectorToWorldSpace(Vector3.new(0,0,-1)) end
        fwd=Vector3.new(fwd.X,0,fwd.Z).Unit

        local wp
        local conn=workspace.ChildAdded:Connect(function(c)
            if c:IsA("BasePart") and not wp then wp=c end
        end)
        local wavePos=gPos+Vector3.new(0,S*1.5,0)+fwd*S*2
        local waveCF=CFrame.new(wavePos,wavePos+fwd)
        f.CreatePart(waveCF)
        local deadline=tick()+3
        repeat task.wait(0.015) until wp or tick()>deadline
        conn:Disconnect()
        if not wp then slashWaveActive=false; return end

        local waveSize=Vector3.new(S*10,S*7,S*1.2)
        f.SetLocked(wp,false)
        f3x("SyncResize",{{Part=wp,CFrame=waveCF,Size=waveSize}})
        f3x("SyncCollision",{{Part=wp,CanCollide=false}})
        f3x("SyncColor",{{Part=wp,Color=Color3.fromRGB(160,215,255),UnionColoring=false}})
        f3x("SyncMaterial",{{Part=wp,Transparency=0.25}})
        f3x("SyncAnchor",{{Part=wp,Anchored=true}})
        task.wait(0.04)

        local STEPS=28; local STEP_DT=1/30; local STEP_D=90*STEP_DT
        local REACH=waveSize.X*0.5
        for _=1,STEPS do
            wavePos=wavePos+fwd*STEP_D
            f3x("SyncMove",{{Part=wp,CFrame=CFrame.new(wavePos,wavePos+fwd)}})
            task.wait(STEP_DT)
            local voidBatch={}
            for _,obj in workspace:GetDescendants() do
                if obj:IsA("BasePart") and not obj:IsDescendantOf(char)
                   and not (rigModel and obj:IsDescendantOf(rigModel)) then
                    if (obj.Position-wavePos).Magnitude<=REACH then table.insert(voidBatch,obj) end
                end
            end
            if #voidBatch>0 then
                f3x("SetLocked",voidBatch,false)
                local moveBatch={}
                for _,obj in voidBatch do table.insert(moveBatch,{Part=obj,CFrame=CFrame.new(0,-10000,0)}) end
                f3x("SyncMove",moveBatch)
            end
        end
        f3x("SyncMaterial",{{Part=wp,Transparency=0.9}})
        task.wait(0.06)
        f.SetLocked(wp,false); f.Kill(wp)
        slashWaveActive=false
    end)
end

-- ── Ground snap ──────────────────────────────────────
local LEG_HEIGHT=S*2
local function getGroundY()
    local origin=Vector3.new(gPos.X,gPos.Y+S*2,gPos.Z)
    local direction=Vector3.new(0,-(S*2+LEG_HEIGHT+50),0)
    local ignore={char}
    if rigModel then table.insert(ignore,rigModel) end
    local ray=RaycastParams.new()
    ray.FilterType=Enum.RaycastFilterType.Exclude
    ray.FilterDescendantsInstances=ignore
    local result=workspace:Raycast(origin,direction,ray)
    if result then return result.Position.Y+LEG_HEIGHT end
    return nil
end

-- ── Puppet math ──────────────────────────────────────
local showToolEnabled=false
local toolPart=nil

-- ── Granite golem animation state ───────────────────
-- When material is Granite, animations become jerky stop-motion
local graniteMode = false  -- set true when Granite is picked

-- Stepped time: snaps to discrete frames like stop-motion
-- Updates every ~0.18s to give that "held pose" feel
local graniteStepT   = 0      -- the quantized idle clock
local graniteStepAcc = 0      -- accumulator
local GRANITE_STEP   = 0.18   -- seconds between pose snaps

-- Random per-limb offsets that get re-rolled each step
local graniteJitter = {
    headYaw   = 0,
    headRoll  = 0,
    rArmRoll  = 0,
    lArmPitch = 0,
    torsoRoll = 0,
}
local function rollGraniteJitter()
    local function rj(a,b) return a+(b-a)*math.random() end
    graniteJitter.headYaw   = math.rad(rj(-8,  8))
    graniteJitter.headRoll  = math.rad(rj(-5,  5))
    graniteJitter.rArmRoll  = math.rad(rj(-6,  6))
    graniteJitter.lArmPitch = math.rad(rj(-5,  5))
    graniteJitter.torsoRoll = math.rad(rj(-3,  3))
end
rollGraniteJitter()

local function getPuppetCFs(t,it,isMoving,pTime,sTime,slTime)
    local r=math.rad; local w=isMoving and 1 or 0

    -- ── Granite: step the idle clock discretely ────────
    local eff_it = it  -- effective idle time (may be quantized)
    if graniteMode then
        eff_it = graniteStepT  -- frozen between steps
    end

    local cyc=t*(_G.__reanimWalkFreq or 6)

    -- Granite walk: quantize leg swing too — stomp, pause, stomp
    local eff_cyc = cyc
    if graniteMode and isMoving then
        -- snap cyc to nearest 0.5 increments for chunky steps
        eff_cyc = math.floor(cyc * 2 + 0.5) / 2
    end

    local bob=math.abs(math.sin(eff_cyc))*0.3*S*w
    -- Granite: heavier bob
    if graniteMode then bob = math.abs(math.sin(eff_cyc))*0.5*S*w end

    local flat=CFrame.new(gPos+Vector3.new(0,-bob,0))*CFrame.Angles(0,gYaw,0)
    local hrpCF=gCF()

    local sPhase=math.clamp((tick()-sTime)/STOMP_DUR,0,1)
    local sEx=sPhase<0.4 and sPhase/0.4 or 1-(sPhase-0.4)/0.6
    local rLegStomp=r(75)*sEx; local bodyLurch=r(10)*sEx

    local slashPhase=math.clamp((tick()-slTime)/SLASH_DUR,0,1)
    local isSlashing=slashPhase>0 and slashPhase<1
    local pPhase=isSlashing and 0 or math.clamp((tick()-pTime)/PUNCH_DUR,0,1)
    local pEx=pPhase<0.5 and pPhase/0.5 or 1-(pPhase-0.5)/0.5
    local rArmPunch=-r(115)*pEx; local rArmFwdZ=-S*0.9*pEx
    local sPitch,sYaw,sRoll=getSlashAngles(slashPhase)

    -- Idle anims — granite uses tiny stiff values + jitter offsets
    local breatheAmt = graniteMode and 0.02 or (_G.__reanimBreathe or 0.12)
    local breathe  = math.sin(eff_it*1.2) * breatheAmt*S * (1-w)
    local armSway  = math.sin(eff_it*0.9) * r(graniteMode and 2 or 8)  * (1-w)
    local headLook = math.sin(eff_it*0.7) * (_G.__reanimHeadLook or r(graniteMode and 4 or 12)) * (1-w)
    local rShrug   = math.sin(eff_it*1.1) * r(graniteMode and 2 or 5)  * (1-w)
    local lShrug   = math.sin(eff_it*1.1+math.pi) * r(graniteMode and 2 or 5) * (1-w)
    local bodySway = math.sin(eff_it*0.8) * r(graniteMode and 1 or 3)  * (1-w)

    local torsoPitch = r(22+10*w)+bodyLurch
    local torsoSway  = math.sin(eff_it*1.8)*r(2.5)*(1-w)
    -- Granite: add jitter offsets on top
    local jTorsoRoll  = graniteMode and graniteJitter.torsoRoll or 0
    local torso = flat
        * CFrame.new(0,S*1.0+breathe,0)
        * CFrame.Angles(torsoPitch, bodySway+jTorsoRoll, 0)

    local headPitch = r(16)-r(8)*w+math.sin(eff_cyc)*r(6)*w
    -- Granite: stiffer head, held at odd angle
    local jHeadYaw  = graniteMode and graniteJitter.headYaw  or 0
    local jHeadRoll = graniteMode and graniteJitter.headRoll or 0
    local head = torso
        * CFrame.new(0,S*1.0,0)
        * CFrame.Angles(headPitch, headLook+jHeadYaw, jHeadRoll)

    local aHang = r(18)
    -- Granite: arms hang more rigidly outward, almost no swing
    local aSwing = graniteMode and r(8)*w or r(20)*w
    local aOut   = r(12)

    local jRArmRoll  = graniteMode and graniteJitter.rArmRoll  or 0
    local jLArmPitch = graniteMode and graniteJitter.lArmPitch or 0

    local rPitch = isSlashing and (aHang+sPitch) or (aHang-math.sin(eff_cyc)*aSwing+rArmPunch+armSway)
    local rYaw   = isSlashing and sYaw or 0
    local rRoll  = isSlashing and (aOut+sRoll) or (aOut+rShrug+jRArmRoll)
    local rFZ    = isSlashing and 0 or rArmFwdZ
    local rArmCF = flat*CFrame.new(S*1.1,S*1.8,rFZ)*CFrame.Angles(rPitch,rYaw,rRoll)
    local rArm   = rArmCF*CFrame.new(0,-S,0)

    local lPitch = aHang+math.sin(eff_cyc)*aSwing-armSway+jLArmPitch
    local lArm   = (flat*CFrame.new(-S*1.1,S*1.8,0)*CFrame.Angles(lPitch,0,-aOut+lShrug))*CFrame.new(0,-S,0)

    -- Granite legs: heavy stomp swing, no smooth fade
    local lSwing = graniteMode and r(35)*w or r(28)*w
    local lOut   = r(3)
    local rLeg   = (flat*CFrame.new(S*0.5,0,0)*CFrame.Angles(-math.sin(eff_cyc)*lSwing+rLegStomp,0,lOut))*CFrame.new(0,-S,0)
    local lLeg   = (flat*CFrame.new(-S*0.5,0,0)*CFrame.Angles(math.sin(eff_cyc)*lSwing,0,-lOut))*CFrame.new(0,-S,0)

    local sword=swordEquipped and getSwordCF(rArm) or nil
    local toolHoldCF=nil
    if showToolEnabled and toolPart and toolPart.Parent then
        local holdArm=swordEquipped and lArm or rArm
        local hand=holdArm*CFrame.new(0,-S*0.5,0)
        local sz=toolPart.Size
        toolHoldCF=hand*CFrame.new(0,-sz.Y*0.5,0)
    end


    -- ── Lay down / chill pose system ────────────────────
    if layBlend > 0 then
        local b  = layBlend
        local bl = math.sin(it*0.45)*0.05*S  -- slow breathe offset

        local groundY    = gPos.Y - S*2
        local seatY      = groundY + S*0.5   -- torso centre when flat on back

        -- Each pose returns a table of CFrames.
        -- All are built in world space from scratch using gPos/gYaw.

        -- Shared base helpers
        local upBase = CFrame.new(gPos) * CFrame.Angles(0, gYaw, 0)  -- standing yaw only
        local backBase = CFrame.new(Vector3.new(gPos.X, seatY, gPos.Z))
                       * CFrame.Angles(0, gYaw, 0)
                       * CFrame.Angles(-math.pi/2, 0, 0)  -- tipped flat on back

        -- ─── POSE 0: Flat on back, arms spread like an angel ───
        local function poseAngel()
            local h  = math.sin(it*0.3)*r(5)   -- lazy head drift
            local af = math.sin(it*0.4)*r(4)   -- arm float
            return {
                HRP      = backBase * CFrame.new(0, S*1.0, bl),
                Torso    = backBase * CFrame.new(0, S*1.0, bl),
                Head     = backBase * CFrame.new(0, S*2.2, bl) * CFrame.Angles(r(-8)+math.sin(it*0.25)*r(3), h, 0),
                RightArm = (backBase * CFrame.new(S*1.1, S*1.8, bl) * CFrame.Angles(0,0, r(90)+af))  * CFrame.new(0,-S,0),
                LeftArm  = (backBase * CFrame.new(-S*1.1,S*1.8, bl) * CFrame.Angles(0,0,-r(90)-af))  * CFrame.new(0,-S,0),
                RightLeg = (backBase * CFrame.new(S*0.55, 0, bl)    * CFrame.Angles(0,0, r(22)))      * CFrame.new(0,-S,0),
                LeftLeg  = (backBase * CFrame.new(-S*0.55,0, bl)    * CFrame.Angles(0,0,-r(22)))      * CFrame.new(0,-S,0),
            }
        end

        -- ─── POSE 1: On right side, curled up slightly ───
        local function poseSideRight()
            local sideBase = CFrame.new(Vector3.new(gPos.X, seatY, gPos.Z))
                           * CFrame.Angles(0, gYaw, 0)
                           * CFrame.Angles(-math.pi/2, 0, -math.pi/2)  -- rolled onto right side
            local nod = math.sin(it*0.3)*r(3)
            return {
                HRP      = sideBase * CFrame.new(0, S*1.0, bl),
                Torso    = sideBase * CFrame.new(0, S*1.0, bl),
                Head     = sideBase * CFrame.new(0, S*2.2, bl) * CFrame.Angles(r(-5)+nod, 0, 0),
                RightArm = (sideBase * CFrame.new(S*1.1, S*1.8, bl-S*0.3) * CFrame.Angles(r(15),0, r(40))) * CFrame.new(0,-S,0),
                LeftArm  = (sideBase * CFrame.new(-S*1.1,S*1.5, bl+S*0.4) * CFrame.Angles(r(-30),0,-r(20))) * CFrame.new(0,-S,0),
                RightLeg = (sideBase * CFrame.new(S*0.5,  0,    bl-S*0.2) * CFrame.Angles(r(15), 0, r(5)))  * CFrame.new(0,-S,0),
                LeftLeg  = (sideBase * CFrame.new(-S*0.5, S*0.3,bl+S*0.3) * CFrame.Angles(r(-25),0,-r(8)))  * CFrame.new(0,-S,0),
            }
        end

        -- ─── POSE 2: On left side ───
        local function poseSideLeft()
            local sideBase = CFrame.new(Vector3.new(gPos.X, seatY, gPos.Z))
                           * CFrame.Angles(0, gYaw, 0)
                           * CFrame.Angles(-math.pi/2, 0, math.pi/2)  -- rolled onto left side
            local nod = math.sin(it*0.28)*r(3)
            return {
                HRP      = sideBase * CFrame.new(0, S*1.0, bl),
                Torso    = sideBase * CFrame.new(0, S*1.0, bl),
                Head     = sideBase * CFrame.new(0, S*2.2, bl) * CFrame.Angles(r(-5)+nod, 0, 0),
                RightArm = (sideBase * CFrame.new(S*1.1, S*1.5, bl+S*0.4) * CFrame.Angles(r(-30),0, r(20))) * CFrame.new(0,-S,0),
                LeftArm  = (sideBase * CFrame.new(-S*1.1,S*1.8, bl-S*0.3) * CFrame.Angles(r(15), 0,-r(40))) * CFrame.new(0,-S,0),
                RightLeg = (sideBase * CFrame.new(S*0.5,  S*0.3,bl+S*0.3) * CFrame.Angles(r(-25),0, r(8)))  * CFrame.new(0,-S,0),
                LeftLeg  = (sideBase * CFrame.new(-S*0.5, 0,    bl-S*0.2) * CFrame.Angles(r(15), 0,-r(5)))  * CFrame.new(0,-S,0),
            }
        end

        -- ─── POSE 3: Sitting, legs out, leaning back casually ───
        local function poseSit()
            local sitY   = groundY + S*1.0
            local sitBase= CFrame.new(Vector3.new(gPos.X, sitY, gPos.Z))
                         * CFrame.Angles(0, gYaw, 0)
            local lean   = math.sin(it*0.3)*r(3)
            local headW  = math.sin(it*0.35)*r(6)
            return {
                HRP      = sitBase,
                Torso    = sitBase * CFrame.Angles(r(15)+lean, 0, 0),
                -- head offset from sitBase: torso is S*2 tall, head sits on top
                Head     = sitBase * CFrame.new(0, S*1.2, -S*0.1) * CFrame.Angles(r(-8)+lean, headW, 0),
                RightArm = (sitBase * CFrame.new(S*1.1, S*1.4,-S*0.5) * CFrame.Angles(r(-35)+lean,0, r(18))) * CFrame.new(0,-S,0),
                LeftArm  = (sitBase * CFrame.new(-S*1.1,S*1.4,-S*0.5) * CFrame.Angles(r(-35)+lean,0,-r(18))) * CFrame.new(0,-S,0),
                RightLeg = (sitBase * CFrame.new(S*0.5, -S*0.5, S*1.0) * CFrame.Angles(r(-80),0, r(4))) * CFrame.new(0,-S,0),
                LeftLeg  = (sitBase * CFrame.new(-S*0.5,-S*0.5, S*1.0) * CFrame.Angles(r(-80),0,-r(4))) * CFrame.new(0,-S,0),
            }
        end

        -- ─── POSE 4: Face down, resting ───
        local function poseFaceDown()
            local faceBase = CFrame.new(Vector3.new(gPos.X, seatY, gPos.Z))
                           * CFrame.Angles(0, gYaw, 0)
                           * CFrame.Angles(math.pi/2, 0, 0)  -- pitched face-down
            local nod = math.sin(it*0.28)*r(3)
            return {
                HRP      = faceBase * CFrame.new(0, S*1.0, bl),
                Torso    = faceBase * CFrame.new(0, S*1.0, bl),
                Head     = faceBase * CFrame.new(0, S*2.2, bl) * CFrame.Angles(r(10)+nod, math.sin(it*0.2)*r(8), 0),
                RightArm = (faceBase * CFrame.new(S*1.1, S*1.8, bl) * CFrame.Angles(r(-30),0, r(50)))  * CFrame.new(0,-S,0),
                LeftArm  = (faceBase * CFrame.new(-S*1.1,S*1.8, bl) * CFrame.Angles(r(-30),0,-r(50)))  * CFrame.new(0,-S,0),
                RightLeg = (faceBase * CFrame.new(S*0.5,  0,    bl) * CFrame.Angles(0,0, r(5)))         * CFrame.new(0,-S,0),
                LeftLeg  = (faceBase * CFrame.new(-S*0.5, 0,    bl) * CFrame.Angles(0,0,-r(5)))         * CFrame.new(0,-S,0),
            }
        end

        -- ─── POSE 5: Sitting cross-legged, arms resting on knees ───
        local function poseCrossLegged()
            local sitY   = groundY + S*1.0
            local sitBase= CFrame.new(Vector3.new(gPos.X, sitY, gPos.Z))
                         * CFrame.Angles(0, gYaw, 0)
            local sway   = math.sin(it*0.22)*r(2)
            local headNd = math.sin(it*0.3)*r(4)
            return {
                HRP      = sitBase,
                Torso    = sitBase * CFrame.Angles(r(5)+sway, 0, 0),
                Head     = sitBase * CFrame.new(0, S*1.2, -S*0.1) * CFrame.Angles(r(-3)+headNd, math.sin(it*0.4)*r(7), 0),
                RightArm = (sitBase * CFrame.new(S*1.1, S*1.2, S*0.6) * CFrame.Angles(r(-55)+sway,0, r(25))) * CFrame.new(0,-S,0),
                LeftArm  = (sitBase * CFrame.new(-S*1.1,S*1.2, S*0.6) * CFrame.Angles(r(-55)+sway,0,-r(25))) * CFrame.new(0,-S,0),
                RightLeg = (sitBase * CFrame.new(S*0.6, -S*0.8, S*0.8) * CFrame.Angles(r(-55), r(40), r(10))) * CFrame.new(0,-S,0),
                LeftLeg  = (sitBase * CFrame.new(-S*0.6,-S*0.8, S*0.8) * CFrame.Angles(r(-55),-r(40),-r(10))) * CFrame.new(0,-S,0),
            }
        end

        -- ─── POSE 6: On back, one knee up ───
        local function poseKneeUp()
            local nod = math.sin(it*0.3)*r(4)
            local af  = math.sin(it*0.35)*r(5)
            return {
                HRP      = backBase * CFrame.new(0, S*1.0, bl),
                Torso    = backBase * CFrame.new(0, S*1.0, bl),
                Head     = backBase * CFrame.new(0, S*2.2, bl) * CFrame.Angles(r(-8)+nod, math.sin(it*0.25)*r(4), 0),
                RightArm = (backBase * CFrame.new(S*1.1, S*1.8, bl) * CFrame.Angles(0,0, r(55)+af))   * CFrame.new(0,-S,0),
                LeftArm  = (backBase * CFrame.new(-S*1.1,S*1.8, bl) * CFrame.Angles(r(-20),0,-r(30))) * CFrame.new(0,-S,0),
                -- right leg flat
                RightLeg = (backBase * CFrame.new(S*0.5, 0, bl)     * CFrame.Angles(0,0, r(5)))        * CFrame.new(0,-S,0),
                -- left leg: knee raised
                LeftLeg  = (backBase * CFrame.new(-S*0.5, S*0.5, bl+S*0.8) * CFrame.Angles(r(50),0,-r(5))) * CFrame.new(0,-S,0),
            }
        end

        local POSES = {poseAngel, poseSideRight, poseSideLeft, poseSit, poseFaceDown, poseCrossLegged, poseKneeUp}

        -- Pose cycling: switch every ~6s with a smooth blend between them
        local curPose  = POSES[layPoseIdx]()
        local nextPose = POSES[layPoseNext]()
        -- smooth ease in/out: f(t) = 3t²-2t³
        local t2 = layPoseBlend
        local pBlend = t2*t2*(3 - 2*t2)

        local function lerpCF(a,b2,t2) return a:Lerp(b2,t2) end
        local blendedPose = {}
        for _,key in {"HRP","Torso","Head","RightArm","LeftArm","RightLeg","LeftLeg"} do
            blendedPose[key] = lerpCF(curPose[key], nextPose[key], pBlend)
        end
        blendedPose.Sword = nil; blendedPose.Tool = nil

        -- Blend between standing and lying
        if b >= 0.999 then
            return blendedPose
        else
            local standPose = {HRP=hrpCF,Torso=torso,Head=head,RightArm=rArm,LeftArm=lArm,RightLeg=rLeg,LeftLeg=lLeg}
            local out = {}
            for _,key in {"HRP","Torso","Head","RightArm","LeftArm","RightLeg","LeftLeg"} do
                out[key] = lerpCF(standPose[key], blendedPose[key], b)
            end
            out.Sword=nil; out.Tool=nil
            return out
        end
    end

    return {HRP=hrpCF,Torso=torso,Head=head,RightArm=rArm,LeftArm=lArm,RightLeg=rLeg,LeftLeg=lLeg,Sword=sword,Tool=toolHoldCF}
end

-- ── Sword spawn/remove ───────────────────────────────
local function spawnSword()
    if swordPart and swordPart.Parent then return end
    local p=spawnPartWS(CFrame.new(gPos))
    if not p then return end
    f.SetName(p,"GR_Sword"); task.wait(0.05)
    f3x("SetParent",{p},rigModel); task.wait(0.1)
    local found=rigModel:FindFirstChild("GR_Sword")
    if not found then return end
    swordPart=found
    f.SetLocked(swordPart,false)
    f.Resize(swordPart,SWORD_SIZE,CFrame.new(gPos)); task.wait(0.08)
    f.NoCollide(swordPart); task.wait(0.04)
    f.Color(swordPart,Color3.fromRGB(180,180,190)); task.wait(0.04)
    f.Anchor(true,swordPart); task.wait(0.04)
    f.AddMesh(swordPart); task.wait(0.15)
    f.SetMesh(swordPart,SWORD_MESH); task.wait(0.05)
    f.SetTex(swordPart,SWORD_TEX); task.wait(0.05)
    f.MeshScale(swordPart,Vector3.new(S*0.55,S*0.55,S*0.55)); task.wait(0.05)
    f.SetLocked(swordPart,true)
end

local function removeSword()
    if swordPart and swordPart.Parent then f.SetLocked(swordPart,false); f.Kill(swordPart) end
    swordPart=nil
end

-- ── Show Tool system ─────────────────────────────────
local lastToolName=""

local function removeToolPart()
    if toolPart and toolPart.Parent then f.SetLocked(toolPart,false); f.Kill(toolPart) end
    toolPart=nil; lastToolName=""
end

local function spawnToolPart(tool)
    if not showToolEnabled or not rigModel or not rigModel.Parent then return end
    local handle=tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
    if not handle then return end
    removeToolPart(); lastToolName=tool.Name
    local p; local conn=workspace.ChildAdded:Connect(function(c) if c:IsA("BasePart") and not p then p=c end end)
    f.CreatePart(CFrame.new(gPos))
    local deadline=tick()+4; repeat task.wait(0.02) until p or tick()>deadline; conn:Disconnect()
    if not p then return end
    f.SetName(p,"GR_Tool"); task.wait(0.04)
    f3x("SetParent",{p},rigModel); task.wait(0.08)
    local found=rigModel:FindFirstChild("GR_Tool")
    if not found then return end
    toolPart=found
    local scaledSize=handle.Size*(S*0.5)
    local spawnCF=CFrame.new(gPos)
    f.SetLocked(toolPart,false); task.wait(0.03)
    f3x("SyncResize",{{Part=toolPart,CFrame=spawnCF,Size=scaledSize}})
    f3x("SyncCollision",{{Part=toolPart,CanCollide=false}})
    f3x("SyncColor",{{Part=toolPart,Color=handle.Color,UnionColoring=false}})
    f3x("SyncMaterial",{{Part=toolPart,Transparency=handle.Transparency}})
    f3x("SyncAnchor",{{Part=toolPart,Anchored=true}}); task.wait(0.04)
    local mesh=handle:FindFirstChildWhichIsA("SpecialMesh") or handle:FindFirstChildWhichIsA("DataModelMesh")
    if mesh then
        f3x("CreateMeshes",{{Part=toolPart}}); task.wait(0.12)
        local sd={Part=toolPart}
        if mesh:IsA("SpecialMesh") then
            if mesh.MeshId~="" then sd.MeshId=mesh.MeshId end
            if mesh.TextureId~="" then sd.TextureId=mesh.TextureId end
            if mesh.Scale then sd.Scale=mesh.Scale*(S*0.5) end
            if mesh.MeshType then sd.MeshType=mesh.MeshType end
        end
        f3x("SyncMesh",{sd}); task.wait(0.05)
    end
    for _,child in handle:GetChildren() do
        if child:IsA("Decal") or child:IsA("Texture") then
            local tt=child:IsA("Decal") and "Decal" or "Texture"
            local face=child.Face
            f3x("CreateTextures",{{Part=toolPart,Face=face,TextureType=tt}}); task.wait(0.04)
            local st={Part=toolPart,Face=face,TextureType=tt,Texture=child.Texture}
            if child:IsA("Texture") then st.StudsPerTileU=child.StudsPerTileU*(S*0.5); st.StudsPerTileV=child.StudsPerTileV*(S*0.5) end
            f3x("SyncTexture",{st}); task.wait(0.03)
        end
    end
    f.SetLocked(toolPart,true)
end

task.spawn(function()
    while true do
        task.wait(0.3)
        if not showToolEnabled then
            if toolPart and toolPart.Parent then removeToolPart() end
        else
            local currentTool
            for _,v in char:GetChildren() do if v:IsA("Tool") then currentTool=v; break end end
            if currentTool then
                if currentTool.Name~=lastToolName then task.spawn(function() spawnToolPart(currentTool) end) end
            else
                if toolPart and toolPart.Parent then removeToolPart() end
            end
        end
    end
end)

-- ── Regen ────────────────────────────────────────────
local regenBusy=false
regen=function()
    if regenBusy then return end
    regenBusy=true
    task.spawn(function()
        if not rigAlive or not rigModel or not rigModel.Parent then
            rigAlive=false
            local ok=buildRig(CFrame.new(gPos))
            rigAlive=ok==true
            if statusLbl then
                statusLbl.Text=rigAlive and "⬤ Rig online" or "❌ Build failed"
                statusLbl.TextColor3=rigAlive and GRN or RED
            end
            if rigAlive and swordEquipped then spawnSword() end
            regenBusy=false; return
        end
        for _,nm in ORDER do
            local p=rp[nm]
            if not p or not p.Parent then
                rp[nm]=nil
                local np=spawnPartWS(CFrame.new(gPos))
                if np then
                    f.SetName(np,"GR_"..nm); task.wait(0.05)
                    f3x("SetParent",{np},rigModel); task.wait(0.1)
                    local found=rigModel:FindFirstChild("GR_"..nm)
                    if found then
                        rp[nm]=found; f.SetLocked(found,false)
                        f.Resize(found,SIZES[nm],CFrame.new(gPos)); task.wait(0.05)
                        f.NoCollide(found)
                        if nm=="HRP" then f.Trans(found,1) else f.Color(found,COL[nm]) end
                        -- re-apply material
                        f3x("SyncMaterial",{{Part=found, Material=rigMaterial}})
                        task.wait(0.05); f.Anchor(true,found); task.wait(0.05)
                        f.SetLocked(found,true); watchPart(nm,found)
                    end
                end
            end
        end
        if swordEquipped and (not swordPart or not swordPart.Parent) then
            swordPart=nil; spawnSword()
        end
        regenBusy=false
    end)
end

-- ── Attacks ──────────────────────────────────────────
local tP,tS,tSl=0,0,0
local GRAB_CD=1.0
local CAGE_CD=2.0
local tGrab=0
local tCage=0

local function killHead(pl)
    local c=pl.Character; if not c then return end
    local h=c:FindFirstChild("Head")
    if h then f.SetLocked(h,false); f.Kill(h) end
end

-- ── Crater spawner ───────────────────────────────────
local craterBusy=false
local function spawnCrater(origin)
    if craterBusy then return end
    craterBusy=true
    task.spawn(function()
        local CRATER_R=S*4.5; local SLAB_COUNT=10
        local SLAB_W=(2*math.pi*CRATER_R/SLAB_COUNT)*1.1
        local SLAB_H=S*1.2; local SLAB_D=S*1.4
        local CENTER_W=CRATER_R*1.4; local CENTER_H=S*0.5
        local groundY=getGroundY() or origin.Y
        local craterY=groundY
        local rubbleCol=Color3.fromRGB(35,30,28); local innerCol=Color3.fromRGB(20,18,16)
        local parts={}
        local function addSlab(cf,size,col)
            local arrived; local conn=workspace.ChildAdded:Connect(function(c)
                if c:IsA("BasePart") and not arrived then arrived=c end end)
            f.CreatePart(cf); local deadline=tick()+3
            repeat task.wait(0.015) until arrived or tick()>deadline; conn:Disconnect()
            if not arrived then return end
            f.SetLocked(arrived,false)
            f3x("SyncResize",{{Part=arrived,CFrame=cf,Size=size}})
            f3x("SyncCollision",{{Part=arrived,CanCollide=false}})
            f3x("SyncColor",{{Part=arrived,Color=col,UnionColoring=false}})
            f3x("SyncAnchor",{{Part=arrived,Anchored=true}})
            f.SetLocked(arrived,true); table.insert(parts,arrived)
        end
        addSlab(CFrame.new(origin.X,craterY-CENTER_H*0.3,origin.Z),Vector3.new(CENTER_W,CENTER_H,CENTER_W),innerCol)
        for i=0,SLAB_COUNT-1 do
            local angle=(2*math.pi/SLAB_COUNT)*i
            local rx=math.cos(angle)*CRATER_R; local rz=math.sin(angle)*CRATER_R
            local slabCF=CFrame.new(origin.X+rx,craterY+SLAB_H*0.3,origin.Z+rz)*CFrame.Angles(0,-angle,0)*CFrame.Angles(math.rad(-35),0,0)
            addSlab(slabCF,Vector3.new(SLAB_W,SLAB_H,SLAB_D),rubbleCol)
        end
        local INNER_COUNT=6; local INNER_R=CRATER_R*0.55
        for i=0,INNER_COUNT-1 do
            local angle=(2*math.pi/INNER_COUNT)*i+math.pi/INNER_COUNT
            local rx=math.cos(angle)*INNER_R; local rz=math.sin(angle)*INNER_R
            local cf=CFrame.new(origin.X+rx,craterY+SLAB_H*0.15,origin.Z+rz)*CFrame.Angles(0,-angle,0)*CFrame.Angles(math.rad(-50),0,0)
            addSlab(cf,Vector3.new(SLAB_W*0.6,SLAB_H*0.6,SLAB_D*0.7),rubbleCol)
        end
        craterBusy=false
        task.delay(3,function()
            for _,p in parts do if p and p.Parent then pcall(function() f.SetLocked(p,false); f.Kill(p) end) end end
        end)
    end)
end

local function voidPartsInRange(origin,radius)
    local unlockList={}; local moveBatch={}
    for _,obj in workspace:GetDescendants() do
        if obj:IsA("BasePart") and not obj:IsDescendantOf(char)
           and not (rigModel and obj:IsDescendantOf(rigModel)) then
            if (obj.Position-origin).Magnitude<=radius then
                table.insert(unlockList,obj)
                table.insert(moveBatch,{Part=obj,CFrame=CFrame.new(0,-10000,0)})
            end
        end
    end
    if #unlockList>0 then
        f3x("SetLocked",unlockList,false)
        f3x("SyncAnchor",(function() local t={} for _,o in unlockList do table.insert(t,{Part=o,Anchored=false}) end return t end)())
        f3x("SyncMove",moveBatch)
    end
end

local function doPunch()
    if swordEquipped then return end
    if tick()-tP<PUNCH_CD then return end
    tP=tick(); punchStart=tick()
    task.delay(0.16,function()
        local aPos=rp["RightArm"] and rp["RightArm"].Position or gPos
        for _,pl in Players:GetPlayers() do
            if pl~=LP and pl.Character then
                local h=pl.Character:FindFirstChild("HumanoidRootPart")
                if h and (h.Position-aPos).Magnitude<=PUNCH_R then killHead(pl) end
            end
        end
        if chaosMode then voidPartsInRange(aPos,PUNCH_R*1.5)
        elseif destructMode then
            for _,obj in workspace:GetDescendants() do
                if obj:IsA("BasePart") and obj.Anchored and not obj:IsDescendantOf(char) then
                    if rigModel and obj:IsDescendantOf(rigModel) then continue end
                    if (obj.Position-aPos).Magnitude<=PUNCH_R*1.5 then f.SetLocked(obj,false); f.Anchor(false,obj) end
                end
            end
        end
    end)
end

local function doSlash()
    if not swordEquipped then return end
    if tick()-tSl<SLASH_CD then return end
    tSl=tick(); slashStart=tick()
    fireSlashWave()
    task.delay(SLASH_DUR*0.55,function()
        local sPos=swordPart and swordPart.Position or gPos
        for _,pl in Players:GetPlayers() do
            if pl~=LP and pl.Character then
                local h=pl.Character:FindFirstChild("HumanoidRootPart")
                if h and (h.Position-sPos).Magnitude<=SLASH_R then
                    killHead(pl)
                    task.spawn(function()
                        local torso=pl.Character and (pl.Character:FindFirstChild("Torso") or pl.Character:FindFirstChild("UpperTorso"))
                        if torso then
                            f.SetLocked(torso,false); f.Anchor(false,torso)
                            local dir=(torso.Position-sPos).Unit
                            f.Move(torso,CFrame.new(torso.Position+dir*40+Vector3.new(0,20,0)))
                        end
                    end)
                end
            end
        end
        if chaosMode then voidPartsInRange(swordPart and swordPart.Position or gPos,SLASH_R*1.4)
        elseif destructMode then
            local sPos2=swordPart and swordPart.Position or gPos
            for _,obj in workspace:GetDescendants() do
                if obj:IsA("BasePart") and obj.Anchored and not obj:IsDescendantOf(char) then
                    if rigModel and obj:IsDescendantOf(rigModel) then continue end
                    if (obj.Position-sPos2).Magnitude<=SLASH_R*1.2 then f.SetLocked(obj,false); f.Anchor(false,obj) end
                end
            end
        end
    end)
end

local function doStomp()
    if tick()-tS<STOMP_CD then return end
    tS=tick(); stompStart=tick()
    task.delay(0.18,function()
        for _,pl in Players:GetPlayers() do
            if pl~=LP and pl.Character then
                local h=pl.Character:FindFirstChild("HumanoidRootPart")
                if h and (h.Position-gPos).Magnitude<=STOMP_R then killHead(pl) end
            end
        end
        if chaosMode then voidPartsInRange(gPos,STOMP_R*1.2) end
    end)
end

-- ════════════════════════════════════════════════════════
--  NEW ATTACKS: GRAB (T) and CAGE (Y)
-- ════════════════════════════════════════════════════════

-- ── GRAB ─────────────────────────────────────────────
-- Points at whoever your mouse is over (any distance).
-- Grabs their HRP and snaps them up in front of the rig,
-- plays a short hold animation, then kills them.
local grabStart=-99
local GRAB_DUR=0.8   -- hold time before kill
local isGrabbing=false
local grabbedPl=nil

local function doGrab()
    if tick()-tGrab<GRAB_CD then return end
    if isGrabbing then return end
    local target=getMouseTargetPlayer()
    if not target or not target.Character then return end
    local tHRP=target.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then return end

    tGrab=tick(); isGrabbing=true; grabbedPl=target
    grabStart=tick()

    -- hold position: in front of rig at chest height
    local holdOffset=CFrame.new(0,S*0.5,-S*2)

    -- Grab loop: keep snapping their HRP to the hold point while grabbing
    task.spawn(function()
        -- unlock their HRP so we can move it
        f.SetLocked(tHRP,false)
        f.Anchor(true,tHRP)

        local elapsed=0
        while isGrabbing and elapsed<GRAB_DUR do
            local holdCF=gCF()*holdOffset
            f3x("SyncMove",{{Part=tHRP,CFrame=holdCF}})
            task.wait(0.05)
            elapsed+=0.05
        end

        -- kill on release
        if grabbedPl and grabbedPl.Character then
            local head=grabbedPl.Character:FindFirstChild("Head")
            if head then f.SetLocked(head,false); f.Kill(head) end
        end

        -- release HRP
        if tHRP and tHRP.Parent then
            f.Anchor(false,tHRP)
        end

        isGrabbing=false; grabbedPl=nil
    end)
end

-- ── CAGE ─────────────────────────────────────────────
-- Points at whoever your mouse is over (any distance).
-- 4 big white beams slam down around them simultaneously,
-- then 4 walls + floor close in to jail them.
-- Jailed player is frozen inside permanently.
local function doCage()
    if tick()-tCage<CAGE_CD then return end
    local target=getMouseTargetPlayer()
    if not target or not target.Character then return end
    local tHRP=target.Character:FindFirstChild("HumanoidRootPart")
    if not tHRP then return end

    tCage=tick()
    local center=tHRP.Position

    task.spawn(function()
        -- Phase 1: 4 beams slam DOWN from above simultaneously
        local BEAM_H    = 60
        local BEAM_SIZE = Vector3.new(S*0.6, BEAM_H, S*0.6)
        local BEAM_R    = S*2.5
        local BEAM_COL  = Color3.fromRGB(240,240,255)
        local beams={}

        local function spawnBeam(offset)
            local arrived
            local conn=workspace.ChildAdded:Connect(function(c)
                if c:IsA("BasePart") and not arrived then arrived=c end
            end)
            local startCF=CFrame.new(center+offset+Vector3.new(0,BEAM_H*0.5+30,0))
            f.CreatePart(startCF)
            local deadline=tick()+4
            repeat task.wait(0.02) until arrived or tick()>deadline
            conn:Disconnect()
            if not arrived then return nil end
            f.SetLocked(arrived,false)
            f3x("SyncResize",{{Part=arrived,CFrame=startCF,Size=BEAM_SIZE}})
            f3x("SyncCollision",{{Part=arrived,CanCollide=false}})
            f3x("SyncColor",{{Part=arrived,Color=BEAM_COL,UnionColoring=false}})
            f3x("SyncMaterial",{{Part=arrived,Transparency=0.15}})
            f3x("SyncAnchor",{{Part=arrived,Anchored=true}})
            f.SetLocked(arrived,true)
            return arrived
        end

        -- spawn all 4 beams at once
        local beamOffsets={
            Vector3.new( BEAM_R,0, BEAM_R),
            Vector3.new(-BEAM_R,0, BEAM_R),
            Vector3.new( BEAM_R,0,-BEAM_R),
            Vector3.new(-BEAM_R,0,-BEAM_R),
        }
        local threads={}
        for _,off in beamOffsets do
            table.insert(threads, task.spawn(function()
                local b=spawnBeam(off)
                if b then table.insert(beams,b) end
            end))
        end
        -- wait for all 4
        task.wait(0.4)

        -- Slam beams down to ground level
        local groundY=(getGroundY() or center.Y)
        local slamBatch={}
        for i,b in beams do
            local off=beamOffsets[i] or Vector3.new(0,0,0)
            local finalCF=CFrame.new(center+off+Vector3.new(0,BEAM_H*0.5,0))
            table.insert(slamBatch,{Part=b,CFrame=finalCF})
        end
        if #slamBatch>0 then f3x("SyncMove",slamBatch) end
        task.wait(0.25)

        -- Freeze target in place
        f.SetLocked(tHRP,false)
        f.Anchor(true,tHRP)
        f3x("SyncMove",{{Part=tHRP,CFrame=CFrame.new(center)}})

        -- Phase 2: build the jail cage around them
        local CAGE_SIZE = S*3.5   -- inner half-width
        local WALL_T    = S*0.4   -- wall thickness
        local CAGE_H    = S*5
        local jailParts={}
        local jailCol=Color3.fromRGB(60,60,80)

        local function addJailPart(cf,size)
            local arrived
            local conn=workspace.ChildAdded:Connect(function(c)
                if c:IsA("BasePart") and not arrived then arrived=c end
            end)
            f.CreatePart(cf); local deadline=tick()+4
            repeat task.wait(0.02) until arrived or tick()>deadline; conn:Disconnect()
            if not arrived then return end
            f.SetLocked(arrived,false)
            f3x("SyncResize",{{Part=arrived,CFrame=cf,Size=size}})
            f3x("SyncCollision",{{Part=arrived,CanCollide=true}})   -- jail has collision!
            f3x("SyncColor",{{Part=arrived,Color=jailCol,UnionColoring=false}})
            f3x("SyncMaterial",{{Part=arrived,Transparency=0.5}})
            f3x("SyncAnchor",{{Part=arrived,Anchored=true}})
            f.SetLocked(arrived,true)
            table.insert(jailParts,arrived)
        end

        local cy=center.Y+CAGE_H*0.5
        -- 4 walls
        local wallDefs={
            -- {position offset, size}
            {Vector3.new(0,0, CAGE_SIZE+WALL_T*0.5), Vector3.new(CAGE_SIZE*2+WALL_T*2, CAGE_H, WALL_T)},
            {Vector3.new(0,0,-(CAGE_SIZE+WALL_T*0.5)),Vector3.new(CAGE_SIZE*2+WALL_T*2, CAGE_H, WALL_T)},
            {Vector3.new( CAGE_SIZE+WALL_T*0.5,0,0), Vector3.new(WALL_T, CAGE_H, CAGE_SIZE*2)},
            {Vector3.new(-(CAGE_SIZE+WALL_T*0.5),0,0),Vector3.new(WALL_T, CAGE_H, CAGE_SIZE*2)},
        }
        -- floor
        local floorDef={Vector3.new(0,-CAGE_H*0.5+WALL_T*0.5,0),Vector3.new(CAGE_SIZE*2+WALL_T*2,WALL_T,CAGE_SIZE*2+WALL_T*2)}
        -- ceiling
        local ceilDef={Vector3.new(0,CAGE_H*0.5-WALL_T*0.5,0),Vector3.new(CAGE_SIZE*2+WALL_T*2,WALL_T,CAGE_SIZE*2+WALL_T*2)}

        for _,wd in wallDefs do
            local off,sz=wd[1],wd[2]
            task.spawn(function()
                addJailPart(CFrame.new(center+off+Vector3.new(0,CAGE_H*0.5,0)),sz)
            end)
        end
        task.spawn(function()
            addJailPart(CFrame.new(center+floorDef[1]+Vector3.new(0,CAGE_H*0.5,0)),floorDef[2])
        end)
        task.spawn(function()
            addJailPart(CFrame.new(center+ceilDef[1]+Vector3.new(0,CAGE_H*0.5,0)),ceilDef[2])
        end)
        task.wait(0.3)

        -- Remove beams now that cage is up
        for _,b in beams do
            if b and b.Parent then pcall(function() f.SetLocked(b,false); f.Kill(b) end) end
        end

        print("[REANIMATE] CAGE deployed on "..target.Name)
    end)
end

-- ════════════════════════════════════════════════════════
--  UI
-- ════════════════════════════════════════════════════════
-- ── ZAP (X) ──────────────────────────────────────────
local ZAP_CD = 0.4
local tZap   = 0

local function doZap()
    if tick()-tZap < ZAP_CD then return end
    tZap = tick()

    local hitPart = getMouseTargetPart()
    if not hitPart or not hitPart:IsA("BasePart") then return end
    if rigModel and hitPart:IsDescendantOf(rigModel) then return end
    if hitPart:IsDescendantOf(char) then return end

    local fromPos = gPos + Vector3.new(0, S*1.5, 0)
    local toPos   = hitPart.Position
    local dist    = (toPos - fromPos).Magnitude
    local mid     = (fromPos + toPos) * 0.5

    -- lookAt: part -Z points toward target
    local beamCF = CFrame.lookAt(mid, toPos)

    -- Brick mesh scale is a direct stud multiplier on the 1x1x1 part
    -- X/Y = beam thickness, Z = full distance
    local W = S * 0.3
    local meshScale = Vector3.new(W, W, dist)

    task.spawn(function()
        local beam
        local conn = workspace.ChildAdded:Connect(function(c)
            if c:IsA("BasePart") and not beam then beam = c end
        end)
        f.CreatePart(beamCF)
        local deadline = tick()+4
        repeat task.wait(0.02) until beam or tick()>deadline
        conn:Disconnect()
        if not beam then return end

        f.SetLocked(beam, false)
        -- keep part size at 1x1x1 — only move + style it
        f3x("SyncMove",     {{Part=beam, CFrame=beamCF}})
        f3x("SyncCollision",{{Part=beam, CanCollide=false}})
        f3x("SyncColor",    {{Part=beam, Color=Color3.fromRGB(255,220,50), UnionColoring=false}})
        f3x("SyncMaterial", {{Part=beam, Transparency=0.1, Material=Enum.Material.Neon}})
        f3x("SyncAnchor",   {{Part=beam, Anchored=true}})
        task.wait(0.05)

        -- create mesh, set type, then scale in separate calls
        f3x("CreateMeshes", {{Part=beam}})
        task.wait(0.1)
        f3x("SyncMesh", {{Part=beam, MeshType=Enum.MeshType.Brick}})
        task.wait(0.05)
        f3x("SyncMesh", {{Part=beam, Scale=meshScale}})
        task.wait(0.04)

        f.SetLocked(beam, true)

        -- delete target
        f.SetLocked(hitPart, false)
        f.Kill(hitPart)

        -- fade out — unlock before each change so F3X accepts it
        task.wait(0.12)
        f.SetLocked(beam, false)
        task.wait(0.02)
        f3x("SyncMaterial",{{Part=beam, Transparency=0.55, Material=Enum.Material.SmoothPlastic}})
        task.wait(0.08)
        f3x("SyncMaterial",{{Part=beam, Transparency=0.9,  Material=Enum.Material.SmoothPlastic}})
        task.wait(0.06)
        f.Kill(beam)
    end)

    print("[REANIMATE] ZAP → "..hitPart.Name)
end

local TweenSvc=game:GetService("TweenService")

do
    local existing=PG:FindFirstChild("ReanimHUD")
    if existing then existing:Destroy() end
    local existingRig=workspace:FindFirstChild("Rig")
    if existingRig then pcall(function() existingRig:Destroy() end) end
end

local sg=Instance.new("ScreenGui",PG)
sg.Name="ReanimHUD"; sg.ResetOnSpawn=false

local BG=Color3.fromRGB(7,7,11); local CARD=Color3.fromRGB(14,14,22)
local RED=Color3.fromRGB(200,35,35); local DIM=Color3.fromRGB(100,100,110)
local TXT=Color3.fromRGB(200,200,200); local ACC=Color3.fromRGB(80,180,255)
local GRN=Color3.fromRGB(80,200,80); local YEL=Color3.fromRGB(220,180,40)

local function corner(p,r) Instance.new("UICorner",p).CornerRadius=UDim.new(0,r or 6) end
local function stroke(p,c,t) local s=Instance.new("UIStroke",p); s.Color=c; s.Thickness=t or 1 end
local function lbl(par,t,x,y,w,h,sz,col,font,xa)
    local l=Instance.new("TextLabel",par)
    l.Position=UDim2.new(0,x,0,y); l.Size=UDim2.new(0,w,0,h)
    l.BackgroundTransparency=1; l.Text=t
    l.Font=font or Enum.Font.Code; l.TextSize=sz or 10; l.TextColor3=col or TXT
    l.TextXAlignment=xa or Enum.TextXAlignment.Left; l.TextYAlignment=Enum.TextYAlignment.Center
    return l
end

local draggingPanel=false
local ANCHOR_POS=UDim2.new(0.5,-(244+4),0,8)
local container=Instance.new("Frame",sg)
container.Name="Container"; container.Size=UDim2.new(0,244+4+224,0,100)
container.Position=ANCHOR_POS; container.BackgroundTransparency=1; container.BorderSizePixel=0

local HUD_W=244
local mainFr=Instance.new("Frame",container)
mainFr.Name="Main"; mainFr.Size=UDim2.new(0,HUD_W,0,104)
mainFr.Position=UDim2.new(0,0,0,0); mainFr.BackgroundColor3=BG; mainFr.BorderSizePixel=0
corner(mainFr,8); stroke(mainFr,RED,1.4)

local dragHandle=Instance.new("TextButton",mainFr)
dragHandle.Size=UDim2.new(1,0,0,20); dragHandle.Position=UDim2.new(0,0,0,0)
dragHandle.BackgroundTransparency=1; dragHandle.Text=""; dragHandle.AutoButtonColor=false; dragHandle.ZIndex=10

lbl(mainFr,"REANIMATE  •  ACTIVE",8,4,HUD_W-16,14,12,RED,Enum.Font.GothamBold)
lbl(mainFr,"WASD=Move  R=Punch  Q=Slash  F=Stomp",8,20,HUD_W-16,12,9,DIM)
lbl(mainFr,"G=Sword  T=Grab  Y=Cage  E=Destruct  V=HUD",8,32,HUD_W-16,12,9,DIM)
local swordLbl=lbl(mainFr,"⬤ SWORD: OFF",8,48,HUD_W-16,14,10,DIM)
local destructLbl=lbl(mainFr,"⬤ DESTRUCT: OFF",8,62,HUD_W-16,14,10,DIM)
local chaosLbl=lbl(mainFr,"💥 CHAOS MODE",8,76,HUD_W-16,14,11,Color3.fromRGB(255,60,60))
chaosLbl.Visible=false
local statusLbl=lbl(mainFr,"⏳ Building...",8,91,HUD_W-16,14,10,YEL)
mainFr.Size=UDim2.new(0,HUD_W,0,110)

local dragStart,posStart
dragHandle.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then
        draggingPanel=true; dragStart=inp.Position; posStart=container.Position
    end
end)
UIS.InputChanged:Connect(function(inp)
    if draggingPanel and inp.UserInputType==Enum.UserInputType.MouseMovement then
        local delta=inp.Position-dragStart
        container.Position=UDim2.new(posStart.X.Scale,posStart.X.Offset+delta.X,posStart.Y.Scale,posStart.Y.Offset+delta.Y)
    end
end)
UIS.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then draggingPanel=false end
end)

local SET_W=224; local SET_COLL=24; local SET_EXP=420; local settingsOpen=false
local setFr=Instance.new("Frame",container)
setFr.Name="Settings"; setFr.Size=UDim2.new(0,SET_W,0,SET_COLL)
setFr.Position=UDim2.new(0,HUD_W+4,0,0); setFr.BackgroundColor3=BG; setFr.BorderSizePixel=0
setFr.ClipsDescendants=true; corner(setFr,8); stroke(setFr,ACC,1.2)

local tabBar=Instance.new("Frame",setFr)
tabBar.Size=UDim2.new(1,0,0,24); tabBar.BackgroundColor3=CARD; tabBar.BorderSizePixel=0; corner(tabBar,6)
local tabSquare=Instance.new("Frame",tabBar)
tabSquare.Size=UDim2.new(1,0,0.5,0); tabSquare.Position=UDim2.new(0,0,0.5,0)
tabSquare.BackgroundColor3=CARD; tabSquare.BorderSizePixel=0
local tabLbl2=Instance.new("TextLabel",tabBar)
tabLbl2.Size=UDim2.new(1,-28,1,0); tabLbl2.Position=UDim2.new(0,10,0,0)
tabLbl2.BackgroundTransparency=1; tabLbl2.Font=Enum.Font.GothamBold
tabLbl2.TextSize=10; tabLbl2.TextColor3=ACC; tabLbl2.TextXAlignment=Enum.TextXAlignment.Left; tabLbl2.Text="⚙  SETTINGS"
local arrowLbl=Instance.new("TextLabel",tabBar)
arrowLbl.Size=UDim2.new(0,22,1,0); arrowLbl.Position=UDim2.new(1,-24,0,0)
arrowLbl.BackgroundTransparency=1; arrowLbl.Font=Enum.Font.GothamBold
arrowLbl.TextSize=11; arrowLbl.TextColor3=ACC; arrowLbl.Text="▼"

local content=Instance.new("ScrollingFrame",setFr)
content.Size=UDim2.new(1,-2,1,-26); content.Position=UDim2.new(0,1,0,25)
content.BackgroundTransparency=1; content.BorderSizePixel=0
content.ScrollBarThickness=3; content.ScrollBarImageColor3=ACC
content.CanvasSize=UDim2.new(0,0,0,0); content.AutomaticCanvasSize=Enum.AutomaticSize.Y
local ll=Instance.new("UIListLayout",content)
ll.SortOrder=Enum.SortOrder.LayoutOrder; ll.Padding=UDim.new(0,3)
local pp=Instance.new("UIPadding",content)
pp.PaddingTop=UDim.new(0,4); pp.PaddingLeft=UDim.new(0,4); pp.PaddingRight=UDim.new(0,4)

local function toggleSettings()
    settingsOpen=not settingsOpen; arrowLbl.Text=settingsOpen and "▲" or "▼"
    TweenSvc:Create(setFr,TweenInfo.new(0.2,Enum.EasingStyle.Quad),{Size=UDim2.new(0,SET_W,0,settingsOpen and SET_EXP or SET_COLL)}):Play()
    TweenSvc:Create(container,TweenInfo.new(0.2,Enum.EasingStyle.Quad),{Size=UDim2.new(0,HUD_W+4+SET_W,0,settingsOpen and SET_EXP or 104)}):Play()
end
tabBar.InputBegan:Connect(function(i)
    if i.UserInputType==Enum.UserInputType.MouseButton1 then toggleSettings() end
end)

local ord=0
local function nxt() ord+=1; return ord end
local function makeSection(title)
    local sec=Instance.new("Frame",content); sec.Size=UDim2.new(1,0,0,16)
    sec.BackgroundTransparency=1; sec.LayoutOrder=nxt()
    local l=Instance.new("TextLabel",sec); l.Size=UDim2.new(1,-4,1,0); l.Position=UDim2.new(0,4,0,0)
    l.BackgroundTransparency=1; l.Font=Enum.Font.GothamBold; l.TextSize=8
    l.TextColor3=Color3.fromRGB(100,110,140); l.TextXAlignment=Enum.TextXAlignment.Left
    l.Text="▸ "..string.upper(title)
end
local function makeSep()
    local sep=Instance.new("Frame",content); sep.Size=UDim2.new(1,0,0,1)
    sep.BackgroundColor3=Color3.fromRGB(25,25,40); sep.BorderSizePixel=0; sep.LayoutOrder=nxt()
end
local function makeSlider(labelTxt,minV,maxV,initV,fmt,onChange)
    local val=initV; local fr2=Instance.new("Frame",content)
    fr2.Size=UDim2.new(1,0,0,34); fr2.BackgroundColor3=CARD; fr2.BorderSizePixel=0; fr2.LayoutOrder=nxt()
    corner(fr2,5); stroke(fr2,Color3.fromRGB(28,28,45),1)
    local lbl2=Instance.new("TextLabel",fr2); lbl2.Size=UDim2.new(0.62,0,0,15); lbl2.Position=UDim2.new(0,8,0,1)
    lbl2.BackgroundTransparency=1; lbl2.Font=Enum.Font.Gotham; lbl2.TextSize=9; lbl2.TextColor3=TXT
    lbl2.TextXAlignment=Enum.TextXAlignment.Left; lbl2.Text=labelTxt
    local fmt2=fmt or "%d"
    local valLbl=Instance.new("TextLabel",fr2); valLbl.Size=UDim2.new(0.38,-8,0,15); valLbl.Position=UDim2.new(0.62,0,0,1)
    valLbl.BackgroundTransparency=1; valLbl.Font=Enum.Font.GothamBold; valLbl.TextSize=9; valLbl.TextColor3=ACC
    valLbl.TextXAlignment=Enum.TextXAlignment.Right; valLbl.Text=string.format(fmt2,initV)
    local track=Instance.new("Frame",fr2); track.Size=UDim2.new(1,-16,0,4); track.Position=UDim2.new(0,8,0,22)
    track.BackgroundColor3=Color3.fromRGB(28,28,45); track.BorderSizePixel=0; corner(track,2)
    local fill=Instance.new("Frame",track); fill.Size=UDim2.new((initV-minV)/(maxV-minV),0,1,0)
    fill.BackgroundColor3=ACC; fill.BorderSizePixel=0; corner(fill,2)
    local knob=Instance.new("Frame",track); knob.Size=UDim2.new(0,10,0,10); knob.AnchorPoint=Vector2.new(0.5,0.5)
    knob.Position=UDim2.new((initV-minV)/(maxV-minV),0,0.5,0); knob.BackgroundColor3=Color3.fromRGB(240,240,240)
    knob.BorderSizePixel=0; corner(knob,5)
    local sdrag=false
    local function upd(x)
        local pct=math.clamp((x-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
        val=minV+(maxV-minV)*pct; if not fmt or fmt=="%d" then val=math.floor(val) end
        valLbl.Text=string.format(fmt2,val); fill.Size=UDim2.new(pct,0,1,0); knob.Position=UDim2.new(pct,0,0.5,0)
        if onChange then onChange(val) end
    end
    track.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sdrag=true; upd(i.Position.X) end end)
    UIS.InputChanged:Connect(function(i) if sdrag and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i.Position.X) end end)
    UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sdrag=false end end)
end
local function makeToggle(labelTxt,initState,onChange)
    local state=initState; local fr2=Instance.new("Frame",content)
    fr2.Size=UDim2.new(1,0,0,26); fr2.BackgroundColor3=CARD; fr2.BorderSizePixel=0; fr2.LayoutOrder=nxt()
    corner(fr2,5); stroke(fr2,Color3.fromRGB(28,28,45),1)
    local lbl2=Instance.new("TextLabel",fr2); lbl2.Size=UDim2.new(1,-50,1,0); lbl2.Position=UDim2.new(0,10,0,0)
    lbl2.BackgroundTransparency=1; lbl2.Font=Enum.Font.Gotham; lbl2.TextSize=10; lbl2.TextColor3=TXT
    lbl2.TextXAlignment=Enum.TextXAlignment.Left; lbl2.Text=labelTxt
    local tr=Instance.new("Frame",fr2); tr.Size=UDim2.new(0,32,0,15); tr.Position=UDim2.new(1,-40,0.5,-7.5)
    tr.BackgroundColor3=state and GRN or Color3.fromRGB(38,38,58); tr.BorderSizePixel=0; corner(tr,8)
    local kn=Instance.new("Frame",tr); kn.Size=UDim2.new(0,11,0,11); kn.AnchorPoint=Vector2.new(0,0.5)
    kn.Position=UDim2.new(0,state and 18 or 2,0.5,0); kn.BackgroundColor3=Color3.fromRGB(255,255,255)
    kn.BorderSizePixel=0; corner(kn,6)
    local function tog()
        state=not state
        TweenSvc:Create(tr,TweenInfo.new(0.12),{BackgroundColor3=state and GRN or Color3.fromRGB(38,38,58)}):Play()
        TweenSvc:Create(kn,TweenInfo.new(0.12),{Position=UDim2.new(0,state and 18 or 2,0.5,0)}):Play()
        if onChange then onChange(state) end
    end
    fr2.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then tog() end end)
    return fr2,function() return state end,function(v) if v~=state then tog() end end
end
local function makeKeybind(labelTxt,currentKey,onChanged)
    local key=currentKey; local waiting=false
    local fr2=Instance.new("Frame",content); fr2.Size=UDim2.new(1,0,0,26); fr2.BackgroundColor3=CARD
    fr2.BorderSizePixel=0; fr2.LayoutOrder=nxt(); corner(fr2,5); stroke(fr2,Color3.fromRGB(28,28,45),1)
    local lbl2=Instance.new("TextLabel",fr2); lbl2.Size=UDim2.new(1,-80,1,0); lbl2.Position=UDim2.new(0,10,0,0)
    lbl2.BackgroundTransparency=1; lbl2.Font=Enum.Font.Gotham; lbl2.TextSize=10; lbl2.TextColor3=TXT
    lbl2.TextXAlignment=Enum.TextXAlignment.Left; lbl2.Text=labelTxt
    local btn=Instance.new("TextButton",fr2); btn.Size=UDim2.new(0,68,0,18); btn.Position=UDim2.new(1,-74,0.5,-9)
    btn.BackgroundColor3=Color3.fromRGB(25,25,42); btn.BorderSizePixel=0; btn.Font=Enum.Font.GothamBold
    btn.TextSize=9; btn.TextColor3=ACC; btn.AutoButtonColor=false; btn.Text=tostring(key.Name)
    corner(btn,4); stroke(btn,ACC,1)
    btn.MouseButton1Click:Connect(function()
        if waiting then return end; waiting=true
        btn.Text="..."; btn.TextColor3=YEL
        TweenSvc:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(35,30,15)}):Play()
        local conn; conn=UIS.InputBegan:Connect(function(inp,gp)
            if gp then return end
            if inp.UserInputType==Enum.UserInputType.Keyboard then
                key=inp.KeyCode; btn.Text=tostring(key.Name); btn.TextColor3=ACC
                TweenSvc:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(25,25,42)}):Play()
                waiting=false; conn:Disconnect(); if onChanged then onChanged(key) end
            end
        end)
    end)
    return fr2,function() return key end
end

local KB={Punch=Enum.KeyCode.R,Slash=Enum.KeyCode.Q,Stomp=Enum.KeyCode.F,
          Sword=Enum.KeyCode.G,Destruct=Enum.KeyCode.E,HUD=Enum.KeyCode.V,
          Grab=Enum.KeyCode.T,Cage=Enum.KeyCode.Y,Zap=Enum.KeyCode.X,
          LayDown=Enum.KeyCode.Z}

local JUMP_HEIGHT=S*5

makeSection("Movement")
makeSlider("Move Speed",5,100,SPEED,"%d",function(v) SPEED=v end)
makeSlider("Update Rate (hz)",5,60,UPDATE_HZ,"%d",function(v) UPDATE_HZ=v end)
makeSlider("Jump Height",1,200,math.floor(JUMP_HEIGHT),"%d",function(v) JUMP_HEIGHT=v end)
makeSep()
makeSection("Combat")
makeSlider("Punch Reach",5,100,PUNCH_R,"%d",function(v) PUNCH_R=v end)
makeSlider("Stomp Reach",5,100,STOMP_R,"%d",function(v) STOMP_R=v end)
makeSlider("Slash Reach",5,100,SLASH_R,"%d",function(v) SLASH_R=v end)
makeSlider("Punch Cooldown",1,50,math.floor(PUNCH_CD*10),"%d×0.1s",function(v) PUNCH_CD=v/10 end)
makeSlider("Stomp Cooldown",1,50,math.floor(STOMP_CD*10),"%d×0.1s",function(v) STOMP_CD=v/10 end)
makeSlider("Slash Cooldown",1,50,math.floor(SLASH_CD*10),"%d×0.1s",function(v) SLASH_CD=v/10 end)
makeSlider("Grab Cooldown",1,30,math.floor(GRAB_CD*10),"%d×0.1s",function(v) GRAB_CD=v/10 end)
makeSlider("Cage Cooldown",1,50,math.floor(CAGE_CD*10),"%d×0.1s",function(v) CAGE_CD=v/10 end)
makeSlider("Zap Cooldown",1,20,math.floor(ZAP_CD*10),"%d×0.1s",function(v) ZAP_CD=v/10 end)
makeSep()
makeSection("Modes")
local _,_,setDestructSync=makeToggle("Destruct Mode",destructMode,function(v) destructMode=v; if not v then chaosMode=false end end)
local _,_,setSwordSync=makeToggle("Sword Equipped",swordEquipped,function(v) swordEquipped=v; if v then task.spawn(spawnSword) else removeSword() end end)
makeToggle("Auto-regen Limbs",true,function(v) _G.__reanimRegenEnabled=v end)
_G.__reanimRegenEnabled=true
makeSep()
makeSection("Animation")
makeSlider("Idle Breathe Amt",0,30,12,"%d%%",function(v) _G.__reanimBreathe=v/100 end)
_G.__reanimBreathe=0.12
makeSlider("Walk Cycle Speed",2,16,6,"%d",function(v) _G.__reanimWalkFreq=v end)
_G.__reanimWalkFreq=6
makeSlider("Head Look Amt",0,30,12,"%d°",function(v) _G.__reanimHeadLook=math.rad(v) end)
_G.__reanimHeadLook=math.rad(12)
makeSep()
makeSection("Keybinds")
makeKeybind("Punch / Slash",KB.Punch,function(k) KB.Punch=k end)
makeKeybind("Slash (sword)",KB.Slash,function(k) KB.Slash=k end)
makeKeybind("Stomp",KB.Stomp,function(k) KB.Stomp=k end)
makeKeybind("Sword Toggle",KB.Sword,function(k) KB.Sword=k end)
makeKeybind("Destruct Mode",KB.Destruct,function(k) KB.Destruct=k end)
makeKeybind("Toggle HUD",KB.HUD,function(k) KB.HUD=k end)
makeKeybind("Grab",KB.Grab,function(k) KB.Grab=k end)
makeKeybind("Cage",KB.Cage,function(k) KB.Cage=k end)
makeKeybind("Zap (X)",KB.Zap,function(k) KB.Zap=k end)
makeKeybind("Lay Down",KB.LayDown,function(k) KB.LayDown=k end)
makeSep()
makeSection("Rig")
makeToggle("Rig Collision",rigCollision,function(v)
    rigCollision=v; if not rigModel or not rigModel.Parent then return end
    local batch={}
    for _,nm in ORDER do local p=rp[nm]; if p and p.Parent then table.insert(batch,{Part=p,CanCollide=v}) end end
    if #batch>0 then f3x("SyncCollision",batch) end
end)
makeToggle("Show Tool",showToolEnabled,function(v) showToolEnabled=v; if not v then removeToolPart() end end)
makeToggle("Stomp On Walk",stompOnWalk,function(v) stompOnWalk=v; lastStepSign=0 end)
makeSep()
makeSection("Appearance")
local function applyColor(nm,col)
    COL[nm]=col; local p=rp[nm]
    if p and p.Parent then f3x("SyncColor",{{Part=p,Color=col,UnionColoring=false}}) end
end
local function makeColorPicker(labelTxt,initCol,onChanged)
    local col=initCol; local expanded=false
    local wrap=Instance.new("Frame",content); wrap.Size=UDim2.new(1,0,0,28)
    wrap.BackgroundTransparency=1; wrap.BorderSizePixel=0; wrap.LayoutOrder=nxt(); wrap.ClipsDescendants=false
    local header=Instance.new("Frame",wrap); header.Size=UDim2.new(1,0,0,28); header.BackgroundColor3=CARD
    header.BorderSizePixel=0; corner(header,5); stroke(header,Color3.fromRGB(28,28,45),1)
    local nLbl=Instance.new("TextLabel",header); nLbl.Size=UDim2.new(1,-52,1,0); nLbl.Position=UDim2.new(0,10,0,0)
    nLbl.BackgroundTransparency=1; nLbl.Font=Enum.Font.Gotham; nLbl.TextSize=10; nLbl.TextColor3=TXT
    nLbl.TextXAlignment=Enum.TextXAlignment.Left; nLbl.Text=labelTxt
    local swatch=Instance.new("Frame",header); swatch.Size=UDim2.new(0,18,0,18); swatch.Position=UDim2.new(1,-42,0.5,-9)
    swatch.BackgroundColor3=col; swatch.BorderSizePixel=0; corner(swatch,4); stroke(swatch,Color3.fromRGB(80,80,100),1)
    local btn=Instance.new("TextButton",header); btn.Size=UDim2.new(0,18,0,18); btn.Position=UDim2.new(1,-20,0.5,-9)
    btn.BackgroundColor3=Color3.fromRGB(28,28,45); btn.BorderSizePixel=0; btn.Font=Enum.Font.GothamBold
    btn.TextSize=10; btn.TextColor3=ACC; btn.Text="▼"; btn.AutoButtonColor=false; corner(btn,4)
    local panel=Instance.new("Frame",wrap); panel.Size=UDim2.new(1,0,0,90); panel.Position=UDim2.new(0,0,0,30)
    panel.BackgroundColor3=Color3.fromRGB(10,10,18); panel.BorderSizePixel=0; panel.Visible=false; corner(panel,5); stroke(panel,Color3.fromRGB(28,28,45),1)
    local rVal=col.R*255; local gVal=col.G*255; local bVal=col.B*255
    local function rebuild()
        local c=Color3.fromRGB(math.floor(rVal),math.floor(gVal),math.floor(bVal))
        col=c; swatch.BackgroundColor3=c; if onChanged then onChanged(c) end
    end
    local function makeChannel(ch,yPos,initV,setter)
        local chCol=ch=="R" and Color3.fromRGB(200,60,60) or ch=="G" and Color3.fromRGB(60,180,60) or Color3.fromRGB(60,120,220)
        local lc=Instance.new("TextLabel",panel); lc.Size=UDim2.new(0,14,0,12); lc.Position=UDim2.new(0,6,0,yPos)
        lc.BackgroundTransparency=1; lc.Font=Enum.Font.GothamBold; lc.TextSize=9; lc.TextColor3=chCol; lc.Text=ch
        local tr=Instance.new("Frame",panel); tr.Size=UDim2.new(1,-52,0,4); tr.Position=UDim2.new(0,22,0,yPos+4)
        tr.BackgroundColor3=Color3.fromRGB(28,28,45); tr.BorderSizePixel=0; corner(tr,2)
        local fill=Instance.new("Frame",tr); fill.Size=UDim2.new(initV/255,0,1,0); fill.BackgroundColor3=chCol; fill.BorderSizePixel=0; corner(fill,2)
        local knob2=Instance.new("Frame",tr); knob2.Size=UDim2.new(0,8,0,8); knob2.AnchorPoint=Vector2.new(0.5,0.5)
        knob2.Position=UDim2.new(initV/255,0,0.5,0); knob2.BackgroundColor3=Color3.fromRGB(240,240,240); knob2.BorderSizePixel=0; corner(knob2,4)
        local vLbl=Instance.new("TextLabel",panel); vLbl.Size=UDim2.new(0,24,0,12); vLbl.Position=UDim2.new(1,-28,0,yPos)
        vLbl.BackgroundTransparency=1; vLbl.Font=Enum.Font.GothamBold; vLbl.TextSize=8; vLbl.TextColor3=TXT; vLbl.Text=tostring(math.floor(initV))
        local sd=false
        local function upd(x)
            local pct=math.clamp((x-tr.AbsolutePosition.X)/tr.AbsoluteSize.X,0,1)
            local v=math.floor(pct*255); vLbl.Text=tostring(v); fill.Size=UDim2.new(pct,0,1,0); knob2.Position=UDim2.new(pct,0,0.5,0); setter(v)
        end
        tr.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=true; upd(i.Position.X) end end)
        UIS.InputChanged:Connect(function(i) if sd and i.UserInputType==Enum.UserInputType.MouseMovement then upd(i.Position.X) end end)
        UIS.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then sd=false end end)
    end
    makeChannel("R",8,col.R*255,function(v) rVal=v; rebuild() end)
    makeChannel("G",34,col.G*255,function(v) gVal=v; rebuild() end)
    makeChannel("B",60,col.B*255,function(v) bVal=v; rebuild() end)
    btn.MouseButton1Click:Connect(function()
        expanded=not expanded; btn.Text=expanded and "▲" or "▼"
        panel.Visible=expanded; wrap.Size=UDim2.new(1,0,0,expanded and 122 or 28)
    end)
end
makeColorPicker("Head",COL.Head,function(c) applyColor("Head",c) end)
makeColorPicker("Torso",COL.Torso,function(c) applyColor("Torso",c) end)
makeColorPicker("Left Arm",COL.LeftArm,function(c) applyColor("LeftArm",c) end)
makeColorPicker("Right Arm",COL.RightArm,function(c) applyColor("RightArm",c) end)
makeColorPicker("Left Leg",COL.LeftLeg,function(c) applyColor("LeftLeg",c) end)
makeColorPicker("Right Leg",COL.RightLeg,function(c) applyColor("RightLeg",c) end)
local presetWrap=Instance.new("Frame",content); presetWrap.Size=UDim2.new(1,0,0,26)
presetWrap.BackgroundTransparency=1; presetWrap.BorderSizePixel=0; presetWrap.LayoutOrder=nxt()
local pll=Instance.new("UIListLayout",presetWrap); pll.FillDirection=Enum.FillDirection.Horizontal; pll.Padding=UDim.new(0,3)
for _,preset in {{"Red",Color3.fromRGB(196,40,28)},{"Green",Color3.fromRGB(75,151,75)},{"Blue",Color3.fromRGB(13,105,172)},{"Black",Color3.fromRGB(17,17,17)},{"White",Color3.fromRGB(242,243,243)},{"Gold",Color3.fromRGB(239,184,56)}} do
    local pb=Instance.new("TextButton",presetWrap); pb.Size=UDim2.new(0,34,1,0); pb.BackgroundColor3=preset[2]
    pb.BorderSizePixel=0; pb.Font=Enum.Font.GothamBold; pb.TextSize=7; pb.TextColor3=Color3.fromRGB(255,255,255)
    pb.Text=preset[1]; pb.AutoButtonColor=false; corner(pb,4)
    pb.MouseButton1Click:Connect(function() for _,nm in LIMBS do applyColor(nm,preset[2]) end end)
end

-- Material picker
local rigMaterial = Enum.Material.SmoothPlastic

local function applyMaterial(mat)
    rigMaterial = mat
    graniteMode = (mat == Enum.Material.Granite or mat == Enum.Material.Slate)
    if graniteMode then graniteStepAcc=0; graniteStepT=0; rollGraniteJitter() end
    for _,nm in LIMBS do
        local p = rp[nm]
        if p and p.Parent then
            f3x("SyncMaterial",{{Part=p, Material=mat}})
        end
    end
end

local MATERIALS = {
    {"SmoothPlastic", Enum.Material.SmoothPlastic},
    {"Plastic",       Enum.Material.Plastic},
    {"Metal",         Enum.Material.Metal},
    {"Neon",          Enum.Material.Neon},
    {"Glass",         Enum.Material.Glass},
    {"ForceField",    Enum.Material.ForceField},
    {"Wood",          Enum.Material.Wood},
    {"WoodPlanks",    Enum.Material.WoodPlanks},
    {"Granite",       Enum.Material.Granite},
    {"Marble",        Enum.Material.Marble},
    {"Slate",         Enum.Material.Slate},
    {"Sandstone",     Enum.Material.Sandstone},
    {"Cobblestone",   Enum.Material.Cobblestone},
    {"Brick",         Enum.Material.Brick},
    {"Concrete",      Enum.Material.Concrete},
    {"DiamondPlate",  Enum.Material.DiamondPlate},
    {"Foil",          Enum.Material.Foil},
    {"Ice",           Enum.Material.Ice},
    {"Glacier",       Enum.Material.Glacier},
    {"Snow",          Enum.Material.Snow},
    {"Sand",          Enum.Material.Sand},
    {"Ground",        Enum.Material.Ground},
    {"Mud",           Enum.Material.Mud},
    {"Rock",          Enum.Material.Rock},
    {"Asphalt",       Enum.Material.Asphalt},
    {"Pebble",        Enum.Material.Pebble},
    {"Basalt",        Enum.Material.Basalt},
    {"CrackedLava",   Enum.Material.CrackedLava},
    {"Limestone",     Enum.Material.Limestone},
    {"Pavement",      Enum.Material.Pavement},
    {"Grass",         Enum.Material.Grass},
    {"LeafyGrass",    Enum.Material.LeafyGrass},
    {"Fabric",        Enum.Material.Fabric},
    {"Cardboard",     Enum.Material.Cardboard},
    {"Rubber",        Enum.Material.Rubber},
    {"CorrodedMetal", Enum.Material.CorrodedMetal},
}

local matWrap = Instance.new("Frame", content)
matWrap.Size = UDim2.new(1,0,0,0)
matWrap.AutomaticSize = Enum.AutomaticSize.Y
matWrap.BackgroundTransparency=1; matWrap.BorderSizePixel=0; matWrap.LayoutOrder=nxt()
local mll = Instance.new("UIListLayout", matWrap)
mll.FillDirection=Enum.FillDirection.Horizontal
mll.Padding=UDim.new(0,3)
mll.Wraps=true
Instance.new("UIPadding",matWrap).PaddingBottom=UDim.new(0,2)

for _,mat in MATERIALS do
    local mb = Instance.new("TextButton", matWrap)
    mb.Size=UDim2.new(0,0,0,20); mb.AutomaticSize=Enum.AutomaticSize.X
    mb.BackgroundColor3=CARD; mb.BorderSizePixel=0
    mb.Font=Enum.Font.Gotham; mb.TextSize=8; mb.TextColor3=ACC
    mb.Text=" "..mat[1].." "; mb.AutoButtonColor=false
    corner(mb,4); stroke(mb,Color3.fromRGB(28,28,45),1)
    mb.MouseButton1Click:Connect(function()
        applyMaterial(mat[2])
        for _,ch in matWrap:GetChildren() do
            if ch:IsA("TextButton") then
                stroke(ch,Color3.fromRGB(28,28,45),1)
                ch.TextColor3=ACC
            end
        end
        stroke(mb,ACC,1.5)
        mb.TextColor3=Color3.fromRGB(255,255,255)
    end)
end
UIS.InputBegan:Connect(function(i,gp)
    if gp then return end
    local k=i.KeyCode
    if k==KB.Punch   then if swordEquipped then doSlash() else doPunch() end end
    if k==KB.Slash   then doSlash() end
    if k==KB.Stomp   then doStomp() end
    if k==KB.Sword   then
        if not rigAlive then return end
        swordEquipped=not swordEquipped
        if swordEquipped then task.spawn(spawnSword) else removeSword() end
    end
    if k==KB.Destruct then
        local now=tick()
        if now-lastDestructTap<0.3 then
            chaosMode=not chaosMode; destructMode=chaosMode
        else
            if chaosMode then chaosMode=false end
            destructMode=not destructMode
        end
        lastDestructTap=now
    end
    if k==KB.HUD    then sg.Enabled=not sg.Enabled end
    if k==KB.Grab   then doGrab() end
    if k==KB.Cage   then doCage() end
    if k==KB.Zap    then doZap()  end
    if k==KB.LayDown then
        layingDown = not layingDown
        if layingDown then
            local NUM_POSES = 7
            layPoseIdx   = math.random(1, NUM_POSES)
            local nxt; repeat nxt=math.random(1,NUM_POSES) until nxt~=layPoseIdx
            layPoseNext     = nxt
            layPoseBlend    = 0
            layPoseTimer    = 0
            layPoseHoldTime = math.random(22, 40)
        end
    end
end)

-- ── Main loop ────────────────────────────────────────
local updAcc=0; local regenAcc=0

RunSvc.RenderStepped:Connect(function(dt)
    -- Camera transparency: fade rig parts that are between camera and HRP
    -- so the camera never zooms in or clips into them.
    if rigAlive and rp["HRP"] and rp["HRP"].Parent then
        local obscuring = Cam:GetPartsObscuringTarget(
            {Cam.CFrame.Position, rp["HRP"].Position},
            {char, rigModel}   -- ignore own char + rig as blockers
        )
        -- build a set for O(1) lookup
        local obscSet = {}
        for _,p in obscuring do obscSet[p]=true end
        -- fade obscuring rig parts, restore non-obscuring ones
        for _,nm in ORDER do
            local p = rp[nm]
            if p and p.Parent then
                p.LocalTransparencyModifier = obscSet[p] and 0.6 or 0
            end
        end
    end

    if swordEquipped then swordLbl.Text="⬤ SWORD: ON"; swordLbl.TextColor3=YEL
    else swordLbl.Text="⬤ SWORD: OFF"; swordLbl.TextColor3=DIM end
    if chaosMode then
        destructLbl.Text="⬤ DESTRUCT: ON"; destructLbl.TextColor3=RED
        chaosLbl.Visible=true
        local pulse=math.abs(math.sin(idleT*4))
        chaosLbl.TextColor3=Color3.fromRGB(255,math.floor(40+pulse*60),math.floor(pulse*40))
    elseif destructMode then
        destructLbl.Text="⬤ DESTRUCT: ON"; destructLbl.TextColor3=RED; chaosLbl.Visible=false
    else
        destructLbl.Text="⬤ DESTRUCT: OFF"; destructLbl.TextColor3=DIM; chaosLbl.Visible=false
    end

    if not rigAlive then return end

    local camYaw=math.atan2(-Cam.CFrame.LookVector.X,-Cam.CFrame.LookVector.Z)
    local mv=Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then mv+=Vector3.new(0,0,-1) end
    if UIS:IsKeyDown(Enum.KeyCode.S) then mv+=Vector3.new(0,0, 1) end
    if UIS:IsKeyDown(Enum.KeyCode.A) then mv+=Vector3.new(-1,0,0) end
    if UIS:IsKeyDown(Enum.KeyCode.D) then mv+=Vector3.new( 1,0,0) end
    moving=mv.Magnitude>0 and not layingDown; idleT+=dt
    -- smooth lay-down blend
    local layTarget = layingDown and 1 or 0
    layBlend = layBlend + (layTarget - layBlend) * math.min(dt*3.5, 1)

    local NUM_POSES = 7
    if layingDown and layBlend > 0.5 then
        -- PHASE 1: blending toward next pose (layPoseBlend 0→1 over BLEND_DUR)
        -- PHASE 2: holding the pose for a random duration, then trigger a new blend
        local BLEND_DUR = 3.0   -- seconds to crossfade between poses

        if layPoseBlend < 1 then
            -- actively blending — advance blend, use smooth ease in/out
            layPoseBlend = math.min(layPoseBlend + dt/BLEND_DUR, 1)
        else
            -- fully in pose — count hold timer
            layPoseTimer += dt
            if layPoseTimer >= layPoseHoldTime then
                -- hold done — commit and pick next random pose + new hold time
                layPoseIdx      = layPoseNext
                layPoseBlend    = 0
                layPoseTimer    = 0
                layPoseHoldTime = math.random(22, 40)
                local nxt
                repeat nxt = math.random(1, NUM_POSES) until nxt ~= layPoseIdx
                layPoseNext = nxt
            end
        end
    elseif not layingDown then
        layPoseTimer = 0; layPoseBlend = 0
    end
    -- granite step clock: advances in discrete snaps
    if graniteMode then
        graniteStepAcc += dt
        if graniteStepAcc >= GRANITE_STEP then
            graniteStepAcc = 0
            graniteStepT  += GRANITE_STEP
            rollGraniteJitter()
        end
    end
    if moving then
        local dir=CFrame.Angles(0,camYaw,0):VectorToWorldSpace(mv.Unit)
        gPos+=dir*SPEED*dt; animT+=dt
        local tYaw=math.atan2(dir.X,dir.Z)
        local diff=((tYaw-gYaw+math.pi)%(2*math.pi))-math.pi
        gYaw+=diff*math.min(dt*12,1)
        if stompOnWalk then
            local cyc=animT*(_G.__reanimWalkFreq or 6); local s=math.sin(cyc)
            if lastStepSign~=0 and ((lastStepSign>0)~=(s>0)) then spawnCrater(gPos) end
            lastStepSign=s>0 and 1 or -1
        end
    else lastStepSign=0 end

    updAcc+=dt
    if updAcc>=1/UPDATE_HZ then
        updAcc=0
        local cfs=getPuppetCFs(animT,idleT,moving,punchStart,stompStart,slashStart)
        local batch={}
        if rp["HRP"] and rp["HRP"].Parent then table.insert(batch,{Part=rp["HRP"],CFrame=cfs.HRP}) end
        for _,nm in LIMBS do local p=rp[nm]; if p and p.Parent then table.insert(batch,{Part=p,CFrame=cfs[nm]}) end end
        if swordEquipped and swordPart and swordPart.Parent and cfs.Sword then table.insert(batch,{Part=swordPart,CFrame=cfs.Sword}) end
        if showToolEnabled and toolPart and toolPart.Parent and cfs.Tool then table.insert(batch,{Part=toolPart,CFrame=cfs.Tool}) end
        if #batch>0 then f.MoveMany(batch) end
    end

    regenAcc+=dt
    if regenAcc>=2 and _G.__reanimRegenEnabled~=false then
        regenAcc=0
        if not rigModel or not rigModel.Parent then rigAlive=false end
        regen()
    end
end)

-- ── Start ────────────────────────────────────────────
task.spawn(function()
    -- Wait for F3X to be fully ready (it needs a frame or two to register the player)
    task.wait(0.5)
    local ok=buildRig(CFrame.new(gPos))
    rigAlive=ok==true
    statusLbl.Text=rigAlive and "⬤ Rig online" or "❌ Build failed"
    statusLbl.TextColor3=rigAlive and GRN or RED
end)

-- ── Respawn handler ──────────────────────────────────
LP.CharacterAdded:Connect(function(newChar)
    for _,n in {"HumanoidRootPart","Head","Torso"} do newChar:WaitForChild(n,10) end
    local newHum=newChar:FindFirstChildOfClass("Humanoid")
    local newHRP=newChar:FindFirstChild("HumanoidRootPart")
    if not newHum or not newHRP then return end
    char=newChar; hum=newHum; hrp=newHRP
    newHum.WalkSpeed=0; newHum.JumpPower=0; newHum.AutoRotate=false
    newHum:SetStateEnabled(Enum.HumanoidStateType.Dead,false)
    newHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown,false)
    f.SetLocked(newHRP,false); f.Anchor(true,newHRP)
    for _,p in newChar:GetDescendants() do if p:IsA("BasePart") then p.LocalTransparencyModifier=1 end end
    if not rigAlive or not rigModel or not rigModel.Parent then
        rigAlive=false
        task.spawn(function()
            local ok=buildRig(CFrame.new(gPos)); rigAlive=ok==true
            if statusLbl then statusLbl.Text=rigAlive and "⬤ Rig online" or "❌ Build failed"; statusLbl.TextColor3=rigAlive and GRN or RED end
            if rigAlive and swordEquipped then task.spawn(spawnSword) end
        end)
    end
end)

-- ── Jump ─────────────────────────────────────────────
local JUMP_DUR=0.55; local JUMP_CD=0.8
local jumpStart=-99; local tJump=0; local isAirborne=false; local jumpBaseY=0
KB.Jump=Enum.KeyCode.Space
local function doJump()
    if tick()-tJump<JUMP_CD then return end
    if isAirborne then return end
    tJump=tick(); jumpStart=tick(); jumpBaseY=gPos.Y; isAirborne=true
end
makeKeybind("Jump",KB.Jump,function(k) KB.Jump=k end)
UIS.InputBegan:Connect(function(i,gp) if gp then return end; if i.KeyCode==KB.Jump then doJump() end end)
local function tickJump(dt)
    if not isAirborne then return end
    local elapsed=tick()-jumpStart; local T=JUMP_DUR
    if elapsed>=T then
        isAirborne=false
        local groundY=getGroundY(); if groundY then gPos=Vector3.new(gPos.X,groundY,gPos.Z) end
        return
    end
    local t2=elapsed/T; local yOff=4*JUMP_HEIGHT*t2*(1-t2)
    gPos=Vector3.new(gPos.X,jumpBaseY+yOff,gPos.Z)
end
_G.__reanimJumpPhase=function()
    if not isAirborne then return 0 end
    return math.clamp((tick()-jumpStart)/JUMP_DUR,0,1)
end
local _origPuppetCFs=getPuppetCFs
getPuppetCFs=function(t,it,isMoving,pTime,sTime,slTime)
    local cfs=_origPuppetCFs(t,it,isMoving,pTime,sTime,slTime)
    local jp=_G.__reanimJumpPhase()
    if jp>0 then
        local r=math.rad; local tuck=math.sin(jp*math.pi)
        local legTuck=r(80)*tuck; local kneeTuck=-r(40)*tuck; local armRaise=-r(30)*tuck
        local flat=CFrame.new(gPos)*CFrame.Angles(0,gYaw,0)
        local lO=r(3)
        cfs.RightLeg=(flat*CFrame.new(S*0.5,0,0)*CFrame.Angles(-legTuck,0,lO+kneeTuck))*CFrame.new(0,-S,0)
        cfs.LeftLeg=(flat*CFrame.new(-S*0.5,0,0)*CFrame.Angles(-legTuck,0,-lO-kneeTuck))*CFrame.new(0,-S,0)
        local aH=r(18); local aO2=r(12)
        cfs.RightArm=(flat*CFrame.new(S*1.1,S*1.8,0)*CFrame.Angles(aH+armRaise,0,aO2))*CFrame.new(0,-S,0)
        cfs.LeftArm=(flat*CFrame.new(-S*1.1,S*1.8,0)*CFrame.Angles(aH+armRaise,0,-aO2))*CFrame.new(0,-S,0)
    end
    return cfs
end
RunSvc.RenderStepped:Connect(function(dt)
    if not rigAlive then return end
    tickJump(dt)
    -- ground snap disabled while laying down so people can't push rig up
    if not isAirborne and not layingDown then
        local groundY=getGroundY()
        if groundY then gPos=Vector3.new(gPos.X,gPos.Y+(groundY-gPos.Y)*math.min(dt*18,1),gPos.Z) end
    end
end)

print("[REANIMATE] v16 — T=Grab  Y=Cage  (mouse-targeted, any distance)")
