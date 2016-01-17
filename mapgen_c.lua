-- Mapgen Valleys 2.3c
print("*** using 2.3c")


-- Read the noise parameters from the actual mapgen.
local function getCppSettingNoise(name, default)
	local noise
	local n = minetest.setting_get(name)

	if n then
		local parse = {spread = {}}
		local n1, n2, n3, n4, n5, n6, n7, n8, n9

		n1, n2, n3, n4, n5, n6, n7, n8, n9 = string.match(n, '([%d%.%-]+), ([%d%.%-]+), %(([%d%.%-]+), ([%d%.%-]+), ([%d%.%-]+)%), ([%d%.%-]+), ([%d%.%-]+), ([%d%.%-]+), ([%d%.%-]+)')
		if n9 then
			noise = {offset = tonumber(n1), scale = tonumber(n2), seed = tonumber(n6), spread = {x = tonumber(n3), y = tonumber(n4), z = tonumber(n5)}, octaves = tonumber(n7), persist = tonumber(n8), lacunarity = tonumber(n9)}
		end
	end

	-- Use the default otherwise.
	if not noise then
		noise = default
	end

	return noise
end


-- Define perlin noises used in this mapgen by default
vmg.noises = {}

-- Noise 2 : Valleys (River where around zero)				2D
vmg.noises[2] = getCppSettingNoise('mg_valleys_np_rivers', {offset = 0, scale = 1, seed = -6050, spread = {x = 256, y = 256, z = 256}, octaves = 5, persist = 0.6, lacunarity = 2})

-- Noise 13 : Clayey dirt noise						2D
vmg.noises[13] = {offset = 0, scale = 1, seed = 2835, spread = {x = 256, y = 256, z = 256}, octaves = 5, persist = 0.5, lacunarity = 4}

-- Noise 14 : Silty dirt noise						2D
vmg.noises[14] = {offset = 0, scale = 1, seed = 6674, spread = {x = 256, y = 256, z = 256}, octaves = 5, persist = 0.5, lacunarity = 4}

-- Noise 15 : Sandy dirt noise						2D
vmg.noises[15] = {offset = 0, scale = 1, seed = 6940, spread = {x = 256, y = 256, z = 256}, octaves = 5, persist = 0.5, lacunarity = 4}

-- Noise 16 : Beaches							2D
vmg.noises[16] = {offset = 2, scale = 8, seed = 2349, spread = {x = 256, y = 256, z = 256}, octaves = 3, persist = 0.5, lacunarity = 2}

-- Noise 21 : Water plants							2D
vmg.noises[21] = {offset = 0.0, scale = 1.0, spread = {x = 200, y = 200, z = 200}, seed = 33, octaves = 3, persist = 0.7, lacunarity = 2.0}

-- function to get noisemaps
function vmg.noisemap(i, minp, chulens)
	local obj = minetest.get_perlin_map(vmg.noises[i], chulens)
	if minp.z then
		return obj:get3dMap_flat(minp)
	else
		return obj:get2dMap_flat(minp)
	end
end

-- If the noises are already defined in settings, use it instead of the noise parameters above.
for i, n in ipairs(vmg.noises) do
	vmg.noises[i] = vmg.define("noise_" .. i, n)
end

-- List of functions to run at the end of the mapgen procedure, used especially by jungle tree roots
vmg.after_mapgen = {}

function vmg.register_after_mapgen(f, ...)
	table.insert(vmg.after_mapgen, {f = f, ...})
end

function vmg.execute_after_mapgen()
	for i, params in ipairs(vmg.after_mapgen) do
		params.f(unpack(params))
	end
	vmg.after_mapgen = {}
end

local function getCppSettingNumeric(name, default)
	local setting = minetest.setting_get(name) 

	if setting and tonumber(setting) then
		setting = tonumber(setting)
	else
		setting = default
	end

	return setting
end

-- Mapgen time stats
local mapgen_times = {
	preparation = {},
	noises = {},
	collecting = {},
	writing = {},
	total = {},
}

-- Define parameters
local river_size = vmg.define("river_size", 5) / 100
local do_cave_stuff = vmg.define("cave_stuff", false)
local dry_dirt_threshold = vmg.define("dry_dirt_threshold", 0.6)

