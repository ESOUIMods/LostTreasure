﻿local LAM2 = LibStub:GetLibrary("LibAddonMenu-2.0")
local LMP = LibStub:GetLibrary("LibMapPins-1.0")

local Addon = {
    Name = "LostTreasure",
    NameSpaced = "Lost Treasure",
    Author = "CrazyDutchGuy & katkat42",
    Version = "3.0.8",
}

LT = ZO_Object:Subclass()
LT.defaults = {
	showTreasure = true,
	showTreasureCompass = true,
	treasurePinTexture = 1,
	treasureMarkMapMenuOption = 2,

	showSurveys = true,
	showSurveysCompass = true,
	surveysPinTexture = 1,
	surveysMarkMapMenuOption = 2,

	showMiniTreasureMap = true,
	miniTreasureMap = { 
		point = TOPLEFT,
		relativeTo = GuiRoot,
		relativePoint = TOPLEFT,
		offsetX = 100,
		offsetY = 100,
	},
	pinTextureSize = 32,
	apiVersion = GetAPIVersion(),
}

-- some strings
local MAP_PIN_TYPES = {
	treasure = Addon.Name.."MapTreasurePin",
	surveys = Addon.Name.."CompassSurveysPin",
}
local COMPASS_PIN_TYPES = {
	treasure = Addon.Name.."MapTreasurePin",
	surveys = Addon.Name.."CompassSurveysPin",
}

local markMapMenuOptions = {
    [1] = [[Mark on use]],
    [2] = [[Mark all in inventory]],
    [3] = [[Mark all locations]]
}

local pinTexturesList = {
    [1] = [[X red]],
    [2] = [[X black]],
    [3] = [[Map black (Mitsarugi)]],
    [4] = [[Map white (Mitsarugi)]],
}

local pinTextures = {
    [1] = [[LostTreasure/Icons/x_red.dds]],
    [2] = [[LostTreasure/Icons/x_black.dds]],
    [3] = [[LostTreasure/Icons/map_black.dds]], 
    [4] = [[LostTreasure/Icons/map_white.dds]], 
}

local pinLayout_Treasure = {
	level = 40,
}

local pinLayout_Surveys = {
	level = 40,
}

local compassLayout_Treasure = {
	maxDistance = 0.05,
	texture = "",
}

local compassLayout_Surveys = {
	maxDistance = 0.05,
	texture = "",
}

local LostTreasureTLW = nil
local currentTreasureMapItemID = nil

local lang
local TREASURE_TEXT = { 
	en = "treasure map",
	de = "schatzkarte",
	fr = "carte au trésor",
	ru = "êapòa coêpoáèû", 
}
local SURVEYS_TEXT = {
	en = "survey:",
	de = "gutachten",
	fr = "repérages",
	ru = "èccìeäoáaîèe",
}
LT.dirtyPins = {}
LT.isUpdating = false

--Creates ToolTip from treasure info
local pinTooltipCreator = {
	creator = function(pin)
        local _, pinTag = pin:GetPinTypeAndTag()
		InformationTooltip:AddLine(pinTag[LOST_TREASURE_INDEX.MAP_NAME], "", ZO_HIGHLIGHT_TEXT:UnpackRGB())--name color
        InformationTooltip:AddLine(string.format("%.2f",pinTag[LOST_TREASURE_INDEX.X]*100).."x"..string.format("%.2f",pinTag[LOST_TREASURE_INDEX.Y]*100), "", ZO_HIGHLIGHT_TEXT:UnpackRGB())--name color
	end,
	tooltip = 1, -- tooltip type is information
}

--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- creates a pin for a specific point, in either/both player map and compass
-- thanks Garkin!
local function CreatePin(treasureType, pinData, map, compass)
	if map then
		LMP:CreatePin(MAP_PIN_TYPES[treasureType], pinData, pinData[LOST_TREASURE_INDEX.X], pinData[LOST_TREASURE_INDEX.Y])
	end
	if compass then
		COMPASS_PINS.pinManager:CreatePin(COMPASS_PIN_TYPES[treasureType], pinData, pinData[LOST_TREASURE_INDEX.X], pinData[LOST_TREASURE_INDEX.Y])
	end
end

