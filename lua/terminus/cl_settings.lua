local SEND_DELAY = 0.25
local SETTLE = 1

local function Send(s, value)
	s.pending = RealTime() + SEND_DELAY + SETTLE
	timer.Create("TerminusSetting_" .. s.name, SEND_DELAY, 1, function()
		if math.abs(GetConVar(s.convar):GetFloat() - value) < 1e-3 then return end
		net.Start("TerminusSetting")
		net.WriteString(s.convar)
		net.WriteString(tostring(value))
		net.SendToServer()
	end)
end

local function Settled(s)
	return RealTime() > (s.pending or 0)
end

local function Admin(control)
	local ply = LocalPlayer()
	local admin = IsValid(ply) and ply:IsSuperAdmin()
	if control:IsEnabled() ~= admin then control:SetEnabled(admin) end
end

local function Toggle(s)
	return s.max == 1 and not s.decimals
end

local function BuildServer(panel)
	for _, s in ipairs(Terminus.SETTINGS) do
		local cv = GetConVar(s.convar)
		local control
		if Toggle(s) then
			control = panel:CheckBox(s.label)
			control:SetChecked(cv:GetBool())
			control.OnChange = function(_, on) Send(s, on and 1 or 0) end
			control.Think = function(self)
				Admin(self)
				if Settled(s) and self:GetChecked() ~= cv:GetBool() then self:SetChecked(cv:GetBool()) end
			end
		else
			control = panel:NumSlider(s.label, nil, s.min, s.max, s.decimals)
			control:SetValue(cv:GetFloat())
			control.OnValueChanged = function(_, value) Send(s, value) end
			control.Think = function(self)
				Admin(self)
				if Settled(s) and not self:IsEditing() and math.abs(self:GetValue() - cv:GetFloat()) > 1e-3 then self:SetValue(cv:GetFloat()) end
			end
		end
		control:SetTooltip(s.help)
	end
end

local function BuildClient(panel)
	for _, s in ipairs(Terminus.CLIENT_SETTINGS) do
		local control
		if Toggle(s) then
			control = panel:CheckBox(s.label, s.convar)
		else
			control = panel:NumSlider(s.label, s.convar, s.min, s.max, s.decimals)
		end
		control:SetTooltip(s.help)
	end
end

hook.Add("PopulateToolMenu", "TerminusSettings", function()
	spawnmenu.AddToolMenuOption("Utilities", "Terminus", "terminus_server", "Server", "", "", BuildServer)
	spawnmenu.AddToolMenuOption("Utilities", "Terminus", "terminus_client", "Client", "", "", BuildClient)
end)