local clay_threshold = vmg.define("clay_threshold", 1)
local silt_threshold = vmg.define("silt_threshold", 1)
local sand_threshold = vmg.define("sand_threshold", 0.75)
local dirt_threshold = vmg.define("dirt_threshold", 0.5)
local average_snow_level = vmg.define("average_snow_level", 100)
local altitude_chill = getCppSettingNumeric('mg_valleys_altitude_chill', 90) 
local heat_multiplier = tonumber(getCppSettingNoise('mg_biome_np_heat', {offset=50}).offset) / 25
local snow_threshold = heat_multiplier * 0.5 ^ (average_snow_level / altitude_chill)

-- Register ores
-- We need more types of stone than just gray. Fortunately, there are
--  two available already. Sandstone forms in layers. Desert stone...
--  doesn't exist, but let's assume it's another sedementary rock
--  and place it similarly.
if vmg.define("stone_ores", true) then
	minetest.register_ore({ore_type="sheet", ore="default:sandstone", wherein="default:stone", clust_num_ores=250, clust_scarcity=60, clust_size=10, y_min=-1000, y_max=31000, noise_threshhold=0.1, noise_params={offset=0, scale=1, spread={x=256, y=256, z=256}, seed=4130293965, octaves=5, persist=0.60}, random_factor=1.0})
	minetest.register_ore({ore_type="sheet", ore="default:desert_stone", wherein="default:stone", clust_num_ores=250, clust_scarcity=60, clust_size=10, y_min=-1000, y_max=31000, noise_threshhold=0.1, noise_params={offset=0, scale=1, spread={x=256, y=256, z=256}, seed=163281090, octaves=5, persist=0.60}, random_factor=1.0})
end

-- These variables hold the content IDs. They aren't available until
-- the actual mapgen loop is run, but they can stay local to the
-- file rather than having to load them for every map chunk.
--
-- Ground nodes
local c_stone, c_dirt, c_lawn, c_dry, c_snow, c_dirt_clay, c_dry_clay
local c_lawn_clay, c_snow_clay, c_dirt_silt, c_lawn_silt, c_dry_silt
local c_snow_silt, c_dirt_sand, c_lawn_sand, c_dry_sand, c_snow_sand
local c_desert_sand, c_sand, c_gravel, c_silt, c_clay, c_water
local c_sandstone, c_desertstone
local c_riverwater, c_lava, c_snow_layer, c_glowing_fungal_stone
local c_stalagmite, c_stalactite

-- Mushrooms
local c_huge_mushroom_cap, c_giant_mushroom_cap, c_giant_mushroom_stem
local c_mushroom_fertile_red, c_mushroom_fertile_brown

-- Air and Ignore
local c_air, c_ignore


---- Create a table of biome ids, so I can use the biomemap.
--if not vmg.biome_ids then
--	vmg.biome_ids = {}
--	for name, desc in pairs(minetest.registered_biomes) do
--		local i = minetest.get_biome_id(desc.name)
--		vmg.biome_ids[i] = desc.name
--	end
--end


