local print, strsplit, select, wipe, remove
    = print, strsplit, select, wipe, table.remove
local CreateFrame, GetSpellInfo, PlaySoundFile, UIParent, UnitBuff
	= CreateFrame, GetSpellInfo, PlaySoundFile, UIParent, UnitBuff
    
local me = ...
local DSEO_BossesAlive = {}
local DSEO_PlayerHasDied = false

local MEDIA_PATH = "Interface\\Addons\\DarkSoulsEventOverlays\\media\\"
local YOU_DIED_TEXT = MEDIA_PATH .. "YOUDIED.tga"
local YOU_DIED_SOUND = MEDIA_PATH .. "YOUDIED.mp3"
local RETRIEVAL_TEXT = MEDIA_PATH .. "RETRIEVAL.tga"
local RETRIEVAL_SOUND = MEDIA_PATH .. "RETRIEVAL.mp3"
local VICTORY_ACHIEVED_TEXT = MEDIA_PATH .. "VICTORYACHIEVED.tga"
local YOU_DEFEATED_TEXT = MEDIA_PATH .. "YOUDEFEATED.tga"
local YOU_RECOVERED_TEXT = MEDIA_PATH .. "YOURECOVERED.tga"
local TEXTURE_WIDTH_HEIGHT_RATIO = 0.32 -- width / height

local BG_END_ALPHA = 0.85 -- [0,1] alpha
local TEXT_END_ALPHA = 0.5 -- [0,1] alpha
local TEXT_SHOW_END_SCALE = 1.25 -- scale factor
local FADE_IN_TIME = 0.45 -- in seconds
local FADE_OUT_TIME = 0.3 -- in seconds
local FADE_OUT_DELAY = 0.4 -- in seconds
local TEXT_END_DELAY = 0.5 -- in seconds
local BACKGROUND_GRADIENT_PERCENT = 0.15 -- of background height
local BACKGROUND_HEIGHT_PERCENT = 0.21 -- of screen height
local TEXT_HEIGHT_PERCENT = 0.18 -- of screen height

local ScreenWidth, ScreenHeight = UIParent:GetSize()
local db

-- ------------------------------------------------------------------
-- Init
-- ------------------------------------------------------------------
local function OnEvent(self, event, ...)
	if type(self[event]) == "function" then
		self[event](self, event, ...)
	end
end

local DSEOFrame = CreateFrame("Frame") -- helper frame
DSEOFrame:SetScript("OnEvent", OnEvent)

-- ------------------------------------------------------------------
-- Display
-- ------------------------------------------------------------------
local UPDATE_TIME = 0.04
local function BGFadeIn(self, e)
	self.elapsed = (self.elapsed or 0) + e
	local progress = self.elapsed / FADE_IN_TIME
	if progress <= 1 then
		self:SetAlpha(progress * BG_END_ALPHA)
	else
		self:SetScript("OnUpdate", nil)
		self.elapsed = nil
	end
end

local function BGFadeOut(self, e)
	self.elapsed = (self.elapsed or 0) + e
	local progress = 1 - (self.elapsed / FADE_OUT_TIME)
	if progress >= 0 then
		self:SetAlpha(progress * BG_END_ALPHA)
	else
		self:SetScript("OnUpdate", nil)
		self.elapsed = nil
	end
end