-- creates/refreshes any pins that need creating/refreshing
-- thanks Garkin!
local function CreatePins()
	local data = LOST_TREASURE_DATA[GetCurrentMapZoneIndex()]
	if GetMapType() == MAPTYPE_SUBZONE then  --subzone in the current map, derive info from texture instead of mapname to avoid issues with french and german clients
		local subzone = string.match(GetMapTileTexture(), "%w+/%w+/%w+/(%w+)_%w+_%d.dds")
		data = LOST_TREASURE_DATA[subzone]
	end

	if data then
		if LT.dirtyPins[1] then
			for treasureType, keys in pairs(LT.dirtyPins[1]) do
				local treasureTypeData = data[treasureType]
				if treasureTypeData then
					for i = 1, GetNumViewableTreasureMaps() do
						local name, textureName  = GetTreasureMapInfo(i)
						local mapTextureName = string.match(textureName, "%w+/%w+/%w+/(.+)%.dds")
						for _, pinData in pairs(treasureTypeData) do
							local mapTexture = pinData[LOST_TREASURE_INDEX.TEXTURE]
							if mapTexture then
								if mapTextureName == mapTexture then
									CreatePin(treasureType, pinData, keys.map, keys.compass)
								end
							else
								if name == pinData[LOST_TREASURE_INDEX.MAP_NAME] then
									CreatePin(treasureType, pinData, keys.map, keys.compass)
								end
							end
						end
					end
				end
			end
		end
		if LT.dirtyPins[2] then
			local bagCache = SHARED_INVENTORY:GenerateFullSlotData(nil, BAG_BACKPACK)
			for slotIndex, itemData in pairs(bagCache) do
				if itemData.itemID and itemData.itemType == ITEMTYPE_TROPHY then
					for treasureType, keys in pairs(LT.dirtyPins[2]) do
						local treasureTypeData = data[treasureType]
						if treasureTypeData then
							for _, pinData in pairs(treasureTypeData) do
								if itemData.itemID == pinData[LOST_TREASURE_INDEX.ITEMID] then
									CreatePin(treasureType, pinData, keys.map, keys.compass)
								end
							end
						end
					end
				end
			end
		end
		if LT.dirtyPins[3] then
			for treasureType, keys in pairs(LT.dirtyPins[3]) do
				local treasureTypeData = data[treasureType]
				if treasureTypeData then
					for _, pinData in pairs(treasureTypeData) do
						CreatePin(treasureType, pinData, keys.map, keys.compass)
					end
				end
			end
		end
	end

	dirtyPins = {}
	LT.isUpdating = false
end

-- prepares the list of dirty pins and sends it to CreatePins()
-- thanks Garkin!
local function QueueCreatePins(treasureType, key)
	local shownMaps = LT.SavedVariables[treasureType.."MarkMapMenuOption"]
	LT.dirtyPins[shownMaps] = LT.dirtyPins[shownMaps] or {}
	LT.dirtyPins[shownMaps][treasureType] = LT.dirtyPins[shownMaps][treasureType] or {}
	LT.dirtyPins[shownMaps][treasureType][key] = true

	if not LT.isUpdating then
		LT.isUpdating = true
		zo_callLater(CreatePins, 250)
	end
end

local function pinCreator(treasureType)
	if not LMP:IsEnabled(MAP_PIN_TYPES[treasureType]) or (GetMapType() > MAPTYPE_ZONE) then return end
	QueueCreatePins(treasureType, "map")
end

local function compassCallback(treasureType)
	if not LT.SavedVariables[zo_strformat("show<<C:1>>Compass", treasureType)] or (GetMapType() > MAPTYPE_ZONE) then return end
	QueueCreatePins(treasureType, "compass")
end

local function showMiniTreasureMap(texture)
    if LT.SavedVariables.showMiniTreasureMap then
        LostTreasureTLW:SetHidden( false )
        LostTreasureTLW.map:SetTexture(texture)
    end
end

local function hideMiniTreasureMap()
    LostTreasureTLW:SetHidden(true)
end

