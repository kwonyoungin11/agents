---
name: color-palette
description: |
  게임용 색상 이론, 테마 팔레트 (다크 판타지, 네온, 파스텔 등), Color3 프리셋, 보색 조합, 색상 조화 시스템.
  Color theory for games, theme palettes (Dark Fantasy, Neon, Pastel, Cyberpunk, Nature), Color3 presets, complementary/analogous/triadic color generation, HSV manipulation.
allowed-tools:
  - Bash
  - Edit
  - Write
  - Read
  - Glob
  - Grep
effort: high
---

# Color Palette & Color Theory System

This skill covers game-oriented color theory, pre-built theme palettes, Color3 utilities, complementary/analogous/triadic color generation, and HSV-based color manipulation for Roblox.

---

## 1. Theme Palette Presets

```luau
--!strict
-- ModuleScript: Pre-built color palettes for common game themes

export type Palette = {
    name: string,
    primary: Color3,
    secondary: Color3,
    accent: Color3,
    background: Color3,
    foreground: Color3,
    highlight: Color3,
    shadow: Color3,
    danger: Color3,
    success: Color3,
    warning: Color3,
}

local Palettes: { [string]: Palette } = {}

Palettes.DarkFantasy = {
    name = "Dark Fantasy",
    primary = Color3.fromRGB(45, 27, 62),       -- deep purple
    secondary = Color3.fromRGB(89, 56, 97),      -- muted plum
    accent = Color3.fromRGB(180, 60, 60),         -- blood red
    background = Color3.fromRGB(18, 12, 25),      -- near black
    foreground = Color3.fromRGB(200, 190, 180),   -- parchment
    highlight = Color3.fromRGB(220, 170, 60),     -- gold
    shadow = Color3.fromRGB(10, 6, 15),           -- void
    danger = Color3.fromRGB(160, 30, 30),         -- crimson
    success = Color3.fromRGB(50, 120, 70),        -- dark emerald
    warning = Color3.fromRGB(180, 130, 40),       -- amber
}

Palettes.Neon = {
    name = "Neon",
    primary = Color3.fromRGB(0, 255, 200),        -- cyan
    secondary = Color3.fromRGB(255, 0, 200),      -- magenta
    accent = Color3.fromRGB(255, 255, 0),          -- electric yellow
    background = Color3.fromRGB(10, 10, 20),       -- deep dark
    foreground = Color3.fromRGB(240, 240, 255),    -- white-blue
    highlight = Color3.fromRGB(0, 200, 255),       -- sky neon
    shadow = Color3.fromRGB(5, 5, 15),             -- abyss
    danger = Color3.fromRGB(255, 50, 50),          -- hot red
    success = Color3.fromRGB(50, 255, 100),        -- neon green
    warning = Color3.fromRGB(255, 180, 0),         -- neon orange
}

Palettes.Pastel = {
    name = "Pastel",
    primary = Color3.fromRGB(180, 210, 240),       -- baby blue
    secondary = Color3.fromRGB(240, 180, 210),     -- soft pink
    accent = Color3.fromRGB(210, 240, 180),         -- mint green
    background = Color3.fromRGB(250, 248, 245),     -- warm white
    foreground = Color3.fromRGB(80, 70, 70),         -- soft dark
    highlight = Color3.fromRGB(255, 230, 150),       -- peach
    shadow = Color3.fromRGB(200, 195, 190),          -- light gray
    danger = Color3.fromRGB(240, 150, 150),          -- soft red
    success = Color3.fromRGB(150, 220, 160),         -- soft green
    warning = Color3.fromRGB(250, 210, 140),         -- soft amber
}

Palettes.Cyberpunk = {
    name = "Cyberpunk",
    primary = Color3.fromRGB(20, 20, 40),          -- midnight
    secondary = Color3.fromRGB(100, 20, 160),      -- electric purple
    accent = Color3.fromRGB(255, 50, 120),          -- hot pink
    background = Color3.fromRGB(8, 8, 16),          -- void
    foreground = Color3.fromRGB(200, 220, 255),     -- hologram white
    highlight = Color3.fromRGB(0, 230, 255),        -- laser blue
    shadow = Color3.fromRGB(15, 10, 25),            -- deep violet
    danger = Color3.fromRGB(255, 30, 60),           -- neon red
    success = Color3.fromRGB(30, 255, 130),         -- matrix green
    warning = Color3.fromRGB(255, 200, 0),          -- hazard yellow
}

Palettes.Nature = {
    name = "Nature",
    primary = Color3.fromRGB(60, 120, 60),         -- forest green
    secondary = Color3.fromRGB(139, 90, 43),       -- bark brown
    accent = Color3.fromRGB(200, 180, 50),          -- sunflower
    background = Color3.fromRGB(230, 240, 220),     -- morning mist
    foreground = Color3.fromRGB(40, 35, 30),         -- earth dark
    highlight = Color3.fromRGB(255, 220, 100),       -- sunlight
    shadow = Color3.fromRGB(30, 50, 30),             -- deep forest
    danger = Color3.fromRGB(180, 50, 30),            -- lava red
    success = Color3.fromRGB(80, 180, 80),           -- spring green
    warning = Color3.fromRGB(220, 160, 40),          -- autumn gold
}

Palettes.Ocean = {
    name = "Ocean",
    primary = Color3.fromRGB(20, 80, 140),         -- deep ocean
    secondary = Color3.fromRGB(40, 160, 180),      -- teal
    accent = Color3.fromRGB(255, 200, 100),         -- sandy gold
    background = Color3.fromRGB(10, 30, 60),        -- deep sea
    foreground = Color3.fromRGB(220, 240, 255),     -- sea foam white
    highlight = Color3.fromRGB(100, 220, 255),      -- shallow water
    shadow = Color3.fromRGB(5, 15, 35),             -- abyss
    danger = Color3.fromRGB(200, 60, 60),           -- coral red
    success = Color3.fromRGB(60, 200, 150),         -- sea green
    warning = Color3.fromRGB(240, 180, 60),         -- treasure gold
}

Palettes.Lava = {
    name = "Lava",
    primary = Color3.fromRGB(180, 40, 20),         -- molten red
    secondary = Color3.fromRGB(255, 140, 20),      -- orange flame
    accent = Color3.fromRGB(255, 220, 60),          -- fire yellow
    background = Color3.fromRGB(25, 10, 8),         -- charcoal
    foreground = Color3.fromRGB(255, 230, 200),     -- warm white
    highlight = Color3.fromRGB(255, 180, 40),       -- bright flame
    shadow = Color3.fromRGB(40, 15, 10),            -- dark ember
    danger = Color3.fromRGB(220, 20, 20),           -- blaze red
    success = Color3.fromRGB(60, 180, 100),         -- oasis green
    warning = Color3.fromRGB(255, 160, 30),         -- warning flame
}

Palettes.Arctic = {
    name = "Arctic",
    primary = Color3.fromRGB(180, 210, 230),       -- ice blue
    secondary = Color3.fromRGB(140, 170, 200),     -- steel blue
    accent = Color3.fromRGB(100, 200, 220),         -- aurora cyan
    background = Color3.fromRGB(240, 245, 250),     -- snow white
    foreground = Color3.fromRGB(40, 50, 70),         -- dark slate
    highlight = Color3.fromRGB(200, 230, 255),       -- glacial glow
    shadow = Color3.fromRGB(100, 120, 140),          -- storm gray
    danger = Color3.fromRGB(200, 80, 80),            -- frostbite red
    success = Color3.fromRGB(80, 200, 160),          -- northern light green
    warning = Color3.fromRGB(230, 200, 100),         -- pale gold
}

return Palettes
```

