---
name: localization
description: |
  Multi-language localization support for Roblox. LocalizationService integration,
  translation tables with CSV/JSON import, dynamic text switching at runtime, RTL
  (right-to-left) text support, locale detection, and fallback language chains.
  다국어 지원, 로컬라이제이션, 번역 테이블, 동적 텍스트 전환, RTL 지원, 로케일 감지
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
effort: high
---

# Multi-Language Localization System

Build a comprehensive localization system with translation tables, runtime language switching, RTL support, locale detection, and fallback language chains.

## Architecture Overview

```
ReplicatedStorage/
  Localization/
    LocalizationManager.lua      -- Core translation engine
    TranslationData.lua          -- Translation tables (all languages)
    LocaleDetector.lua           -- Detect player's locale
    RTLHelper.lua                -- Right-to-left text utilities
StarterPlayerScripts/
  LocalizationClient.lua         -- Client-side locale setup, UI text binding
ServerScriptService/
  LocalizationService.server.lua -- Server-side locale tracking
StarterGui/
  LanguageSelector/              -- UI for manual language switching
```

## Translation Data

```lua
-- ReplicatedStorage/Localization/TranslationData.lua
local TranslationData = {}

-- Supported locales with metadata
TranslationData.SupportedLocales = {
    en = { name = "English", nativeName = "English", direction = "LTR" },
    ko = { name = "Korean", nativeName = "한국어", direction = "LTR" },
    ja = { name = "Japanese", nativeName = "日本語", direction = "LTR" },
    zh = { name = "Chinese (Simplified)", nativeName = "简体中文", direction = "LTR" },
    es = { name = "Spanish", nativeName = "Español", direction = "LTR" },
    pt = { name = "Portuguese", nativeName = "Português", direction = "LTR" },
    de = { name = "German", nativeName = "Deutsch", direction = "LTR" },
    fr = { name = "French", nativeName = "Français", direction = "LTR" },
    ar = { name = "Arabic", nativeName = "العربية", direction = "RTL" },
    he = { name = "Hebrew", nativeName = "עברית", direction = "RTL" },
    th = { name = "Thai", nativeName = "ไทย", direction = "LTR" },
    vi = { name = "Vietnamese", nativeName = "Tiếng Việt", direction = "LTR" },
}

-- Fallback chain: if a translation is missing, try these in order
TranslationData.FallbackChain = {
    ko = { "ko", "en" },
    ja = { "ja", "en" },
    zh = { "zh", "en" },
    es = { "es", "en" },
    pt = { "pt", "es", "en" },  -- Portuguese falls back to Spanish then English
    de = { "de", "en" },
    fr = { "fr", "en" },
    ar = { "ar", "en" },
    he = { "he", "en" },
    th = { "th", "en" },
    vi = { "vi", "en" },
    en = { "en" },
}

-- Translation tables organized by key
-- Format: translations[key][locale] = translated string
-- Supports parameter interpolation: {playerName}, {count}, {item}
TranslationData.Translations: { [string]: { [string]: string } } = {
    -- UI Labels
    ["ui.play"] = {
        en = "Play",
        ko = "플레이",
        ja = "プレイ",
        zh = "开始游戏",
        es = "Jugar",
        pt = "Jogar",
        de = "Spielen",
        fr = "Jouer",
        ar = "العب",
    },
    ["ui.settings"] = {
        en = "Settings",
        ko = "설정",
        ja = "設定",
        zh = "设置",
        es = "Configuración",
        pt = "Configurações",
        de = "Einstellungen",
        fr = "Paramètres",
        ar = "الإعدادات",
    },
    ["ui.shop"] = {
        en = "Shop",
        ko = "상점",
        ja = "ショップ",
        zh = "商店",
        es = "Tienda",
        pt = "Loja",
        de = "Shop",
        fr = "Boutique",
        ar = "المتجر",
    },
    ["ui.inventory"] = {
        en = "Inventory",
        ko = "인벤토리",
        ja = "インベントリ",
        zh = "物品栏",
        es = "Inventario",
        pt = "Inventário",
        de = "Inventar",
        fr = "Inventaire",
        ar = "المخزون",
    },
    ["ui.close"] = {
        en = "Close",
        ko = "닫기",
        ja = "閉じる",
        zh = "关闭",
        es = "Cerrar",
        pt = "Fechar",
        de = "Schließen",
        fr = "Fermer",
        ar = "إغلاق",
    },

    -- Game Messages (with parameters)
    ["msg.welcome"] = {
        en = "Welcome, {playerName}!",
        ko = "{playerName}님, 환영합니다!",
        ja = "{playerName}さん、ようこそ！",
        zh = "欢迎，{playerName}！",
        es = "¡Bienvenido, {playerName}!",
        ar = "!{playerName} مرحباً",
    },
    ["msg.coins_earned"] = {
        en = "You earned {count} coins!",
        ko = "{count}개의 코인을 획득했습니다!",
        ja = "{count}コインを獲得しました！",
        zh = "获得了 {count} 个金币！",
        es = "¡Ganaste {count} monedas!",
        ar = "!لقد ربحت {count} عملات",
    },
    ["msg.level_up"] = {
        en = "Level up! You are now level {level}!",
        ko = "레벨 업! 현재 레벨 {level}!",
        ja = "レベルアップ！レベル{level}になりました！",
        zh = "升级了！你现在是 {level} 级！",
        es = "¡Subiste de nivel! ¡Ahora eres nivel {level}!",
    },
    ["msg.item_obtained"] = {
        en = "Obtained: {item}",
        ko = "획득: {item}",
        ja = "入手: {item}",
        zh = "获得: {item}",
        es = "Obtenido: {item}",
    },

    -- Pluralization example
    ["msg.players_online"] = {
        en = "{count} player(s) online",
        ko = "온라인 플레이어 {count}명",
        ja = "{count}人のプレイヤーがオンライン",
        zh = "{count} 名玩家在线",
    },

    -- Error messages
    ["error.not_enough_coins"] = {
        en = "Not enough coins! You need {required} but have {current}.",
        ko = "코인이 부족합니다! {required}개 필요하지만 {current}개 보유 중.",
        ja = "コインが足りません！{required}必要ですが、{current}しかありません。",
        zh = "金币不足！需要 {required}，但只有 {current}。",
    },
}

return TranslationData
```