local function createMiniTreasureMap()
    LostTreasureTLW = WINDOW_MANAGER:CreateTopLevelWindow("LostTreasureMap")
    LostTreasureTLW:SetMouseEnabled(true)
    LostTreasureTLW:SetMovable( true )
    LostTreasureTLW:SetClampedToScreen(true)
    LostTreasureTLW:SetDimensions( 400 , 400 )
    LostTreasureTLW:SetAnchor( 
        LT.SavedVariables.miniTreasureMap.point,
        GetControl(LT.SavedVariables.miniTreasureMap.relativeTo),
        LT.SavedVariables.miniTreasureMap.relativePoint,
        LT.SavedVariables.miniTreasureMap.offsetX,
        LT.SavedVariables.miniTreasureMap.offsetY
	)
    LostTreasureTLW:SetHidden( true )
    LostTreasureTLW:SetHandler("OnMoveStop", function(self,...)
            local _, point, relativeTo, relativePoint, offsetX, offsetY = self:GetAnchor()
            LT.SavedVariables.miniTreasureMap.point = point
            LT.SavedVariables.miniTreasureMap.relativeTo = relativeTo:GetName()
            LT.SavedVariables.miniTreasureMap.relativePoint = relativePoint
            LT.SavedVariables.miniTreasureMap.offsetX = offsetX
            LT.SavedVariables.miniTreasureMap.offsetY = offsetY
        end
	)

    LostTreasureTLW.map = WINDOW_MANAGER:CreateControl(nil,  LostTreasureTLW, CT_TEXTURE)
    LostTreasureTLW.map:SetAnchorFill(LostTreasureTLW)

    LostTreasureTLW.map.close = WINDOW_MANAGER:CreateControlFromVirtual(nil, LostTreasureTLW.map, "ZO_CloseButton")
    LostTreasureTLW.map.close:SetHandler("OnClicked", function(...) hideMiniTreasureMap() end)
end

function LT:EVENT_SHOW_TREASURE_MAP(event, treasureMapIndex)
	local name, textureName  = GetTreasureMapInfo(treasureMapIndex)

    showMiniTreasureMap(textureName)

    local mapTextureName = string.match(textureName, "%w+/%w+/%w+/(.+)%.dds")
    for _, v in pairs(LOST_TREASURE_DATA) do
		if v["treasure"] ~= nil then
			for _, pinData in pairs(v["treasure"]) do
				if mapTextureName == pinData[LOST_TREASURE_INDEX.TEXTURE] then
					currentTreasureMapItemID = pinData[LOST_TREASURE_INDEX.ITEMID]
					return
				end
			end
		end
		if v["surveys"] ~= nil then
			for _, pinData in pairs(v["surveys"]) do
				if mapTextureName == pinData[LOST_TREASURE_INDEX.TEXTURE] then
					currentTreasureMapItemID = pinData[LOST_TREASURE_INDEX.ITEMID]
					return
				end
			end
		end
    end

	name = zo_strformat(SI_TOOLTIP_ITEM_NAME, name)
	local myLink
	local bagCache = SHARED_INVENTORY:GenerateFullSlotData(nil, BAG_BACKPACK)
	for slot, itemData in pairs(bagCache) do
		if name == itemData.name then 
			myLink = GetItemLink(BAG_BACKPACK, slot)
			break 
		end
	end

	if myLink and #myLink > 0 then
		local itemID = select(4,ZO_LinkHandler_ParseLink(myLink))
		d("Unknown treasure map: "..name..", "..mapTextureName..", "..itemID)
		-- d("Sending update to addon author for map " .. name )
		-- RequestOpenMailbox()
		-- SendMail("@YourAccountName", "Lost Treasure " .. Addon.Version .. " :  ".. name,  name .. "::" .. textureName .."::" .. mapTextureName .. "::"..itemID)
	end
end

-- callback to check if an item was added to inventory; if it was a map, update its pins
-- thanks Garkin!
function LT:SlotAdded(bagId, slotIndex, slotData)
	if not (bagId == BAG_BACKPACK and slotData and slotData.itemType == ITEMTYPE_TROPHY) then return end

	local isTreasureMap = zo_plainstrfind(zo_strlower(slotData.name), TREASURE_TEXT[lang])
	local isSurveyMap = zo_plainstrfind(zo_strlower(slotData.name), SURVEYS_TEXT[lang])

	if isTreasureMap or isSurveyMap then
		local itemID = select(4, ZO_LinkHandler_ParseLink(GetItemLink(BAG_BACKPACK, slotIndex)))
		slotData.itemID = tonumber(itemID)
	end

	if isTreasureMap and LT.SavedVariables["treasureMarkMapMenuOption"] == 2 then
		LMP:RefreshPins(MAP_PIN_TYPES.treasure)
		COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.treasure)
	end
	if isSurveyMap and LT.SavedVariables["surveysMarkMapMenuOption"] == 2 then
		LMP:RefreshPins(MAP_PIN_TYPES.surveys)
		COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.surveys)
	end