---

## 2. Color Theory Utility

```luau
--!strict
-- ModuleScript: Color theory functions for generating harmonious colors

local ColorTheory = {}

--- Converts Color3 (0-1 range) to HSV components.
function ColorTheory.toHSV(color: Color3): (number, number, number)
    return color:ToHSV()
end

--- Creates Color3 from HSV (hue 0-1, saturation 0-1, value 0-1).
function ColorTheory.fromHSV(h: number, s: number, v: number): Color3
    return Color3.fromHSV(h % 1, math.clamp(s, 0, 1), math.clamp(v, 0, 1))
end

--- Returns the complementary color (180 degrees opposite on the color wheel).
function ColorTheory.complementary(color: Color3): Color3
    local h, s, v = color:ToHSV()
    return Color3.fromHSV((h + 0.5) % 1, s, v)
end

--- Returns a pair of split-complementary colors (150 and 210 degrees).
function ColorTheory.splitComplementary(color: Color3): (Color3, Color3)
    local h, s, v = color:ToHSV()
    return Color3.fromHSV((h + 5/12) % 1, s, v),
           Color3.fromHSV((h + 7/12) % 1, s, v)
end

--- Returns two analogous colors (30 degrees each side).
function ColorTheory.analogous(color: Color3): (Color3, Color3)
    local h, s, v = color:ToHSV()
    return Color3.fromHSV((h + 1/12) % 1, s, v),
           Color3.fromHSV((h - 1/12) % 1, s, v)
end

--- Returns two triadic colors (120 degrees apart).
function ColorTheory.triadic(color: Color3): (Color3, Color3)
    local h, s, v = color:ToHSV()
    return Color3.fromHSV((h + 1/3) % 1, s, v),
           Color3.fromHSV((h + 2/3) % 1, s, v)
end

--- Returns three tetradic colors (90 degrees apart forming a rectangle).
function ColorTheory.tetradic(color: Color3): (Color3, Color3, Color3)
    local h, s, v = color:ToHSV()
    return Color3.fromHSV((h + 0.25) % 1, s, v),
           Color3.fromHSV((h + 0.5) % 1, s, v),
           Color3.fromHSV((h + 0.75) % 1, s, v)
end

--- Generates a monochromatic palette (same hue, varying saturation/value).
function ColorTheory.monochromatic(color: Color3, count: number): { Color3 }
    local h, s, v = color:ToHSV()
    local colors: { Color3 } = {}
    for i = 1, count do
        local t = (i - 1) / (count - 1)
        local newV = 0.2 + t * 0.7
        local newS = s * (0.5 + t * 0.5)
        table.insert(colors, Color3.fromHSV(h, newS, newV))
    end
    return colors
end

--- Linearly interpolates between two colors.
function ColorTheory.lerp(a: Color3, b: Color3, t: number): Color3
    return a:Lerp(b, math.clamp(t, 0, 1))
end

--- Generates a gradient of N colors between two endpoints.
function ColorTheory.gradient(startColor: Color3, endColor: Color3, steps: number): { Color3 }
    local colors: { Color3 } = {}
    for i = 0, steps - 1 do
        local t = i / math.max(steps - 1, 1)
        table.insert(colors, startColor:Lerp(endColor, t))
    end
    return colors
end

--- Adjusts brightness of a color (factor > 1 = brighter, < 1 = darker).
function ColorTheory.adjustBrightness(color: Color3, factor: number): Color3
    local h, s, v = color:ToHSV()
    return Color3.fromHSV(h, s, math.clamp(v * factor, 0, 1))
end

--- Adjusts saturation of a color (factor > 1 = more saturated, < 1 = desaturated).
function ColorTheory.adjustSaturation(color: Color3, factor: number): Color3
    local h, s, v = color:ToHSV()
    return Color3.fromHSV(h, math.clamp(s * factor, 0, 1), v)
end

--- Desaturates a color completely (grayscale).
function ColorTheory.desaturate(color: Color3): Color3
    local h, s, v = color:ToHSV()
    return Color3.fromHSV(h, 0, v)
end

--- Returns a warm-shifted version of the color.
function ColorTheory.warmShift(color: Color3, amount: number): Color3
    local h, s, v = color:ToHSV()
    -- Shift toward orange (hue ~0.08)
    local warmHue = 0.08
    local newH = h + (warmHue - h) * math.clamp(amount, 0, 1)
    return Color3.fromHSV(newH % 1, s, v)
end

--- Returns a cool-shifted version of the color.
function ColorTheory.coolShift(color: Color3, amount: number): Color3
    local h, s, v = color:ToHSV()
    -- Shift toward blue (hue ~0.6)
    local coolHue = 0.6
    local newH = h + (coolHue - h) * math.clamp(amount, 0, 1)
    return Color3.fromHSV(newH % 1, s, v)
end

return ColorTheory
```

