local config = require("r.config").get_config()
local warn = require("r").warn

local check_installed = function()
    if vim.fn.executable(config.pdfviewer) == 0 then
        warn(
            "R.nvim: Please, set the value of `pdfviewer`. The application `"
                .. config.pdfviewer
                .. "` was not found."
        )
    end
end

local M = {}

M.setup = function()
    local ptime = vim.fn.reltime()
    check_installed()
    if config.pdfviewer == "zathura" then
        M.open2 = require("r.pdf.zathura").open
        M.SyncTeX_forward = require("r.pdf.zathura").SyncTeX_forward
    elseif config.pdfviewer == "evince" then
        M.open2 = require("r.pdf.evince").open
        M.SyncTeX_forward = require("r.pdf.evince").SyncTeX_forward
    elseif config.pdfviewer == "okular" then
        M.open2 = require("r.pdf.okular").open
        M.SyncTeX_forward = require("r.pdf.okular").SyncTeX_forward
    elseif config.is_windows and config.pdfviewer == "sumatra" then
        M.open2 = require("r.pdf.sumatra").open
        M.SyncTeX_forward = require("r.pdf.sumatra").SyncTeX_forward
    elseif config.is_darwin and config.pdfviewer == "skim" then
        M.open2 = require("r.pdf.skim").open
        M.SyncTeX_forward = require("r.pdf.skim").SyncTeX_forward
    elseif config.pdfviewer == "qpdfview" then
        M.open2 = require("r.pdf.qpdfview").open
        M.SyncTeX_forward = require("r.pdf.qpdfview").SyncTeX_forward
    else
        M.open2 = require("r.pdf.generic").open
        M.SyncTeX_forward = require("r.pdf.generic").SyncTeX_forward
    end

    config.has_wmctrl = false

    if not config.is_windows and not config.is_darwin and not vim.env.WAYLAND_DISPLAY then
        if vim.fn.executable("wmctrl") > 0 then
            config.has_wmctrl = true
        else
            if vim.o.filetype == "rnoweb" and config.synctex then
                warn(
                    "The application wmctrl must be installed to edit Rnoweb effectively."
                )
            end
        end
    end

    require("r.edit").add_to_debug_info(
        "pdf setup",
        vim.fn.reltimefloat(vim.fn.reltime(ptime, vim.fn.reltime())),
        "Time"
    )
end

M.open = function(fullpath)
    if config.openpdf == 0 then return end

    if fullpath == "Get Master" then
        local fpath = require("r.rnw").SyncTeX_get_master() .. ".pdf"
        fpath = vim.b.rplugin_pdfdir .. "/" .. fpath:gsub(".*/", "")
        M.open(fpath)
        return
    end

    if not vim.b.pdf_is_open then
        if config.openpdf == 1 then vim.b.pdf_is_open = true end
        M.open2(fullpath)
    end
end

M.raise_window = function(wttl)
    if config.has_wmctrl then
        vim.fn.system("wmctrl -a '" .. wttl .. "'")
    elseif vim.env.WAYLAND_DISPLAY then
        if os.getenv("XDG_CURRENT_DESKTOP") == "sway" then
            local sout = vim.fn.system("swaymsg -t get_tree")
            if vim.v.shell_error ~= 0 then
                warn("Error running swaymsg: " .. vim.fn.substitute(sout, "\n", " ", "g"))
            end
        end
    end
end

return M
