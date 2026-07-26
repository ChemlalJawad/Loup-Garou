--!strict
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local CurrencyPill = {}

export type CurrencyPillProps = {
	Parent: Instance?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Label: string,
	IconText: string?, -- placeholder glyph until a real icon asset id is uploaded
	AccentColor: Color3?,
}

-- Returns the pill frame plus the amount TextLabel so callers can update it
-- (e.g. `local pill, label = CurrencyPill.new(...); label.Text = "1,250"`).
function CurrencyPill.new(props: CurrencyPillProps): (Frame, TextLabel)
	local accent = props.AccentColor or Theme.Color.AccentPrimary

	local pill = Util.Create("Frame", {
		Name = "CurrencyPill",
		BackgroundColor3 = Theme.Color.Surface,
		Size = UDim2.new(0, 140, 0, 40),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		BorderSizePixel = 0,
		Parent = props.Parent,
	}) :: Frame

	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = pill })
	Util.Create("UIStroke", { Color = accent, Thickness = Theme.Stroke.Thin, Transparency = 0.5, Parent = pill })
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = pill,
	})
	Util.Create("UIPadding", {
		PaddingLeft = UDim.new(0, 10),
		PaddingRight = UDim.new(0, 10),
		Parent = pill,
	})

	Util.Create("TextLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.new(0, 20, 1, 0),
		Text = props.IconText or "*",
		TextColor3 = accent,
		Font = Theme.Font.SubHeading,
		TextSize = 18,
		Parent = pill,
	})

	local label = Util.Create("TextLabel", {
		Name = "Amount",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -30, 1, 0),
		Text = props.Label,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.SubHeading,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = pill,
	}) :: TextLabel

	return pill, label
end

return CurrencyPill