local background
local function SpawnBackground()
	if not background then
		background = CreateFrame("Frame")
		background:SetPoint("CENTER", 0, 0)
		background:SetFrameStrata("MEDIUM")
		
		local bg = background:CreateTexture()
		bg:SetTexture(0, 0, 0)
		background.bg = bg
		
		local top = background:CreateTexture()
		top:SetTexture(0, 0, 0)
		top:SetGradientAlpha("VERTICAL", 0, 0, 0, 1, 0, 0, 0, 0) -- orientation, startR, startG, startB, startA, endR, endG, endB, endA (start = bottom, end = top)
		background.top = top
		
		local btm = background:CreateTexture()
		btm:SetTexture(0, 0, 0)
		btm:SetGradientAlpha("VERTICAL", 0, 0, 0, 0, 0, 0, 0, 1)
		background.btm = btm
	end
	
	local height = BACKGROUND_HEIGHT_PERCENT * ScreenHeight
	local bgHeight = BACKGROUND_GRADIENT_PERCENT * height
	background:SetSize(ScreenWidth, height)
	
	-- size the background's constituent components
	background.top:ClearAllPoints()
	background.top:SetPoint("TOPLEFT", 0, 0)
	background.top:SetPoint("BOTTOMRIGHT", background, "TOPRIGHT", 0, -bgHeight)
	
	background.bg:ClearAllPoints()
	background.bg:SetPoint("TOPLEFT", 0, -bgHeight)
	background.bg:SetPoint("BOTTOMRIGHT", 0, bgHeight)
	
	background.btm:ClearAllPoints()
	background.btm:SetPoint("BOTTOMLEFT", 0, 0)
	background.btm:SetPoint("TOPRIGHT", background, "BOTTOMRIGHT", 0, bgHeight)
	
	background:SetAlpha(0)
	-- ideally this would use Animations, but they seem to set the alpha on all elements in the region which destroys the alpha gradient
	-- ie, the background becomes just a solid-color rectangle
	background:SetScript("OnUpdate", BGFadeIn)
end

local function FadeOutOnUpdate(self, e)
	self.elapsed = (self.elapsed or 0) + e
	if self.elapsed > FADE_OUT_DELAY then
		background:SetScript("OnUpdate", BGFadeOut)
		self:SetScript("OnUpdate", nil)
		self.elapsed = nil
	end
end

local DSEO_TextFrame
local function SpawnText(tex, textWidth)
	if not DSEO_TextFrame then
		DSEO_TextFrame = CreateFrame("Frame")
		DSEO_TextFrame:SetPoint("CENTER", 0, 0)
		DSEO_TextFrame:SetFrameStrata("HIGH")
		
		-- "YOU DIED"
		DSEO_TextFrameTexture = DSEO_TextFrame:CreateTexture()
		DSEO_TextFrameTexture:SetAllPoints()
		
		-- intial animation (fade-in + zoom)
		local show = DSEO_TextFrame:CreateAnimationGroup()
		local fadein = show:CreateAnimation("Alpha")
		fadein:SetChange(TEXT_END_ALPHA)
		fadein:SetOrder(1)
		fadein:SetStartDelay(FADE_IN_TIME)
		fadein:SetDuration(FADE_IN_TIME + 0.15)
		fadein:SetEndDelay(TEXT_END_DELAY)
		local zoom = show:CreateAnimation("Scale")
		zoom:SetOrigin("CENTER", 0, 0)
		zoom:SetScale(TEXT_SHOW_END_SCALE, TEXT_SHOW_END_SCALE)
		zoom:SetOrder(1)
		zoom:SetDuration(1.3)
		zoom:SetEndDelay(TEXT_END_DELAY)
		
		-- hide animation (fade-out + slower zoom)
		local hide = DSEO_TextFrame:CreateAnimationGroup()
		local fadeout = hide:CreateAnimation("Alpha")
		fadeout:SetChange(-1)
		fadeout:SetOrder(1)
		fadeout:SetSmoothing("IN_OUT")
		fadeout:SetStartDelay(FADE_OUT_DELAY)
		fadeout:SetDuration(FADE_OUT_TIME + FADE_OUT_DELAY)
		local zoom = hide:CreateAnimation("Scale")
		zoom:SetOrigin("CENTER", 0, 0)
		zoom:SetScale(1.07, 1.038)
		zoom:SetOrder(1)
		zoom:SetDuration(FADE_OUT_TIME + FADE_OUT_DELAY + 0.3)
		
		show:SetScript("OnFinished", function(self)
			-- hide once the delay finishes
			DSEO_TextFrame:SetAlpha(TEXT_END_ALPHA)
			DSEO_TextFrame:SetScale(TEXT_SHOW_END_SCALE)
			fadeout:SetScript("OnUpdate", FadeOutOnUpdate)
			hide:Play()
		end)
		hide:SetScript("OnFinished", function(self)
			-- reset to initial state
			DSEO_TextFrame:SetAlpha(0)
			DSEO_TextFrame:SetScale(1)
		end)
		DSEO_TextFrame.show = show
	end
    
	--[[if DSEO_TextFrame.tex:GetTexture() ~= db.tex then
		DSEO_TextFrame.tex:SetTexture(db.tex)
	end]]--
	
	local height = TEXT_HEIGHT_PERCENT * ScreenHeight
	--DSEO_TextFrame:SetSize(height / TEXTURE_WIDTH_HEIGHT_RATIO, height)
	DSEO_TextFrame:SetSize(textWidth*(ScreenWidth/25), height)
	DSEO_TextFrame:SetAlpha(0)
	DSEO_TextFrame:SetScale(1)
	DSEO_TextFrameTexture:SetTexture(tex)
	DSEO_TextFrame.show:Play()
