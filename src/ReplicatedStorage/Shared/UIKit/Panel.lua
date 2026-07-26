--!strict
local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local Panel = {}

export type PanelProps = {
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Name: string?,
	Raised: boolean?,
	Padding: number?,
}

function Panel.new(props: PanelProps): Frame
	local panel = Util.Create("Frame", {
		Name = props.Name or "Panel",
		BackgroundColor3 = if props.Raised then Theme.Color.SurfaceRaised else Theme.Color.Surface,
		Size = props.Size or UDim2.new(0, 300, 0, 200),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BorderSizePixel = 0,
		Parent = props.Parent,
	}) :: Frame

	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Large, Parent = panel })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.4,
		Parent = panel,
	})

	if props.Padding then
		Util.Create("UIPadding", {
			PaddingTop = UDim.new(0, props.Padding),
			PaddingBottom = UDim.new(0, props.Padding),
			PaddingLeft = UDim.new(0, props.Padding),
			PaddingRight = UDim.new(0, props.Padding),
			Parent = panel,
		})
	end

	return panel
end

return Panel
