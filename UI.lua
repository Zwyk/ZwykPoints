local _, FW = ...

-- The editor is created once, then refreshed in place. Unapplied weights stay in
-- the editor while cache updates or profile visibility changes refresh the UI.
local UI
local ROW_HEIGHT = 30
local unpack = unpack or table.unpack
local finite = function(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function setEnabled(control, enabled)
    if control.SetEnabled then
        control:SetEnabled(enabled)
    elseif enabled and control.Enable then
        control:Enable()
    elseif not enabled and control.Disable then
        control:Disable()
    end
end

local function backdrop(frame, color)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(unpack(color or { 0.055, 0.07, 0.095, 0.97 }))
    frame:SetBackdropBorderColor(0.25, 0.3, 0.38, 1)
end

local function panel(parent)
    local frame = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    backdrop(frame, { 0.035, 0.045, 0.065, 0.85 })
    return frame
end

local function label(parent, text, size, color)
    local font = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if size then font:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") end
    font:SetText(text or "")
    font:SetJustifyH("LEFT")
    font:SetJustifyV("MIDDLE")
    if color then font:SetTextColor(unpack(color)) end
    return font
end

local function button(parent, text, width, action)
    local frame = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    frame:SetSize(width or 90, 25)
    frame:SetText(text)
    if action then frame:SetScript("OnClick", action) end
    return frame
end

local function editBox(parent, width)
    local frame = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    frame:SetSize(width or 100, 24)
    frame:SetAutoFocus(false)
    frame:SetFontObject("GameFontHighlight")
    frame:SetTextInsets(4, 4, 0, 0)
    frame:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return frame
end

local function hint(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if text then GameTooltip:AddLine(text, 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function status(text, kind)
    if not UI then return end
    UI.status:SetText(text or "")
    if kind == "error" then
        UI.status:SetTextColor(1, 0.36, 0.3)
    elseif kind == "success" then
        UI.status:SetTextColor(0.42, 0.9, 0.59)
    else
        UI.status:SetTextColor(0.64, 0.78, 0.96)
    end
end

local function profiles()
    return FW:GetProfiles(false) or {}
end

local function selectedProfile()
    if not UI or not UI.selectedID then return nil end
    for _, profile in ipairs(profiles()) do
        if profile.id == UI.selectedID then return profile end
    end
end

local function hexColor(color)
    color = color or {}
    local function channel(value)
        return math.floor(math.max(0, math.min(1, tonumber(value) or 1)) * 255 + 0.5)
    end
    return string.format("#%02X%02X%02X", channel(color.r), channel(color.g), channel(color.b))
end

local function parseColor(text)
    local value = trim(text):gsub("^#", "")
    if not value:match("^%x%x%x%x%x%x$") then return nil end
    return {
        r = tonumber(value:sub(1, 2), 16) / 255,
        g = tonumber(value:sub(3, 4), 16) / 255,
        b = tonumber(value:sub(5, 6), 16) / 255,
    }
end

local function previewColor(color)
    if not UI then return end
    color = color or { r = 1, g = 1, b = 1 }
    UI.colorSwatch:SetColorTexture(color.r, color.g, color.b, 1)
end

local function updateUnitHelp(profile)
    local rating = profile and profile.secondaryUnit == "rating"
    UI.percent:SetChecked(not rating)
    UI.rating:SetChecked(rating)
    if rating then
        UI.unitHelp:SetText("Rating mode: hit, crit, haste, expertise, dodge, parry, block and defense use weights per 1 rating.")
    else
        UI.unitHelp:SetText("Percent mode: hit, crit, haste, expertise, dodge, parry and block use weights per 1 percentage point (1% = 1). Defense uses skill points.")
    end
end

local function refreshEditor(force)
    local profile = selectedProfile()
    local enabled = profile ~= nil
    for _, control in ipairs(UI.profileControls) do
        setEnabled(control, enabled)
    end
    UI.copy:SetEnabled(enabled)
    UI.delete:SetEnabled(enabled)
    UI.export:SetEnabled(enabled)
    UI.exportWeights:SetEnabled(enabled)
    UI.loading = true
    if profile then
        if force or not UI.dirtyName then UI.name:SetText(profile.name or "") end
        if force or not UI.dirtyColor then UI.color:SetText(hexColor(profile.color)) end
        UI.active:SetChecked(profile.active and true or false)
        previewColor(parseColor(UI.color:GetText()) or profile.color)
        updateUnitHelp(profile)
        for _, field in ipairs(UI.fields) do
            setEnabled(field.box, true)
            if force or not UI.dirtyWeights then
                field.box:SetText(tostring((profile.weights or {})[field.key] or 0))
            end
        end
        UI.editorTitle:SetText("Weights for " .. (profile.name or "profile"))
    else
        UI.name:SetText("")
        UI.color:SetText("#FFFFFF")
        UI.active:SetChecked(false)
        previewColor()
        updateUnitHelp(nil)
        for _, field in ipairs(UI.fields) do
            field.box:SetText("0")
            setEnabled(field.box, false)
        end
        UI.editorTitle:SetText("Create a profile to set weights")
    end
    if force then
        UI.dirtyName, UI.dirtyColor, UI.dirtyWeights = false, false, false
    end
    UI.weightState:SetText(UI.dirtyWeights and "Unsaved weights" or "Weights saved")
    UI.weightState:SetTextColor(UI.dirtyWeights and 1 or 0.6, UI.dirtyWeights and 0.78 or 0.72, UI.dirtyWeights and 0.35 or 0.64)
    UI.loading = false
end

local function commit(changes, clearDraft, success)
    local profile = selectedProfile()
    if not profile then return false end
    UI.committing = true
    local ok, err = FW:UpdateProfile(profile.id, changes)
    UI.committing = false
    if not ok then
        status(err or "Could not save this profile.", "error")
        FW:RefreshUI()
        return false
    end
    if clearDraft == "name" then UI.dirtyName = false end
    if clearDraft == "color" then UI.dirtyColor = false end
    if clearDraft == "weights" then UI.dirtyWeights = false end
    FW:RefreshUI()
    status(success or "Profile saved.", "success")
    return true
end

local function applyWeights()
    if not selectedProfile() then return end
    local weights = {}
    for _, field in ipairs(UI.fields) do
        local text = trim(field.box:GetText())
        local value = text == "" and 0 or tonumber(text)
        if not finite(value) then
            status("Enter a finite number for " .. field.label .. ".", "error")
            field.box:SetFocus()
            field.box:HighlightText()
            return
        end
        weights[field.key] = value
    end
    commit({ weights = weights }, "weights", "Weights saved. Cached scores will use the updated weights.")
end

local function selectProfile(id, reveal)
    UI.selectedID = id
    UI.revealSelected = reveal
    refreshEditor(true)
    FW:RefreshUI()
    status("", nil)
end

local function uniqueName(base)
    local names = {}
    for _, profile in ipairs(profiles()) do names[profile.name] = true end
    if not names[base] then return base end
    local index = 2
    while names[base .. " " .. index] do index = index + 1 end
    return base .. " " .. index
end

local function newProfile()
    UI.committing = true
    local profile, err = FW:CreateProfile(uniqueName("New profile"), {})
    UI.committing = false
    if not profile then status(err or "Could not create a profile.", "error") return end
    selectProfile(profile.id, true)
    UI.name:SetFocus()
    UI.name:HighlightText()
    status("Name this profile, enter weights, then apply them.")
end

local function copyProfile()
    local profile = selectedProfile()
    if not profile then return end
    UI.committing = true
    local copy, err = FW:CopyProfile(profile.id)
    UI.committing = false
    if not copy then status(err or "Could not copy the profile.", "error") return end
    selectProfile(copy.id, true)
    status("Profile copied.", "success")
end

local function deleteProfile(id)
    UI.committing = true
    local ok, err = FW:DeleteProfile(id)
    UI.committing = false
    if not ok then status(err or "Could not delete the profile.", "error") return end
    local remaining = profiles()
    selectProfile(remaining[1] and remaining[1].id, true)
    status("Profile deleted.", "success")
end

local function confirmDelete()
    local profile = selectedProfile()
    if not profile then return end
    if not StaticPopupDialogs or not StaticPopup_Show then
        status("The game's confirmation dialog is unavailable.", "error")
        return
    end
    StaticPopupDialogs.ZWYKVALUES_DELETE_PROFILE = StaticPopupDialogs.ZWYKVALUES_DELETE_PROFILE or {
        text = 'Delete weight profile "%s"?',
        button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
        OnAccept = function(_, data)
            if data and data.profileID then deleteProfile(data.profileID) end
        end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
    }
    StaticPopup_Show("ZWYKVALUES_DELETE_PROFILE", profile.name, nil, { profileID = profile.id })
end

local function createJSONDialog()
    local dialog = panel(UI.frame)
    UI.dialog = dialog
    dialog:SetSize(740, 470)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("DIALOG")
    dialog:SetFrameLevel(UI.frame:GetFrameLevel() + 20)
    dialog:EnableMouse(true)
    backdrop(dialog, { 0.055, 0.065, 0.09, 1 })
    dialog.title = label(dialog, "", 17, { 1, 0.82, 0 })
    dialog.title:SetPoint("TOPLEFT", 18, -17)
    dialog.help = label(dialog, "", 11, { 0.79, 0.84, 0.91 })
    dialog.help:SetPoint("TOPLEFT", 18, -47)
    dialog.help:SetPoint("TOPRIGHT", -18, -47)
    dialog.help:SetHeight(30)
    dialog.help:SetJustifyV("TOP")
    dialog.nameLabel = label(dialog, "Profile name:", 11)
    dialog.nameLabel:SetPoint("TOPLEFT", 18, -86)
    dialog.name = editBox(dialog, 260)
    dialog.name:SetPoint("TOPLEFT", 112, -79)
    local inset = panel(dialog)
    inset:SetPoint("TOPLEFT", 16, -112)
    inset:SetPoint("BOTTOMRIGHT", -16, 66)
    dialog.scroll = CreateFrame("ScrollFrame", "ZwykValuesJSONScroll", inset, "UIPanelScrollFrameTemplate")
    dialog.scroll:SetPoint("TOPLEFT", 8, -8)
    dialog.scroll:SetPoint("BOTTOMRIGHT", -29, 8)
    dialog.text = CreateFrame("EditBox", nil, dialog.scroll)
    dialog.text:SetMultiLine(true)
    dialog.text:SetAutoFocus(false)
    dialog.text:SetMaxLetters(131072)
    dialog.text:SetFontObject("ChatFontNormal")
    dialog.text:SetTextInsets(3, 3, 3, 3)
    dialog.text:SetWidth(665)
    dialog.text:SetHeight(270)
    dialog.scroll:SetScrollChild(dialog.text)
    dialog.text:SetScript("OnEscapePressed", function(self) self:ClearFocus() dialog:Hide() end)
    dialog.text:SetScript("OnTextChanged", function(self)
        local lineHeight = 14
        if self.GetFont then
            local _, height = self:GetFont()
            lineHeight = (height or 12) + 2
        end
        local count = self.GetNumLines and self:GetNumLines() or 20
        self:SetHeight(math.max(dialog.scroll:GetHeight(), count * lineHeight + 16))
        dialog.scroll:UpdateScrollChildRect()
    end)
    dialog.text:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local scroll = dialog.scroll:GetVerticalScroll()
        local position = -y
        if position < scroll then
            dialog.scroll:SetVerticalScroll(math.max(0, position))
        elseif position + height > scroll + dialog.scroll:GetHeight() then
            dialog.scroll:SetVerticalScroll(position + height - dialog.scroll:GetHeight())
        end
    end)
    dialog.message = label(dialog, "", 11, { 1, 0.42, 0.34 })
    dialog.message:SetPoint("BOTTOMLEFT", 18, 42)
    dialog.message:SetWidth(680)
    dialog.message:SetHeight(17)
    dialog.close = button(dialog, "Close", 90, function() dialog:Hide() end)
    dialog.close:SetPoint("BOTTOMRIGHT", -18, 12)
    dialog.import = button(dialog, "Import profile", 120, function()
        UI.committing = true
        local profile, err, warnings = FW:ImportProfile(dialog.text:GetText(), trim(dialog.name:GetText()))
        UI.committing = false
        if not profile then
            dialog.message:SetText(err or "Could not import this JSON.")
            return
        end
        dialog:Hide()
        selectProfile(profile.id, true)
        local message = "Imported " .. profile.name .. "."
        if type(warnings) == "table" and #warnings > 0 then
            message = message .. " " .. table.concat(warnings, " ")
        elseif type(warnings) == "string" and warnings ~= "" then
            message = message .. " " .. warnings
        end
        status(message, "success")
    end)
    dialog.import:SetPoint("RIGHT", dialog.close, "LEFT", -8, 0)
    dialog.selectAll = button(dialog, "Select all", 90, function()
        dialog.text:SetFocus()
        dialog.text:HighlightText()
    end)
    dialog.selectAll:SetPoint("BOTTOMLEFT", 18, 12)
    dialog:SetScript("OnHide", function()
        dialog.text:ClearFocus()
        dialog.name:ClearFocus()
    end)
    dialog:Hide()
end

local function showJSON(mode)
    if not UI.dialog then createJSONDialog() end
    local dialog = UI.dialog
    dialog.text:SetMaxLetters(131072)
    dialog.mode = mode
    dialog.message:SetText("")
    if mode == "import" then
        dialog.title:SetText("Import a weight profile")
        dialog.help:SetText("Paste a Sixty Upgrades weights object, a ZwykValues profile, or a legacy ZwykPoints/ForeverWeights profile. A bare weights object uses percent mode; choose its unit after importing.")
        dialog.nameLabel:Show()
        dialog.name:Show()
        dialog.name:SetText(uniqueName("Imported profile"))
        dialog.import:Show()
        dialog.text:SetText("")
    else
        local profile = selectedProfile()
        if not profile then return end
        local text, err = FW:ExportProfile(profile.id, mode == "weights")
        if not text then status(err or "Could not export this profile.", "error") return end
        dialog.title:SetText(mode == "weights" and "Export weights only" or "Export a weight profile")
        dialog.help:SetText(mode == "weights"
            and "Sixty Upgrades compatible keys. The weights-only JSON does not include this profile's name, color, visibility or unit. Press Ctrl+C to copy."
            or "Includes all weights, name, color and stat units. Press Ctrl+C to copy this profile, then import it on another character or account.")
        dialog.nameLabel:Hide()
        dialog.name:Hide()
        dialog.import:Hide()
        dialog.text:SetText(text)
    end
    dialog:Show()
    dialog.scroll:SetVerticalScroll(0)
    dialog.text:SetFocus()
    if mode ~= "import" then dialog.text:HighlightText() end
end

local statHints = {
    hit = "The unified hit stat. Use a weight per 1 percentage point in percent mode, or per 1 rating in rating mode.",
    crit = "The unified critical strike stat. Use a weight per 1 percentage point in percent mode, or per 1 rating in rating mode.",
    haste = "Use a weight per 1 percentage point in percent mode, or per 1 rating in rating mode.",
    expertise = "Use a weight per 1 percentage point of reduced dodge/parry chance in percent mode, or per 1 rating in rating mode.",
    dps = "Melee weapon damage per second. It is scored separately from damage and weapon speed weights.",
    rangedDps = "Ranged weapon damage per second.",
    lowDamage = "The weapon's minimum damage. Combining multiple damage weights intentionally adds each contribution.",
    highDamage = "The weapon's maximum damage. Combining multiple damage weights intentionally adds each contribution.",
    weaponDamage = "Average weapon damage, (minimum + maximum) / 2. Combining this with DPS weights adds both contributions.",
    speed = "Melee weapon speed in seconds. Negative weights can favor faster weapons.",
    rangedSpeed = "Ranged weapon speed in seconds.",
    armor = "The item's base armor. Bonus armor is tracked separately.",
    armorBonus = "Extra armor beyond base armor.",
    blockValue = "Base shield block value. Bonus block value is tracked separately.",
    blockValueBonus = "Additional block value from item stats.",
    feralAttackPower = "Attack power that applies specifically in feral forms; it has its own weight.",
}

local function buildWeightFields()
    UI.fields, UI.fieldGroups = {}, {}
    local groups = {}
    for _, definition in ipairs(FW.StatDefinitions or {}) do
        local groupName = definition.group or "Stats"
        if type(groupName) ~= "string" then groupName = tostring(groupName) end
        local group = groups[groupName]
        if not group then
            group = { name = groupName, fields = {} }
            group.heading = label(UI.weightContent, groupName, 12, { 0.95, 0.79, 0.42 })
            groups[groupName] = group
            UI.fieldGroups[#UI.fieldGroups + 1] = group
        end
        local field = { key = definition.key, label = definition.label or definition.key }
        field.frame = CreateFrame("Frame", nil, UI.weightContent)
        field.frame:SetHeight(ROW_HEIGHT)
        field.text = label(field.frame, field.label, 11, { 0.85, 0.89, 0.94 })
        field.text:SetPoint("LEFT", 0, 0)
        field.text:SetHeight(26)
        field.text:SetWordWrap(false)
        field.box = editBox(field.frame, 86)
        field.box:SetPoint("RIGHT", -4, 0)
        field.box:SetJustifyH("RIGHT")
        field.box:SetMaxLetters(30)
        field.box:SetScript("OnTextChanged", function(_, userInput)
            if UI.loading or not userInput then return end
            UI.dirtyWeights = true
            UI.weightState:SetText("Unsaved weights")
            UI.weightState:SetTextColor(1, 0.78, 0.35)
            status("Unsaved weights. Apply weights to update item scores.")
        end)
        field.box:SetScript("OnEnterPressed", function(self) self:ClearFocus() applyWeights() end)
        hint(field.box, field.label, (statHints[field.key] or "Weight per 1 unit of this stat. Zero ignores it. Negative and decimal weights are allowed.") .. "\nImport/export key: " .. field.key)
        UI.fields[#UI.fields + 1] = field
        group.fields[#group.fields + 1] = field
    end
    for index, field in ipairs(UI.fields) do
        field.box:SetScript("OnTabPressed", function(self)
            local nextIndex = IsShiftKeyDown() and index - 1 or index + 1
            if nextIndex < 1 then nextIndex = #UI.fields end
            if nextIndex > #UI.fields then nextIndex = 1 end
            self:ClearFocus()
            local nextField = UI.fields[nextIndex]
            if nextField then
                nextField.box:SetFocus()
                nextField.box:HighlightText()
                local _, _, _, _, y = nextField.frame:GetPoint()
                local scroll = UI.weightsScroll:GetVerticalScroll()
                local position = -(y or 0)
                if position < scroll or position + ROW_HEIGHT > scroll + UI.weightsScroll:GetHeight() then
                    UI.weightsScroll:SetVerticalScroll(math.max(0, math.min(position, UI.weightsScroll:GetVerticalScrollRange())))
                end
            end
        end)
    end
end

local function layoutWeights()
    if not UI or not UI.weightContent then return end
    local width = math.max(200, UI.weightsScroll:GetWidth())
    UI.weightContent:SetWidth(width)
    local columns = width >= 470 and 2 or 1
    local gap = 20
    local columnWidth = (width - gap * (columns - 1) - 8) / columns
    local y = 2
    for _, group in ipairs(UI.fieldGroups) do
        group.heading:ClearAllPoints()
        group.heading:SetPoint("TOPLEFT", 3, -y)
        group.heading:SetWidth(width - 8)
        group.heading:SetHeight(20)
        y = y + 24
        for index, field in ipairs(group.fields) do
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            field.frame:ClearAllPoints()
            field.frame:SetPoint("TOPLEFT", column * (columnWidth + gap) + 4, -(y + row * ROW_HEIGHT))
            field.frame:SetWidth(columnWidth)
            field.text:SetWidth(math.max(50, columnWidth - 100))
        end
        y = y + math.ceil(#group.fields / columns) * ROW_HEIGHT + 9
    end
    UI.weightContent:SetHeight(math.max(y + 8, UI.weightsScroll:GetHeight()))
    UI.weightsScroll:UpdateScrollChildRect()
end

local function createProfileRow(index)
    local row = CreateFrame("Button", nil, UI.profileContent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_HEIGHT)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints()
    row.highlight:SetColorTexture(0.17, 0.25, 0.37, 0.9)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.active = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    row.active:SetSize(25, 25)
    row.active:SetPoint("LEFT", 0, 0)
    row.active:SetScript("OnClick", function(self)
        if not row.profileID then return end
        UI.committing = true
        local ok, err = FW:UpdateProfile(row.profileID, { active = self:GetChecked() and true or false })
        UI.committing = false
        FW:RefreshUI()
        if not ok then status(err or "Could not update profile visibility.", "error") end
    end)
    hint(row.active, "Show this profile", "Active profiles appear in item tooltips and item comparisons.")
    row.name = label(row, "", 12)
    row.name:SetPoint("LEFT", 29, 0)
    row.name:SetPoint("RIGHT", -5, 0)
    row.name:SetHeight(26)
    row.name:SetWordWrap(false)
    row:SetScript("OnClick", function() selectProfile(row.profileID, false) end)
    row:SetScript("OnEnter", function(self)
        if row.profileName then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(row.profileName, 1, 1, 1)
            GameTooltip:AddLine(row.isActive and "Active in tooltips" or "Inactive in tooltips", 0.7, 0.8, 0.9)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.rows[index] = row
    return row
end

local function createUI()
    UI = { rows = {}, fields = {}, profileControls = {} }
    local frame = CreateFrame("Frame", "ZwykValuesFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    UI.frame = frame
    FW.UI = frame
    frame:SetSize(930, 720)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(850, 600, 1400, 1100)
    elseif frame.SetMinResize then frame:SetMinResize(850, 600) end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    backdrop(frame)
    label(frame, "ZwykValues", 21, { 1, 0.82, 0.35 }):SetPoint("TOPLEFT", 21, -19)
    label(frame, "Item scores from your own stat weights", 12, { 0.69, 0.77, 0.87 }):SetPoint("TOPLEFT", 22, -46)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -3, -3)
    close:SetScript("OnClick", function() frame:Hide() end)
    local resize = CreateFrame("Button", nil, frame)
    resize:SetSize(18, 18)
    resize:SetPoint("BOTTOMRIGHT", -3, 3)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function(_, mouseButton) if mouseButton == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end end)
    resize:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "ZwykValuesFrame") end

    UI.left = panel(frame)
    UI.left:SetPoint("TOPLEFT", 18, -71)
    UI.left:SetPoint("BOTTOMLEFT", 18, 90)
    UI.left:SetWidth(220)
    label(UI.left, "Profiles", 13, { 1, 0.82, 0.35 }):SetPoint("TOPLEFT", 12, -13)
    UI.profileScroll = CreateFrame("ScrollFrame", "ZwykValuesProfilesScroll", UI.left, "UIPanelScrollFrameTemplate")
    UI.profileScroll:SetPoint("TOPLEFT", 9, -38)
    UI.profileScroll:SetPoint("BOTTOMRIGHT", -30, 47)
    UI.profileContent = CreateFrame("Frame", nil, UI.profileScroll)
    UI.profileContent:SetSize(179, 1)
    UI.profileScroll:SetScrollChild(UI.profileContent)
    UI.new = button(UI.left, "New", 61, newProfile)
    UI.new:SetPoint("BOTTOMLEFT", 10, 12)
    UI.copy = button(UI.left, "Copy", 61, copyProfile)
    UI.copy:SetPoint("LEFT", UI.new, "RIGHT", 7, 0)
    UI.delete = button(UI.left, "Delete", 61, confirmDelete)
    UI.delete:SetPoint("LEFT", UI.copy, "RIGHT", 7, 0)

    UI.right = panel(frame)
    UI.right:SetPoint("TOPLEFT", 250, -71)
    UI.right:SetPoint("BOTTOMRIGHT", -18, 90)
    label(UI.right, "Profile name", 11, { 0.76, 0.82, 0.9 }):SetPoint("TOPLEFT", 15, -12)
    UI.name = editBox(UI.right, 315)
    UI.name:SetPoint("TOPLEFT", 17, -30)
    UI.name:SetPoint("TOPRIGHT", -122, -30)
    UI.name:SetMaxLetters(80)
    UI.name:SetScript("OnTextChanged", function(_, userInput)
        if not UI.loading and userInput then UI.dirtyName = true end
    end)
    local function rename()
        commit({ name = trim(UI.name:GetText()) }, "name", "Profile renamed.")
    end
    UI.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() rename() end)
    UI.rename = button(UI.right, "Rename", 90, rename)
    UI.rename:SetPoint("TOPRIGHT", -15, -29)
    UI.active = CreateFrame("CheckButton", nil, UI.right, "UICheckButtonTemplate")
    UI.active:SetSize(27, 27)
    UI.active:SetPoint("TOPLEFT", 9, -61)
    label(UI.active, "Active in tooltips", 11, { 0.88, 0.91, 0.96 }):SetPoint("LEFT", UI.active, "RIGHT", 1, 0)
    UI.active:SetScript("OnClick", function(self)
        commit({ active = self:GetChecked() and true or false }, nil, "Tooltip visibility updated.")
    end)
    hint(UI.active, "Active profile", "Each active profile adds a score and comparison to item tooltips, in its chosen color.")
    label(UI.right, "Color", 11, { 0.76, 0.82, 0.9 }):SetPoint("TOPLEFT", 198, -69)
    UI.color = editBox(UI.right, 85)
    UI.color:SetPoint("TOPLEFT", 245, -61)
    UI.color:SetMaxLetters(7)
    UI.color:SetScript("OnTextChanged", function(self, userInput)
        if not UI.loading and userInput then
            UI.dirtyColor = true
            local color = parseColor(self:GetText())
            if color then previewColor(color) end
        end
    end)
    local function setColor()
        local color = parseColor(UI.color:GetText())
        if not color then status("Enter a color as #RRGGBB, such as #66CCFF.", "error") return end
        commit({ color = color }, "color", "Tooltip color saved.")
    end
    UI.color:SetScript("OnEnterPressed", function(self) self:ClearFocus() setColor() end)
    UI.colorButton = button(UI.right, "Set color", 85, setColor)
    UI.colorButton:SetPoint("LEFT", UI.color, "RIGHT", 12, 0)
    UI.colorSwatch = UI.right:CreateTexture(nil, "ARTWORK")
    UI.colorSwatch:SetSize(19, 19)
    UI.colorSwatch:SetPoint("LEFT", UI.colorButton, "RIGHT", 10, 0)
    hint(UI.color, "Tooltip color", "Enter a six-digit hexadecimal color, for example #66CCFF. Click Set color to save it.")

    label(UI.right, "Secondary units", 11, { 0.76, 0.82, 0.9 }):SetPoint("TOPLEFT", 15, -106)
    local function unitButton(text, x, unit)
        local control = CreateFrame("CheckButton", nil, UI.right, "UICheckButtonTemplate")
        control:SetSize(25, 25)
        control:SetPoint("TOPLEFT", x, -98)
        label(control, text, 11, { 0.88, 0.91, 0.96 }):SetPoint("LEFT", control, "RIGHT", 1, 0)
        control:SetScript("OnClick", function()
            commit({ secondaryUnit = unit }, nil, "Secondary stat units saved. Check that your weights use the chosen unit.")
        end)
        return control
    end
    UI.percent = unitButton("Percent / skill", 132, "percent")
    UI.rating = unitButton("Rating", 276, "rating")
    UI.unitHelp = label(UI.right, "", 10, { 0.65, 0.74, 0.85 })
    UI.unitHelp:SetPoint("TOPLEFT", 15, -129)
    UI.unitHelp:SetPoint("TOPRIGHT", -15, -129)
    UI.unitHelp:SetHeight(28)
    UI.unitHelp:SetJustifyV("TOP")
    UI.editorTitle = label(UI.right, "Weights", 12, { 1, 0.82, 0.35 })
    UI.editorTitle:SetPoint("TOPLEFT", 15, -165)
    UI.editorTitle:SetPoint("TOPRIGHT", -15, -165)
    UI.editorTitle:SetHeight(20)
    UI.weightsScroll = CreateFrame("ScrollFrame", "ZwykValuesStatsScroll", UI.right, "UIPanelScrollFrameTemplate")
    UI.weightsScroll:SetPoint("TOPLEFT", 12, -193)
    UI.weightsScroll:SetPoint("BOTTOMRIGHT", -33, 51)
    UI.weightContent = CreateFrame("Frame", nil, UI.weightsScroll)
    UI.weightContent:SetSize(610, 1)
    UI.weightsScroll:SetScrollChild(UI.weightContent)
    UI.weightState = label(UI.right, "Weights saved", 11, { 0.6, 0.72, 0.64 })
    UI.weightState:SetPoint("BOTTOMLEFT", 15, 22)
    UI.apply = button(UI.right, "Apply weights", 120, applyWeights)
    UI.apply:SetPoint("BOTTOMRIGHT", -15, 14)
    UI.import = button(UI.right, "Import", 70, function() showJSON("import") end)
    UI.import:SetPoint("RIGHT", UI.apply, "LEFT", -8, 0)
    UI.export = button(UI.right, "Export", 70, function() showJSON("profile") end)
    UI.export:SetPoint("RIGHT", UI.import, "LEFT", -6, 0)
    UI.exportWeights = button(UI.right, "Weights JSON", 104, function() showJSON("weights") end)
    UI.exportWeights:SetPoint("RIGHT", UI.export, "LEFT", -6, 0)
    hint(UI.export, "Export profile", "Exports the saved profile with its name, color and units. Apply edited weights before exporting.")
    hint(UI.exportWeights, "Export weights", "Exports the saved weights using Sixty Upgrades keys. Name, color and unit metadata are omitted.")
    UI.profileControls = { UI.name, UI.rename, UI.active, UI.color, UI.colorButton, UI.percent, UI.rating, UI.apply }
    buildWeightFields()

    local note = label(frame, "Fixed weights ignore caps, procs, sets and rotations.", 10, { 0.66, 0.71, 0.79 })
    note:SetPoint("BOTTOMLEFT", 21, 73)
    note:SetWidth(305)
    local function option(text, x, key, default)
        local control = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        control:SetSize(24, 24)
        control:SetPoint("BOTTOMLEFT", x, 65)
        label(control, text, 10, { 0.76, 0.82, 0.9 }):SetPoint("LEFT", control, "RIGHT", 0, 0)
        control:SetScript("OnClick", function(self)
            FW.DB.options = FW.DB.options or {}
            FW.DB.options[key] = self:GetChecked() and true or false
            if FW.RefreshTooltips then FW:RefreshTooltips() end
        end)
        control.optionKey, control.default = key, default
        return control
    end
    UI.debugUnknown = option("Mark unrecognized stats", 340, "debugUnknownStats", false)
    UI.comparisons = option("Show upgrade comparisons", 590, "showComparisons", true)
    hint(UI.debugUnknown, "Unrecognized stat diagnostics", "Adds [ZV ?] next to unrecognized stat lines. Partial-data warnings and the issue log are available even when this option is off.")
    hint(UI.comparisons, "Item comparisons", "Show the flat score change and percentage upgrade or downgrade against equipped items for every active profile.")
    UI.status = label(frame, "", 11)
    UI.status:SetPoint("BOTTOMLEFT", 21, 44)
    UI.status:SetPoint("BOTTOMRIGHT", -21, 44)
    UI.status:SetHeight(27)
    UI.status:SetJustifyV("TOP")
    UI.cache = label(frame, "", 11, { 0.67, 0.75, 0.84 })
    UI.cache:SetPoint("BOTTOMLEFT", 21, 20)
    UI.clearCache = button(frame, "Clear cache", 105, function()
        FW:InvalidateCache()
        FW:RefreshUI()
        status("Item cache cleared. Scores will be rebuilt as items are inspected.", "success")
    end)
    UI.clearCache:SetPoint("BOTTOMRIGHT", -29, 13)
    hint(UI.clearCache, "Clear local item cache", "Discards cached item stats and scores. Profiles and their weights are kept.")
    UI.exportIssues = button(frame, "Export issues", 110, function() FW:ExportItemIssues() end)
    UI.exportIssues:SetPoint("RIGHT", UI.clearCache, "LEFT", -8, 0)
    hint(UI.exportIssues, "Export item diagnostics", "Copies JSON for every encountered item variant with parsing or stat-unit issues, including raw stats, tooltip lines and known scores. The log is saved between sessions. /zv clearissues resets it.")
    frame:SetScript("OnSizeChanged", function()
        UI.profileContent:SetWidth(math.max(100, UI.profileScroll:GetWidth()))
        layoutWeights()
    end)
    frame:SetScript("OnHide", function()
        if UI.dialog then UI.dialog:Hide() end
        UI.name:ClearFocus()
        UI.color:ClearFocus()
        for _, field in ipairs(UI.fields) do field.box:ClearFocus() end
    end)
    frame:SetScript("OnShow", function() FW:RefreshUI() layoutWeights() end)
    local existing = profiles()
    UI.selectedID = existing[1] and existing[1].id
    refreshEditor(true)
    layoutWeights()
    frame:Hide()
end

function FW:RefreshUI()
    if not UI or UI.committing then return end
    local all = profiles()
    if not selectedProfile() then
        UI.selectedID = all[1] and all[1].id
        refreshEditor(true)
    else
        refreshEditor(false)
    end
    local currentScroll = UI.profileScroll:GetVerticalScroll()
    local selectedIndex
    for index, profile in ipairs(all) do
        local row = UI.rows[index] or createProfileRow(index)
        row.profileID, row.profileName, row.isActive = profile.id, profile.name, profile.active
        row.name:SetText(profile.name)
        local color = profile.color or { r = 1, g = 1, b = 1 }
        row.name:SetTextColor(color.r, color.g, color.b)
        row.active:SetChecked(profile.active and true or false)
        row.highlight:SetShown(profile.id == UI.selectedID)
        if profile.id == UI.selectedID then selectedIndex = index end
        row:Show()
    end
    for index = #all + 1, #UI.rows do UI.rows[index]:Hide() end
    UI.profileContent:SetWidth(math.max(100, UI.profileScroll:GetWidth()))
    UI.profileContent:SetHeight(math.max(1, #all * ROW_HEIGHT, UI.profileScroll:GetHeight()))
    UI.profileScroll:UpdateScrollChildRect()
    local maxScroll = math.max(0, UI.profileContent:GetHeight() - UI.profileScroll:GetHeight())
    currentScroll = math.min(currentScroll, maxScroll)
    if UI.revealSelected and selectedIndex then
        local top = (selectedIndex - 1) * ROW_HEIGHT
        if top < currentScroll then currentScroll = top end
        if top + ROW_HEIGHT > currentScroll + UI.profileScroll:GetHeight() then
            currentScroll = math.min(maxScroll, top + ROW_HEIGHT - UI.profileScroll:GetHeight())
        end
    end
    UI.revealSelected = false
    UI.profileScroll:SetVerticalScroll(math.max(0, currentScroll))
    local count = 0
    if self.GetCacheCount then
        count = self:GetCacheCount() or 0
    elseif self.DB and self.DB.cache and self.DB.cache.items then
        for _ in pairs(self.DB.cache.items) do count = count + 1 end
    end
    UI.cache:SetText(string.format("Cached items: %d  |  Profiles: %d", count, #all))
    local options = self.DB and self.DB.options or {}
    for _, control in ipairs({ UI.debugUnknown, UI.comparisons }) do
        local value = options[control.optionKey]
        if value == nil then value = control.default end
        control:SetChecked(value and true or false)
    end
end

function FW:ToggleUI()
    if not UI then createUI() end
    if UI.frame:IsShown() then UI.frame:Hide() else UI.frame:Show() end
end

function FW:ShowTextDialog(title, text, importMode)
    if not UI then createUI() end
    UI.frame:Show()
    if importMode then
        showJSON("import")
        if title then UI.dialog.title:SetText(title) end
        if text then UI.dialog.text:SetText(text) end
        return
    end
    if not UI.dialog then createJSONDialog() end
    local dialog = UI.dialog
    dialog.mode = "text"
    dialog.title:SetText(title or "ZwykValues")
    dialog.help:SetText("Select all, then press Ctrl+C to copy this text.")
    dialog.nameLabel:Hide()
    dialog.name:Hide()
    dialog.import:Hide()
    dialog.message:SetText("")
    -- Diagnostics can contain every encountered issue item. Do not silently
    -- truncate a large export at the profile editor's input limit.
    dialog.text:SetMaxLetters(0)
    dialog.text:SetText(text or "")
    dialog:Show()
    dialog.scroll:SetVerticalScroll(0)
    dialog.text:SetFocus()
    dialog.text:HighlightText()
end