end

-- ------------------------------------------------------------------
-- Event handlers
-- ------------------------------------------------------------------
DSEOFrame:RegisterEvent("ADDON_LOADED")
function DSEOFrame:ADDON_LOADED(event, name)
    if name == me then
        DarkSoulsEventOverlays = DarkSoulsEventOverlays or {
            --[[
            default db
            --]]
            enabled = true,
            sound = true,
            tex = YOU_DIED_TEXT,
        }
        db = DarkSoulsEventOverlays
        if not db.enabled then
            self:SetScript("OnEvent", nil)
        end
        self.ADDON_LOADED = nil
    end
end

local SpiritOfRedemption = GetSpellInfo(20711)
local FeignDeath = GetSpellInfo(5384)
DSEOFrame:RegisterEvent("PLAYER_DEAD")
function DSEOFrame:PLAYER_DEAD(event)
	local SOR = UnitBuff("player", SpiritOfRedemption)
	local FD = UnitBuff("player", FeignDeath)
	-- event==nil means a fake event
	if not event or not (UnitBuff("player", SpiritOfRedemption) or UnitBuff("player", FeignDeath)) then
		if db.sound then
			PlaySoundFile(YOU_DIED_SOUND, "Master")
		end
		SpawnBackground()
		SpawnText(YOU_DIED_TEXT, 7)
		DSEO_PlayerHasDied = true
	end
end

DSEOFrame:RegisterEvent("PLAYER_UNGHOST")
function DSEOFrame:PLAYER_UNGHOST(event)
	if db.sound then
		PlaySoundFile(RETRIEVAL_SOUND, "Master")
	end
	SpawnBackground()
	SpawnText(YOU_RECOVERED_TEXT, 12)
	DSEO_PlayerHasDied = false
end

DSEOFrame:RegisterEvent("PLAYER_ALIVE")
function DSEOFrame:PLAYER_ALIVE(event)
	if not UnitIsGhost("player") and DSEO_PlayerHasDied then -- check because this event fires when someone releases or is resurrected by another player
		if db.sound then
			PlaySoundFile(RETRIEVAL_SOUND, "Master")
		end
		SpawnBackground()
		SpawnText(YOU_RECOVERED_TEXT, 12)
		DSEO_PlayerHasDied = false
	end
end

DSEOFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
function DSEOFrame:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
	local timestamp, eventType, hideCaster, sourceGUID, sourceName, sourceFlags, sourceFlags2, destGUID, destName, destFlags, destFlags2 = select(1, ...)
	if eventType == "UNIT_DIED" then
		if #DSEO_BossesAlive == 1 and DSEO_BossesAlive[1] == destGUID then -- last boss died
			table.remove(DSEO_BossesAlive,1)
			if db.sound then
				PlaySoundFile(RETRIEVAL_SOUND, "Master")
			end
			SpawnBackground()
			SpawnText(YOU_DEFEATED_TEXT, 11)
		elseif DSEO_findTableIndexByValue(DSEO_BossesAlive, destGUID) then -- a boss died
			print("Removing " .. destName .. " from DSEO_BossesAlive")
			table.remove(DSEO_BossesAlive, DSEO_findTableIndexByValue(DSEO_BossesAlive, destGUID))
		end
	end
end

-- Enter combat, enumerate bosses
DSEOFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
function DSEOFrame:PLAYER_REGEN_DISABLED(event)
	DSEO_BossesAlive = {}
	for i=1,4 do
		if UnitExists("boss" .. i) and not UnitIsDead("boss" .. i) then
			table.insert(DSEO_BossesAlive, UnitGUID("boss" .. i))
		end
	end