end

-- callback to check if an item was removed from inventory; if it was a map, update its pins
-- thanks Garkin!
function LT:SlotRemoved(bagId, slotIndex, slotData)
	if not (slotData and slotData.itemID) then return end

	local isTreasureMap = zo_plainstrfind(zo_strlower(slotData.name), TREASURE_TEXT[lang])
	local isSurveyMap = zo_plainstrfind(zo_strlower(slotData.name), SURVEYS_TEXT[lang])

	if (currentTreasureMapItemID and currentTreasureMapItemID == slotData.itemID) then
		hideMiniTreasureMap()
	end

	if isTreasureMap and LT.SavedVariables["treasureMarkMapMenuOption"] <= 2 then
		LMP:RefreshPins(MAP_PIN_TYPES.treasure)
		COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.treasure)
	end
	if isSurveyMap and LT.SavedVariables["surveysMarkMapMenuOption"] <= 2 then
		LMP:RefreshPins(MAP_PIN_TYPES.surveys)
		COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.surveys)
	end
end


local function createLAM2Panel()
    local treasureMapIcon
	local strings = LOST_TREASURE_STRINGS[lang]
    local panelData = {
        type = "panel",
        name = Addon.NameSpaced,
        displayName = ZO_HIGHLIGHT_TEXT:Colorize(Addon.NameSpaced),
        author = Addon.Author,
        version = Addon.Version,
        registerForRefresh = true,
    }

    local optionsData = {
		[1] = {
			type = "checkbox",
			name = strings.TREASURE_ON_MAP,
			tooltip = strings.TREASURE_ON_MAP_TOOLTIP,
			getFunc = function() return LT.SavedVariables.showTreasure end,
			setFunc = function(value) 
				LT.SavedVariables.showTreasure = value 
				LMP:SetEnabled(MAP_PIN_TYPES.treasure, value)
			end,
		},
		[2] = {
			type = "checkbox",
			name = strings.TREASURE_ON_COMPASS,
			tooltip = strings.TREASURE_ON_COMPASS_TOOLTIP,
			getFunc = function() return LT.SavedVariables.showTreasureCompass end,
			setFunc = function(value) 
				LT.SavedVariables.showTreasureCompass = value 
				COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.treasure)
			end,
		},
        [3] = {
            type = "dropdown",
            name = strings.TREASURE_ICON,
            tooltip = strings.TREASURE_ICON_TOOLTIP,
            choices = pinTexturesList,
            getFunc = function() return pinTexturesList[LT.SavedVariables.treasurePinTexture] end,
            setFunc = function(value) 
                for i,v in pairs(pinTexturesList) do
                    if v == value then
                        LT.SavedVariables.treasurePinTexture = i
                        treasureMapIcon:SetTexture(pinTextures[i])
                        LMP:SetLayoutKey(MAP_PIN_TYPES.treasure, "texture", pinTextures[i])
						LMP:RefreshPins(MAP_PIN_TYPES.treasure)
						COMPASS_PINS.pinLayouts[COMPASS_PIN_TYPES.treasure].texture = pinTextures[i]
						COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.treasure)
						break
                    end
                end
            end,
			reference = "LT_TreasureMapOption",
			disabled = function() return not LT.SavedVariables.showTreasure and not LT.SavedVariables.showTreasureCompass end,
        },
        [4] = {
            type = "dropdown",
            name = strings.TREASURE_MARK_WHICH,
            tooltip = strings.TREASURE_MARK_WHICH_TOOLTIP,
            choices = markMapMenuOptions,
            getFunc = function() return markMapMenuOptions[LT.SavedVariables.treasureMarkMapMenuOption] end,
            setFunc = function(value) 
                for i,v in pairs(markMapMenuOptions) do
                    if v == value then
                        LT.SavedVariables.treasureMarkMapMenuOption = i
                        LMP:RefreshPins(MAP_PIN_TYPES.treasure)
			COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.treasure)
		    else
			if LT.dirtyPins[i] then LT.dirtyPins[i].treasure = nil end
                    end
                end
            end,
            disabled = function() return not LT.SavedVariables.showTreasure and not LT.SavedVariables.showTreasureCompass end,
        },

		[5] = {
			type = "checkbox",
			name = strings.SURVEYS_ON_MAP,
			tooltip = strings.SURVEYS_ON_MAP_TOOLTIP,
			getFunc = function() return LT.SavedVariables.showSurveys end,
			setFunc = function(value) 
				LT.SavedVariables.showSurveys = value 
				LMP:SetEnabled(MAP_PIN_TYPES.surveys, value)
			end,
		},
		[6] = {
			type = "checkbox",
			name = strings.SURVEYS_ON_COMPASS,
			tooltip = strings.SURVEYS_ON_COMPASS_TOOLTIP,
			getFunc = function() return LT.SavedVariables.showSurveysCompass end,
			setFunc = function(value) 
				LT.SavedVariables.showSurveysCompass = value 
				COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.surveys)
			end,
		},
        [7] = {
            type = "dropdown",
            name = strings.SURVEYS_ICON,
            tooltip = strings.SURVEYS_ICON_TOOLTIP,
            choices = pinTexturesList,
            getFunc = function() return pinTexturesList[LT.SavedVariables.surveysPinTexture] end,
            setFunc = function(value) 
                for i,v in pairs(pinTexturesList) do
                    if v == value then
                        LT.SavedVariables.surveysPinTexture = i
                        surveysMapIcon:SetTexture(pinTextures[i])
                        LMP:SetLayoutKey(MAP_PIN_TYPES.surveys, "texture", pinTextures[i])
						LMP:RefreshPins(MAP_PIN_TYPES.surveys)
						COMPASS_PINS.pinLayouts[COMPASS_PIN_TYPES.surveys].texture = pinTextures[i]
						COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.surveys)
						break
                    end
                end
            end,
			reference = "LT_SurveysMapOption",
			disabled = function() return not LT.SavedVariables.showSurveys and not LT.SavedVariables.showSurveysCompass end,
        },
        [8] = {
            type = "dropdown",
            name = strings.SURVEYS_MARK_WHICH,
            tooltip = strings.SURVEYS_MARK_WHICH_TOOLTIP,
            choices = markMapMenuOptions,
            getFunc = function() return markMapMenuOptions[LT.SavedVariables.surveysMarkMapMenuOption] end,
            setFunc = function(value) 
                for i,v in pairs(markMapMenuOptions) do
                    if v == value then
                        LT.SavedVariables.surveysMarkMapMenuOption = i
                        LMP:RefreshPins(MAP_PIN_TYPES.surveys)
						COMPASS_PINS:RefreshPins(COMPASS_PIN_TYPES.surveys)
					else
						if LT.dirtyPins[i] then LT.dirtyPins[i].surveys = nil end
                    end
                end
            end,
			disabled = function() return not LT.SavedVariables.showSurveys and not LT.SavedVariables.showSurveysCompass end,
        },

        [9] = {
            type = "slider",
            name = strings.PIN_SIZE,
            tooltip = strings.PIN_SIZE_TOOLTIP,
            min = 12, 
            max = 48, 
            step = 2, 
            getFunc = function() return LT.SavedVariables.pinTextureSize end, 
            setFunc = function(value) 
                LT.SavedVariables.pinTextureSize = value
                LMP:SetLayoutKey(MAP_PIN_TYPES.treasure, "size", value)
				LMP:SetLayoutKey(MAP_PIN_TYPES.surveys, "size", value)
				LMP:RefreshPins(MAP_PIN_TYPES.treasure)
				LMP:RefreshPins(MAP_PIN_TYPES.surveys)
			end,
        },


        [10] = {
            type = "checkbox",
            name = strings.SHOW_MINIMAP,
            tooltip = strings.SHOW_MINIMAP_TOOLTIP,
            getFunc = function() return LT.SavedVariables.showMiniTreasureMap end,
            setFunc = function(value) LT.SavedVariables.showMiniTreasureMap = value end,
        },  
    }

    local myPanel = LAM2:RegisterAddonPanel(Addon.Name.."LAM2Options", panelData)
    LAM2:RegisterOptionControls(Addon.Name.."LAM2Options", optionsData)

    local SetupLAMMapIcon = function(control)
		if control ~= myPanel then return end
        if not treasureMapIcon then
            treasureMapIcon = WINDOW_MANAGER:CreateControl(nil, LT_TreasureMapOption, CT_TEXTURE)
            treasureMapIcon:SetAnchor(RIGHT, LT_TreasureMapOption.dropdown:GetControl(), LEFT, -10, 0)
            treasureMapIcon:SetTexture(pinTextures[LT.SavedVariables.treasurePinTexture])
            treasureMapIcon:SetDimensions(32, 32)
        end
        if not surveysMapIcon then
            surveysMapIcon = WINDOW_MANAGER:CreateControl(nil, LT_SurveysMapOption, CT_TEXTURE)
            surveysMapIcon:SetAnchor(RIGHT, LT_SurveysMapOption.dropdown:GetControl(), LEFT, -10, 0)
            surveysMapIcon:SetTexture(pinTextures[LT.SavedVariables.surveysPinTexture])
            surveysMapIcon:SetDimensions(32, 32)
        end
		CALLBACK_MANAGER:UnregisterCallback("LAM-PanelControlsCreated", SetupLAMMapIcon)
    end
    CALLBACK_MANAGER:RegisterCallback("LAM-PanelControlsCreated", SetupLAMMapIcon)
