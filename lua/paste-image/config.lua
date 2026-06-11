local M = {}

M.config = {
    default = {
        img_name = function()
            return os.date("%Y-%m-%d_%H-%M-%S") .. "_" .. tostring(vim.loop.hrtime() % 1e6)
        end,
        img_dir = function()
            local file = vim.api.nvim_buf_get_name(0)
            local dir = vim.fn.fnamemodify(file, ":h")
            local asset_dir = vim.fn.fnamemodify(file, ":t") .. ".assets"
            return {dir, asset_dir}
        end,
        rel_dir = function()
            return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
        end,
        affix = "![{name}]({relpath})",
        img_handler = function(img) end,
    },
    asciidoc = {
        affix = "image::%s[]",
    },
    markdown = {
        affix = "![](%s)",
    },
}

---@return table config
M.get_config = function()
    return M.config
end

---@param old_opts table
---@param new_opts table
---@return table config
M.merge_config = function(old_opts, new_opts)
    return vim.tbl_deep_extend("force", old_opts, new_opts or {})
end

---TODO: Need better name and description
---*Default* config for all filetype and current ft config need to be merged to be usable before pasting image
---@return table config
M.get_usable_config = function()
    local filetype = vim.bo.filetype
    local config = M.get_config()
    local default_config, filetype_config = config.default, config[filetype]
    return M.merge_config(default_config, filetype_config)
end

---Load argument if it is a function
---Used in config.load_config
---@param opt any
---@return any opt
M.load_opt = function(opt)
    if type(opt) == "function" then
        return opt()
    end
    return opt
end

---Field which value is function needs to be loaded first
---`{img_name = function () return os.date('%Y-%m-%d-%H-%M-%S') end}`
---to `{img_name = "2021-08-21-16-14-17"}`
---@param config_toload table
---@return table loaded_config
M.load_config = function(config_toload)
    return {
        affix = M.load_opt(config_toload.affix),
        img_name = M.load_opt(config_toload.img_name),
        img_dir = M.load_opt(config_toload.img_dir),
        rel_dir = M.load_opt(config_toload.rel_dir),
        img_handler = config_toload.img_handler,
    }
end

return M