end

-- Leave combat, reset bosses
DSEOFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
function DSEOFrame:PLAYER_REGEN_ENABLED(event)
	DSEO_BossesAlive = {}
end


-- ------------------------------------------------------------------
-- Helper Functions
-- ------------------------------------------------------------------
function DSEO_findTableIndexByValue(table, value)
	for i=1,#table do
		if table[i] == value then
			return i
		end
	end
	return nil
end

function DSEO_findBossIdentifierByGUID(guid)
	for i=1,4 do
		if UnitExists("boss" .. i) and UnitGUID("boss" .. i) == guid then
			return "boss" .. i
		end
	end
	return nil
end

-- ------------------------------------------------------------------
-- Slash cmd
-- ------------------------------------------------------------------
local slash = "/dseo"
SLASH_DARKSOULSEVENTOVERLAYS1 = slash

local ADDON_COLOR = "ff999999"
local function Print(msg)
    print(("|c%sDSDS|r: %s"):format(ADDON_COLOR, msg))
end

local function OnOffString(bool)
    return bool and "|cff00FF00enabled|r" or "|cffFF0000disabled|r"
end

local split = {}
local function pack(...)
    wipe(split)

    local numArgs = select('#', ...)
    for i = 1, numArgs do
        split[i] = select(i, ...)
    end
    return split
end

local commands = {}
commands["enable"] = function(args)
    db.enabled = true
    DSEOFrame:SetScript("OnEvent", OnEvent)
    Print(OnOffString(db.enabled))
end
commands["on"] = commands["enable"] -- enable alias
commands["disable"] = function(args)
    db.enabled = false
    DSEOFrame:SetScript("OnEvent", nil)
    Print(OnOffString(db.enabled))
end
commands["off"] = commands["disable"] -- disable alias
commands["sound"] = function(args)
    local doPrint = true
    local enable = args[1]
    if enable then
        if enable == "on" or enable == "true" then
            db.sound = true
        elseif enable == "off" or enable == "false" or enable == "nil" then
            db.sound = false
        else
            Print(("Usage: %s sound [on/off]"):format(slash))
            doPrint = false
        end
    else
        -- toggle
        db.sound = not db.sound
    end
    
    if doPrint then
        Print(("Sound %s"):format(OnOffString(db.sound)))
    end
end
--[[commands["tex"] = function(args)
    local tex = args[1]
    local currentTex = db.tex
    if tex then
        db.tex = tex
    else
        -- toggle
        if currentTex == YOU_DIED_TEXT then
            db.tex = THANKS_OBAMA
            tex = "THANKS OBAMA"
        else
            -- this will also default to "YOU DIED" if a custom texture path was set
            db.tex = YOU_DIED_TEXT
            tex = "YOU DIED"
        end
    end
    Print(("Texture set to '%s'"):format(tex))
end]]--
commands["test"] = function(args)
    DSEOFrame:PLAYER_DEAD()
end

local indent = "  "
local usage = {
    ("Usage: %s"):format(slash),
    ("%s%s on/off: Enables/disables the death screen."),
    ("%s%s sound [on/off]: Enables/disables the death screen sound. Toggles if passed no argument."),
    --("%s%s tex [path\\to\\custom\\texture]: Toggles between the 'YOU DIED' and 'THANKS OBAMA' textures. If an argument is supplied, the custom texture will be used instead."),
    ("%s%s test: Shows the death screen."),
    ("%s%s help: Shows this message."),
}
do -- format the usage lines
    for i = 2, #usage do
        usage[i] = usage[i]:format(indent, slash)
    end
end
commands["help"] = function(args)
    for i = 1, #usage do
        Print(usage[i])
    end
end
commands["h"] = commands["help"] -- help alias

local delim = " "
function SlashCmdList.DARKSOULSEVENTOVERLAYS(msg)
	msg = msg and msg:lower()
    local args = pack(strsplit(delim, msg))
    local cmd = remove(args, 1)
	
    local exec = cmd and type(commands[cmd]) == "function" and commands[cmd] or commands["h"]
    exec(args)
end
