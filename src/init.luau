--[=[
	@class DailyRewards

	API for handling daily rewards.

	What to track on the server for each player:
	- Claim streak (default to 0)
	- Time of last claim (default to 0)

	Setting up the rewards
	```lua
	local DailyRewardData = {
		[1] = {
			label = "+10 Cash",
			icon = "rbxassetid://117582891502895",
			rewardType = "Coins",
			value = 10,
		},
		[2] = {
			label = "+50 Cash",
			icon = "rbxassetid://18209599044",
			rewardType = "Coins",
			value = 50,
		},
		[3] = {
			label = "Knife Skin",
			icon = "rbxassetid://7660845823",
			rewardType = "skin",
			value = "Golden",
		},
		-- and so on
	}
	```

	Initiating the client:
	```lua
	local DailyRewards = require(Packages.DailyRewards)

	local profileData = getProfileData() -- Replace with your data fetcher

	DailyRewards.setupUI({
		screenGui = game.Players.LocalPlayer.PlayerGui.DailyRewards,

		-- New players should default to 0 for both values
		claimedDays = profileData.claimedDays,
		lastClaim = profileData.lastClaimTime or 0,

		data = DailyRewardData
	})
	```

	Handling claim requests on the server:
	```lua
	local DailyRewards = require(Packages.DailyRewards)

	local canClaim = DailyRewards.canClaim(day, playerProfile.lastClaimTime, playerProfile.claimedDays)

	-- "PlayerClaimRequest" is a signal that fires when a player requests
	-- to claim a reward using the Claim button in the daily rewards UI.
	DailyRewards.PlayerClaimRequest:Connect(function(
		player: Player,
		dayData: DailyRewards.DayData,
		day: DailyRewards.Day,
		claimTime: number
	)
		local playerData = DataService:GetData(player)

		if playerData then
			-- Check if the player can claim the reward
			local canClaim: boolean = DailyRewards.canClaim(day, playerProfile.lastClaimTime, playerProfile.claimedDays)

			if canClaim then
				-- Give the player the reward
				playerProfile.claimedDays = day
				playerProfile.lastClaimTime = claimTime
			end
		end
	end)
	```

	### Server signals
	`DailyRewards.PlayerClaimRequest - Signal.Signal<Player, DailyRewards.DayData, DailyRewards.Day, number>`

	### Client signals
	`DailyRewards.Claimed - :: Signal.Signal<DailyRewards.Day, DailyRewards.DayData>,
	`DailyRewards.VisibilityChanged :: Signal.Signal<boolean>`
]=]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Signal = require(script.Parent.Signal)

local OPEN_POSITION = UDim2.fromScale(0.5, 0.5)
local CLOSED_POSITION = UDim2.fromScale(0.5, -1)

local remote: RemoteEvent

if RunService:IsClient() then
	remote = script:WaitForChild("DailyRewardsEvent")
else
	remote = Instance.new("RemoteEvent")
	remote.Name = "DailyRewardsEvent"
	remote.Parent = script
end

export type Day = number

export type DayData = {
	label: string,
	icon: string,

	-- Internal
	rewardType: string,
	value: unknown,
}

export type Settings = {
	claimedDays: number,
	lastClaim: number,
	screenGui: ScreenGui,

	data: { [Day]: DayData },
}

export type InitialData = {
	lastClaimAt: number,
	claimedDays: number,
}

local TIME_DAY = 86400

local DailyRewards = {
	_running = false,

	_wrap = nil :: GuiObject?,
	_rewards = {} :: { [Day]: {
		object: GuiObject,
		claimed: GuiObject,
	} },

	_connections = {} :: { RBXScriptConnection },

	visible = true :: boolean,

	-- Server signals
	PlayerClaimRequest = Signal.new() :: Signal.Signal<Player, DayData, Day, number>,

	-- Client signals
	Claimed = Signal.new() :: Signal.Signal<Day, DayData>,
	VisibilityChanged = Signal.new() :: Signal.Signal<boolean>,
}

--[=[
	Returns the number of days passed since the last claim.

	@param lastClaimAt number -- Time of the last claim
	@return number -- Number of days passed
]=]
function DailyRewards.daysPassed(lastClaimAt: number): number
	return (Workspace:GetServerTimeNow() - lastClaimAt) / TIME_DAY
end

--[=[
	Checks if the streak should be reset based on the last claim time.
	If the claim was over 48 hours ago, the streak should be reset.

	@param lastClaimAt number -- Time of the last claim
	@return boolean -- Whether the streak should be reset
]=]
function DailyRewards.shouldResetStreak(lastClaimAt: number): boolean
	return DailyRewards.daysPassed(lastClaimAt) >= 2
end

--[=[
	Returns time remaining until the next claim can be made.

	@param lastClaimAt number -- Time of the last claim
	@return number -- Time until the next claim in seconds
]=]
function DailyRewards.timeUntilNextClaim(lastClaimAt: number): number
	return TIME_DAY - (Workspace:GetServerTimeNow() - lastClaimAt) % TIME_DAY
end

--[=[
	Returns what day the player can claim at the current time.

	If `nil` is returned, the player cannot claim anything yet.

	If the streak should be reset, then the return value will be 1 (the first day).

	@param lastClaimAt number -- Time of the last claim
	@param daysClaimed number -- Number of days the player has claimed
	@return number? -- The day the player can claim, or nil if they cannot claim yet
]=]
function DailyRewards.dayToClaim(lastClaimAt: number, daysClaimed: number): number?
	local daysPassed = DailyRewards.daysPassed(lastClaimAt)

	if DailyRewards.shouldResetStreak(lastClaimAt) then
		return 1
	end

	-- Cannot claim yet
	if daysPassed < 1 then
		return nil
	end

	return daysClaimed + 1
end

--[=[
	Verification function to check if the player can claim a requested day.

	@param requestedDay number -- The day the player wants to claim
	@param lastClaimAt number -- Time of the last claim
	@param daysClaimed number -- Number of days the player has claimed
	@return boolean -- Whether the player can claim the requested day
]=]
function DailyRewards.canClaim(
	requestedDay: number,
	lastClaimAt: number,
	daysClaimed: number
): boolean
	local dayToClaim = DailyRewards.dayToClaim(lastClaimAt, daysClaimed)

	return if dayToClaim then dayToClaim == requestedDay else false
end

-- UI functions
--[=[
	Sets the current UI visibility.

	@client
	@param visible boolean -- Whether to show the UI
	@param instant boolean? -- Whether to show the UI instantly instead of tweening it (default: false)
]=]
function DailyRewards.setVisibility(visible: boolean, instant: boolean?)
	assert(
		DailyRewards._running,
		"DailyRewards.initClient must be called before setting visibility"
	)

	if DailyRewards._wrap then
		local newPosition = if visible then OPEN_POSITION else CLOSED_POSITION

		if instant then
			DailyRewards._wrap.Position = newPosition
		else
			DailyRewards._wrap:TweenPosition(
				newPosition,
				Enum.EasingDirection.InOut,
				Enum.EasingStyle.Quad,
				0.3,
				true
			)
		end
	end

	DailyRewards.visible = visible
	DailyRewards.VisibilityChanged:Fire(visible)
end

--[=[
	Shows the daily rewards UI.

	Shortcut for `DailyRewards.setVisibility(true)`.

	@client
	@param instant boolean? -- Whether to show the UI instantly (default: false)
]=]
function DailyRewards.show()
	DailyRewards.setVisibility(true)
end

--[=[
	Hides the daily rewards UI.

	Shortcut for `DailyRewards.setVisibility(false)`.

	@client
	@param instant boolean? -- Whether to hide the UI instantly (default: false)
]=]
function DailyRewards.hide()
	DailyRewards.setVisibility(false)
end

local function setClaimedDays(days: number)
	for day: Day, data: { object: GuiObject, claimed: GuiObject } in
		pairs(DailyRewards._rewards)
	do
		data.claimed.Visible = day <= days
	end
end

--[=[
	Sets up server-side functionality for daily rewards.

	Each day given in `data` should also exist inside the UI (example we have )

	@param data { [number]: DailyRewards.DayData } -- The reward data for each day
]=]
function DailyRewards.initServer(data: { DayData })
	remote.OnServerEvent:Connect(function(player: Player, day: number)
		local dayData = data[day]

		if not dayData then
			return
		end

		DailyRewards.PlayerClaimRequest:Fire(
			player,
			dayData,
			day,
			Workspace:GetServerTimeNow()
		)
	end)
end

--[=[
	Sets up the UI for the daily rewards.

	@param settings Settings
]=]
function DailyRewards.initClient(settings: Settings)
	assert(RunService:IsClient(), "DailyRewards.initClient must be called on the client")
	assert(not DailyRewards._running, "DailyRewards is already running")

	local lastClaimAt: number = settings.lastClaim
	local claimedDays: number = settings.claimedDays

	DailyRewards._running = true

	DailyRewards._screenGui = settings.screenGui
	DailyRewards._wrap = settings.screenGui:WaitForChild("Wrap") :: GuiObject

	assert(DailyRewards._wrap, `"Wrap" not found in the provided ScreenGui`)

	DailyRewards._list = DailyRewards._wrap:WaitForChild("List") :: GuiObject
	DailyRewards._closeButton =
		DailyRewards._wrap:WaitForChild("CloseButton") :: GuiButton
	DailyRewards._claimButton =
		DailyRewards._wrap:WaitForChild("ClaimButton") :: GuiButton

	assert(DailyRewards._list, `"List" not found in DailyRewards.Wrap`)
	assert(DailyRewards._closeButton, `"CloseButton" not found in DailyRewards.Wrap`)
	assert(DailyRewards._claimButton, `"ClaimButton" not found in DailyRewards.Wrap`)

	DailyRewards.setVisibility(false, true)
	settings.screenGui.Enabled = true

	-- Set up day frames
	for day: Day, data: DayData in pairs(settings.data) do
		local guiObject = DailyRewards._list:FindFirstChild(tostring(day)) :: GuiObject

		assert(
			guiObject,
			`Frame for day {day} named "{day}" not found in DailyRewards.Wrap.List`
		)

		local claimedFrame = guiObject:FindFirstChild("Claimed") :: GuiObject
		local lock = guiObject:FindFirstChild("Lock") :: GuiObject
		local lockLabel = lock and lock:FindFirstChild("Label") :: TextLabel
		local label = guiObject:FindFirstChild("Label") :: TextLabel
		local icon = guiObject:FindFirstChild("Icon") :: ImageLabel

		assert(
			claimedFrame,
			`Frame for claimed day {day} named "Claimed" not found in DailyRewards.Wrap.List.{day}`
		)
		assert(lockLabel, `Lock label not found in DailyRewards.Wrap.List.{day}.Lock`)
		assert(label, `Label not found in DailyRewards.Wrap.List.{day}`)
		assert(icon, `Icon not found in DailyRewards.Wrap.List.{day}`)

		label.Text = data.label
		lockLabel.Text = `Day {day}`
		icon.Image = data.icon

		DailyRewards._rewards[day] = {
			object = guiObject,
			claimed = claimedFrame,
		}
	end

	table.insert(
		DailyRewards._connections,
		DailyRewards._closeButton.Activated:Connect(function()
			DailyRewards.setVisibility(not DailyRewards.visible)
		end)
	)

	table.insert(
		DailyRewards._connections,
		DailyRewards._claimButton.Activated:Connect(function()
			local dayToClaim = DailyRewards.dayToClaim(lastClaimAt, claimedDays)

			if not dayToClaim then
				-- Cannot claim yet
				return
			end

			lastClaimAt = Workspace:GetServerTimeNow()

			setClaimedDays(dayToClaim)

			local dayData = settings.data[dayToClaim]

			DailyRewards.Claimed:Fire(1, dayData)

			remote:FireServer(dayToClaim)
		end)
	)

	table.insert(
		DailyRewards._connections,
		RunService.Stepped:Connect(function()
			if DailyRewards.shouldResetStreak(lastClaimAt) then
				setClaimedDays(0)
			end

			-- Check if the calendar should reset
			local isLastDay = claimedDays == #settings.data

			if not isLastDay then
				local daysPassed = DailyRewards.daysPassed(lastClaimAt)

				if daysPassed >= 2 then
					setClaimedDays(0)
				end
			end
		end)
	)

	setClaimedDays(claimedDays)
end

return DailyRewards