## Core Localization Manager

```lua
-- ReplicatedStorage/Localization/LocalizationManager.lua
local LocalizationService = game:GetService("LocalizationService")

local TranslationData = require(script.Parent:WaitForChild("TranslationData"))

local LocalizationManager = {}

-- Current active locale (set per client)
local activeLocale: string = "en"

-- Event for locale change notifications
local localeChangedEvent = Instance.new("BindableEvent")
localeChangedEvent.Name = "LocaleChanged"

LocalizationManager.LocaleChanged = localeChangedEvent.Event

--------------------------------------------------------------------------------
-- Set the active locale
--------------------------------------------------------------------------------
function LocalizationManager.setLocale(locale: string)
    local supported = TranslationData.SupportedLocales[locale]
    if not supported then
        -- Try matching by language prefix (e.g., "en-us" -> "en")
        local prefix = string.match(locale, "^(%a+)")
        if prefix and TranslationData.SupportedLocales[prefix] then
            locale = prefix
        else
            warn("[Localization] Unsupported locale:", locale, "- falling back to en")
            locale = "en"
        end
    end

    activeLocale = locale
    localeChangedEvent:Fire(locale)
end

--------------------------------------------------------------------------------
-- Get the active locale
--------------------------------------------------------------------------------
function LocalizationManager.getLocale(): string
    return activeLocale
end

--------------------------------------------------------------------------------
-- Get locale metadata
--------------------------------------------------------------------------------
function LocalizationManager.getLocaleInfo(): { name: string, nativeName: string, direction: string }
    return TranslationData.SupportedLocales[activeLocale] or TranslationData.SupportedLocales["en"]
end

--------------------------------------------------------------------------------
-- Check if current locale is RTL
--------------------------------------------------------------------------------
function LocalizationManager.isRTL(): boolean
    local info = TranslationData.SupportedLocales[activeLocale]
    return info and info.direction == "RTL" or false
end

--------------------------------------------------------------------------------
-- Translate a key with optional parameters
-- Parameters are interpolated: {paramName} -> value
--------------------------------------------------------------------------------
function LocalizationManager.translate(key: string, params: { [string]: any }?): string
    local translations = TranslationData.Translations[key]
    if not translations then
        warn("[Localization] Missing translation key:", key)
        return key
    end

    -- Walk the fallback chain
    local fallbackChain = TranslationData.FallbackChain[activeLocale] or { activeLocale, "en" }
    local text: string? = nil

    for _, locale in fallbackChain do
        if translations[locale] then
            text = translations[locale]
            break
        end
    end

    if not text then
        -- Last resort: return the key itself
        return key
    end

    -- Interpolate parameters
    if params then
        for paramName, paramValue in params do
            text = string.gsub(text, "{" .. paramName .. "}", tostring(paramValue))
        end
    end

    return text
end

-- Shorthand alias
LocalizationManager.t = LocalizationManager.translate

--------------------------------------------------------------------------------
-- Get all supported locales
--------------------------------------------------------------------------------
function LocalizationManager.getSupportedLocales(): { [string]: { name: string, nativeName: string, direction: string } }
    return TranslationData.SupportedLocales
end

--------------------------------------------------------------------------------
-- Bulk translate: translate multiple keys at once
--------------------------------------------------------------------------------
function LocalizationManager.translateBulk(keys: { string }, params: { [string]: any }?): { [string]: string }
    local results = {}
    for _, key in keys do
        results[key] = LocalizationManager.translate(key, params)
    end
    return results
end

--------------------------------------------------------------------------------
-- Register Roblox LocalizationTable for automatic GUI translation
-- This integrates with Roblox's built-in localization system
--------------------------------------------------------------------------------
function LocalizationManager.registerWithRoblox()
    local table_ = Instance.new("LocalizationTable")
    table_.Name = "GameLocalization"

    local entries = {}
    for key, translations in TranslationData.Translations do
        local entry = {
            Key = key,
            Source = translations["en"] or key,
            Context = "",
            Example = "",
            Values = {},
        }
        for locale, text in translations do
            if locale ~= "en" then
                entry.Values[locale] = text
            end
        end
        table.insert(entries, entry)
    end

    table_:SetEntries(entries)
    table_.Parent = LocalizationService
end

return LocalizationManager
```

