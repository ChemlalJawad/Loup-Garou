--!strict
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local RarityBadge = {}

export type RarityBadgeProps = {
	Parent: Instance?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Rarity: string,
}

function RarityBadge.new(props: RarityBadgeProps): TextLabel
	local color = Theme.RarityColor(props.Rarity)

	local badge = Util.Create("TextLabel", {
		Name = "RarityBadge",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 84, 0, 22),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Text = string.upper(props.Rarity),
		TextColor3 = Color3.fromRGB(15, 15, 20),
		Font = Theme.Font.SubHeading,
		TextSize = 12,
		Parent = props.Parent,
	}) :: TextLabel

	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = badge })

	return badge
end

return RarityBadge
