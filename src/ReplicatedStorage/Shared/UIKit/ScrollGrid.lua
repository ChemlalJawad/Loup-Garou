--!strict
-- A ScrollingFrame pre-wired with a UIGridLayout (or UIListLayout) whose
-- CanvasSize tracks its content automatically. Saves every system from
-- re-deriving the AbsoluteContentSize plumbing.

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local ScrollGrid = {}

export type ScrollGridProps = {
	Parent: Instance?,
	Position: UDim2?,
	Size: UDim2?,
	CellSize: UDim2?, -- omit for a vertical list instead of a grid
	CellPadding: UDim2?,
	Vertical: boolean?, -- true = UIListLayout (rows) instead of a grid
}

export type ScrollGridHandle = {
	Root: ScrollingFrame,
	Clear: (self: ScrollGridHandle) -> (),
}

function ScrollGrid.new(props: ScrollGridProps): ScrollGridHandle
	local scroller = Util.Create("ScrollingFrame", {
		Name = "ScrollGrid",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 1, 0),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = Theme.Color.Stroke,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = props.Parent,
	}) :: ScrollingFrame

	local layout: Instance
	if props.Vertical then
		layout = Util.Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Theme.Spacing.S),
			Parent = scroller,
		})
	else
		layout = Util.Create("UIGridLayout", {
			CellSize = props.CellSize or UDim2.fromOffset(150, 170),
			CellPadding = props.CellPadding or UDim2.fromOffset(Theme.Spacing.M, Theme.Spacing.M),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = scroller,
		})
	end

	local function resize()
		local contentSize = (layout :: any).AbsoluteContentSize
		scroller.CanvasSize = UDim2.new(0, 0, 0, contentSize.Y + Theme.Spacing.M)
	end
	(layout :: any):GetPropertyChangedSignal("AbsoluteContentSize"):Connect(resize)
	resize()

	local handle: ScrollGridHandle
	handle = {
		Root = scroller,
		Clear = function(_self: ScrollGridHandle)
			for _, child in scroller:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
		end,
	}
	return handle
end

return ScrollGrid