## Locale Detector

```lua
-- ReplicatedStorage/Localization/LocaleDetector.lua
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local TranslationData = require(script.Parent:WaitForChild("TranslationData"))

local LocaleDetector = {}

--------------------------------------------------------------------------------
-- Detect the player's preferred locale
-- Priority: 1) Saved preference 2) Roblox locale 3) System locale 4) "en"
--------------------------------------------------------------------------------
function LocaleDetector.detect(player: Player): string
    -- 1. Check saved preference (Attribute on player)
    local savedLocale = player:GetAttribute("PreferredLocale")
    if savedLocale and TranslationData.SupportedLocales[savedLocale] then
        return savedLocale
    end

    -- 2. Try Roblox's locale detection
    local success, robloxLocale = pcall(function()
        return LocalizationService.RobloxLocaleId
    end)

    if success and robloxLocale then
        -- Roblox returns codes like "en-us", "ko-kr", "ja-jp"
        local langCode = string.match(robloxLocale, "^(%a+)")
        if langCode and TranslationData.SupportedLocales[langCode] then
            return langCode
        end
    end

    -- 3. Try system locale
    local success2, systemLocale = pcall(function()
        return LocalizationService.SystemLocaleId
    end)

    if success2 and systemLocale then
        local langCode = string.match(systemLocale, "^(%a+)")
        if langCode and TranslationData.SupportedLocales[langCode] then
            return langCode
        end
    end

    -- 4. Default to English
    return "en"
end

return LocaleDetector
```

