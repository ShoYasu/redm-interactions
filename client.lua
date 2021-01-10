local PickerIsOpen = false
local InteractionMarker = 0
local StartingCoords

local entityEnumerator = {
	__gc = function(enum)
		if enum.destructor and enum.handle then
			enum.destructor(enum.handle)
		end
		enum.destructor = nil
		enum.handle = nil
	end
}

function EnumerateEntities(firstFunc, nextFunc, endFunc)
	return coroutine.wrap(function()
		local iter, id = firstFunc()

		if not id or id == 0 then
			endFunc(iter)
			return
		end

		local enum = {handle = iter, destructor = endFunc}
		setmetatable(enum, entityEnumerator)

		local next = true
		repeat
			coroutine.yield(id)
			next, id = nextFunc(iter)
		until not next

		enum.destructor, enum.handle = nil, nil
		endFunc(iter)
	end)
end

function EnumerateObjects()
	return EnumerateEntities(FindFirstObject, FindNextObject, EndFindObject)
end

function IsPlayerNearCoords(coords, radius)
	local playerCoords = GetEntityCoords(PlayerPedId())

	return #(playerCoords - coords) <= radius
end

function HasCompatibleModel(entity, models)
	local entityModel = GetEntityModel(entity)

	for _, model in ipairs(models) do
		if entityModel  == GetHashKey(model) then
			return model
		end
	end
	return nil
end

function CanStartInteractionAtObject(interaction, object, objectCoords)
	if not IsPlayerNearCoords(objectCoords, interaction.radius) then
		return nil
	end

	return HasCompatibleModel(object, interaction.objects)
end

function StartInteractionAtObject(interaction)
	local objectHeading = GetEntityHeading(interaction.object)
	local objectCoords = GetEntityCoords(interaction.object)

	local r = math.rad(objectHeading)
	local cosr = math.cos(r)
	local sinr = math.sin(r)

	local x = interaction.x * cosr - interaction.y * sinr + objectCoords.x
	local y = interaction.y * cosr + interaction.x * sinr + objectCoords.y
	local z = interaction.z + objectCoords.z
	local h = interaction.heading + objectHeading

	local ped = PlayerPedId()

	if not StartingCoords then
		StartingCoords = GetEntityCoords(ped)
	end

	ClearPedTasksImmediately(ped)

	FreezeEntityPosition(ped, true)

	TaskStartScenarioAtPosition(ped, GetHashKey(interaction.scenario), x, y, z, h, -1, false, true)
end

function IsCompatible(t)
	return not t.isCompatible or t.isCompatible()
end

function SortInteractions(a, b)
	if a.distance == b.distance then
		if a.object == b.object then
			return a.scenario < b.scenario
		else
			return a.object < b.object
		end
	else
		return a.distance < b.distance
	end
end

function StartInteraction()
	local playerCoords = GetEntityCoords(PlayerPedId())

	local availableInteractions = {}

	for _, interaction in ipairs(Config.Interactions) do
		if IsCompatible(interaction) then
			for object in EnumerateObjects() do
				local objectCoords = GetEntityCoords(object)

				local modelName = CanStartInteractionAtObject(interaction, object, objectCoords)

				if modelName then
					local distance = #(playerCoords - objectCoords)

					for _, scenario in ipairs(interaction.scenarios) do
						if IsCompatible(scenario) then
							table.insert(availableInteractions, {
								x = interaction.x,
								y = interaction.y,
								z = interaction.z,
								heading = interaction.heading,
								scenario = scenario.name,
								object = object,
								modelName = modelName,
								distance = distance,
								label = interaction.label
							})
						end
					end
				end
			end
		end

		Wait(0)
	end

	if #availableInteractions > 0 then
		table.sort(availableInteractions, SortInteractions)
		SendNUIMessage({
			type = 'showInteractionPicker',
			interactions = json.encode(availableInteractions)
		})
		PickerIsOpen = true
	else
		SendNUIMessage({
			type = 'hideInteractionPicker'
		})
		SetInteractionMarker(0)
		PickerIsOpen = false
	end
end

function StopInteraction()
	local ped = PlayerPedId()

	ClearPedTasksImmediately(ped)
	FreezeEntityPosition(ped, false)

	Wait(100)

	if StartingCoords then
		SetEntityCoordsNoOffset(ped, StartingCoords.x, StartingCoords.y, StartingCoords.z)
		StartingCoords = nil
	end
end

function SetInteractionMarker(entity)
	InteractionMarker = entity
end

RegisterNUICallback('startInteraction', function(data, cb)
	StartInteractionAtObject(data)
	cb({})
end)

RegisterNUICallback('stopInteraction', function(data, cb)
	StopInteraction()
	cb({})
end)

RegisterNUICallback('setInteractionMarker', function(data, cb)
	SetInteractionMarker(data.entity)
	cb({})
end)

RegisterCommand('interact', function(source, args, raw)
	StartInteraction()
end, false)

AddEventHandler('onResourceStop', function(resourceName)
	if GetCurrentResourceName() == resourceName then
		SetInteractionMarker(0)
	end
end)

function DrawMarker(type, posX, posY, posZ, dirX, dirY, dirZ, rotX, rotY, rotZ, scaleX, scaleY, scaleZ, red, green, blue, alpha, bobUpAndDown, faceCamera, p19, rotate, textureDict, textureName, drawOnEnts)
	Citizen.InvokeNative(0x2A32FAA57B937173, type, posX, posY, posZ, dirX, dirY, dirZ, rotX, rotY, rotZ, scaleX, scaleY, scaleZ, red, green, blue, alpha, bobUpAndDown, faceCamera, p19, rotate, textureDict, textureName, drawOnEnts)
end

function DrawInteractionMarker()
	if InteractionMarker == 0 then
		return
	end

	local x, y, z = table.unpack(GetEntityCoords(InteractionMarker))

	DrawMarker(Config.MarkerType, x, y, z, 0, 0, 0, 0, 0, 0, 1.0, 1.0, 1.0, Config.MarkerColor[1], Config.MarkerColor[2], Config.MarkerColor[3], Config.MarkerColor[4], 0, 0, 2, 0, 0, 0, 0)
end

CreateThread(function()
	while true do
		Wait(0)

		if IsControlJustPressed(0, Config.InteractControl) then
			StartInteraction()
		end

		if PickerIsOpen then
			DisableAllControlActions(0)

			if IsDisabledControlJustPressed(0, 0x911CB09E) then
				SendNUIMessage({
					type = 'moveSelectionUp'
				})
			end

			if IsDisabledControlJustPressed(0, 0x4403F97F) then
				SendNUIMessage({
					type = 'moveSelectionDown'
				})
			end

			if IsDisabledControlJustPressed(0, 0x43DBF61F) then
				SendNUIMessage({
					type = 'startInteraction'
				})
				SetInteractionMarker(0)
				PickerIsOpen = false
			end

			if IsDisabledControlJustPressed(0, 0x308588E6) then
				SendNUIMessage({
					type = 'hideInteractionPicker'
				})
				SetInteractionMarker(0)
				PickerIsOpen = false
			end
		end

		DrawInteractionMarker()
	end
end)
