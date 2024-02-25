---@diagnostic disable: undefined-global
---@diagnostic disable: undefined-field
local jobopts = { rpc = true, width = 80, height = 24 }
local rpcrequest = vim.rpcrequest

describe("rmd module", function()
    local nvim -- Channel of the embedded Neovim process
    -- TODO: Move this to helpers file
    local function send_lua_via_rpc(lua_command, args)
        return rpcrequest(nvim, "nvim_exec_lua", lua_command, args or {})
    end
    local function set_filetype(filetype)
        rpcrequest(nvim, "nvim_buf_set_option", 0, "filetype", filetype)
    end
    local function get_current_line()
        return rpcrequest(nvim, "nvim_win_get_cursor", 0)[2]
    end

    before_each(
        function()
            nvim = vim.fn.jobstart(
                { "nvim", "--embed", "--headless", "tests/examples/example.Rmd" },
                jobopts
            )
        end
    )

    after_each(function() vim.fn.jobstop(nvim) end)

    describe("is_in_code_chunk(language, verbose) Unit Tests", function()
        it("returns true if in R chunk", function()
            rpcrequest(nvim, "nvim_win_set_cursor", 0, { 13, 0 })
            local result =
                send_lua_via_rpc([[return require('r.rmd').is_in_code_chunk('r', false)]])
            assert.is_true(result)
        end)
        it("returns false if outside R chunk", function()
            rpcrequest(nvim, "nvim_win_set_cursor", 0, { 1, 0 })
            local result =
                send_lua_via_rpc([[return require('r.rmd').is_in_code_chunk('r', false)]])
            assert.is_false(result)
        end)
        it("returns true if in Python chunk", function()
            rpcrequest(nvim, "nvim_win_set_cursor", 0, { 19, 0 })
            local result = send_lua_via_rpc(
                [[return require('r.rmd').is_in_code_chunk('python', false)]]
            )
            assert.is_true(result)
        end)
        it("returns false if not in Python chunk", function()
            rpcrequest(nvim, "nvim_win_set_cursor", 0, { 13, 0 })
            local result = send_lua_via_rpc(
                [[return require('r.rmd').is_in_code_chunk('python', false)]]
            )
            assert.is_false(result)
        end)
        it("returns true if on an '```{r' line", function()
            rpcrequest(nvim, "nvim_win_set_cursor", 0, { 12, 3 })
            local result =
                send_lua_via_rpc([[return require('r.rmd').is_in_code_chunk('r', false)]])
            assert.is_true(result)
        end)
        it("test verbosity", function() pending("test verbosity") end)
        it(
            "returns true if inside code chunk (filetype-agnostic)",
            function() pending("test filetype-agnostic code chunk detection") end
        )
        it(
            "returns false if outside code chunk (filetype-agnostic)",
            function() pending("test filetype-agnostic code chunk detection") end
        )
        it(
            "returns false if it cannot match ```",
            function() pending("test behaviour if chunk start/end not found") end
        )
    end)
    describe("write_chunk() Unit Tests", function()
        it(
            "Inserts an R code chunk in an empty line for RMarkdown",
            function() pending("Not implemented") end
        )
        it(
            "Inserts an R code chunk in an empty line for Quarto",
            function() pending("Not implemented") end
        )
        it(
            "Does not insert an R code chunk in a non-empty line in RMarkdown",
            function() pending("Not implemented") end
        )
        it(
            "Does not insert an R code chunk in a non-empty line in Quarto",
            function() pending("Not implemented") end
        )
        it(
            "Does not insert an R code chunk in a code chunk line in RMarkdown",
            function() pending("Not implemented") end
        )
        it(
            "Does not insert an R code chunk in a code chunk in Quarto",
            function() pending("Not implemented") end
        )

    end)
end)
