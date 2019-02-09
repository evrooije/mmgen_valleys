local mmgen_valleys_path = minetest.get_modpath("mmgen_valleys")
dofile(mmgen_valleys_path.."/valleys_init.lua")

-- assumes that multi_map_generators or something else has set up multi_map.number_of_layers etc.
multi_map.register_generator(21, vmg.generate)
multi_map.set_layer_params(21, { name = "Valleys" })
