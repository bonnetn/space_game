AddCSLuaFile()

DEFINE_BASECLASS("base_anim")

ENT.PrintName = "Warp Drive"
ENT.Author = "Marmotte"

ENT.RenderGroup = RENDERGROUP_TRANSLUCENT

local Vector2 = GrandEspace.Vector2

local PHASE_IDLE = 1
local PHASE_LOADING = 2
local PHASE_MOVING = 3

function ENT:applyModules( mod )

	local range = 2
	local loading = 10
	
	for k,v in pairs(mod) do

		if v.moduleCategory == "WarpDrive" then

		end
	end

	self:SetNWInt("warprange", range)
	self:SetNWInt("warploading", loading)
end

function ENT:Initialize()

	Vector2 = GrandEspace.Vector2

	if CLIENT then
		self.lastClick = CurTime()
		self.lastQuery = CurTime()
		self.stars = nil			-- closest, reachable stars
		self.starId = 1
		self.window = { pixelPerUnit = 150, pos = Vector(0, 0, 0) }
		self.starPos = Vector2()		-- position of the selected star
		self.lastScanPos = Vector2()	-- position of the ship during the last DB query
		self.enteringPoint = Vector2()
		--self.locationText = "[Unknown location]"
		--self.distanceText = "0 pc"
		return
	end

	-- SHARED
	self:SetNWInt("warprange", 2)
	self:SetNWInt("warploading",10)
	self.speed = 0.02/66		-- parsec/tick
	self.state = PHASE_IDLE

	self:SetModel("models/props_combine/combine_intmonitor003.mdl")
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetUseType( SIMPLE_USE )

	local phys = self:GetPhysicsObject()
	if IsValid(phys) then
		phys:Wake()
	end
end

function ENT:Setup(firstSpawn)
	if firstSpawn then
		self:SetAngles(self:GetAngles() + Angle(-90, 0, 0))
	end
end

function ENT:SetState(state)
	self.state = state
	
	if SERVER then
		net.Start("PulpMod_WarpDrive")
			net.WriteEntity(self)
			net.WriteVector2(self.starPos)
			net.WriteFloat(state)
		net.Broadcast()
	end
end

if SERVER then

	util.AddNetworkString("GrandEspace - Pop up the galaxy map")
	function ENT:Use( ply)

		if not IsValid(ply) or not ply:IsPlayer() then return end

		ply.lastHyperSpaceEntity = self
		net.Start("GrandEspace - Pop up the galaxy map")
			net.WriteEntity(self)
		net.Send(ply)

	end

	util.AddNetworkString("PulpMod_WarpDrive")
	net.Receive("PulpMod_WarpDrive", function(len, ply)
		local ent = net.ReadEntity()

		if ent.traveling then return end
		ent.traveling = true

		net.ReadFloat()

		local pos = net.ReadVector2()
		ent.starPos = pos


		ent:SetState(PHASE_LOADING)

		-- First, load the warp drive...
		timer.Simple(ent:GetNWInt("warploading"), function()
			if not IsValid(ent) then return end

			ent:SetState(PHASE_MOVING)
			ent.parentSpaceship:setInHyperSpace(true)



			print("go")
			-- ... then, move the ship
			local timername = "warp_" .. ent:EntIndex()
			timer.Create(timername, 0, 0, function()

				if not IsValid(ent) or not ent.parentSpaceship then
					timer.Destroy(timername)
					ent.traveling = false
					if ent.parentSpaceship then ent.parentSpaceship:setInHyperSpace(false) end
					return
				end

				local direction = pos - ent.parentSpaceship:getGalaxyPos()

				if direction:Length() <= ent.speed then
					ent.parentSpaceship:setGalaxyPos(pos, true)
					timer.Destroy(timername)
					ent.traveling = false
					if ent.parentSpaceship then ent.parentSpaceship:setInHyperSpace(false) end
					ent:SetState(PHASE_IDLE)
				else
					ent.parentSpaceship:setGalaxyPos(ent.parentSpaceship:getGalaxyPos() + direction:GetNormalized()*ent.speed, true)
				end
			end)
		end)
	
	end)

	util.AddNetworkString("GrandEspace - Change hyperspace target")
	net.Receive("GrandEspace - Change hyperspace target", function(_, ply)

		local targetStar = net.ReadUInt(64)
		print(targetStar, type(targetStar))
		local targetPos = net.ReadVector2() -- easier to send to send the vector than searching the star in the table (im lazy) -- Poulpe
		local e = ply.lastHyperSpaceEntity
		if IsValid(e) and e.parentSpaceship then
			e:SetNWString("locationText", "[" .. GrandEspace.getStarName(targetStar) .. " System]")
			e:SetNWFloat("distanceText", targetPos:Distance(e.parentSpaceship:getGalaxyPos()))
		end

	end)
	
