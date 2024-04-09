if
    vim.fn.exists("g:R_filetypes") == 1
    and type(vim.g.R_filetypes) == "table"
    and vim.fn.index(vim.g.R_filetypes, "rmd") == -1
then
    return
end

require("r.config").real_setup()
require("r.config").rproj_setup()
require("r.rmd").setup()