---

## 3. Color Palette Applicator

```luau
--!strict
-- ModuleScript: Applies palettes to UI or world objects

local Palettes = require(script.Parent.Palettes)

local PaletteApplicator = {}

--- Applies a palette to a set of BaseParts by role mapping.
function PaletteApplicator.applyToWorld(palette: Palettes.Palette, roleMap: { [string]: { BasePart } })
    local colorMap: { [string]: Color3 } = {
        primary = palette.primary,
        secondary = palette.secondary,
        accent = palette.accent,
        background = palette.background,
        highlight = palette.highlight,
        shadow = palette.shadow,
        danger = palette.danger,
        success = palette.success,
        warning = palette.warning,
    }

    for role, parts in roleMap do
        local color = colorMap[role]
        if color then
            for _, part in parts do
                part.Color = color
            end
        end
    end
end

--- Applies a palette to ScreenGui elements by naming convention.
--- Elements named "Primary", "Secondary", etc. get matching colors.
function PaletteApplicator.applyToGui(palette: Palettes.Palette, gui: ScreenGui)
    local colorMap: { [string]: Color3 } = {
        Primary = palette.primary,
        Secondary = palette.secondary,
        Accent = palette.accent,
        Background = palette.background,
        Foreground = palette.foreground,
        Highlight = palette.highlight,
    }

    for name, color in colorMap do
        for _, descendant in gui:GetDescendants() do
            if descendant.Name == name then
                if descendant:IsA("GuiObject") then
                    descendant.BackgroundColor3 = color
                end
            end
        end
    end
end

return PaletteApplicator
```