end

function LT:EVENT_ADD_ON_LOADED(event, name)
   	if name ~= Addon.Name then return end
	LT.SavedVariables = ZO_SavedVars:New("LOST_TREASURE_SV", 3, nil, LT.defaults)

	lang = GetCVar("Language.2")
	if lang == "de" then
		LOST_TREASURE_INDEX.MAP_NAME = LOST_TREASURE_INDEX.MAP_NAME_DE
	elseif lang == "fr" then
		LOST_TREASURE_INDEX.MAP_NAME = LOST_TREASURE_INDEX.MAP_NAME_FR
	else
		lang = "en"
		LOST_TREASURE_INDEX.MAP_NAME = LOST_TREASURE_INDEX.MAP_NAME_EN
	end

	createMiniTreasureMap()

   	EVENT_MANAGER:RegisterForEvent(Addon.Name, EVENT_SHOW_TREASURE_MAP, function(...) LT:EVENT_SHOW_TREASURE_MAP(...) end)

	SHARED_INVENTORY:RegisterCallback("SlotAdded", LT.SlotAdded, self)
	SHARED_INVENTORY:RegisterCallback("SlotRemoved", LT.SlotRemoved, self)

	pinLayout_Treasure.texture = pinTextures[LT.SavedVariables.treasurePinTexture]
	pinLayout_Treasure.size = LT.SavedVariables.pinTextureSize
	compassLayout_Treasure.texture = pinTextures[LT.SavedVariables.treasurePinTexture]
   	LMP:AddPinType(MAP_PIN_TYPES.treasure, function() pinCreator("treasure") end, nil, pinLayout_Treasure, pinTooltipCreator)
	LMP:AddPinFilter(MAP_PIN_TYPES.treasure, "Lost Treasure Maps", false, LT.SavedVariables, "showTreasure")
	COMPASS_PINS:AddCustomPin(COMPASS_PIN_TYPES.treasure, function() compassCallback("treasure") end, compassLayout_Treasure)

	pinLayout_Surveys.texture = pinTextures[LT.SavedVariables.surveysPinTexture]
	pinLayout_Surveys.size = LT.SavedVariables.pinTextureSize
	compassLayout_Surveys.texture = pinTextures[LT.SavedVariables.surveysPinTexture]
   	LMP:AddPinType(MAP_PIN_TYPES.surveys, function() pinCreator("surveys") end, nil, pinLayout_Surveys, pinTooltipCreator)
	LMP:AddPinFilter(MAP_PIN_TYPES.surveys, "Lost Treasure Survey Maps", false, LT.SavedVariables, "showSurveys")
	COMPASS_PINS:AddCustomPin(COMPASS_PIN_TYPES.surveys, function() compassCallback("surveys") end, compassLayout_Surveys)

	createLAM2Panel()

	EVENT_MANAGER:UnregisterForEvent(Addon.Name, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(Addon.Name, EVENT_ADD_ON_LOADED, function(...) LT:EVENT_ADD_ON_LOADED(...) end)
