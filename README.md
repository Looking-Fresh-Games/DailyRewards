# Daily Rewards

### Setting up the UI
Download the [daily-rewards-template.rbxm](https://github.com/Looking-Fresh-Games/DailyRewards/blob/main/daily-rewards-template.rbxm) file from the repository and import it into Roblox Studio.
This template contains the necessary UI elements for the daily rewards system.

### Installing the wally dependency
Add the below line to your wally.toml file
```toml
DailyRewards = "lfg-studio/dailyrewards@1.0.0"
```

What to track on the server for each player:
- Claim streak (default to 0)
- Time of last claim (default to 0)

### Setting up the rewards
```lua
local DailyRewardData = {
	[1] = {
		label = "+10 Cash",
		icon = "rbxassetid://117582891502895",
		rewardType = "coins",
		value = 10,
	},
	[2] = {
		label = "+50 Cash",
		icon = "rbxassetid://18209599044",
		rewardType = "coins",
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

Note: Each day reward defined in `DailyRewardData` should have it's own frame in `DailyRewards.Wrap.List`

(example: `DailyRewards.Wrap.List.1`, `DailyRewards.Wrap.List.2`, `DailyRewards.Wrap.List.3`, etc.)

Each day frame should also contain:
- A `Label` for the reward name named "Label"
- An `ImageLabel` for the reward icon named "Icon"
- A `TextLabel` named "Label" insde a `Frame` named "Lock" to indicate which day streak the reward is for.

These labels and icons will be set depending on the data you provide in `DailyRewardData`.

### Initiating the client
```lua
local DailyRewards = require(Packages.DailyRewards)

local profileData = getProfileData() -- Replace with your data fetcher

DailyRewards.initClient({
	screenGui = game.Players.LocalPlayer.PlayerGui.DailyRewards,

	-- New players should default to 0 for both values
	claimedDays = profileData.claimedDays,
	lastClaim = profileData.lastClaimTime or 0,

	data = DailyRewardData
})
```

### Handling claim requests on the server
The `rewardType` and `value` fields in the `DailyRewardData` table are used to determine what reward to give the player.
They can be set to any value you want.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DailyRewards = require(Packages.DailyRewards)

local DailyRewardData = require(ReplicatedStorage.Shared.Data.DailyRewardData)

DailyRewards.initServer(DailyRewardData) -- Must initialize the rewards system by passing the reward data

-- "PlayerClaimRequest" is a signal that fires when a player requests
-- to claim a reward using the Claim button in the daily rewards UI.
DailyRewards.PlayerClaimRequest:Connect(function(
	player: Player,
	dayData: DailyRewards.DayData,
	day: DailyRewards.Day,
	claimTime: number
)
	local playerData = DataService:GetData(player)

	if not playerData then
		return
	end

	-- Check if the player can claim the reward
	local canClaim: boolean = DailyRewards.canClaim(day, playerData.LastClaim, playerData.ClaimedDays)

	if not canClaim then
		return
	end

	-- Give the player the reward
	playerData.ClaimedDays = day
	playerData.LastClaim = claimTime

	-- Handle awarding the reward based on the `rewardType` and `value` fields
	if dayData.rewardType == "coins" then
		playerData.Coins += dayData.value :: number
	end
end)
```

## Signals
You can listen to the following signals to handle events in your game.

### Server

---
`DailyRewards.PlayerClaimRequest :: Signal.Signal<player: Player, dayData: DailyRewards.DayData, streak: number, claimTime: number>`

The `PlayerClaimRequest` signal is fired when a player requests to claim a reward using the Claim button in the daily rewards UI.

Use the `DailyRewards.canClaim` function to validate their claim request.

```lua
local DailyRewards = require(Packages.DailyRewards)

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
			print(`{player.Name} can claim the reward!`)

			-- Save the `claimTime` and `day` values to the player's data
			-- to track their claim streak
			-- and then award the player with the daily reward
		end
	end
end)
```

---

### Client

---

`DailyRewards.Claimed :: Signal.Signal<streak: number, dayData: DailyRewards.DayData>`

Use the `Claimed` signal to handle the reward claim on the client side or any special effects you want to trigger when a player claims a reward.

---

`DailyRewards.VisibilityChanged :: Signal.Signal<visible: boolean>`

The `VisiblityChanged` signal is useful for handling state changes in the UI, such as highlighting a daily rewards button when the UI is open.

---
