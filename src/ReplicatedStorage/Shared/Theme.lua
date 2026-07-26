--!strict
-- Design tokens shared by every UI surface in the game.
-- Keep this the single source of truth for colors/fonts/spacing so the whole
-- game reads as one consistent product instead of five bolted-together UIs.

local Theme = {}

Theme.Color = {
	Background = Color3.fromRGB(18, 18, 26), -- near-black navy, base canvas
	Surface = Color3.fromRGB(27, 27, 40), -- panels / cards
	SurfaceRaised = Color3.fromRGB(36, 36, 52), -- hovered / elevated cards
	Stroke = Color3.fromRGB(52, 52, 74),

	TextPrimary = Color3.fromRGB(245, 245, 250),
	TextSecondary = Color3.fromRGB(168, 168, 190),
	TextDisabled = Color3.fromRGB(102, 102, 122),

	AccentPrimary = Color3.fromRGB(57, 255, 136), -- neon green (CTA, coins)
	AccentSecondary = Color3.fromRGB(177, 78, 255), -- neon purple (gems, secret rarity)
	AccentDanger = Color3.fromRGB(255, 82, 82),
	AccentWarning = Color3.fromRGB(255, 184, 76),
	AccentInfo = Color3.fromRGB(70, 158, 255),

	Robux = Color3.fromRGB(53, 214, 100), -- Roblox's own green, used only for Robux price tags
}

Theme.Rarity = {
	Common = Color3.fromRGB(158, 165, 178),
	Rare = Color3.fromRGB(70, 158, 255),
	Epic = Color3.fromRGB(177, 78, 255),
	Legendary = Color3.fromRGB(255, 184, 76),
	Secret = Color3.fromRGB(255, 82, 130),
}

Theme.Team = {
	Red = Color3.fromRGB(255, 71, 87),
	Blue = Color3.fromRGB(46, 134, 255),
}

Theme.Font = {
	Heading = Enum.Font.GothamBlack,
	SubHeading = Enum.Font.GothamBold,
	Body = Enum.Font.GothamMedium,
	Mono = Enum.Font.RobotoMono,
}

Theme.CornerRadius = {
	Small = UDim.new(0, 8),
	Medium = UDim.new(0, 14),
	Large = UDim.new(0, 22),
	Pill = UDim.new(1, 0),
}

Theme.Spacing = {
	XS = 4,
	S = 8,
	M = 12,
	L = 20,
	XL = 32,
}

Theme.Stroke = {
	Thin = 1,
	Regular = 2,
	Thick = 3,
}

-- Standard tween timing so every panel opens/closes with the same feel.
Theme.Motion = {
	Fast = 0.12,
	Normal = 0.22,
	Slow = 0.35,
	EasingStyle = Enum.EasingStyle.Quint,
	EasingDirection = Enum.EasingDirection.Out,
}

function Theme.RarityColor(rarity: string): Color3
	return Theme.Rarity[rarity] or Theme.Rarity.Common
end

return Theme