---

## 4. Quick Reference: Color3 Constructors

```luau
-- RGB (0-255 integers)
Color3.fromRGB(255, 128, 0)

-- HSV (0-1 floats: hue, saturation, value)
Color3.fromHSV(0.5, 1, 1) -- cyan

-- Hex string
Color3.fromHex("#FF8800")

-- Normalized (0-1 floats)
Color3.new(1, 0.5, 0)

-- Lerp between colors
Color3.fromRGB(255, 0, 0):Lerp(Color3.fromRGB(0, 0, 255), 0.5) -- purple
```

---

## 

---

## Learned Lessons

<!-- skill-evolve 에이전트가 자동으로 이 섹션에 교훈을 추가합니다 -->
<!-- 형식: ### [날짜] 문제명 / 원인 / 해결 / 규칙 -->

## Self-Evolution Protocol

이 스킬에서 에러가 발생하면:
1. 에러의 근본 원인을 분석한다
2. 이 파일의 `## Learned Lessons` 섹션에 교훈을 추가한다
3. 같은 실수가 반복되지 않도록 규칙화한다
4. SessionManager에 에러와 학습 내용을 기록한다

```lua
local SM = require(game.ServerStorage._RobloxEngine.SessionManager)
SM.logAction("SKILL_ERROR", "[이 스킬 이름] | [에러 설명]")
SM.logAction("SKILL_LEARNED", "[이 스킬 이름] | [배운 교훈]")
```

**매 작업 시 반드시 Learned Lessons 섹션을 먼저 읽고, 기존 교훈을 위반하지 않는지 확인한다.**

$ARGUMENTS

- `palette_name` (string) - Theme name: "DarkFantasy", "Neon", "Pastel", "Cyberpunk", "Nature", "Ocean", "Lava", "Arctic"
- `base_color` (Color3) - Base color for generating harmonies
- `harmony_type` (string) - "complementary", "analogous", "triadic", "tetradic", "splitComplementary", "monochromatic"
- `brightness_factor` (number) - Brightness adjustment multiplier (1 = unchanged)
- `saturation_factor` (number) - Saturation adjustment multiplier (1 = unchanged)
- `gradient_steps` (number) - Number of colors in a gradient
- `gradient_start` (Color3) - Starting color for gradient
- `gradient_end` (Color3) - Ending color for gradient