## RTL Helper

```lua
-- ReplicatedStorage/Localization/RTLHelper.lua
local RTLHelper = {}

--------------------------------------------------------------------------------
-- Apply RTL layout adjustments to a GUI element
-- Mirrors horizontal positioning and alignment for RTL locales
--------------------------------------------------------------------------------
function RTLHelper.applyRTL(gui: GuiObject)
    -- Mirror horizontal position
    local pos = gui.Position
    gui.Position = UDim2.new(
        1 - pos.X.Scale - gui.Size.X.Scale,
        -pos.X.Offset,
        pos.Y.Scale,
        pos.Y.Offset
    )

    -- Flip anchor point X
    local anchor = gui.AnchorPoint
    gui.AnchorPoint = Vector2.new(1 - anchor.X, anchor.Y)

    -- Flip text alignment for TextLabels
    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        local textGui = gui :: TextLabel
        if textGui.TextXAlignment == Enum.TextXAlignment.Left then
            textGui.TextXAlignment = Enum.TextXAlignment.Right
        elseif textGui.TextXAlignment == Enum.TextXAlignment.Right then
            textGui.TextXAlignment = Enum.TextXAlignment.Left
        end
    end
end

--------------------------------------------------------------------------------
-- Apply RTL to a container and all its children recursively
--------------------------------------------------------------------------------
function RTLHelper.applyRTLRecursive(container: GuiObject)
    RTLHelper.applyRTL(container)
    for _, child in container:GetDescendants() do
        if child:IsA("GuiObject") then
            RTLHelper.applyRTL(child)
        end
    end

    -- Reverse UIListLayout direction
    for _, child in container:GetDescendants() do
        if child:IsA("UIListLayout") then
            if child.HorizontalAlignment == Enum.HorizontalAlignment.Left then
                child.HorizontalAlignment = Enum.HorizontalAlignment.Right
            elseif child.HorizontalAlignment == Enum.HorizontalAlignment.Right then
                child.HorizontalAlignment = Enum.HorizontalAlignment.Left
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Reverse RTL adjustments (revert to LTR)
--------------------------------------------------------------------------------
function RTLHelper.revertRTL(gui: GuiObject)
    -- This requires storing original values; typically you'd rebuild the UI
    -- or store originals in attributes
    local origPosXScale = gui:GetAttribute("_origPosXScale")
    if origPosXScale then
        gui.Position = UDim2.new(
            origPosXScale, gui:GetAttribute("_origPosXOffset") or 0,
            gui.Position.Y.Scale, gui.Position.Y.Offset
        )
        gui.AnchorPoint = Vector2.new(
            gui:GetAttribute("_origAnchorX") or 0,
            gui.AnchorPoint.Y
        )
    end
end

--------------------------------------------------------------------------------
-- Store original layout values before applying RTL
-- Call this BEFORE applyRTL to enable revertRTL later
--------------------------------------------------------------------------------
function RTLHelper.saveOriginalLayout(gui: GuiObject)
    gui:SetAttribute("_origPosXScale", gui.Position.X.Scale)
    gui:SetAttribute("_origPosXOffset", gui.Position.X.Offset)
    gui:SetAttribute("_origAnchorX", gui.AnchorPoint.X)

    if gui:IsA("TextLabel") or gui:IsA("TextButton") or gui:IsA("TextBox") then
        gui:SetAttribute("_origTextAlign", (gui :: TextLabel).TextXAlignment.Name)
    end
end

function RTLHelper.saveOriginalLayoutRecursive(container: GuiObject)
    RTLHelper.saveOriginalLayout(container)
    for _, child in container:GetDescendants() do
        if child:IsA("GuiObject") then
            RTLHelper.saveOriginalLayout(child)
        end
    end
end

return RTLHelper
```

