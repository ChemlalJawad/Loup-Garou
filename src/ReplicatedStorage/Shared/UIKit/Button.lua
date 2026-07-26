--!strict
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local Button = {}

export type ButtonVariant = "Primary" | "Secondary" | "Danger" | "Ghost"

export type ButtonProps = {
	Text: string,
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	LayoutOrder: number?,
	Variant: ButtonVariant?,
	OnClick: (() -> ())?,
}

local VARIANT_STYLE = {
	Primary = { Background = Theme.Color.AccentPrimary, Text = Color3.fromRGB(10, 20, 14), Stroke = false },
	Secondary = { Background = Theme.Color.Surface, Text = Theme.Color.TextPrimary, Stroke = true },
	Danger = { Background = Theme.Color.AccentDanger, Text = Color3.fromRGB(35, 8, 8), Stroke = false },
	Ghost = { Background = Theme.Color.Background, Text = Theme.Color.TextSecondary, Stroke = true },
}

function Button.new(props: ButtonProps): TextButton
	local style = VARIANT_STYLE[props.Variant or "Primary"]

	local button = Util.Create("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundColor3 = style.Background,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.new(0, 180, 0, 44),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder,
		Text = props.Text,
		TextColor3 = style.Text,
		Font = Theme.Font.SubHeading,
		TextSize = 18,
		Parent = props.Parent,
	}) :: TextButton

	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = button })

	if style.Stroke then
		Util.Create("UIStroke", {
			Color = Theme.Color.Stroke,
			Thickness = Theme.Stroke.Thin,
			Parent = button,
		})
	end

	button.MouseEnter:Connect(function()
		Util.Tween(button, { BackgroundTransparency = 0.12 }, Theme.Motion.Fast)
	end)
	button.MouseLeave:Connect(function()
		Util.Tween(button, { BackgroundTransparency = 0 }, Theme.Motion.Fast)
	end)

	if props.OnClick then
		button.MouseButton1Click:Connect(props.OnClick)
	end

	return button
end

return Button
