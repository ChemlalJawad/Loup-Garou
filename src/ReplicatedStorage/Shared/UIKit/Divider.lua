--!strict
-- A thin rule for separating sections inside a Panel (e.g. between a header
-- and a scrolling list). Matches the same `.new(props)` + Theme-token
-- pattern as every other UIKit component.

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local Divider = {}

export type DividerProps = {
	Parent: Instance?,
	LayoutOrder: number?,
	Vertical: boolean?, -- default false (horizontal rule)
	Thickness: number?, -- default 1
	Color: Color3?, -- default Theme.Color.Stroke
	Transparency: number?, -- default 0.3
}

function Divider.new(props: DividerProps): Frame
	local vertical = props.Vertical == true
	local thickness = props.Thickness or 1

	local divider = Util.Create("Frame", {
		Name = "Divider",
		BackgroundColor3 = props.Color or Theme.Color.Stroke,
		BackgroundTransparency = if props.Transparency then props.Transparency else 0.3,
		BorderSizePixel = 0,
		Size = if vertical then UDim2.new(0, thickness, 1, 0) else UDim2.new(1, 0, 0, thickness),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}) :: Frame

	return divider
end

return Divider
