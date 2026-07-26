--!strict
-- Minimal imperative instance builder used by every UIKit component.
-- Not a reactive framework on purpose: this project has no build step, so a
-- tiny `Create(className, props, children)` helper keeps UI code readable
-- without pulling in Roact/Fusion as a dependency.

local TweenService = game:GetService("TweenService")

local Util = {}

export type PropsTable = { [string]: any }

function Util.Create(className: string, props: PropsTable?, children: { Instance }?): Instance
	local instance = Instance.new(className)

	if props then
		for key, value in props do
			if key ~= "Parent" then
				(instance :: any)[key] = value
			end
		end
	end

	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	if props and props.Parent then
		instance.Parent = props.Parent
	end

	return instance
end

function Util.Tween(
	instance: Instance,
	properties: { [string]: any },
	duration: number?,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tweenInfo = TweenInfo.new(duration or 0.22, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out)
	local tween = TweenService:Create(instance :: any, tweenInfo, properties)
	tween:Play()
	return tween
end

return Util
