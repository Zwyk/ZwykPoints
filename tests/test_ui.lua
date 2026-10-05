-- Smoke actual editor callbacks with a small WoW widget model.
-- Run from the addon directory: luatex --luaonly tests/test_ui.lua
local addonPath = (arg and arg[1]) or "."
local widgets, methods = {}, {}
local passed = 0
local function check(value, message)
    assert(value, message or "assertion failed")
    passed = passed + 1
end
local function equal(actual, expected, message)
    check(actual == expected, (message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function widget(kind, name, parent)
    local result = setmetatable({ kind = kind, name = name, parent = parent, children = {}, points = {}, scripts = {}, shown = true, enabled = true, text = "", fontSize = 12, scroll = 0 }, { __index = methods })
    widgets[#widgets + 1] = result
    if parent then parent.children[#parent.children + 1] = result end
    if name then _G[name] = result end
    return result
end
function CreateFrame(kind, name, parent) return widget(kind, name, parent or UIParent) end
function methods:CreateFontString(name) return widget("FontString", name, self) end
function methods:CreateTexture(name) return widget("Texture", name, self) end
function methods:SetSize(width, height) self.width, self.height = width, height end
function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:SetPoint(point, relative, relativePoint, x, y)
    if type(relative) == "number" then x, y, relative, relativePoint = relative, relativePoint, self.parent, point
    elseif relative == nil then relative, relativePoint, x, y = self.parent, point, 0, 0
    elseif type(relativePoint) == "number" then x, y, relativePoint = relativePoint, x, point end
    self.points[#self.points + 1] = { point, relative, relativePoint or point, x or 0, y or 0 }
end
function methods:GetPoint(index) return table.unpack(self.points[index or 1]) end
function methods:ClearAllPoints() self.points = {} end
function methods:SetAllPoints(target)
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", target or self.parent, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", target or self.parent, "BOTTOMRIGHT", 0, 0)
end
local fractions = {
    TOPLEFT = {0, 0}, TOP = {.5, 0}, TOPRIGHT = {1, 0}, LEFT = {0, .5}, CENTER = {.5, .5}, RIGHT = {1, .5},
    BOTTOMLEFT = {0, 1}, BOTTOM = {.5, 1}, BOTTOMRIGHT = {1, 1},
}
function methods:Rect()
    if self == UIParent then return 0, 0, self.width, self.height end
    local width = self.width or math.max(1, #self.text * self.fontSize * .56)
    local height = self.height or self.fontSize
    local axis = { {}, {} }
    for _, point in ipairs(self.points) do
        local relative = point[2] or self.parent
        local left, top, rw, rh = relative:Rect()
        local own, anchor = fractions[point[1]], fractions[point[3]]
        axis[1][#axis[1] + 1] = { own[1], left + anchor[1] * rw + point[4] }
        axis[2][#axis[2] + 1] = { own[2], top + anchor[2] * rh - point[5] }
    end
    local dimensions = { width, height }
    local positions = {}
    for index = 1, 2 do
        for a = 1, #axis[index] do
            for b = a + 1, #axis[index] do
                local first, second = axis[index][a], axis[index][b]
                if first[1] ~= second[1] then dimensions[index] = (second[2] - first[2]) / (second[1] - first[1]) end
            end
        end
        local first = axis[index][1]
        positions[index] = first and first[2] - first[1] * dimensions[index] or 0
    end
    return positions[1], positions[2], dimensions[1], dimensions[2]
end
function methods:GetWidth() local _, _, width = self:Rect() return width end
function methods:GetHeight() local _, _, _, height = self:Rect() return height end
function methods:SetScript(event, script) self.scripts[event] = script end
function methods:GetScript(event) return self.scripts[event] end
function methods:Fire(event, ...) if self.scripts[event] then return self.scripts[event](self, ...) end end
function methods:SetText(text)
    self.text = tostring(text)
    if self.kind == "EditBox" then self:Fire("OnTextChanged", false) end
end
function methods:GetText() return self.text end
function methods:SetFont(_, size) self.fontSize = size end
function methods:GetFont() return "font", self.fontSize end
function methods:SetTextColor(...) self.color = {...} end
function methods:SetColorTexture(...) self.color = {...} end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:SetEnabled(value) self.enabled = value end
function methods:SetFocus() self.focused = true end
function methods:ClearFocus() self.focused = false end
function methods:HighlightText() self.highlighted = true end
function methods:IsShown() return self.shown end
function methods:Show() if not self.shown then self.shown = true self:Fire("OnShow") end end
function methods:Hide() if self.shown then self.shown = false self:Fire("OnHide") end end
function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function methods:SetFrameLevel(value) self.level = value end
function methods:GetFrameLevel() return self.level or 1 end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:GetVerticalScroll() return self.scroll end
function methods:SetVerticalScroll(value) self.scroll = value end
function methods:GetVerticalScrollRange() return math.max(0, self.scrollChild:GetHeight() - self:GetHeight()) end
function methods:GetNumLines() local _, lines = self.text:gsub("\n", "") return lines + 1 end
for _, name in ipairs({ "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetJustifyH", "SetJustifyV", "SetFontObject", "SetTextInsets", "SetAutoFocus", "SetMaxLetters", "SetMultiLine", "SetWordWrap", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "SetResizable", "SetResizeBounds", "EnableMouse", "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "StartSizing", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture", "UpdateScrollChildRect", "RegisterEvent" }) do
    methods[name] = function() end
end
function methods:SetMaxLetters(value) self.maxLetters=value end
UIParent = widget("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
BackdropTemplateMixin = {}
IsShiftKeyDown = function() return false end
GetItemSubClassInfo = function(classID, subClassID)
    if classID == 2 and subClassID == 0 then return "Localized one-handed axes" end
end
local popup
StaticPopup_Show = function(kind, _, _, data) popup = { kind = kind, data = data } end

local FW = {}
for _, file in ipairs({ "JSON.lua", "Stats.lua", "Core.lua", "UI.lua" }) do assert(loadfile(addonPath .. "/" .. file))("ZwykValues", FW) end
local tooltipRefreshes, upgradeRefreshes = 0, 0
function FW:RefreshTooltips() tooltipRefreshes = tooltipRefreshes + 1 end
function FW:RefreshUpgradeIndicators() upgradeRefreshes = upgradeRefreshes + 1 end
function FW:InstallTooltipHooks() end
assert(loadfile(addonPath .. "/Bootstrap.lua"))("ZwykValues", FW)
equal(FW.UI, nil, "loading modules creates no editor")
FW:Initialize()
equal(FW.UI, nil, "initializing profiles preserves lazy editor construction")
SlashCmdList.ZWYKVALUES("")
check(FW.UI and FW.UI:IsShown(), "/zv opens the editor")
local created = #widgets
SlashCmdList.ZWYKVALUES("")
check(not FW.UI:IsShown(), "/zv closes the editor")
SlashCmdList.ZWYKVALUES("")
equal(#widgets, created, "reopening editor reuses widgets")

local function find(predicate)
    for _, control in ipairs(widgets) do if predicate(control) then return control end end
    error("Missing UI control")
end
local function byText(text, kind)
    return find(function(control) return control.text == text and (not kind or control.kind == kind) end)
end
local function click(text) byText(text, "Button"):Fire("OnClick") end
local function userText(control, text) control:SetText(text) control:Fire("OnTextChanged", true) end
local function weightBox(text)
    local label = byText(text, "FontString")
    for _, child in ipairs(label.parent.children) do if child.kind == "EditBox" then return child end end
    error("Missing weight editor: " .. text)
end
local function filterControl(group, key)
    return find(function(control) return control.filterGroup == group and control.filterKey == key end)
end
local strength, hit = weightBox("Strength"), weightBox("Hit")
local profile = FW:GetProfiles()[1]
userText(strength, "2.5")
userText(hit, "-3")
equal(profile.weights.strength, 0, "weights remain drafts before applying")
click("Item filters")
local filterScroll = ZwykValuesItemFiltersScroll
local filterDialog = filterScroll.parent.parent
check(filterDialog:IsShown(), "Item filters opens the filter dialog")
local filterCount = 0
for _, group in ipairs(FW.ItemFilterGroups) do
    for _, definition in ipairs(group.types) do
        filterCount = filterCount + 1
        check(filterControl(group.key, definition.key):GetChecked(), "new profiles include " .. group.key .. ":" .. definition.key)
    end
end
check(filterCount >= 22, "filter dialog offers weapon and armor subtype choices")
check(byText("Localized one-handed axes", "FontString"), "subtype labels use client localization when available")
check(byText("Plate", "FontString"), "subtype labels retain the definition fallback when the client has none")
local otherClasses = byText("Include items restricted to other classes", "FontString").parent
check(otherClasses:GetChecked(), "other-class items are included by default")
local weaponFilter, armorFilter = filterControl("weapons", "0"), filterControl("armor", "4")
local beforeFilters = upgradeRefreshes
weaponFilter:SetChecked(false)
weaponFilter:Fire("OnClick")
armorFilter:SetChecked(false)
armorFilter:Fire("OnClick")
otherClasses:SetChecked(false)
otherClasses:Fire("OnClick")
equal(profile.itemFilters.weapons["0"], false, "weapon filter is saved immediately")
equal(profile.itemFilters.armor["4"], false, "armor filter is saved immediately")
equal(profile.itemFilters.includeOtherClasses, false, "other-class restriction filter is saved immediately")
equal(profile.itemFilters.weapons["1"], true, "partial filter updates retain other weapon types")
equal(profile.itemFilters.armor["1"], true, "partial filter updates retain other armor types")
equal(upgradeRefreshes, beforeFilters + 3, "each filter edit refreshes indicators")
equal(strength:GetText(), "2.5", "filter edits preserve unsaved strength weights")
equal(hit:GetText(), "-3", "filter edits preserve every unsaved weight")
equal(profile.weights.strength, 0, "filter edits do not apply unsaved weights")
click("Done")
check(not filterDialog:IsShown(), "Done closes item filters")
local filterWidgets = #widgets
click("Item filters")
equal(#widgets, filterWidgets, "reopening filters reuses its widgets")
check(not weaponFilter:GetChecked() and not armorFilter:GetChecked() and not otherClasses:GetChecked(), "saved exclusions survive reopening filters")
click("Done")
FW:InvalidateCache()
equal(strength:GetText(), "2.5", "cache refresh preserves unsaved weights")
equal(hit:GetText(), "-3", "cache refresh preserves every unsaved weight")
click("Apply weights")
equal(profile.weights.strength, 2.5, "apply commits decimal weights")
equal(profile.weights.hit, -3, "apply commits negative weights")
userText(strength, "invalid")
click("Apply weights")
equal(profile.weights.strength, 2.5, "invalid weight input leaves saved profile intact")
check(strength.focused, "validation focuses the invalid input")
userText(strength, "4")
click("Apply weights")

local name = find(function(control) return control.kind == "EditBox" and control.parent == strength.parent.parent.parent.parent and control:GetText() == "My profile" end)
local color = find(function(control) return control.kind == "EditBox" and control:GetText():match("^#%x%x%x%x%x%x$") end)
userText(name, "Draft name")
userText(color, "#12345Z")
FW:RefreshUI()
equal(name:GetText(), "Draft name", "cache updates preserve unsaved name")
equal(color:GetText(), "#12345Z", "cache updates preserve unsaved color")
local oldRed = profile.color.r
click("Set color")
equal(profile.color.r, oldRed, "invalid HEX does not change profile color")
userText(color, "#123456")
click("Set color")
equal(profile.color.r, 0x12 / 255, "valid HEX saves red")
equal(profile.color.g, 0x34 / 255, "valid HEX saves green")
equal(profile.color.b, 0x56 / 255, "valid HEX saves blue")
click("Rename")
equal(profile.name, "Draft name", "rename commits name")

local debug = find(function(control) return control.optionKey == "debugUnknownStats" end)
check(not debug:GetChecked(), "unknown-stat debug option starts disabled")
debug:SetChecked(true)
local beforeRefresh = tooltipRefreshes
debug:Fire("OnClick")
equal(FW.DB.options.debugUnknownStats, true, "debug checkbox persists the requested option")
equal(tooltipRefreshes, beforeRefresh + 1, "debug toggle refreshes item tooltips")
debug:SetChecked(false)
debug:Fire("OnClick")
equal(FW.DB.options.debugUnknownStats, false, "debug checkbox can disable warnings")

local main = byText("Main for upgrade arrows", "FontString").parent
local mainName = byText("Main: None", "FontString")
equal(FW:GetMainProfile(), nil, "arrows start with no main profile")
check(not main:GetChecked(), "selected profile is not main by default")
local arrowControls = {}
for _, key in ipairs({ "upgradeBags", "upgradeRolls", "upgradeChat" }) do
    local control = find(function(candidate) return candidate.optionKey == key end)
    arrowControls[#arrowControls + 1] = control
    check(not control:GetChecked(), key .. " starts disabled")
    control:SetChecked(true)
    local before = upgradeRefreshes
    control:Fire("OnClick")
    equal(FW.DB.options[key], true, key .. " can be enabled independently")
    equal(upgradeRefreshes, before + 1, key .. " immediately refreshes upgrade indicators")
    equal(FW:GetMainProfile(), nil, "location toggles do not implicitly choose a main profile")
end
main:SetChecked(true)
local beforeMainRefresh = upgradeRefreshes
main:Fire("OnClick")
equal(FW:GetMainProfile(), profile, "selected profile can be designated main")
equal(mainName:GetText(), "Main: " .. profile.name, "main name appears in upgrade panel")
equal(upgradeRefreshes, beforeMainRefresh + 1, "main selection immediately refreshes arrows")
local active = byText("Active in tooltips", "FontString").parent
active:SetChecked(false)
active:Fire("OnClick")
check(not profile.active, "tooltip visibility can be disabled on the main profile")
equal(FW:GetMainProfile(), profile, "main profile remains chosen while inactive in tooltips")
check(main:GetChecked(), "main checkbox stays checked after tooltip visibility changes")

click("Copy")
equal(#FW:GetProfiles(), 2, "copy creates another profile")
local copied = FW:GetProfiles()[2]
equal(copied.weights.strength, 4, "copy retains saved weights")
click("Item filters")
check(not weaponFilter:GetChecked() and not armorFilter:GetChecked() and not otherClasses:GetChecked(), "copied profile keeps original item filters")
weaponFilter:SetChecked(true)
weaponFilter:Fire("OnClick")
equal(copied.itemFilters.weapons["0"], true, "filter edit targets the selected copied profile")
equal(profile.itemFilters.weapons["0"], false, "copied profile filters are independent")
find(function(control) return control.kind == "Button" and control.profileID == profile.id end):Fire("OnClick")
check(not weaponFilter:GetChecked(), "open filter dialog follows a profile selection change")
check(byText("Item filters for " .. profile.name, "FontString"), "filter dialog identifies selected profile")
find(function(control) return control.kind == "Button" and control.profileID == copied.id end):Fire("OnClick")
check(weaponFilter:GetChecked(), "switching back restores the copied profile filter")
click("Done")
check(not main:GetChecked(), "copying a main profile does not designate the copy main")
equal(FW:GetMainProfile(), profile, "copy leaves original main designation intact")
main:SetChecked(true)
main:Fire("OnClick")
equal(FW:GetMainProfile(), copied, "choosing a second main replaces the first")
equal(mainName:GetText(), "Main: " .. copied.name, "main display follows chosen profile")
main:SetChecked(false)
main:Fire("OnClick")
equal(FW:GetMainProfile(), nil, "main checkbox can clear the main profile")
equal(mainName:GetText(), "Main: None", "clearing main displays None")
for index, key in ipairs({ "upgradeBags", "upgradeRolls", "upgradeChat" }) do
    equal(FW.DB.options[key], true, "clearing main preserves " .. key .. " preference")
    arrowControls[index]:SetChecked(false)
    arrowControls[index]:Fire("OnClick")
    equal(FW.DB.options[key], false, key .. " can be independently disabled")
end
click("Export")
local dialogText = ZwykValuesJSONScroll.scrollChild
local exported = assert(FW.JSON.Decode(dialogText:GetText()))
equal(exported.name, copied.name, "export is the selected full profile")
equal(exported.weights.strength, 4, "export carries weights")
equal(exported.color.b, copied.color.b, "export carries color")
equal(exported.secondaryUnit, copied.secondaryUnit, "export carries stat units")
equal(exported.itemFilters.weapons["0"], true, "profile export carries its item filters")
equal(exported.itemFilters.armor["4"], false, "profile export retains subtype exclusions")
equal(dialogText.maxLetters, 131072, "profile input retains its limit")
click("Close")
click("Export issues")
local issues = assert(FW.JSON.Decode(dialogText:GetText()))
equal(issues.format, "ZwykValuesIssues", "issue export button copies the aggregate diagnostics")
equal(issues.itemCount, 0, "issue export works before any issues are recorded")
equal(dialogText.maxLetters, 0, "aggregate diagnostics must not be silently truncated")
local largeDiagnostics = string.rep("x", 140000)
FW:ShowTextDialog("Large diagnostics", largeDiagnostics, false)
equal(dialogText:GetText(), largeDiagnostics, "full diagnostics remain available to copy")
click("Close")
click("Weights JSON")
equal(dialogText.maxLetters, 131072, "reopening profile export restores its input limit")
local bare = assert(FW.JSON.Decode(dialogText:GetText()))
equal(bare.strength, 4, "weights-only export uses Sixty Upgrades keys")
equal(bare.name, nil, "weights-only export omits profile metadata")
click("Close")
click("Import")
userText(dialogText, '{"strength":9,"expertise":1.75}')
click("Import profile")
equal(#FW:GetProfiles(), 3, "JSON dialog imports a profile")
local imported = FW:GetProfiles()[3]
equal(imported.weights.strength, 9, "import applies weights")
equal(imported.weights.expertise, 1.75, "import supports Forever expertise")
click("New")
equal(#FW:GetProfiles(), 4, "New creates a blank profile")
equal(FW:GetProfiles()[4].weights.strength, 0, "new profile is deliberately unweighted")
click("Delete")
equal(#FW:GetProfiles(), 4, "deleting requires the native confirmation")
check(popup and popup.kind == "ZWYKVALUES_DELETE_PROFILE")
StaticPopupDialogs[popup.kind].OnAccept(nil, popup.data)
equal(#FW:GetProfiles(), 3, "accepting the confirmation deletes that profile")

-- Approximate geometry checks catch clipping/overlap at default and minimum
-- sizes. Font metrics and native templates still require an in-game review.
local function within(control, outer, message)
    local x, y, width, height = control:Rect()
    local left, top, ow, oh = outer:Rect()
    check(x >= left - .1 and y >= top - .1 and x + width <= left + ow + .1 and y + height <= top + oh + .1, message)
end
local function separate(first, second, message)
    local x, y, width, height = first:Rect()
    local ax, ay, aw, ah = second:Rect()
    check(x + width <= ax or ax + aw <= x or y + height <= ay or ay + ah <= y, message)
end
for _, dimensions in ipairs({ {930, 720}, {850, 600} }) do
    FW.UI:SetSize(table.unpack(dimensions))
    FW.UI:Fire("OnSizeChanged")
    within(byText("Mark unrecognized stats", "FontString"), FW.UI, "debug label fits minimum width")
    within(byText("Show upgrade comparisons", "FontString"), FW.UI, "comparison label fits minimum width")
    separate(byText("Mark unrecognized stats", "FontString"), find(function(control) return control.optionKey == "showComparisons" end), "footer options do not overlap")
    separate(byText("Fixed weights ignore caps, procs, sets and rotations.", "FontString"), debug, "footer note leaves space for options")
    separate(byText("Weights saved", "FontString"), byText("Weights JSON", "Button"), "weight state does not overlap action buttons")
    within(byText("Apply weights", "Button"), FW.UI, "apply button fits editor")
    within(byText("Clear cache", "Button"), FW.UI, "cache button fits footer")
    check(ZwykValuesStatsScroll:GetHeight() >= 190, "resized editor keeps useful visible weight area")
    within(byText("Item filters", "Button"), FW.UI, "filter button fits minimum editor width")
    separate(byText("Item filters", "Button"), byText("Rating", "FontString"), "filter button leaves room for secondary-unit choices")
    within(filterDialog, FW.UI, "filter dialog fits minimum editor size")
    within(otherClasses, filterDialog, "class-restriction checkbox fits filter dialog")
    within(byText("Include items restricted to other classes", "FontString"), filterDialog, "class-restriction label fits filter dialog")
    separate(otherClasses, filterScroll, "class restriction does not overlap subtype choices")
    check(filterScroll:GetHeight() >= 290, "filter dialog keeps a useful visible subtype list")
    check(filterScroll:GetVerticalScrollRange() > 0, "long subtype choices are available through scrolling")
    for _, group in ipairs(FW.ItemFilterGroups) do
        for _, definition in ipairs(group.types) do
            local control = filterControl(group.key, definition.key)
            within(control, filterScroll.scrollChild, "subtype checkbox fits scroll content")
            for _, child in ipairs(control.children) do within(child, filterScroll.scrollChild, "subtype label fits scroll content") end
        end
    end
    local upgradePanel = main.parent
    within(upgradePanel, FW.UI, "upgrade panel fits minimum editor size")
    within(mainName, upgradePanel, "main name fits upgrade panel")
    within(byText("Main for upgrade arrows", "FontString"), upgradePanel, "main checkbox label fits compact panel")
    separate(ZwykValuesProfilesScroll, upgradePanel, "profile list leaves room for upgrade settings")
    separate(upgradePanel, byText("New", "Button"), "upgrade settings leave room for profile buttons")
    check(ZwykValuesProfilesScroll:GetHeight() >= 170, "compact settings retain useful profile list height")
    for _, control in ipairs(arrowControls) do
        within(control, upgradePanel, "arrow location checkbox fits panel")
        for _, child in ipairs(control.children) do within(child, upgradePanel, "arrow location label fits panel") end
        separate(main, control, "main choice does not overlap arrow locations")
    end
    separate(arrowControls[1], arrowControls[2], "bag and roll arrow toggles do not overlap")
    separate(arrowControls[2], arrowControls[3], "roll and chat arrow toggles do not overlap")
end
click("Item filters")
local remaining = FW:GetProfiles()
for _, existing in ipairs(remaining) do FW:DeleteProfile(existing.id) end
check(not byText("Item filters", "Button").enabled, "filter button is disabled without a profile")
check(not otherClasses.enabled and not weaponFilter.enabled and not armorFilter.enabled, "open filters disable their controls when the profile is deleted")
local restored = assert(FW:CreateProfile("Restored profile", {}))
check(byText("Item filters", "Button").enabled, "creating a profile re-enables filters")
check(otherClasses.enabled and weaponFilter.enabled and armorFilter.enabled, "new profile enables existing dialog controls")
check(otherClasses:GetChecked() and weaponFilter:GetChecked() and armorFilter:GetChecked(), "new profile restores default inclusion")
click("Done")
click("Item filters")
FW.UI:Hide()
check(not filterDialog:IsShown(), "closing the editor hides its filter dialog")
print("UI: " .. passed .. " checks passed (widget smoke and approximate geometry).")
