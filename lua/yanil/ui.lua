local vim = vim
local api = vim.api
local loop = vim.loop
local validate = vim.validate

local nodelib    = require("yanil/node")
local decorators = require("yanil/decorators")
local utils      = require("yanil/utils")
local git        = require("yanil/git")

local config = {
    colors   = require("yanil/colors"),
    commands = require("yanil/commands"),
    keymaps  = require("yanil/keymaps"),
}

local ns_id = utils.ns_id

local M = {}

M.tree = {
    bufname = "Yanil",
    bufnr = nil,
    win_width = 30,
    cwd = nil,
    root = nil,
    header_height = 2,
    winnr = function()
        for _, winnr in ipairs(api.nvim_list_wins()) do
            local bufname = api.nvim_buf_get_name(api.nvim_win_get_buf(winnr))
            if bufname:match(".*/"..M.tree.bufname.."$") then
                return winnr
            end
        end
    end,
    options = {
        'noswapfile',
        'norelativenumber',
        'nonumber',
        'nolist',
        'nobuflisted',
        'winfixwidth',
        'winfixheight',
        'nofoldenable',
        'nospell',
        'foldmethod=manual',
        'foldcolumn=0',
        'signcolumn=yes:1'
    },
    draw_opts = {
        decorators = {
            decorators.plain_indent,
            -- decorators.pretty_indent,
            git.decorator(),
            decorators.devicons,
            decorators.default,
            decorators.executable,
            decorators.readonly,
            decorators.link_to,
        },
    },
}

function M.init(cwd)
    cwd = cwd and vim.fn.fnamemodify(cwd, ":p:h") or loop.cwd()
    M.tree.cwd = cwd
    local root = nodelib.Dir:new {
        name = cwd,
        abs_path = cwd,
    }
    root:open()

    M.tree.root = root
end

function M.set_mappings()
    api.nvim_buf_set_keymap(M.tree.bufnr, "n", "<CR>", '<cmd>lua require("yanil/ui").open_current_node()<CR>', {
        nowait = true,
        noremap = false,
        silent = false,
    })
    api.nvim_buf_set_keymap(M.tree.bufnr, "n", "c", '<cmd>lua require("yanil/ui").change_dir_to_current_node()<CR>', {
        nowait = true,
        noremap = false,
        silent = false,
    })
    api.nvim_buf_set_keymap(M.tree.bufnr, "n", "u", '<cmd>lua require("yanil/ui").change_dir_to_parent()<CR>', {
        nowait = true,
        noremap = false,
        silent = false,
    })
    api.nvim_buf_set_keymap(M.tree.bufnr, "n", "r", '<cmd>lua require("yanil/ui").refresh_current_node()<CR>', {
        nowait = true,
        noremap = false,
        silent = false,
    })
end

function M.open_current_node()
    local cursor = api.nvim_win_get_cursor(M.tree.winnr())
    local linenr = cursor[1] - 1
    local node = M.get_node_by_linenr(linenr)
    if not node then return end

    if not node:is_dir() then
        api.nvim_command("wincmd p")
        api.nvim_command("e " .. node.abs_path)
        return
    end

    M.refresh_node(node, linenr, function()
        node:toggle()
    end)
end

function M.refresh_current_node()
    local cursor = api.nvim_win_get_cursor(M.tree.winnr())
    local linenr = cursor[1] - 1
    local node = M.get_node_by_linenr(linenr)
    if not node then return end

    M.refresh_node(node, linenr)
end

function M.refresh_node(node, linenr, action)
    validate {
        node = {node, "table", false},
        linenr = {linenr, "number", false},
        action = {action, "function", true},
    }

    local bufnr = M.tree.bufnr

    local total_lines = node:total_lines()

    if action then action() end

    local lines, highlights = node:draw(M.tree.draw_opts)

    api.nvim_buf_set_option(bufnr, "modifiable", true)
    api.nvim_buf_set_lines(bufnr, linenr, linenr + total_lines, false, lines)
    for _, hl in ipairs(highlights) do
        api.nvim_buf_add_highlight(bufnr, ns_id, hl.hl_group, linenr + hl.line, hl.col_start, hl.col_end)
    end
    api.nvim_buf_set_option(bufnr, "modifiable", false)
end

function M.change_dir_to_current_node()
    local node = M.get_node_under_cursor()
    if not node or not node:is_dir() then return end

    M.change_dir(node.abs_path)
end

function M.change_dir_to_parent()
    if M.tree.cwd == "/" then return end
    local parent = vim.fn.fnamemodify(M.tree.cwd, ":p:h")
    if not parent then return end

    M.change_dir(parent)
end

function M.get_node_under_cursor()
    local cursor = api.nvim_win_get_cursor(M.tree.winnr())
    return M.get_node_by_linenr(cursor[1] - 1)
end

-- linenr 0-based
function M.get_node_by_linenr(linenr)
    local index = M.tree.header_height
    return M.tree.root:get_nth_node(linenr - index)
end

local function create_buf()
    local options = {
        bufhidden = "wipe",
        buftype = "nofile",
        modifiable = false,
    }
    local bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(bufnr, M.tree.bufname)
    for k, v in pairs(options) do
        api.nvim_buf_set_option(bufnr, k, v)
    end
    return bufnr
end

local function create_win()
    api.nvim_command("topleft vertical " .. M.tree.win_width .. " new")
    api.nvim_command("setlocal nobuflisted")
end

function M.open()
    if M.tree.winnr() then return end

    M.tree.bufnr = create_buf()
    create_win()
    api.nvim_win_set_buf(M.tree.winnr(), M.tree.bufnr)

    for _, opt in ipairs(M.tree.options) do
        api.nvim_command("setlocal " .. opt)
    end
end

function M.draw()
    local lines, highlights = M.tree.root:draw(M.tree.draw_opts, {"", ""})

    api.nvim_buf_set_option(M.tree.bufnr, "modifiable", true)
    api.nvim_buf_set_lines(M.tree.bufnr, 0, -1, false, {})
    api.nvim_buf_set_lines(M.tree.bufnr, 0, -1, false, lines)
    for _, hl in ipairs(highlights) do
        api.nvim_buf_add_highlight(M.tree.bufnr, ns_id, hl.hl_group, hl.line, hl.col_start, hl.col_end)
    end

    M.set_mappings()

    api.nvim_buf_set_option(M.tree.bufnr, "modifiable", false)
end

function M.refresh_ui()
    M.draw()
end

function M.change_dir(cwd)

    M.init(cwd)
    M.draw()

    api.nvim_win_set_cursor(M.tree.winnr(), {3, 0})
end

function M.startup(cwd)
    M.init(cwd)
    git.update()
    M.open()
    M.draw()
end

function M.setup(opts)
    opts = opts or {}
    config.colors.setup()
    config.commands.setup()
    config.keymaps.setup(opts.keymaps)
    git.setup(opts.git)
end

return M
