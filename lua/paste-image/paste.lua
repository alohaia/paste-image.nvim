local M = {}
local conf_utils = require "paste-image.config"
local utils = require "paste-image.utils"
local check_dependency = require("paste-image.health").check_current_dep

local cmd_check, cmd_paste = utils.get_clip_command()

---@param path string
local paste_img_to = function(path)
    cmd_paste:run():save_result(path, true)
end

---@param opts table
---@param fallback function?
M.paste_img = function(opts, fallback)
    local is_dep_exist, deps_msg = check_dependency()
    if not is_dep_exist then
        vim.notify(deps_msg, vim.log.levels.ERROR)
        return false
    end

    local content = utils.get_clip_content(cmd_check)
    if utils.is_clipboard_img(content) ~= true then
        if fallback then
            fallback()
        else
            vim.notify("There is no image data in clipboard", vim.log.levels.ERROR)
        end
    else
        local conf_toload = conf_utils.get_usable_config()
        conf_toload = conf_utils.merge_config(conf_toload, opts)
        local conf = conf_utils.load_config(conf_toload)

        local path = utils.get_img_path(conf.img_dir, conf.img_name)

        utils.create_dir(conf.img_dir)
        paste_img_to(path)

        local image = {
            name = conf.img_name,
            dir = conf.img_dir,
            abspath = path,
            rel_dir = conf.rel_dir or "nil",
            relpath = utils.rel_path(path, conf.rel_dir) or "nil",
        }

        utils.insert_img_txt(conf.affix, image)

        if type(conf.img_handler) == "function" then
            conf.img_handler(image)
        end
    end
end

return M