else



	-- CLIENT
	surface.CreateFont("WarpDriveConsole", {
		font = "Arial",
		extended = false,
		size = 48,
		weight = 500,
		blursize = 0,
		scanlines = 0,
		antialias = true,
		underline = false,
		italic = false,
		strikeout = false,
		symbol = false,
		rotary = false,
		shadow = false,
		additive = false,
		outline = false,
	})

	GrandEspace.inHyperSpace = false

	local function toggleHyperSpace(bool)
		GrandEspace.inHyperSpace = bool

		LocalPlayer():StopSound("hyperspace_bg")
		if bool then
			LocalPlayer():EmitSound("hyperspace_bg")
		end
	end

	-- Retrieve the state of the warp drive from the server
	net.Receive("PulpMod_WarpDrive", function(len)
		local ent = net.ReadEntity()
		ent.starPos = net.ReadVector2()
		ent.state = net.ReadFloat()

		local ship = ent.parentSpaceship
		local inHyperSpace = ent.state == PHASE_MOVING
		
		if ent.state == PHASE_IDLE then
			LocalPlayer():EmitSound( "warpdrive_boom" )
		end

		if ship then
			ent.parentSpaceship:setInHyperSpace(inHyperSpace)
			if inHyperSpace then
				ent.enteringPoint = ship:getGalaxyPos()
			end

			if ent.parentSpaceship == LocalPlayer():getSpaceship() then
				toggleHyperSpace(inHyperSpace)

				if ent.state == PHASE_LOADING then
					LocalPlayer():EmitSound("warpdrive_load")
				elseif ent.state == PHASE_MOVING then
					LocalPlayer():EmitSound("warpdrive_jump")
				end
			end
		end	
	end)


	-- Taken from https://maurits.tv/data/garrysmod/wiki/wiki.garrysmod.com/indexedb0.html
	local function worldToScreen(vWorldPos,vPos,vScale,aRot)
	    local vWorldPos=vWorldPos-vPos
	    vWorldPos:Rotate(Angle(0,-aRot.y,0))
	    vWorldPos:Rotate(Angle(-aRot.p,0,0))
	    vWorldPos:Rotate(Angle(0,0,-aRot.r))
	    return vWorldPos.x/vScale,(-vWorldPos.y)/vScale
	end

	local function getScreenCursorPos(tr, vPos, vScale, aRot)
		local n = aRot:Up()
		local ray = tr.HitPos - tr.StartPos
		local u = n:Dot(vPos - tr.StartPos)/n:Dot(ray)
		return worldToScreen(tr.StartPos + u*ray, vPos, vScale, aRot)
	end

	local function isCursorOnButton(curX, curY, x, y, w, h)
		return curX > x and curX < x + w and curY > y and curY < y + h
	end

	-- Regrouping stencil calls for better readability
	local function stencilStart()
		render.SetStencilEnable(true)
		render.ClearStencil()
		render.SetStencilWriteMask(4)
		render.SetStencilTestMask(4)
		render.SetStencilReferenceValue(4)
		render.SetStencilFailOperation(STENCILOPERATION_KEEP)
		render.SetStencilZFailOperation(STENCILOPERATION_KEEP)
		render.SetStencilPassOperation(STENCILOPERATION_REPLACE)
		render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_ALWAYS)
	end

	local function stencilSwitch()
		render.SetStencilCompareFunction(STENCILCOMPARISONFUNCTION_EQUAL)
	end

	local function stencilEnd()
		render.SetStencilReferenceValue(1)	-- Fix the holo bug with the physgun
		render.ClearStencil()
		render.SetStencilEnable(false)
	end

	local triangle = {{ x = 0, y = 0 },	{ x = 0, y = 0 }, { x = 0, y = 0 }}
	local triangleScale = 0.4
	local function getTriangle(x, y, dir)
		triangle[1].x = x + dir.x*20*triangleScale
		triangle[1].y = y + dir.y*20*triangleScale

		triangle[2].x = x - dir.y*12*triangleScale - dir.x*12*triangleScale
		triangle[2].y = y + dir.x*12*triangleScale - dir.y*12*triangleScale

		triangle[3].x = x + dir.y*12*triangleScale - dir.x*12*triangleScale
		triangle[3].y = y - dir.x*12*triangleScale - dir.y*12*triangleScale
		return triangle
	end

	-- Compute and define variables only once when possible
	local black = Color(0, 0, 0, 255)
	local black2 = Color(0, 0, 0, 240)
	local black3 = Color(50, 50, 50, 240)
	local black4 = Color(50, 50, 50, 255)
	local gray = Color(150, 150, 150, 255)
	local white = Color(255, 255, 255, 255)
	local red = Color(255, 0, 0, 255)
	local red2 = Color(100, 0, 0, 240)
	local red3 = Color(150, 0, 0, 240)

	local scrScale = 0.05
	local scrSizeX = 14*3.5/scrScale
	local scrSizeY = 10*3.5/scrScale
	local scrCenterX = scrSizeX/2
	local scrCenterY = scrSizeY/2

	local button1W = 10.5/scrScale
	local button1H = 3.5/scrScale
	local button1X = 8/scrScale
	local button1Y = 38.5/scrScale

	local button2W = 10.5/scrScale
	local button2H = 3.5/scrScale
	local button2X = 29/scrScale
	local button2Y = 38.5/scrScale

	local button3W = 16/scrScale
	local button3H = 4/scrScale
	local button3X = (button1X + button1W/2 + button2X + button2W/2)/2 - button3W/2
	local button3Y = 43/scrScale

	local button1TextX = button1X + button1W/2
	local button1TextY = button1Y + button1H/2

	local button2TextX = button2X + button2W/2
	local button2TextY = button2Y + button2H/2

	local button3TextX = button3X + button3W/2
	local button3TextY = button3Y + button3H/2

	local titleScale = 0.05
	local titleSizeX = 35/titleScale
	local titleSizeY = 7/titleScale
	local titleCenterX = titleSizeX/2
	local titleCenterY = titleSizeY/2

	local BUTTON_PREV = 1
	local BUTTON_NEXT = 2
	local BUTTON_JUMP = 3

	local mapUp = Vector2(0, -1)

	function ENT:Draw()
		self:DrawModel()

		-- Draw the map and buttons
		local camPos = self:GetPos() + self:GetForward()*27 + self:GetUp()*49 - self:GetRight()*16
		local camAngle = self:LocalToWorldAngles(Angle(90, 0, 0))
		local curX, curY = getScreenCursorPos(LocalPlayer():GetEyeTrace(), camPos, scrScale, camAngle)
		local click = 0
		local ship = self.parentSpaceship	
		cam.Start3D2D(camPos, camAngle, scrScale)
			-- Draw the stars map
			surface.SetDrawColor(black)
			stencilStart()
			surface.DrawRect(0, 0, scrSizeX, scrSizeY)
			stencilSwitch()

			local shipx = 0
			local shipy = 0
			if ship then
				shipx = ship:getGalaxyPos().x
				shipy = ship:getGalaxyPos().y
				self.window.pos = Vector(shipx, shipy, 0)
			end

			GrandEspace.drawStars(0, 0, scrSizeX, scrSizeY, self.window)
			GrandEspace.drawGrid(0, 0, scrSizeX, scrSizeY, self.window, 0.5, black4)
			stencilEnd()

			-- Warp drive status text or distance
			if not ship then
				draw.SimpleText("WARP DRIVE OFFLINE", "WarpDriveConsole", scrCenterX, scrCenterY, Color(204, 0, 0, math.abs(math.sin(CurTime()))*255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			elseif self.starPos then
				local coeff = self.window.pixelPerUnit/10/2
				local line = self.starPos - ship:getGalaxyPos()

				surface.SetDrawColor(red)
				surface.DrawLine(scrCenterX, scrCenterY, scrCenterX + coeff*line.x/scrScale, scrCenterY + coeff*line.y/scrScale)

				if ship:isInHyperSpace() then
					local line2 = self.enteringPoint - ship:getGalaxyPos()
					surface.DrawLine(scrCenterX, scrCenterY, scrCenterX + coeff*line2.x/scrScale, scrCenterY + coeff*line2.y/scrScale)
				end

				-- Draw the ship on the map
				surface.SetDrawColor(255, 255, 255, 100)
				surface.SetDrawColor(red)

				draw.NoTexture()
				if line.x ~= 0 and line.y ~= 0 then
					surface.DrawPoly(getTriangle(scrCenterX, scrCenterY, line:GetNormalized()))
				else
					surface.DrawPoly(getTriangle(scrCenterX, scrCenterY, mapUp))
				end
				
				-- Is the drive loading ?
				if self.state == PHASE_LOADING then
					draw.SimpleText("WARP DRIVE CHARGING", "WarpDriveConsole", scrCenterX, scrCenterY, Color(204, 0, 0, math.abs(math.sin(CurTime()))*255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
				end
			end

	--[[
			-- <Prev button
			surface.SetDrawColor(black2)
			if isCursorOnButton(curX, curY, button1X, button1Y, button1W, button1H) then
				surface.SetDrawColor(black3)
				if self:IsClicking() then
					click = BUTTON_PREV
				end
			end
			surface.DrawRect(button1X, button1Y, button1W, button1H)
			draw.SimpleText("<Prev", "WarpDriveConsole", button1TextX, button1TextY, gray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			-- Next> button
			surface.SetDrawColor(black2)
			if isCursorOnButton(curX, curY, button2X, button2Y, button2W, button2H) then
				surface.SetDrawColor(black3)
				if self:IsClicking() then
					click = BUTTON_NEXT
				end
			end
			surface.DrawRect(button2X, button2Y, button2W, button2H)
			draw.SimpleText("Next>", "WarpDriveConsole", button2TextX, button2TextY, gray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

			-- JUMP! button
			surface.SetDrawColor(red2)
			if isCursorOnButton(curX, curY, button3X, button3Y, button3W, button3H) then
				surface.SetDrawColor(red3)
				if self:IsClicking() then
					click = BUTTON_JUMP
				end
			end
			surface.DrawRect(button3X, button3Y, button3W, button3H)
			draw.SimpleText("JUMP!", "WarpDriveConsole", button3TextX, button3TextY, gray, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	
]]
		cam.End3D2D()

		-- Draw the location and distance
		local distance = 0
		if ship then
			distance = self.starPos:Distance(ship:getGalaxyPos())
		end

		cam.Start3D2D(self:GetPos() + self:GetForward()*31.8 + self:GetUp()*45 - self:GetRight()*28.5, self:LocalToWorldAngles(Angle(90, -19, 0)), titleScale)
			surface.SetDrawColor(black2)
			surface.DrawRect(0, 0, titleSizeX, titleSizeY)

			--self.distanceText = math.Round(distance, 2) .. " pc"
			draw.SimpleText(self:GetNWString("locationText"), "WarpDriveConsole", titleCenterX, titleCenterY - 25, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			local dist = self:GetNWFloat("distanceText",0)
			draw.SimpleText( tostring(math.Round(dist,2)).. " pc", "WarpDriveConsole", titleCenterX, titleCenterY + 25, white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		cam.End3D2D()

--[[
		-- Check for button press
		if click > 0 and ship and not ship:isInHyperSpace() then
			if not self.stars or self.lastScanPos ~= ship:getGalaxyPos() then 
				self.stars = self:GetClosestStars(ship:getGalaxyPos().x, ship:getGalaxyPos().y, 50, self:GetNWInt("warprange"))
			end
			if self.stars and #self.stars > 0 then
				if click == BUTTON_PREV then
					self.starId = math.max(1, self.starId - 1)
				elseif click == BUTTON_NEXT then
					self.starId = math.min(#self.stars, self.starId + 1)
				elseif click == BUTTON_JUMP then
					local distance = self.starPos:Distance(ship:getGalaxyPos())
					if self.stars and #self.stars > 0 and distance <= self:GetNWInt("warprange") then
						self.stars = nil
						self.starId = 1

						net.Start("PulpMod_WarpDrive")
							net.WriteEntity(self)
							net.WriteFloat(PHASE_LOADING)
							net.WriteVector2(self.starPos)
						net.SendToServer()
					end
				end
				if self.stars and #self.stars > 0 then
					self.starPos.x = self.stars[self.starId].x
					self.starPos.y = self.stars[self.starId].y
					--self.locationText = "[Star " .. self.stars[self.starId].id .. "]"
					self.locationText = "[" .. GrandEspace.getStarName(self.stars[self.starId].id) .. " System]"
				end
			end
		end
		]]
	end


	function ENT:IsClicking()
		if LocalPlayer():KeyDown(IN_USE) and CurTime() - self.lastClick > 0.15 and LocalPlayer():GetPos():DistToSqr(self:GetPos()) < 20000 then
			self.lastClick = CurTime()
			return true
		end
	end

	function ENT:GetClosestStars(x, y, count, range)
		local result = nil
		if CurTime() - self.lastQuery > 0.5 then
			result = sql.Query("SELECT * FROM " .. GrandEspace.sqlStarTable .. " WHERE ((X-(" .. x .. "))*(X-(" .. x .. "))+(Y-(" .. y .. "))*(Y-(" .. y .. "))) <= " .. math.pow(range,2) .. " ORDER BY ((X-(" .. x .. "))*(X-(" .. x .. "))+(Y-(" .. y .. "))*(Y-(" .. y .. "))) LIMIT " .. count .. ";")
			self.lastQuery = CurTime()
			self.lastScanPos = Vector2(x, y)
		end
		return result
	end

	net.Receive("GrandEspace - Pop up the galaxy map", function()


		local ship = LocalPlayer():getSpaceship()
		local hyperspaceEnt = net.ReadEntity()
		LocalPlayer().hyperspaceEnt = hyperspaceEnt
		if ship then

			local scale = 0.80
			local w,h = ScrW(), ScrH()

			local mapFrame = vgui.Create( "DFrame" )
			mapFrame:SetSize( w*scale, h*scale )
			mapFrame:Center()
			mapFrame:SetTitle( "MAP" )
			mapFrame:MakePopup()

			local mapPanel = mapFrame:Add("GrandEspace - MapPanel")
			mapPanel:SetPos(2,24)
			mapPanel:SetSize(w*scale - 4, h*scale - 26)
			mapPanel.warpRange = hyperspaceEnt:GetNWInt("warprange")

			mapPanel.window.pos = ship:getGalaxyPos()
		end

	end)

	-- Handle sounds
	sound.Add({
		name = "hyperspace_bg",
		channel = CHAN_STATIC,
		volume = 1,
		level = 511,
		pitch = 100,
		sound = "grandespace/warpdrive/hyperspace_bg.wav"
	})

	sound.Add({
		name = "warpdrive_load",
		channel = CHAN_STATIC,
		volume = 1,
		level = 511,
		pitch = 100,
		sound = "grandespace/warpdrive/warpdrive_load.mp3"
	})

	sound.Add({
		name = "warpdrive_jump",
		channel = CHAN_STATIC,
		volume = 0.5,
		level = 511,
		pitch = 100,
		sound = "grandespace/warpdrive/warpdrive_jump.mp3"
	})

	sound.Add({
		name = "warpdrive_boom",
		channel = CHAN_STATIC,
		volume = 1,
		level = 511,
		pitch = 100,
		sound = "grandespace/warpdrive/warpdrive_boom.mp3"
	})

	hook.Add("GrandEspace - LocalPlayer changed ship", "ToggleHyperSpace", function(ship, old)
		if ship then
			toggleHyperSpace(ship:isInHyperSpace())
		else
			toggleHyperSpace(false)
		end
	end)

	
end

scripted_ents.Register( ENT, "grandespace_warpdrive" ) 