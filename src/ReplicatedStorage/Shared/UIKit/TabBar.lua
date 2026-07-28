--!strict
-- Horizontal tab switcher. Calls OnChange(tabId) when the selection changes;
-- the caller is responsible for showing/hiding its own content frames.

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local TabBar = {}

export type TabSpec = {
	Id: string,
	Label: string,
}

export type TabBarProps = {
	Tabs: { TabSpec },
	Parent: Instance?,
	Position: UDim2?,
	Size: UDim2?,
	AccentColor: Color3?,
	OnChange: (tabId: string) -> (),
}

export type TabBarHandle = {
	Root: Frame,
	Select: (self: TabBarHandle, tabId: string) -> (),
	GetSelected: (self: TabBarHandle) -> string,
}

function TabBar.new(props: TabBarProps): TabBarHandle
	local accent = props.AccentColor or Theme.Color.AccentPrimary

	local root = Util.Create("Frame", {
		Name = "TabBar",
		BackgroundTransparency = 1,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, 40),
		Parent = props.Parent,
	}) :: Frame
	Util.Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, Theme.Spacing.S),
		Parent = root,
	})

	local buttons: { [string]: TextButton } = {}
	local selected = props.Tabs[1] and props.Tabs[1].Id or ""

	local function paint()
		for id, button in buttons do
			local isActive = id == selected
			button.BackgroundColor3 = if isActive then accent else Theme.Color.Background
			button.TextColor3 = if isActive then Color3.fromRGB(12, 18, 14) else Theme.Color.TextSecondary
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = if isActive then 1 else 0
			end
		end
	end

	local handle: TabBarHandle
	handle = {
		Root = root,
		Select = function(_self: TabBarHandle, tabId: string)
			if not buttons[tabId] or selected == tabId then
				return
			end
			selected = tabId
			paint()
			props.OnChange(tabId)
		end,
		GetSelected = function(_self: TabBarHandle): string
			return selected
		end,
	}

	for index, tab in props.Tabs do
		local button = Util.Create("TextButton", {
			Name = `Tab_{tab.Id}`,
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Color.Background,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 130, 1, 0),
			LayoutOrder = index,
			Text = tab.Label,
			TextColor3 = Theme.Color.TextSecondary,
			Font = Theme.Font.SubHeading,
			TextSize = 15,
			Parent = root,
		}) :: TextButton
		Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = button })
		Util.Create("UIStroke", { Color = Theme.Color.Stroke, Thickness = Theme.Stroke.Thin, Parent = button })

		button.MouseButton1Click:Connect(function()
			handle:Select(tab.Id)
		end)

		buttons[tab.Id] = button
	end

	paint()
	return handle
end

return TabBar