## Client: Localization Setup

```lua
-- StarterPlayerScripts/LocalizationClient.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LocalizationManager = require(ReplicatedStorage.Localization.LocalizationManager)
local LocaleDetector = require(ReplicatedStorage.Localization.LocaleDetector)
local RTLHelper = require(ReplicatedStorage.Localization.RTLHelper)

local player = Players.LocalPlayer

--------------------------------------------------------------------------------
-- Auto-detect and set locale
--------------------------------------------------------------------------------
local detectedLocale = LocaleDetector.detect(player)
LocalizationManager.setLocale(detectedLocale)

print("[Localization] Detected locale:", detectedLocale)

-- Register with Roblox's built-in system for automatic GUI text
LocalizationManager.registerWithRoblox()

--------------------------------------------------------------------------------
-- Bind text labels to translation keys
-- Tag TextLabels with attribute "LocaleKey" to auto-translate
--------------------------------------------------------------------------------
local function bindTextElement(element: TextLabel)
    local key = element:GetAttribute("LocaleKey")
    if not key then return end

    local function updateText()
        -- Check for parameter attributes (e.g., LocaleParam_playerName)
        local params = {}
        for attrName, attrValue in element:GetAttributes() do
            local paramName = string.match(attrName, "^LocaleParam_(.+)$")
            if paramName then
                params[paramName] = attrValue
            end
        end

        local translated = LocalizationManager.translate(key, next(params) and params or nil)
        element.Text = translated
    end

    updateText()

    -- Re-translate when locale changes
    LocalizationManager.LocaleChanged:Connect(function()
        updateText()

        -- Apply or revert RTL
        if LocalizationManager.isRTL() then
            RTLHelper.applyRTL(element)
        end
    end)
end

-- Scan all existing text elements
local function scanForLocalizableElements()
    local playerGui = player:WaitForChild("PlayerGui")
    for _, descendant in playerGui:GetDescendants() do
        if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox"))
            and descendant:GetAttribute("LocaleKey") then
            bindTextElement(descendant)
        end
    end
end

-- Scan on load and when new GUIs are added
task.defer(scanForLocalizableElements)

local playerGui = player:WaitForChild("PlayerGui")
playerGui.DescendantAdded:Connect(function(descendant)
    if (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox"))
        and descendant:GetAttribute("LocaleKey") then
        task.defer(function()
            bindTextElement(descendant)
        end)
    end
end)

--------------------------------------------------------------------------------
-- Language Selector UI
--------------------------------------------------------------------------------
local function createLanguageSelector()
    local gui = Instance.new("ScreenGui")
    gui.Name = "LanguageSelector"
    gui.Parent = playerGui

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.fromOffset(40, 40)
    btn.Position = UDim2.new(1, -50, 0, 10)
    btn.BackgroundColor3 = Color3.fromRGB(50, 50, 65)
    btn.Text = "🌐"
    btn.TextSize = 20
    btn.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = btn

    local dropdown = Instance.new("Frame")
    dropdown.Size = UDim2.fromOffset(180, 0)
    dropdown.Position = UDim2.new(1, -190, 0, 55)
    dropdown.BackgroundColor3 = Color3.fromRGB(35, 35, 48)
    dropdown.Visible = false
    dropdown.ClipsDescendants = true
    dropdown.Parent = gui

    local dropCorner = Instance.new("UICorner")
    dropCorner.CornerRadius = UDim.new(0, 8)
    dropCorner.Parent = dropdown

    local listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.Name
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = dropdown

    local locales = LocalizationManager.getSupportedLocales()
    local itemCount = 0
    for code, info in locales do
        itemCount += 1
        local item = Instance.new("TextButton")
        item.Size = UDim2.new(1, 0, 0, 30)
        item.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
        item.BackgroundTransparency = 0.3
        item.Text = info.nativeName .. " (" .. code .. ")"
        item.TextColor3 = Color3.fromRGB(220, 220, 220)
        item.TextSize = 13
        item.Font = Enum.Font.Gotham
        item.Name = code
        item.Parent = dropdown

        item.MouseButton1Click:Connect(function()
            LocalizationManager.setLocale(code)
            player:SetAttribute("PreferredLocale", code)
            dropdown.Visible = false
        end)
    end

    dropdown.Size = UDim2.fromOffset(180, math.min(itemCount * 32, 300))

    btn.MouseButton1Click:Connect(function()
        dropdown.Visible = not dropdown.Visible
    end)
end

createLanguageSelector()

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------
local LocalizationClient = {}

function LocalizationClient.translate(key: string, params: { [string]: any }?): string
    return LocalizationManager.translate(key, params)
end

LocalizationClient.t = LocalizationClient.translate

function LocalizationClient.setLocale(locale: string)
    LocalizationManager.setLocale(locale)
    player:SetAttribute("PreferredLocale", locale)
end

function LocalizationClient.getLocale(): string
    return LocalizationManager.getLocale()
end

function LocalizationClient.isRTL(): boolean
    return LocalizationManager.isRTL()
end

return LocalizationClient
```