-- THE MAPGEN FUNCTION
function vmg.generate(minp, maxp, seed)
	if vmg.registered_on_first_mapgen then -- Run callbacks
		for _, f in ipairs(vmg.registered_on_first_mapgen) do
			f()
		end
		vmg.registered_on_first_mapgen = nil
		vmg.register_on_first_mapgen = nil
	end

	-- minp and maxp strings, used by logs
	local minps, maxps = minetest.pos_to_string(minp), minetest.pos_to_string(maxp)
	if vmg.loglevel >= 2 then
		print("[Valleys Mapgen] Preparing to generate map from " .. minps .. " to " .. maxps .. " ...")
	elseif vmg.loglevel == 1 then
		--print("[Valleys Mapgen] Generating map from " .. minps .. " to " .. maxps .. " ...")
	end
	-- start the timer
	local t0 = os.clock()

	-- Define content IDs
	-- A content ID is a number that represents a node in the core of Minetest.
	-- Every nodename has its ID.
	-- The VoxelManipulator uses content IDs instead of nodenames.

	if not c_stone then
		c_stone = minetest.get_content_id("default:stone")
		c_sandstone = minetest.get_content_id("default:sandstone")
		c_desertstone = minetest.get_content_id("default:desert_stone")
		c_dirt = minetest.get_content_id("default:dirt")
		c_lawn = minetest.get_content_id("default:dirt_with_grass")
		c_dry = minetest.get_content_id("default:dirt_with_dry_grass")
		c_snow = minetest.get_content_id("default:dirt_with_snow")
		c_dirt_clay = minetest.get_content_id("valleys_mapgen:dirt_clayey")
		c_lawn_clay = minetest.get_content_id("valleys_mapgen:dirt_clayey_with_grass")
		c_dry_clay = minetest.get_content_id("valleys_mapgen:dirt_clayey_with_dry_grass")
		c_snow_clay = minetest.get_content_id("valleys_mapgen:dirt_clayey_with_snow")
		c_dirt_silt = minetest.get_content_id("valleys_mapgen:dirt_silty")
		c_lawn_silt = minetest.get_content_id("valleys_mapgen:dirt_silty_with_grass")
		c_dry_silt = minetest.get_content_id("valleys_mapgen:dirt_silty_with_dry_grass")
		c_snow_silt = minetest.get_content_id("valleys_mapgen:dirt_silty_with_snow")
		c_dirt_sand = minetest.get_content_id("valleys_mapgen:dirt_sandy")
		c_lawn_sand = minetest.get_content_id("valleys_mapgen:dirt_sandy_with_grass")
		c_dry_sand = minetest.get_content_id("valleys_mapgen:dirt_sandy_with_dry_grass")
		c_snow_sand = minetest.get_content_id("valleys_mapgen:dirt_sandy_with_snow")
		c_desert_sand = minetest.get_content_id("default:desert_sand")
		c_sand = minetest.get_content_id("default:sand")
		c_gravel = minetest.get_content_id("default:gravel")
		c_silt = minetest.get_content_id("valleys_mapgen:silt")
		c_clay = minetest.get_content_id("valleys_mapgen:red_clay")
		c_water = minetest.get_content_id("default:water_source")
		c_riverwater = minetest.get_content_id("default:river_water_source")
		c_lava = minetest.get_content_id("default:lava_source")
		c_snow_layer = minetest.get_content_id("default:snow")
		c_glowing_fungal_stone = minetest.get_content_id("valleys_mapgen:glowing_fungal_stone")
		c_stalactite = minetest.get_content_id("valleys_mapgen:stalactite")
		c_stalagmite = minetest.get_content_id("valleys_mapgen:stalagmite")

		-- Mushrooms
		c_huge_mushroom_cap = minetest.get_content_id("valleys_mapgen:huge_mushroom_cap")
		c_giant_mushroom_cap = minetest.get_content_id("valleys_mapgen:giant_mushroom_cap")
		c_giant_mushroom_stem = minetest.get_content_id("valleys_mapgen:giant_mushroom_stem")
		c_mushroom_fertile_red = minetest.get_content_id("flowers:mushroom_fertile_red")
		c_mushroom_fertile_brown = minetest.get_content_id("flowers:mushroom_fertile_brown")

		-- Air and Ignore
		c_air = minetest.get_content_id("air")
		c_ignore = minetest.get_content_id("ignore")
	end

	-- The VoxelManipulator, a complicated but speedy method to set many nodes at the same time
	local vm, emin, emax = minetest.get_mapgen_object("voxelmanip")
	local data = vm:get_data() -- data is the original array of content IDs (solely or mostly air)
	-- Be careful: emin ≠ minp and emax ≠ maxp !
	-- The data array is not limited by minp and maxp. It exceeds it by 16 nodes in the 6 directions.
	-- The real limits of data array are emin and emax.
	-- The VoxelArea is used to convert a position into an index for the array.
	local a = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
	local ystride = a.ystride -- Tip : the ystride of a VoxelArea is the number to add to the array index to get the index of the position above. It's faster because it avoids to completely recalculate the index.

	local chulens = vector.add(vector.subtract(maxp, minp), 1) -- Size of the generated area, used by noisemaps
	local chulens_sup = {x = chulens.x, y = chulens.y + 6, z = chulens.z} -- for the noise #6 that needs extra values
	local minp2d = pos2d(minp)

	-- The biomemap is a table of biome index numbers for each horizontal
	--  location. It's created in the mapgen, and is right most of the time.
	--  It's off in about 1% of cases, for various reasons.
	-- Bear in mind that biomes can change from one voxel to the next.
	--local biomemap = minetest.get_mapgen_object("biomemap")
	local heightmap = minetest.get_mapgen_object("heightmap")
	local heatmap = minetest.get_mapgen_object("heatmap")
	local humiditymap = minetest.get_mapgen_object("humiditymap")

	-- Mapgen preparation is now finished. Check the timer to know the elapsed time.
	local t1 = os.clock()
	if vmg.loglevel >= 2 then
		print("[Valleys Mapgen] Mapgen preparation finished in " .. displaytime(t1-t0))
		print("[Valleys Mapgen] Calculating noises ...")
	end

	-- Calculate the noise values
	local n2 = vmg.noisemap(2, minp2d, chulens)
	local n13 = vmg.noisemap(13, minp2d, chulens)
	local n14 = vmg.noisemap(14, minp2d, chulens)
	local n15 = vmg.noisemap(15, minp2d, chulens)
	local n16 = vmg.noisemap(16, minp2d, chulens)
	local n21 = vmg.noisemap(21, minp2d, chulens)

	-- After noise calculation, check the timer
	local t2 = os.clock()
	if vmg.loglevel >= 2 then
		print("[Valleys Mapgen] Noises calculation finished in " .. displaytime(t2-t1))
		print("[Valleys Mapgen] Collecting data ...")
	end

	-- THE CORE OF THE MOD: THE MAPGEN ALGORITHM ITSELF

	-- indexes for noise arrays
	local i2d = 1 -- index for 2D noises
	local i3d_sup = 1 -- index for noise #6 which has a special size
	local i3d = 1 -- index for 3D noises

	-- Calculate increments
	local i2d_incrZ = chulens.z
	local i2d_decrX = chulens.x * chulens.z - 1
	local i3d_incrY = chulens.y
	local i3d_sup_incrZ = 6 * chulens.y
	local i3d_decrX = chulens.x * chulens.y * chulens.z - 1
	local i3d_sup_decrX = chulens.x * (chulens.y + 6) * chulens.z - 1

	for x = minp.x, maxp.x do -- for each YZ plane
		for z = minp.z, maxp.z do -- for each vertical line in this plane
			local air_count = 0
			local v2, v13, v14, v15, v16 = n2[i2d], n13[i2d], n14[i2d], n15[i2d], n16[i2d] -- take the noise values for 2D noises

			-- Choose biome, by default normal dirt
			local dirt = c_dirt
			local lawn = c_lawn
			local dry = c_dry
			local snow = c_snow
			local max = math.max(v13, v14, v15) -- the biome is the maximal of these 3 values.
			if max > dirt_threshold then -- if one of these values is bigger than dirt_threshold, make clayey, silty or sandy dirt, depending on the case. If none of clay, silt or sand is predominant, make normal dirt.
				if v13 == max then
					if v13 > clay_threshold then
						dirt = c_clay
						lawn = c_clay
						dry = c_clay
						snow = c_clay
					else
						dirt = c_dirt_clay
						lawn = c_lawn_clay
						dry = c_dry_clay
						snow = c_snow_clay
					end
				elseif v14 == max then
					if v14 > silt_threshold then
						dirt = c_silt
						lawn = c_silt
						dry = c_silt
						snow = c_silt
					else
						dirt = c_dirt_silt
						lawn = c_lawn_silt
						dry = c_dry_silt
						snow = c_snow_silt
					end
				else
					if v15 > sand_threshold then
						dirt = c_desert_sand
						lawn = c_desert_sand
						dry = c_desert_sand
						snow = c_desert_sand
					else
						dirt = c_dirt_sand
						lawn = c_lawn_sand
						dry = c_dry_sand
						snow = c_snow_sand
					end
				end
			end

			for y = maxp.y, minp.y, -1 do -- for each node in vertical line
				local ivm = a:index(x, y, z) -- index of the data array, matching the position {x, y, z}
				local ground = math.max(heightmap[i2d], 0) - 5

				if data[ivm] == c_snow_layer then
					data[ivm] = c_air
				end

				-- Replace dirt and sand nodes appropriately.
				if data[ivm] == c_dirt or data[ivm] == c_dry or data[ivm] == c_lawn or data[ivm] == c_snow or data[ivm] == c_sand then

					-- a top node
					if y >= ground and data[ivm + ystride] == c_air then
						-- Humidity and temperature are simplified from the original,
						-- and derived from the actual mapgen.
						local humidity = 2 ^ (v13 - v15 + (humiditymap[i2d] / 25) - 2)
						--humidity = humidity * (1 - math.exp(-math.max(4 - math.sqrt(math.abs(y)) / 4, 0) - 0.5))
						local temperature = (heatmap[i2d] - 32) / 60 + 1

						-- Add sea humidity (the mapgen doesn't)
						if humidity < 1.8 and y < 5 then
							humidity = humidity * (1 + (5 - y) * 10)
						end

						-- Replace the nodes.
						if data[ivm] == c_dirt then
							data[ivm] = dirt
						else
							if temperature < snow_threshold then
								data[ivm] = snow
								data[ivm + ystride] = c_snow_layer
							elseif humidity < dry_dirt_threshold then
								data[ivm] = dry
							else
								data[ivm] = lawn
							end
						end

						v2 = math.abs(v2) - river_size -- v2 represents the distance from the river, in arbitrary units.

						-- Most of the terrain noises are unavailable.
						local conditions = { -- pack it in a table, for plants API
						v1 = 0,
						v2 = v2,
						v3 = 0,
						v4 = 0,
						v5 = 0,
						v6 = 0,
						v7 = 0,
						v8 = 0,
						v9 = 0,
						v10 = 0,
						v11 = 0,
						v12 = 0,
						v13 = v13,
						v14 = v14,
						v15 = v15,
						v16 = v16,
						v17 = 0,
						v18 = 0,
						v19 = 0,
						v20 = 0,
						temp = temperature,
						humidity = humidity,
						sea_water = 0,
						river_water = 0,
						water = 0,
						thickness = 0 }

						vmg.choose_generate_plant(conditions, {x=x,y=y,z=z}, data, a, ivm + ystride)
					else
						if data[ivm] == c_dirt or data[ivm] == c_sand then
							data[ivm] = dirt
						end
					end
				end
				
				-- cave ceilings
				if do_cave_stuff and y < maxp.y and data[ivm] == c_air and data[ivm + ystride] == c_stone then
					local sr = math.random(20)
					if sr == 1 then
						data[ivm + ystride] = c_glowing_fungal_stone
					elseif sr < 5 then
						data[ivm] = c_stalactite
					end
				end

				-- cave floors
				if do_cave_stuff and y > minp.y and y < ground and data[ivm] == c_air then
					air_count = air_count + 1
					if data[ivm - ystride] == c_stone then
						local sr = math.random(100)
						if sr < 21 then
							data[ivm] = c_stalagmite
						elseif sr < 24 then
							data[ivm] = c_mushroom_fertile_red
							data[ivm - ystride] = c_dirt
						elseif sr < 27 then
							data[ivm] = c_mushroom_fertile_brown
							data[ivm - ystride] = c_dirt
						elseif air_count > 1 and sr < 29 then
							data[ivm + ystride] = c_huge_mushroom_cap
							data[ivm] = c_giant_mushroom_stem
							data[ivm - ystride] = c_dirt
						elseif air_count > 2 and sr < 30 then
							data[ivm + 2 * ystride] = c_giant_mushroom_cap
							data[ivm + ystride] = c_giant_mushroom_stem
							data[ivm] = c_giant_mushroom_stem
							data[ivm - ystride] = c_dirt
						elseif sr < 34 then
							data[ivm - ystride] = c_dirt
						end
					end
				end

--				if y > minp.y and data[ivm] == c_air and data[ivm - ystride] == c_river_water_source then
--					local biome = vmg.biome_ids[biomemap[i2d]]
--					-- I haven't figured out what the decoration manager is
--					--  doing with the noise functions, but this works ok.
--					if table.contains(water_lily_biomes, biome) and n21[i2d] > 0.5 and math.random(5) == 1 then
--						data[ivm] = c_waterlily
--					end
--				end

				if data[ivm] ~= c_air then
					air_count = 0
				end

				i3d = i3d - i3d_incrY -- decrement i3d by one line
				i3d_sup = i3d_sup + i3d_incrY -- idem
			end
			i2d = i2d + i2d_incrZ -- increment i2d by one Z
			-- useless to increment i3d, because increment would be 0 !
			i3d_sup = i3d_sup + i3d_sup_incrZ -- for i3d_sup, just avoid the 6 supplemental lines
		end
		i2d = i2d - i2d_decrX -- decrement the Z line previously incremented and increment by one X (1)
		i3d = i3d - i3d_decrX -- decrement the YZ plane previously incremented and increment by one X (1)
		i3d_sup = i3d_sup - i3d_sup_decrX -- idem, including the supplemental lines
	end
	vmg.execute_after_mapgen() -- needed for jungletree roots

	-- After data collecting, check timer
	local t3 = os.clock()
	if vmg.loglevel >= 2 then
		print("[Valleys Mapgen] Data collecting finished in " .. displaytime(t3-t2))
		print("[Valleys Mapgen] Writing data ...")
	end

	-- execute voxelmanip boring stuff to write to the map...
	vm:set_data(data)
	vm:calc_lighting()
	vm:write_to_map()

	local t4 = os.clock()
	if vmg.loglevel >= 2 then
		print("[Valleys Mapgen] Data writing finished in " .. displaytime(t4-t3))
	end
	if vmg.loglevel >= 1 then
		--print("[Valleys Mapgen] Mapgen finished in " .. displaytime(t4-t0)) 
	end

	table.insert(mapgen_times.preparation, t1 - t0)
	table.insert(mapgen_times.noises, t2 - t1)
	table.insert(mapgen_times.collecting, t3 - t2)
	table.insert(mapgen_times.writing, t4 - t3)
	table.insert(mapgen_times.total, t4 - t0)
end

-- Display mapgen stats on shutdown
local function stats(t)
	local n = #t

	local sum = 0
	local sum_sq = 0
	for _, k in ipairs(t) do
		sum = sum + k
		sum_sq = sum_sq + k^2
	end
	local average = sum / n
	local variance = sum_sq / n - average^2
	local standard_dev = math.sqrt(variance)

	return average, standard_dev
end

minetest.register_on_shutdown(function()
	if #mapgen_times.total == 0 then
		return
	end

	if vmg.loglevel >= 1 then
		local average, standard_dev
		print("[Valleys Mapgen] Mapgen statistics:")

		if vmg.loglevel >= 2 then
			average, standard_dev = stats(mapgen_times.preparation)
			print("[Valleys Mapgen] Mapgen preparation step:")
			print("                               average " .. displaytime(average))
			print("                    standard deviation " .. displaytime(standard_dev))
		
			average, standard_dev = stats(mapgen_times.noises)
			print("[Valleys Mapgen] Noises calculation step:")
			print("                               average " .. displaytime(average))
			print("                    standard deviation " .. displaytime(standard_dev))
		
			average, standard_dev = stats(mapgen_times.collecting)
			print("[Valleys Mapgen] Data collecting step:")
			print("                               average " .. displaytime(average))
			print("                    standard deviation " .. displaytime(standard_dev))
		
			average, standard_dev = stats(mapgen_times.writing)
			print("[Valleys Mapgen] Data writing step:")
			print("                               average " .. displaytime(average))
			print("                    standard deviation " .. displaytime(standard_dev))
		end
		average, standard_dev = stats(mapgen_times.total)
		print("[Valleys Mapgen] TOTAL:")
		print("                               average " .. displaytime(average))
		print("                    standard deviation " .. displaytime(standard_dev))
	end
end)

-- Trees are registered in a separate file
dofile(vmg.path .. "/trees.lua")
dofile(vmg.path .. "/plants_api.lua")
dofile(vmg.path .. "/plants.lua")

function vmg.get_noise(pos, i)
	local n = vmg.noises[i]
	local noise = minetest.get_perlin(n)
	if not pos.z then -- 2D noise
		return noise:get2d(pos)
	else -- 3D noise
		return noise:get3d(pos)
	end
end

local function round(n)
	return math.floor(n + 0.5)
end

