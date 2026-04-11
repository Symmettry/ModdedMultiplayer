local mod = SMODS.current_mod

mod.config = mod.config or {}
mod.config.endpoint = tostring(mod.config.endpoint or "127.0.0.1:3001")

mod.config_tab = function()
    print(mod)

    return {
        n = G.UIT.ROOT,
        config = {align = "cm", padding = 0.1, colour = G.C.CLEAR},
        nodes = {
            {
                n = G.UIT.R,
                config = {align = "cm", padding = 0.12},
                nodes = {
                    {n = G.UIT.T, config = {
                        text = "Endpoint URL",
                        scale = 0.4,
                        colour = G.C.UI.TEXT_LIGHT,
                        shadow = true
                    }}
                }
            },
            {
                n = G.UIT.R,
                config = {align = "cm", padding = 0.1},
                nodes = {
                    create_text_input({
                        id = 'mod_config_endpoint_input',
                        prompt_text = 'Endpoint URL',
                        ref_table = mod.config,
                        ref_value = 'endpoint',
                        w = 6.5,
                        h = 0.8,
                        text_scale = 0.35,
                        max_length = 200,
                        all_caps = false,
                        extended_corpus = true
                    })
                }
            },
        }
    }
end