--!strict
-- A standard centred screen panel: titled header, close button, and a content
-- frame for the caller to fill. This is the shell every full-screen system UI
-- (Eggs, Shop, Store, Index, Quests, Daily, Leaderboards, Settings) should use
-- so they all share one silhouette instead of each hand-rolling a Frame.
--
-- Usage:
--   local modal = UIKit.Modal.new({ Title = "EGGS", Size = UDim2.fromOffset(760, 520) })
--   modal.Root.Parent = Shell.GetScreenGui()
--   Shell.RegisterPanel("Eggs", modal.Root)   -- Shell owns visibility
--   -- build into modal.Content

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)

local Modal = {}

export type ModalProps = {
	Title: string,
	Subtitle: string?,
	Size: UDim2?,
	Parent: Instance?,
	AccentColor: Color3?,
	OnClose: (() -> ())?,
}

export type ModalHandle = {
	Root: Frame,
	Content: Frame,
	Header: Frame,
	TitleLabel: TextLabel,
	SubtitleLabel: TextLabel,
	SetTitle: (self: ModalHandle, title: string, subtitle: string?) -> (),
}

function Modal.new(props: ModalProps): ModalHandle
	local accent = props.AccentColor or Theme.Color.AccentPrimary

	local root = Util.Create("Frame", {
		Name = "Modal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = props.Size or UDim2.fromOffset(760, 520),
		BackgroundColor3 = Theme.Color.Surface,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 20,
		Parent = props.Parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Large, Parent = root })
	Util.Create("UIStroke", {
		Color = accent,
		Thickness = Theme.Stroke.Thin,
		Transparency = 0.5,
		Parent = root,
	})

	local header = Util.Create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 64),
		Parent = root,
	}) :: Frame

	local titleLabel = Util.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 24, 0, 12),
		Size = UDim2.new(1, -90, 0, 26),
		Text = props.Title,
		TextColor3 = Theme.Color.TextPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Heading,
		TextSize = 22,
		Parent = header,
	}) :: TextLabel

	local subtitleLabel = Util.Create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 24, 0, 38),
		Size = UDim2.new(1, -90, 0, 18),
		Text = props.Subtitle or "",
		TextColor3 = Theme.Color.TextSecondary,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Font.Body,
		TextSize = 14,
		Parent = header,
	}) :: TextLabel

	-- Accent underline separating header from content.
	Util.Create("Frame", {
		Name = "HeaderRule",
		BackgroundColor3 = accent,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = header,
	})

	local closeButton = Util.Create("TextButton", {
		Name = "CloseButton",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Color.Background,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -18, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		Text = "X",
		TextColor3 = Theme.Color.TextSecondary,
		Font = Theme.Font.SubHeading,
		TextSize = 16,
		Parent = header,
	}) :: TextButton
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = closeButton })
	Util.Create("UIStroke", { Color = Theme.Color.Stroke, Thickness = Theme.Stroke.Thin, Parent = closeButton })

	closeButton.MouseEnter:Connect(function()
		Util.Tween(closeButton, { BackgroundColor3 = Theme.Color.AccentDanger }, Theme.Motion.Fast)
	end)
	closeButton.MouseLeave:Connect(function()
		Util.Tween(closeButton, { BackgroundColor3 = Theme.Color.Background }, Theme.Motion.Fast)
	end)
	closeButton.MouseButton1Click:Connect(function()
		root.Visible = false
		if props.OnClose then
			props.OnClose()
		end
	end)

	local content = Util.Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 64),
		Size = UDim2.new(1, 0, 1, -64),
		Parent = root,
	}) :: Frame
	Util.Create("UIPadding", {
		PaddingTop = UDim.new(0, Theme.Spacing.M),
		PaddingBottom = UDim.new(0, Theme.Spacing.M),
		PaddingLeft = UDim.new(0, Theme.Spacing.L),
		PaddingRight = UDim.new(0, Theme.Spacing.L),
		Parent = content,
	})

	local handle: ModalHandle
	handle = {
		Root = root,
		Content = content,
		Header = header,
		TitleLabel = titleLabel,
		SubtitleLabel = subtitleLabel,
		SetTitle = function(_self: ModalHandle, title: string, subtitle: string?)
			titleLabel.Text = title
			if subtitle ~= nil then
				subtitleLabel.Text = subtitle
			end
		end,
	}
	return handle
end

return Modal
