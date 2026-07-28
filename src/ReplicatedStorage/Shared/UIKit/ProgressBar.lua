--!strict
-- Labelled progress/fill bar, used for quest progress, XP, cooldowns and
-- index-completion meters.

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local ProgressBar = {}

export type ProgressBarProps = {
	Parent: Instance?,
	Position: UDim2?,
	Size: UDim2?,
	LayoutOrder: number?,
	AccentColor: Color3?,
	ShowLabel: boolean?, -- centred "3 / 10" text inside the bar
}

export type ProgressBarHandle = {
	Root: Frame,
	SetProgress: (self: ProgressBarHandle, current: number, total: number, animate: boolean?) -> (),
}

function ProgressBar.new(props: ProgressBarProps): ProgressBarHandle
	local accent = props.AccentColor or Theme.Color.AccentPrimary

	local track = Util.Create("Frame", {
		Name = "ProgressBar",
		BackgroundColor3 = Theme.Color.Background,
		BorderSizePixel = 0,
		Position = props.Position,
		Size = props.Size or UDim2.new(1, 0, 0, 18),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = track })
	Util.Create("UIStroke", {
		Color = Theme.Color.Stroke,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.5,
		Parent = track,
	})

	local fill = Util.Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
		Parent = track,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = fill })

	local label: TextLabel? = nil
	if props.ShowLabel then
		label = Util.Create("TextLabel", {
			Name = "Label",
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 1, 0),
			Text = "0 / 0",
			TextColor3 = Theme.Color.TextPrimary,
			Font = Theme.Font.SubHeading,
			TextSize = 12,
			ZIndex = 2,
			Parent = track,
		}) :: TextLabel
	end

	local handle: ProgressBarHandle
	handle = {
		Root = track,
		SetProgress = function(_self: ProgressBarHandle, current: number, total: number, animate: boolean?)
			local ratio = if total > 0 then math.clamp(current / total, 0, 1) else 0
			local goal = UDim2.new(ratio, 0, 1, 0)
			if animate == false then
				fill.Size = goal
			else
				Util.Tween(fill, { Size = goal }, Theme.Motion.Normal)
			end
			if label then
				label.Text = `{math.floor(current)} / {math.floor(total)}`
			end
		end,
	}
	return handle
end

return ProgressBar