## Usage Examples

```lua
-- In any client script:
local L = require(ReplicatedStorage.Localization.LocalizationManager)

-- Simple translation
local playText = L.t("ui.play") -- Returns "플레이" if locale is "ko"

-- With parameters
local welcome = L.t("msg.welcome", { playerName = player.Name })
-- Returns "PlayerName님, 환영합니다!" if locale is "ko"

local coinMsg = L.t("msg.coins_earned", { count = 50 })
-- Returns "50개의 코인을 획득했습니다!" if locale is "ko"

-- In Studio: set TextLabel attributes for auto-binding
-- TextLabel.LocaleKey = "ui.shop"
-- TextLabel.LocaleParam_count = 5
```

## Roblox Studio Integration

For TextLabels in Studio, set these Attributes to auto-translate:
- `LocaleKey` (string): The translation key (e.g., "ui.play")
- `LocaleParam_*` (any): Parameters for interpolation (e.g., `LocaleParam_playerName`)

The client automatically scans for these attributes and binds translations.

## Key Implementation Notes

1. **Fallback chains**: If Korean translation is missing, it falls back to English. Portuguese falls back to Spanish then English.

2. **Parameter interpolation**: Use `{paramName}` in translation strings. Pass params as a table to `translate()`.

3. **RTL support**: Arabic and Hebrew are flagged as RTL. The RTL helper mirrors horizontal positions, anchor points, and text alignment.

4. **Auto-binding**: TextLabels with `LocaleKey` attribute are automatically translated. New GUI elements added at runtime are also detected.

5. **Roblox integration**: `registerWithRoblox()` creates a LocalizationTable that works with Roblox's built-in text replacement system.

6. **Locale detection**: Checks saved preference, then Roblox locale, then system locale, defaulting to English.

7. **Language selector**: Globe button in top-right corner opens a dropdown of all supported languages. Selection is saved as a player attribute.

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 교훈 추가 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. Learned Lessons 섹션에 교훈을 추가한다
3. 규칙화하여 반복 방지
4. SessionManager에 기록

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[스킬명] | [에러]")
SM.logAction("SKILL_LEARNED", "[스킬명] | [교훈]")
```

**매 작업 시 Learned Lessons를 먼저 읽고 위반하지 않는지 확인.**

$ARGUMENTS

When the user asks for localization, ask:
- What languages do you need to support?
- Do you need RTL (right-to-left) support? (Arabic, Hebrew)
- Should the player be able to manually switch languages?
- Do you have existing translation data (CSV, JSON)?
- How many text strings need translation approximately?
- Do you need dynamic text with parameters (player names, numbers)?
