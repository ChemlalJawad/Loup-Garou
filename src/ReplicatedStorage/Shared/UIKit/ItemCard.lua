--!strict
-- The one card used for anything collectible: inventory entries, index slots,
-- shop offers, hatch-reveal results. Rarity-accented, optional count badge,
-- optional locked/silhouette state, optional footer button.
--
-- Every system showing a Brainrot should use this so a Legendary looks
-- identical whether you're seeing it in your inventory, the index, or a
-- hatch reveal.

local Theme = require(script.Parent.Parent.Theme)
local Util = require(script.Parent.Util)
local RarityBadge = require(script.Parent.RarityBadge)

local ItemCard = {}

export type ItemCardProps = {
	Parent: Instance?,
	LayoutOrder: number?,
	Size: UDim2?,
	Title: string,
	Rarity: string?,
	Subtitle: string?,
	Count: number?, -- shows an "x3" badge when > 1
	Locked: boolean?, -- undiscovered: dims everything and hides the title
	Selected: boolean?,
	OnClick: (() -> ())?,
	FooterText: string?, -- e.g. a price or "EQUIP"
	OnFooterClick: (() -> ())?,
}

export type ItemCardHandle = {
	Root: Frame,
	SetSelected: (self: ItemCardHandle, selected: boolean) -> (),
	SetFooterText: (self: ItemCardHandle, text: string) -> (),
}

function ItemCard.new(props: ItemCardProps): ItemCardHandle
	local rarity = props.Rarity or "Common"
	local accent = Theme.RarityColor(rarity)
	local locked = props.Locked == true

	local card = Util.Create("Frame", {
		Name = "ItemCard",
		BackgroundColor3 = Theme.Color.SurfaceRaised,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(150, 170),
		LayoutOrder = props.LayoutOrder,
		Parent = props.Parent,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = card })

	local stroke = Util.Create("UIStroke", {
		Color = if locked then Theme.Color.Stroke else accent,
		Thickness = if props.Selected then Theme.Stroke.Thick else Theme.Stroke.Thin,
		Transparency = if locked then 0.5 else 0,
		Parent = card,
	}) :: UIStroke

	-- Rarity wash: a vertical gradient tinted by rarity behind the content, so
	-- a Secret reads as special at a glance without needing an icon asset.
	local wash = Util.Create("Frame", {
		Name = "Wash",
		BackgroundColor3 = accent,
		BackgroundTransparency = if locked then 0.94 else 0.78,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = card,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Medium, Parent = wash })
	Util.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 90,
		Parent = wash,
	})

	-- Placeholder art plate. There's no mesh/decal pipeline in this project, so
	-- collectibles are represented by a rarity-colored plate carrying the
	-- character's initials rather than a portrait image.
	local artPlate = Util.Create("Frame", {
		Name = "ArtPlate",
		BackgroundColor3 = Theme.Color.Background,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 10, 0, 10),
		Size = UDim2.new(1, -20, 0, 84),
		Parent = card,
	}) :: Frame
	Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = artPlate })

	local initials = ""
	if not locked then
		for word in string.gmatch(props.Title, "%u") do
			initials ..= word
			if #initials >= 3 then
				break
			end
		end
		if initials == "" then
			initials = string.upper(string.sub(props.Title, 1, 2))
		end
	else
		initials = "?"
	end

	Util.Create("TextLabel", {
		Name = "Initials",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 1, 0),
		Text = initials,
		TextColor3 = if locked then Theme.Color.TextDisabled else accent,
		Font = Theme.Font.Heading,
		TextSize = 30,
		Parent = artPlate,
	})

	Util.Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 8, 0, 98),
		Size = UDim2.new(1, -16, 0, 20),
		Text = if locked then "???" else props.Title,
		TextColor3 = if locked then Theme.Color.TextDisabled else Theme.Color.TextPrimary,
		TextScaled = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Font = Theme.Font.SubHeading,
		TextSize = 13,
		Parent = card,
	})

	if props.Subtitle then
		Util.Create("TextLabel", {
			Name = "Subtitle",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 8, 0, 116),
			Size = UDim2.new(1, -16, 0, 16),
			Text = props.Subtitle,
			TextColor3 = Theme.Color.TextSecondary,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Font = Theme.Font.Body,
			TextSize = 11,
			Parent = card,
		})
	end

	if props.Rarity and not locked then
		local badge = RarityBadge.new({ Rarity = rarity, Parent = card })
		badge.Position = UDim2.new(0, 8, 0, 134)
		badge.Size = UDim2.new(0, 70, 0, 18)
	end

	if props.Count and props.Count > 1 then
		local countBadge = Util.Create("TextLabel", {
			Name = "CountBadge",
			BackgroundColor3 = Theme.Color.Background,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.fromOffset(34, 22),
			Text = `x{props.Count}`,
			TextColor3 = accent,
			Font = Theme.Font.SubHeading,
			TextSize = 12,
			ZIndex = 3,
			Parent = card,
		}) :: TextLabel
		Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Pill, Parent = countBadge })
		Util.Create("UIStroke", { Color = accent, Thickness = Theme.Stroke.Thin, Parent = countBadge })
	end

	local footerLabel: TextLabel? = nil
	if props.FooterText then
		local footer = Util.Create("TextButton", {
			Name = "Footer",
			AutoButtonColor = false,
			BackgroundColor3 = if locked then Theme.Color.Background else accent,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -8),
			Size = UDim2.new(1, -16, 0, 26),
			Text = props.FooterText,
			TextColor3 = if locked then Theme.Color.TextDisabled else Color3.fromRGB(14, 18, 16),
			Font = Theme.Font.SubHeading,
			TextSize = 12,
			ZIndex = 3,
			Parent = card,
		}) :: TextButton
		Util.Create("UICorner", { CornerRadius = Theme.CornerRadius.Small, Parent = footer })
		if props.OnFooterClick and not locked then
			footer.MouseButton1Click:Connect(props.OnFooterClick)
		end
		footerLabel = footer :: any
	end

	if props.OnClick and not locked then
		local hit = Util.Create("TextButton", {
			Name = "HitArea",
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = 2,
			Parent = card,
		}) :: TextButton
		hit.MouseButton1Click:Connect(props.OnClick)
		hit.MouseEnter:Connect(function()
			Util.Tween(card, { BackgroundColor3 = Theme.Color.Stroke }, Theme.Motion.Fast)
		end)
		hit.MouseLeave:Connect(function()
			Util.Tween(card, { BackgroundColor3 = Theme.Color.SurfaceRaised }, Theme.Motion.Fast)
		end)
	end

	local handle: ItemCardHandle
	handle = {
		Root = card,
		SetSelected = function(_self: ItemCardHandle, selected: boolean)
			stroke.Thickness = if selected then Theme.Stroke.Thick else Theme.Stroke.Thin
		end,
		SetFooterText = function(_self: ItemCardHandle, text: string)
			if footerLabel then
				footerLabel.Text = text
			end
		end,
	}
	return handle
end

return ItemCard
