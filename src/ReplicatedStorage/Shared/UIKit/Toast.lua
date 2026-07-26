--!strict
-- A single auto-dismissing toast notification card. Extracted from
-- Shell.lua's original inline implementation so any future screen that
-- wants a one-off notification can reuse the same visual without a second,
-- competing implementation living inside Shell.lua. Shell.Notify (the
-- public API other systems call) is now a thin wrapper around this.

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local Toast = {}

export type ToastKind = "Info" | "Success" | "Warning" | "Error"

export type ToastProps = {
	Parent: Instance,
	Message: string,
	Kind: ToastKind?,
	Duration: number?, -- seconds fully visible before it fades out, default 3.2
	LayoutOrder: number?,
}

local KIND_COLOR: { [string]: Color3 } = {
	Info = Theme.Color.AccentInfo,
	Success = Theme.Color.AccentPrimary,
	Warning = Theme.Color.AccentWarning,
	Error = Theme.Color.AccentDanger,
}

function Toast.new(props: ToastProps): Frame
	local color = KIND_COLOR[props.Kind or "Info"] or Theme.Color.AccentInfo

	local toast = Util.Create("Frame", {
		Name = "Toast",
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = toast })
	Util.Create("UIStroke", { Color = color, Thickness = Theme.Stroke.Regular, Parent = toast })
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, 10),
		PaddingBottom = UDim.new(0, 10),
		PaddingLeft = UDim.new(0, 18),
		PaddingRight = UDim.new(0, 14),
		Parent = toast,
	})

	-- Left accent tab - a quick "what kind of toast is this" read before the
	-- text even registers, common in modern notification-card UIs.
	Util.Create("Frame", {
		Name = "AccentBar",
		BackgroundColor3 = color,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 4, 1, 0),
		Parent = toast,
	})

	local textLabel = Util.Create("TextLabel", {
		Name = "Message",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = props.Message,
		TextWrapped = true,
		TextTransparency = 1,
		TextColor3 = Theme.Color.TextPrimary,
		Font = Theme.Font.Body,
		TextSize = 15,
		Parent = toast,
	}) :: TextLabel

	local accentBar = toast:FindFirstChild("AccentBar") :: Frame
	Util.Tween(toast, { BackgroundTransparency = 0 }, Theme.Motion.Normal)
	Util.Tween(textLabel, { TextTransparency = 0 }, Theme.Motion.Normal)
	Util.Tween(accentBar, { BackgroundTransparency = 0 }, Theme.Motion.Normal)

	task.delay(props.Duration or 3.2, function()
		if not toast.Parent then
			return
		end
		Util.Tween(toast, { BackgroundTransparency = 1 }, Theme.Motion.Normal)
		Util.Tween(textLabel, { TextTransparency = 1 }, Theme.Motion.Normal)
		Util.Tween(accentBar, { BackgroundTransparency = 1 }, Theme.Motion.Normal)
		task.delay(Theme.Motion.Normal, function()
			toast:Destroy()
		end)
	end)

	return toast
end

return Toast
