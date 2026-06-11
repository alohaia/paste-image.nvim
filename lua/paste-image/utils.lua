local M = {}

---@class Command
---@field argv string[]
---@field _result vim.SystemCompleted?
---@field result string
---@field result_lines string[]
---@field text boolean
local Command = {}

---@param argv string[]
---@param opts table?
---@return Command
function Command:new(argv, opts)
    opts = opts or {text = false}

    return setmetatable({
        argv = argv,
        text = opts.text ~= false
    }, {
        ---@param obj table
        ---@param key string|integer
        ---@return any
        __index = function(obj, key)
            if key == "result" then
                if obj._result == nil then
                    vim.notify("no result yet", vim.log.levels.ERROR)
                else
                    return obj._result.stdout
                end
            elseif key == "result_lines" then
                if obj._result == nil then
                    vim.notify("no result yet", vim.log.levels.ERROR)
                else
                    return vim.split(obj._result.stdout, "\n", { trimempty = true })
                end
            end
            return Command[key]
        end
    })
end

---@return Command
function Command:run()
    self._result = vim.system(self.argv, { text = self.text }):wait()

    if self._result.code ~= 0 then
        vim.notify(self._result.stderr, vim.log.levels.ERROR)
    end

    return self
end

---@param output_file string
---@param binary boolean?
---@return Command
function Command:save_result(output_file, binary)
    binary = binary or true

    local f = assert(io.open(output_file, binary and "wb" or "w"))
    f:write(self._result.stdout)
    f:close()

    return self
end

M.Command = Command


---@param template string
---@param vars table
local function format_named(template, vars)
    return (template:gsub("{(%w+)}", vars))
end

---@param target string
---@param current string? dir or file that target is relative to
---@return string|nil
M.rel_path = function(target, current)
    current = M.resolve_dir(current) or vim.api.nvim_buf_get_name(0)
    local stat = vim.uv.fs_stat(current) or {}

    return vim.fs.relpath(
        stat.type == "directory" and current or vim.fs.dirname(current),
        target
    )
end


---@return boolean
M.is_insert_mode = function()
    return vim.fn.mode():sub(1, 1) == "i"
end


---Reference https://vi.stackexchange.com/a/2577/33116
---@return string os_name
M.get_os = function()
    if vim.fn.has "win32" == 1 then
        return "Windows"
    end

    local this_os = tostring(io.popen("uname"):read())
    if this_os == "Linux" and
        vim.fn.readfile("/proc/version")[1]:lower():match "microsoft" then
        this_os = "Wsl"
    end
    return this_os
end




---Get command to *check* and *paste* clipboard content
---@return Command cmd_check, Command cmd_paste
M.get_clip_command = function()
    local cmd_check, cmd_paste
    local this_os = M.get_os()
    if this_os == "Linux" then
        local display_server = os.getenv "XDG_SESSION_TYPE"
        if display_server == "x11" or display_server == "tty" then
            cmd_check = Command:new(
                {"xclip", "-selection", "clipboard", "-o", "-t", "TARGETS"},
                {text=true}
            )
            cmd_paste = Command:new(
                {"xclip", "-selection", "clipboard", "-t", "image/png", "-o"},
                {text=false}
            )
        elseif display_server == "wayland" then
            cmd_check = Command:new(
                {"wl-paste", "--list-types"},
                {text=true}
            )
            cmd_paste = Command:new(
                {"wl-paste", "--no-newline", "--type", "image/png"},
                {text=false}
            )
        end
    elseif this_os == "Darwin" then
        -- cmd_check = "pngpaste -b 2>&1"
        cmd_check = Command:new(
            {"pngpaste", "-b"},
            {text=true}
        )
        -- cmd_paste = "pngpaste '%s'"
        cmd_paste = Command:new(
            {"pngpaste"},
            {text=false}
        )
    elseif this_os == "Windows" or this_os == "Wsl" then
        -- cmd_check = "Get-Clipboard -Format Image"
        -- cmd_paste = "$content = " .. cmd_check .. ";$content.Save('%s', 'png')"
        -- cmd_check = 'powershell.exe "' .. cmd_check .. '"'
        -- cmd_paste = 'powershell.exe "' .. cmd_paste .. '"'
        vim.notify("Windows or WSL not supported now.", vim.log.levels.ERROR)
    end
    return cmd_check, cmd_paste
end

---Will be used in utils.is_clipboard_img to check if image data exist
---@param command Command #command to check clip_content
---@return string[]
M.get_clip_content = function(command)
    return command:run().result_lines
end

---Check if clipboard contain image data
---See also: [Data URI scheme](https://en.wikipedia.org/wiki/Data_URI_scheme)
---@param content string[] #clipboard content
---@return boolean
M.is_clipboard_img = function(content)
    local this_os = M.get_os()
    if this_os == "Linux" and vim.tbl_contains(content, "image/png") then
        return true
    elseif this_os == "Darwin" and string.sub(content[1], 1, 9) == "iVBORw0KG" then -- Magic png number in base64
        return true
    elseif this_os == "Windows" or this_os == "Wsl" and content ~= nil then
        return true
    end
    return false
end

---Check if resolve any complicated pathings
---@param dirs string|table
---@param path_separator string?
---@return string full_path
M.resolve_dir = function(dirs, path_separator)
    path_separator = path_separator or "/"
    if type(dirs) == "table" then
        local full_path = ""
        for _, dir in pairs(dirs) do
            full_path = full_path .. vim.fn.expand(dir) .. path_separator
        end
        return full_path
    else
        return vim.fn.expand(dirs) .. path_separator
    end
end

---@param dir string|table
M.create_dir = function(dir)
    dir = M.resolve_dir(dir)
    if vim.fn.isdirectory(dir) == 0 then
        vim.notify("[paste-image.nvim] Create dir: " .. dir)
        vim.fn.mkdir(dir, "p")
    end
end

---@param dir string | table
---@param img_name string
---@param is_txt? boolean
---@return string img_path
M.get_img_path = function(dir, img_name, is_txt)
    is_txt = is_txt ~= nil and is_txt or false

    local this_os = M.get_os()
    local img = img_name .. ".png"

    ---On cwd
    if dir == "" or dir == nil then
        return img
    end

    if this_os == "Windows" and is_txt then
        dir = M.resolve_dir(dir, "\\")
    else
        dir = M.resolve_dir(dir)
    end

    return dir .. img
end


---Insert image's path with affix
---TODO: Probably need better description
---@param affix string
---@param image table
M.insert_img_txt = function(affix, image)
    local txt_topaste = format_named(affix, image)

    ---Convert txt_topaste to lines table so it can handle multiline string
    local lines = {}
    for line in txt_topaste:gmatch "[^\r\n]+" do
        table.insert(lines, line)
    end

    vim.api.nvim_put(lines, "c", M.is_insert_mode() == false, true)
end

return M
