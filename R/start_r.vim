"==============================================================================
" Function to start R and functions that are called only after R is started.
"==============================================================================

let g:SendCmdToR = luaeval('require("r.send").cmd')

let g:rplugin = {}

function s:RGetBufDir()
    let rwd = nvim_buf_get_name(0)
    if has("win32")
        let rwd = substitute(rwd, '\\', '/', 'g')
    endif
    let rwd = substitute(rwd, '\(.*\)/.*', '\1', '')
    return rwd
endfunction


"==============================================================================
" Internal communication with R
"==============================================================================

" Send a message to nvimrserver job which will send the message to nvimcom
" through a TCP connection.
function SendToNvimcom(code, attch)
    exe 'lua require("r.run").send_to_nvimcom("' . a:code . '", "' . a:attch . '")'
endfunction


"==============================================================================
"  Functions triggered by nvimcom after user action on R Console
"==============================================================================

function ShowRObj(howto, bname, ftype, txt)
    let bfnm = substitute(a:bname, '[ [:punct:]]', '_', 'g')
    call AddForDeletion(g:rplugin.tmpdir . "/" . bfnm)
    silent exe a:howto . ' ' . substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') . '/' . bfnm
    silent exe 'set ft=' . a:ftype
    call setline(1, split(substitute(a:txt, "\x13", "'", "g"), "\x14"))
    set nomodified
endfunction

" This function is called by nvimcom
function EditRObject(fname)
    let fcont = readfile(a:fname)
    exe "tabnew " . substitute($NVIMR_TMPDIR . "/edit_" . $NVIMR_ID, ' ', '\\ ', 'g')
    call setline(".", fcont)
    set filetype=r
    stopinsert
    autocmd BufUnload <buffer> call delete($NVIMR_TMPDIR . "/edit_" . $NVIMR_ID . "_wait") | startinsert
endfunction


"==============================================================================
"  Object Browser (see also ../ftplugin/rbrowser.vim)
"==============================================================================

function StartObjBrowser()
    " Either open or close the Object Browser
    let savesb = &switchbuf
    set switchbuf=useopen,usetab
    if bufloaded('Object_Browser')
        let curwin = win_getid()
        let curtab = tabpagenr()
        exe 'sb Object_Browser'
        let objbrtab = tabpagenr()
        quit
        call win_gotoid(curwin)
        if curtab != objbrtab
            call StartObjBrowser()
        endif
    else
        let edbuf = bufnr()

        if g:Rcfg.objbr_place =~# 'RIGHT'
            sil exe 'botright vsplit Object_Browser'
        elseif g:Rcfg.objbr_place =~# 'LEFT'
            sil exe 'topleft vsplit Object_Browser'
        elseif g:Rcfg.objbr_place =~# 'TOP'
            sil exe 'topleft split Object_Browser'
        elseif g:Rcfg.objbr_place =~# 'BOTTOM'
            sil exe 'botright split Object_Browser'
        else
            if g:Rcfg.objbr_place =~? 'console'
                sil exe 'sb ' . g:rplugin.R_bufnr
            else
                sil exe 'sb ' . luaeval('require("r.edit").get_rscript_name()')
            endif
            if g:Rcfg.objbr_place =~# 'right'
                sil exe 'rightbelow vsplit Object_Browser'
            elseif g:Rcfg.objbr_place =~# 'left'
                sil exe 'leftabove vsplit Object_Browser'
            elseif g:Rcfg.objbr_place =~# 'above'
                sil exe 'aboveleft split Object_Browser'
            elseif g:Rcfg.objbr_place =~# 'below'
                sil exe 'belowright split Object_Browser'
            else
                call RWarningMsg('Invalid value for R_objbr_place: "' . R_objbr_place . '"')
                exe "set switchbuf=" . savesb
                return
            endif
        endif
        if g:Rcfg.objbr_place =~? 'left' || g:Rcfg.objbr_place =~? 'right'
            sil exe 'vertical resize ' . g:Rcfg.objbr_w
        else
            sil exe 'resize ' . g:Rcfg.objbr_h
        endif
        sil set filetype=rbrowser
        let g:rplugin.curview = "GlobalEnv"
        let g:rplugin.ob_winnr = win_getid()
        let g:rplugin.ob_buf = nvim_win_get_buf(g:rplugin.ob_winnr)

        if exists('s:autosttobjbr') && s:autosttobjbr == 1
            let s:autosttobjbr = 0
            exe edbuf . 'sb'
        endif
    endif
    exe "set switchbuf=" . savesb
endfunction

" Open an Object Browser window
function RObjBrowser(...)
    " Only opens the Object Browser if R is running
    if g:R_Nvim_status < 5
        call RWarningMsg("The Object Browser can be opened only if R is running.")
        return
    endif

    if s:running_objbr == 1
        " Called twice due to BufEnter event
        return
    endif

    let s:running_objbr = 1

    " call RealUpdateRGlbEnv(1)
    call JobStdin("Server", "31\n")
    call SendToNvimcom("A", "RObjBrowser")

    call StartObjBrowser()
    let s:running_objbr = 0

    if len(g:Rcfg.after_ob_open) > 0
        redraw
        for cmd in g:Rcfg.after_ob_open
            exe substitute(cmd, '^:', '', '')
        endfor
    endif

    return
endfunction

function RBrOpenCloseLs(stt)
    call JobStdin("Server", "34" . a:stt . g:rplugin.curview . "\n")
endfunction


"==============================================================================
" Support for debugging R code
"==============================================================================

" No support for break points
"if synIDattr(synIDtrans(hlID("SignColumn")), "bg") =~ '^#'
"    exe 'hi def StopSign guifg=red guibg=' . synIDattr(synIDtrans(hlID("SignColumn")), "bg")
"else
"    exe 'hi def StopSign ctermfg=red ctermbg=' . synIDattr(synIDtrans(hlID("SignColumn")), "bg")
"endif
"call sign_define('stpline', {'text': '●', 'texthl': 'StopSign', 'linehl': 'None', 'numhl': 'None'})

" Functions sign_define(), sign_place() and sign_unplace() require Neovim >= 0.4.3
"call sign_define('dbgline', {'text': '▬▶', 'texthl': 'SignColumn', 'linehl': 'QuickFixLine', 'numhl': 'Normal'})

if &ambiwidth == "double"
    sign define dbgline text==> texthl=SignColumn linehl=QuickFixLine
else
    sign define dbgline text=▬▶ texthl=SignColumn linehl=QuickFixLine
endif

let s:func_offset = -2
let s:rdebugging = 0
function StopRDebugging()
    "call sign_unplace('rdebugcurline')
    "sign unplace rdebugcurline
    sign unplace 1
    let s:func_offset = -2 " Did not seek yet
    let s:rdebugging = 0
endfunction

function FindDebugFunc(srcref)
    if type(g:Rcfg.external_term) == v:t_bool && g:Rcfg.external_term == v:false
        let s:func_offset = -1 " Not found
        let sbopt = &switchbuf
        set switchbuf=useopen,usetab
        let curtab = tabpagenr()
        let isnormal = mode() ==# 'n'
        let curwin = winnr()
        exe 'sb ' . g:rplugin.R_bufnr
        sleep 30m " Time to fill the buffer lines
        let rlines = getline(1, "$")
        exe 'sb ' . luaeval('require("r.edit").get_rscript_name()')
    elseif string(g:SendCmdToR) == "function('SendCmdToR_Term')"
        let tout = system('tmux -L NvimR capture-pane -p -t ' . g:rplugin.tmuxsname)
        let rlines = split(tout, "\n")
    elseif string(g:SendCmdToR) == "function('SendCmdToR_TmuxSplit')"
        let tout = system('tmux capture-pane -p -t ' . g:rplugin.rconsole_pane)
        let rlines = split(tout, "\n")
    else
        let rlines = []
    endif

    let idx = len(rlines) - 1
    while idx > 0
        if rlines[idx] =~# '^debugging in: '
            let funcnm = substitute(rlines[idx], '^debugging in: \(.\{-}\)(.*', '\1', '')
            let s:func_offset = search('.*\<' . funcnm . '\s*<-\s*function\s*(', 'b')
            if s:func_offset < 1
                let s:func_offset = search('.*\<' . funcnm . '\s*=\s*function\s*(', 'b')
            endif
            if s:func_offset < 1
                let s:func_offset = search('.*\<' . funcnm . '\s*<<-\s*function\s*(', 'b')
            endif
            if s:func_offset > 0
                let s:func_offset -= 1
            endif
            if a:srcref == '<text>'
                if &filetype == 'rmd' || &filetype == 'quarto'
                    let s:func_offset = search('^\s*```\s*{\s*r', 'nb')
                elseif &filetype == 'rnoweb'
                    let s:func_offset = search('^<<', 'nb')
                endif
            endif
            break
        endif
        let idx -= 1
    endwhile

    if type(g:Rcfg.external_term) == v:t_bool && g:Rcfg.external_term == v:false
        if tabpagenr() != curtab
            exe 'normal! ' . curtab . 'gt'
        endif
        exe curwin . 'wincmd w'
        if isnormal
            stopinsert
        endif
        exe 'set switchbuf=' . sbopt
    endif
endfunction

function RDebugJump(fnm, lnum)
    let saved_so = &scrolloff
    if g:Rcfg.debug_center
        set so=999
    endif
    if a:fnm == '' || a:fnm == '<text>'
        " Functions sent directly to R Console have no associated source file
        " and functions sourced by knitr have '<text>' as source reference.
        if s:func_offset == -2
            call FindDebugFunc(a:fnm)
        endif
        if s:func_offset < 0
            return
        endif
    endif

    if s:func_offset >= 0
        let flnum = a:lnum + s:func_offset
        let fname = luaeval('require("r.edit").get_rscript_name()')
    else
        let flnum = a:lnum
        let fname = expand(a:fnm)
    endif

    let bname = bufname("%")

    if !bufloaded(fname) && fname != luaeval('require("r.edit").get_rscript_name()') && fname != expand("%") && fname != expand("%:p")
        if filereadable(fname)
            exe 'sb ' . luaeval('require("r.edit").get_rscript_name()')
            if &modified
                split
            endif
            exe 'edit ' . fname
        elseif glob("*") =~ fname
            exe 'sb ' . luaeval('require("r.edit").get_rscript_name()')
            if &modified
                split
            endif
            exe 'edit ' . fname
        else
            return
        endif
    endif

    if bufloaded(fname)
        if fname != expand("%")
            exe 'sb ' . fname
        endif
        exe ':' . flnum
    endif

    " Call sign_place() and sign_unplace() when requiring Vim 8.2 and Neovim 0.5
    "call sign_unplace('rdebugcurline')
    "call sign_place(1, 'rdebugcurline', 'dbgline', fname, {'lnum': flnum})
    sign unplace 1
    exe 'sign place 1 line=' . flnum . ' name=dbgline file=' . fname
    if g:Rcfg.dbg_jump && !s:rdebugging && type(g:Rcfg.external_term) == v:t_bool && g:Rcfg.external_term == v:false
        exe 'sb ' . g:rplugin.R_bufnr
        startinsert
    elseif bname != expand("%")
        exe 'sb ' . bname
    endif
    let s:rdebugging = 1
    exe 'set so=' . saved_so
endfunction


"==============================================================================
" Functions that ask R to help editing the code
"==============================================================================

function RFormatCode() range
    if g:rplugin.R_pid == 0
        return
    endif

    let wco = &textwidth
    if wco == 0
        let wco = 78
    elseif wco < 20
        let wco = 20
    elseif wco > 180
        let wco = 180
    endif

    let lns = getline(a:firstline, a:lastline)
    let txt = substitute(substitute(join(lns, "\x14"), '\\', '\\\\', 'g'), "'", "\x13", "g")
    call SendToNvimcom("E", "nvimcom:::nvim_format(" . a:firstline . ", " . a:lastline . ", " . wco . ", " . &shiftwidth. ", '" . txt . "')")
endfunction

function FinishRFormatCode(lnum1, lnum2, txt)
    let lns =  split(substitute(a:txt, "\x13", "'", "g"), "\x14")
    silent exe a:lnum1 . "," . a:lnum2 . "delete"
    call append(a:lnum1 - 1, lns)
    echo (a:lnum2 - a:lnum1 + 1) . " lines formatted."
endfunction

function RInsert(cmd, type)
    if g:rplugin.R_pid == 0
        return
    endif
    call SendToNvimcom("E", 'nvimcom:::nvim_insert(' . a:cmd . ', "' . a:type . '")')
endfunction

function SendLineToRAndInsertOutput()
    let lin = getline(".")
    let cleanl = substitute(lin, '".\{-}"', '', 'g')
    if cleanl =~ ';'
        call RWarningMsg('`print(line)` works only if `line` is a single command')
    endif
    let cleanl = substitute(lin, '\s*#.*', "", "")
    call RInsert("print(" . cleanl . ")", "comment")
endfunction

function FinishRInsert(type, txt)
    let ilines = split(substitute(a:txt, "\x13", "'", "g"), "\x14")
    if a:type == "comment"
        call map(ilines, '"# " . v:val')
    endif
    call append(line('.'), ilines)
endfunction

function GetROutput(fnm, txt)
    if a:fnm == "NewtabInsert"
        let tnum = 1
        while bufexists("so" . tnum)
            let tnum += 1
        endwhile
        exe 'tabnew so' . tnum
        call setline(1, split(substitute(a:txt, "\x13", "'", "g"), "\x14"))
        set filetype=rout
        setlocal buftype=nofile
        setlocal noswapfile
    else
        exe 'tabnew ' a:fnm
        call setline(1, split(substitute(a:txt, "\x13", "'", "g"), "\x14"))
    endif
    normal! gT
    redraw
endfunction


function RViewDF(oname, howto, txt)
    if has_key(g:Rcfg, 'csv_app')
        let tsvnm = g:rplugin.tmpdir . '/' . a:oname . '.tsv'
        call writefile(split(substitute(a:txt, "\x13", "'", "g"), "\x14"), tsvnm)
        call AddForDeletion(tsvnm)

        if g:Rcfg.csv_app =~ '%s'
            let cmd = printf(g:Rcfg.csv_app, tsvnm)
        else
            let cmd = g:Rcfg.csv_app . ' ' . tsvnm
        endif

        if g:Rcfg.csv_app =~# '^:'
            exe cmd
            return
        elseif g:Rcfg.csv_app =~# '^terminal:'
            let cmd = substitute(cmd, '^terminal:', '', '')
            tabnew
            exe 'terminal ' . cmd
            startinsert
            return
        endif

        normal! :<Esc>
        let appcmd = split(cmd)
        call jobstart(appcmd, {'detach': v:true})
        return
    endif

    let location = a:howto
    silent exe location . ' ' . a:oname
    " silent 1,$d
    call setline(1, split(substitute(a:txt, "\x13", "'", "g"), "\x14"))
    setlocal filetype=csv
    setlocal nomodified
    setlocal bufhidden=wipe
    setlocal noswapfile
    set buftype=nofile
    redraw
endfunction


"==============================================================================
" Show R documentation
"==============================================================================

function SetRTextWidth(rkeyword)
    if g:Rcfg.nvimpager == "tabnew"
        let s:rdoctitle = a:rkeyword
    else
        let s:tnr = tabpagenr()
        if g:Rcfg.nvimpager != "tab" && s:tnr > 1
            let s:rdoctitle = "R_doc" . s:tnr
        else
            let s:rdoctitle = "R_doc"
        endif
        unlet s:tnr
    endif
    if !bufloaded(s:rdoctitle) || g:rplugin_newsize == 1
        let g:rplugin_newsize = 0

        " s:vimpager is used to calculate the width of the R help documentation
        " and to decide whether to obey R_nvimpager = 'vertical'
        let s:vimpager = g:Rcfg.nvimpager

        let wwidth = winwidth(0)

        " Not enough room to split vertically
        if g:Rcfg.nvimpager == "vertical" && wwidth <= (g:Rcfg.help_w + g:Rcfg.editor_w)
            let s:vimpager = "horizontal"
        endif

        if s:vimpager == "horizontal"
            " Use the window width (at most 80 columns)
            let htwf = (wwidth > 80) ? 88.1 : ((wwidth - 1) / 0.9)
        elseif g:Rcfg.nvimpager == "tab" || g:Rcfg.nvimpager == "tabnew"
            let wwidth = &columns
            let htwf = (wwidth > 80) ? 88.1 : ((wwidth - 1) / 0.9)
        else
            let min_e = (g:Rcfg.editor_w > 80) ? g:Rcfg.editor_w : 80
            let min_h = (g:Rcfg.help_w > 73) ? g:Rcfg.help_w : 73

            if wwidth > (min_e + min_h)
                " The editor window is large enough to be split
                let s:hwidth = min_h
            elseif wwidth > (min_e + g:Rcfg.help_w)
                " The help window must have less than min_h columns
                let s:hwidth = wwidth - min_e
            else
                " The help window must have the minimum value
                let s:hwidth = g:Rcfg.help_w
            endif
            let htwf = (s:hwidth - 1) / 0.9
        endif
        let s:htw = float2nr(htwf)
        let s:htw = s:htw - (&number || &relativenumber) * &numberwidth
    endif
endfunction

function RAskHelp(...)
    if a:1 == ""
        call g:SendCmdToR("help.start()")
        return
    endif
    if g:Rcfg.nvimpager == "no"
        call g:SendCmdToR("help(" . a:1. ")")
    else
        call AskRDoc(a:1, "", 0)
    endif
endfunction

" Show R's help doc in Nvim's buffer
" (based  on pydoc plugin)
function AskRDoc(rkeyword, package, getclass)
    let firstobj = ""
    if bufname("%") =~ "Object_Browser" || (has_key(g:rplugin, "R_bufnr") && bufnr("%") == g:rplugin.R_bufnr)
        let savesb = &switchbuf
        set switchbuf=useopen,usetab
        exe "sb " . luaeval('require("r.edit").get_rscript_name()')
        exe "set switchbuf=" . savesb
    else
        if a:getclass
            let firstobj = RGetFirstObj(a:rkeyword)[0]
        endif
    endif

    call SetRTextWidth(a:rkeyword)

    if firstobj == "" && a:package == ""
        let rcmd = 'nvimcom:::nvim.help("' . a:rkeyword . '", ' . s:htw . 'L)'
    elseif a:package != ""
        let rcmd = 'nvimcom:::nvim.help("' . a:rkeyword . '", ' . s:htw . 'L, package="' . a:package  . '")'
    else
        let rcmd = 'nvimcom:::nvim.help("' . a:rkeyword . '", ' . s:htw . 'L, "' . firstobj . '")'
    endif

    call SendToNvimcom("E", rcmd)
endfunction

" Function called by nvimcom
function ShowRDoc(rkeyword, txt)
    let rkeyw = a:rkeyword
    if a:rkeyword =~ "^MULTILIB"
        let topic = split(a:rkeyword)[1]
        let libs = split(a:txt)
        let msg = "The topic '" . topic . "' was found in more than one library:\n"
        for idx in range(0, len(libs) - 1)
            let msg .= idx + 1 . " : " . libs[idx] . "\n"
        endfor
        redraw
        let chn = input(msg . "Please, select one of them: ")
        if chn > 0 && chn <= len(libs)
            call SendToNvimcom("E", 'nvimcom:::nvim.help("' . topic . '", ' . s:htw . 'L, package="' . libs[chn - 1] . '")')
        endif
        return
    endif

    if has_key(g:rplugin, "R_bufnr") && bufnr("%") == g:rplugin.R_bufnr
        " Exit Terminal mode and go to Normal mode
        stopinsert
    endif

    let s:running_rhelp = 0

    if bufname("%") =~ "Object_Browser" || (has_key(g:rplugin, "R_bufnr") && bufnr("%") == g:rplugin.R_bufnr)
        let savesb = &switchbuf
        set switchbuf=useopen,usetab
        exe "sb " . luaeval('require("r.edit").get_rscript_name()')
        exe "set switchbuf=" . savesb
    endif
    call SetRTextWidth(a:rkeyword)

    let rdoccaption = substitute(s:rdoctitle, '\', '', "g")
    if a:rkeyword =~ "R History"
        let rdoccaption = "R_History"
        let s:rdoctitle = "R_History"
    endif
    if bufloaded(rdoccaption)
        let curtabnr = tabpagenr()
        let savesb = &switchbuf
        set switchbuf=useopen,usetab
        exe "sb ". s:rdoctitle
        exe "set switchbuf=" . savesb
        if g:Rcfg.nvimpager == "tabnew"
            exe "tabmove " . curtabnr
        endif
    else
        if g:Rcfg.nvimpager == "tab" || g:Rcfg.nvimpager == "tabnew"
            exe 'tabnew ' . s:rdoctitle
        elseif s:vimpager == "vertical"
            let splr = &splitright
            set splitright
            exe s:hwidth . 'vsplit ' . s:rdoctitle
            let &splitright = splr
        elseif s:vimpager == "horizontal"
            exe 'split ' . s:rdoctitle
            if winheight(0) < 20
                resize 20
            endif
        elseif s:vimpager == "no"
            " The only way of ShowRDoc() being called when R_nvimpager=="no"
            " is the user setting the value of R_nvimpager to 'no' after
            " Neovim startup. It should be set in the vimrc.
            if type(g:Rcfg.external_term) == v:t_bool && g:Rcfg.external_term == v:false
                let g:Rcfg.nvimpager = "vertical"
            else
                let g:Rcfg.nvimpager = "tab"
            endif
            call ShowRDoc(a:rkeyword)
            return
        else
            echohl WarningMsg
            echomsg 'Invalid R_nvimpager value: "' . g:Rcfg.nvimpager . '". Valid values are: "tab", "vertical", "horizontal", "tabnew" and "no".'
            echohl None
            return
        endif
    endif

    setlocal modifiable

    let save_unnamed_reg = @@
    set modifiable
    sil normal! ggdG
    let fcntt = split(substitute(a:txt, "\x13", "'", "g"), "\x14")
    call setline(1, fcntt)
    if a:rkeyword =~ "R History"
        set filetype=r
        call cursor(1, 1)
    elseif a:rkeyword =~ '(help)' || search("\x08", "nw") > 0
        set filetype=rdoc
        call cursor(1, 1)
    elseif a:rkeyword =~? '\.Rd$'
        " Called by devtools::load_all().
        " See https://github.com/jalvesaq/Nvim-R/issues/482
        set filetype=rhelp
        call cursor(1, 1)
    else
        set filetype=rout
        setlocal bufhidden=wipe
        setlocal nonumber
        setlocal noswapfile
        set buftype=nofile
        nnoremap <buffer><silent> q :q<CR>
        call cursor(1, 1)
    endif
    let @@ = save_unnamed_reg
    setlocal nomodified
    stopinsert
    redraw
endfunction


"==============================================================================
" Functions to send code directly to R Console
"==============================================================================

function GetSourceArgs(e)
    let sargs = ""
    if g:Rcfg.source_args != ""
        let sargs = ", " . g:Rcfg.source_args
    endif
    if a:e == "echo"
        let sargs .= ', echo=TRUE'
    endif
    return sargs
endfunction

" Send sources to R
function RSourceLines(...)
    let lines = a:1
    if &filetype == "rrst"
        let lines = map(copy(lines), 'substitute(v:val, "^\\.\\. \\?", "", "")')
    endif
    if &filetype == "rmd" || &filetype == "quarto"
        let lines = map(copy(lines), 'substitute(v:val, "^(\\`\\`)\\?", "", "")')
    endif

    if a:0 == 3 && a:3 == "NewtabInsert"
        call writefile(lines, s:Rsource_write)
        call SendToNvimcom("E", 'nvimcom:::nvim_capture_source_output("' . s:Rsource_read . '", "NewtabInsert")')
        return 1
    endif

    " The "brackted paste" option is not documented because it is not well
    " tested and source() have always worked flawlessly.
    if g:Rcfg.source_args == "bracketed paste"
        let rcmd = "\x1b[200~" . join(lines, "\n") . "\x1b[201~"
    else
        call writefile(lines, s:Rsource_write)
        let sargs = substitute(GetSourceArgs(a:2), '^, ', '', '')
        if a:0 == 3
            let rcmd = 'NvimR.' . a:3 . '(' . sargs . ')'
        else
            let rcmd = 'NvimR.source(' . sargs . ')'
        endif
    endif

    if a:0 == 3 && a:3 == "PythonCode"
        let rcmd = 'reticulate::py_run_file("' . s:Rsource_read . '")'
    endif

    let ok = g:SendCmdToR(rcmd)
    return ok
endfunction

function CleanOxygenLine(line)
    let cline = a:line
    if cline =~ "^\s*#\\{1,2}'"
        let synName = synIDattr(synID(line("."), col("."), 1), "name")
        if synName == "rOExamples"
            let cline = substitute(cline, "^\s*#\\{1,2}'", "", "")
        endif
    endif
    return cline
endfunction

function CleanCurrentLine()
    let curline = substitute(getline("."), '^\s*', "", "")
    if &filetype == "r"
        let curline = CleanOxygenLine(curline)
    endif
    return curline
endfunction

" Skip empty lines and lines whose first non blank char is '#'
function GoDown()
    if &filetype == "rnoweb"
        let curline = getline(".")
        if curline[0] == '@'
            call RnwNextChunk()
            return
        endif
    elseif &filetype == "rmd" || &filetype == "quarto"
        let curline = getline(".")
        if curline =~ '^```$'
            call RmdNextChunk()
            return
        endif
    elseif &filetype == "rrst"
        let curline = getline(".")
        if curline =~ '^\.\. \.\.$'
            call RrstNextChunk()
            return
        endif
    endif

    let i = line(".") + 1
    call cursor(i, 1)
    let curline = CleanCurrentLine()
    let lastLine = line("$")
    while i < lastLine && (curline[0] == '#' || strlen(curline) == 0)
        let i = i + 1
        call cursor(i, 1)
        let curline = CleanCurrentLine()
    endwhile
endfunction

" Send motion to R
function SendMotionToR(type)
    let lstart = line("'[")
    let lend = line("']")
    if lstart == lend
        call SendLineToR("stay", lstart)
    else
        let lines = getline(lstart, lend)
        call RSourceLines(lines, "", "block")
    endif
endfunction

" Send block to R
" Adapted from marksbrowser plugin
" Function to get the marks which the cursor is between
function SendMBlockToR(e, m)
    if &filetype != "r" && b:IsInRCode(1) != 1
        return
    endif

    let curline = line(".")
    let lineA = 1
    let lineB = line("$")
    let maxmarks = strlen(s:all_marks)
    let n = 0
    while n < maxmarks
        let c = strpart(s:all_marks, n, 1)
        let lnum = line("'" . c)
        if lnum != 0
            if lnum <= curline && lnum > lineA
                let lineA = lnum
            elseif lnum > curline && lnum < lineB
                let lineB = lnum
            endif
        endif
        let n = n + 1
    endwhile
    if lineA == 1 && lineB == (line("$"))
        call RWarningMsg("The file has no mark!")
        return
    endif
    if lineB < line("$")
        let lineB -= 1
    endif
    let lines = getline(lineA, lineB)
    let ok = RSourceLines(lines, a:e, "block")
    if ok == 0
        return
    endif
    if a:m == "down" && lineB != line("$")
        call cursor(lineB, 1)
        call GoDown()
    endif
endfunction

" Count braces
function CountBraces(line)
    let line2 = substitute(a:line, "{", "", "g")
    let line3 = substitute(a:line, "}", "", "g")
    let result = strlen(line3) - strlen(line2)
    return result
endfunction

" Send functions to R
function SendFunctionToR(e, m)
    if &filetype != "r" && b:IsInRCode(1) != 1
        return
    endif

    let startline = line(".")
    let save_cursor = getpos(".")
    let line = SanitizeRLine(getline("."))
    let i = line(".")
    while i > 0 && line !~ "function"
        let i -= 1
        let line = SanitizeRLine(getline(i))
    endwhile
    if i == 0
        call RWarningMsg("Begin of function not found.")
        return
    endif
    let functionline = i
    while i > 0 && line !~ '\(<-\|=\)[[:space:]]*\($\|function\)'
        let i -= 1
        let line = SanitizeRLine(getline(i))
    endwhile
    if i == 0
        call RWarningMsg("The function assign operator  <-  was not found.")
        return
    endif
    let firstline = i
    let i = functionline
    let line = SanitizeRLine(getline(i))
    let tt = line("$")
    while i < tt && line !~ "{"
        let i += 1
        let line = SanitizeRLine(getline(i))
    endwhile
    if i == tt
        call RWarningMsg("The function opening brace was not found.")
        return
    endif
    let nb = CountBraces(line)
    while i < tt && nb > 0
        let i += 1
        let line = SanitizeRLine(getline(i))
        let nb += CountBraces(line)
    endwhile
    if nb != 0
        call RWarningMsg("The function closing brace was not found.")
        return
    endif
    let lastline = i

    if startline > lastline
        call setpos(".", [0, firstline - 1, 1])
        call SendFunctionToR(a:e, a:m)
        call setpos(".", save_cursor)
        return
    endif

    let lines = getline(firstline, lastline)
    let ok = RSourceLines(lines, a:e, "function")
    if  ok == 0
        return
    endif
    if a:m == "down"
        call cursor(lastline, 1)
        call GoDown()
    endif
endfunction

" Send selection to R
function SendSelectionToR(...)
    let ispy = 0
    if &filetype != "r"
        if (&filetype == 'rmd' || &filetype == 'quarto') && RmdIsInPythonCode(0)
            let ispy = 1
        elseif b:IsInRCode(0) != 1
            if (&filetype == "rnoweb" && getline(".") !~ "\\Sexpr{") || ((&filetype == "rmd" || &filetype == "quarto") && getline(".") !~ "`r ") || (&filetype == "rrst" && getline(".") !~ ":r:`")
                call RWarningMsg("Not inside an R code chunk.")
                return
            endif
        endif
    endif

    if line("'<") == line("'>")
        let i = col("'<") - 1
        let j = col("'>") - i
        let l = getline("'<")
        let line = strpart(l, i, j)
        if &filetype == "r"
            let line = CleanOxygenLine(line)
        endif
        let ok = g:SendCmdToR(line)
        if ok && a:2 =~ "down"
            call GoDown()
        endif
        return
    endif

    let lines = getline("'<", "'>")

    if visualmode() == "\<C-V>"
        let lj = line("'<")
        let cj = col("'<")
        let lk = line("'>")
        let ck = col("'>")
        if cj > ck
            let bb = ck - 1
            let ee = cj - ck + 1
        else
            let bb = cj - 1
            let ee = ck - cj + 1
        endif
        if cj > len(getline(lj)) || ck > len(getline(lk))
            for idx in range(0, len(lines) - 1)
                let lines[idx] = strpart(lines[idx], bb)
            endfor
        else
            for idx in range(0, len(lines) - 1)
                let lines[idx] = strpart(lines[idx], bb, ee)
            endfor
        endif
    else
        let i = col("'<") - 1
        let j = col("'>")
        let lines[0] = strpart(lines[0], i)
        let llen = len(lines) - 1
        let lines[llen] = strpart(lines[llen], 0, j)
    endif

    let curpos = getpos(".")
    let curline = line("'<")
    for idx in range(0, len(lines) - 1)
        call setpos(".", [0, curline, 1, 0])
        if &filetype == "r"
            let lines[idx] = CleanOxygenLine(lines[idx])
        endif
        let curline += 1
    endfor
    call setpos(".", curpos)

    if a:0 == 3 && a:3 == "NewtabInsert"
        let ok = RSourceLines(lines, a:1, "NewtabInsert")
    elseif ispy
        let ok = RSourceLines(lines, a:1, 'PythonCode')
    else
        let ok = RSourceLines(lines, a:1, 'selection')
    endif

    if ok == 0
        return
    endif

    if a:2 == "down"
        call GoDown()
    else
        if a:0 < 3 || (a:0 == 3 && a:3 != "normal")
            normal! gv
        endif
    endif
endfunction

" Send R code from the first chunk up to current line
function SendFHChunkToR()
    if &filetype == "rnoweb"
        let begchk = "^<<.*>>=\$"
        let endchk = "^@"
        let chdchk = "^<<.*child *= *"
    elseif &filetype == "rmd" || &filetype == "quarto"
        let begchk = "^[ \t]*```[ ]*{r"
        let endchk = "^[ \t]*```$"
        let chdchk = "^```.*child *= *"
    elseif &filetype == "rrst"
        let begchk = "^\\.\\. {r"
        let endchk = "^\\.\\. \\.\\."
        let chdchk = "^\.\. {r.*child *= *"
    else
        " Should never happen
        call RWarningMsg('Strange filetype (SendFHChunkToR): "' . &filetype . '"')
    endif

    let codelines = []
    let here = line(".")
    let curbuf = getline(1, "$")
    let idx = 0
    while idx < here
        if curbuf[idx] =~ begchk && curbuf[idx] !~ '\<eval\s*=\s*F'
            " Child R chunk
            if curbuf[idx] =~ chdchk
                " First run everything up to child chunk and reset buffer
                call RSourceLines(codelines, "silent", "chunk")
                let codelines = []

                " Next run child chunk and continue
                call KnitChild(curbuf[idx], 'stay')
                let idx += 1
                " Regular R chunk
            else
                let idx += 1
                while curbuf[idx] !~ endchk && idx < here
                    let codelines += [curbuf[idx]]
                    let idx += 1
                endwhile
            endif
        else
            let idx += 1
        endif
    endwhile
    call RSourceLines(codelines, "silent", "chunk")
endfunction

function KnitChild(line, godown)
    let nline = substitute(a:line, '.*child *= *', "", "")
    let cfile = substitute(nline, nline[0], "", "")
    let cfile = substitute(cfile, nline[0] . '.*', "", "")
    if filereadable(cfile)
        let ok = g:SendCmdToR("require(knitr); knit('" . cfile . "', output=" . s:null . ")")
        if a:godown =~ "down"
            call cursor(line(".")+1, 1)
            call GoDown()
        endif
    else
        call RWarningMsg("File not found: '" . cfile . "'")
    endif
endfunction

function RParenDiff(str)
    let clnln = substitute(a:str, '\\"',  "", "g")
    let clnln = substitute(clnln, "\\\\'",  "", "g")
    let clnln = substitute(clnln, '".\{-}"',  '', 'g')
    let clnln = substitute(clnln, "'.\\{-}'",  "", "g")
    let clnln = substitute(clnln, "#.*", "", "g")
    let llen1 = strlen(substitute(clnln, '[{(\[]', '', 'g'))
    let llen2 = strlen(substitute(clnln, '[})\]]', '', 'g'))
    return llen1 - llen2
endfunction

if exists('g:r_indent_op_pattern')
    let g:rplugin.op_pattern = g:r_indent_op_pattern
else
    let g:rplugin.op_pattern = '\(&\||\|+\|-\|\*\|/\|=\|\~\|%\|->\||>\)\s*$'
endif

" Send current line to R.
function SendLineToR(godown, ...)
    let lnum = get(a:, 1, ".")
    let line = getline(lnum)
    if strlen(line) == 0
        if a:godown =~ "down"
            call GoDown()
        endif
        return
    endif

    if &filetype == "rnoweb"
        if line == "@"
            if a:godown =~ "down"
                call GoDown()
            endif
            return
        endif
        if line =~ "^<<.*child *= *"
            call KnitChild(line, a:godown)
            return
        endif
        if RnwIsInRCode(1) != 1
            return
        endif
    endif

    if &filetype == "rmd" || &filetype == "quarto"
        if line == "```"
            if a:godown =~ "down"
                call GoDown()
            endif
            return
        endif
        if line =~ "^```.*child *= *"
            call KnitChild(line, a:godown)
            return
        endif
        let line = substitute(line, "^(\\`\\`)\\?", "", "")
        if RmdIsInRCode(0) != 1
            if RmdIsInPythonCode(0) == 0
                call RWarningMsg("Not inside an R code chunk.")
                return
            else
                let line = 'reticulate::py_run_string("' . substitute(line, '"', '\\"', 'g') . '")'
            endif
        endif
    endif

    if &filetype == "rrst"
        if line == ".. .."
            if a:godown =~ "down"
                call GoDown()
            endif
            return
        endif
        if line =~ "^\.\. {r.*child *= *"
            call KnitChild(line, a:godown)
            return
        endif
        let line = substitute(line, "^\\.\\. \\?", "", "")
        if RrstIsInRCode(1) != 1
            return
        endif
    endif

    if &filetype == "rdoc"
        if getline(1) =~ '^The topic'
            let topic = substitute(line, '.*::', '', "")
            let package = substitute(line, '::.*', '', "")
            call AskRDoc(topic, package, 1)
            return
        endif
        if RdocIsInRCode(1) != 1
            return
        endif
    endif

    if &filetype == "rhelp" && b:IsInRCode(1) != 1
        return
    endif

    if &filetype == "r"
        let line = CleanOxygenLine(line)
    endif

    let block = 0
    if g:Rcfg.parenblock
        let chunkend = ""
        if &filetype == "rmd" || &filetype == "quarto"
            let chunkend = "```"
        elseif &filetype == "rnoweb"
            let chunkend = "@"
        elseif &filetype == "rrst"
            let chunkend = ".. .."
        endif
        let rpd = RParenDiff(line)
        let has_op = substitute(line, '#.*', '', '') =~ g:rplugin.op_pattern
        if rpd < 0
            let line1 = line(".")
            let cline = line1 + 1
            while cline <= line("$")
                let txt = getline(cline)
                if chunkend != "" && txt == chunkend
                    break
                endif
                let rpd += RParenDiff(txt)
                if rpd == 0
                    let has_op = substitute(getline(cline), '#.*', '', '') =~ g:rplugin.op_pattern
                    for lnum in range(line1, cline)
                        if g:Rcfg.bracketed_paste
                            if lnum == line1 && lnum == cline
                                let ok = g:SendCmdToR("\x1b[200~" . getline(lnum) . "\x1b[201~\n", 0)
                            elseif lnum == line1
                                let ok = g:SendCmdToR("\x1b[200~" . getline(lnum))
                            elseif lnum == cline
                                let ok = g:SendCmdToR(getline(lnum) . "\x1b[201~\n", 0)
                            else
                                let ok = g:SendCmdToR(getline(lnum))
                            endif
                        else
                            let ok = g:SendCmdToR(getline(lnum))
                        end
                        if !ok
                            " always close bracketed mode upon failure
                            if g:Rcfg.bracketed_paste
                                call g:SendCmdToR("\x1b[201~\n", 0)
                            end
                            return
                        endif
                    endfor
                    call cursor(cline, 1)
                    let block = 1
                    break
                endif
                let cline += 1
            endwhile
        endif
    endif

    if !block
        if g:Rcfg.bracketed_paste
            let ok = g:SendCmdToR("\x1b[200~" . line . "\x1b[201~\n", 0)
        else
            let ok = g:SendCmdToR(line)
        end
    endif

    if ok
        if a:godown =~ "down"
            call GoDown()
            if exists('has_op') && has_op
                call SendLineToR(a:godown)
            endif
        else
            if a:godown == "newline"
                normal! o
            endif
        endif
    endif
endfunction

function RSendPartOfLine(direction, correctpos)
    let lin = getline(".")
    let idx = col(".") - 1
    if a:correctpos
        call cursor(line("."), idx)
    endif
    if a:direction == "right"
        let rcmd = strpart(lin, idx)
    else
        let rcmd = strpart(lin, 0, idx + 1)
    endif
    call g:SendCmdToR(rcmd)
endfunction

" Clear the console screen
function RClearConsole()
    if g:Rcfg.clear_console == v:false
        return
    endif
    if has("win32") && type(g:Rcfg.external_term) == v:t_bool && g:Rcfg.external_term
        call JobStdin("Server", "86\n")
        sleep 50m
        call JobStdin("Server", "87\n")
    else
        call g:SendCmdToR("\014", 0)
    endif
endfunction

" Remove all objects
function RClearAll()
    if g:Rcfg.rmhidden
        call g:SendCmdToR("rm(list=ls(all.names = TRUE))")
    else
        call g:SendCmdToR("rm(list=ls())")
    endif
    sleep 500m
    call RClearConsole()
endfunction

" Set working directory to the path of current buffer
function RSetWD()
    let wdcmd = 'setwd("' . s:RGetBufDir() . '")'
    if has("win32")
        let wdcmd = substitute(wdcmd, "\\", "/", "g")
    endif
    call g:SendCmdToR(wdcmd)
    sleep 100m
endfunction

" knit the current buffer content
function RKnit()
    update
    call g:SendCmdToR('require(knitr); .nvim_oldwd <- getwd(); setwd("' . s:RGetBufDir() . '"); knit("' . expand("%:t") . '"); setwd(.nvim_oldwd); rm(.nvim_oldwd)')
endfunction

function StartTxtBrowser(brwsr, url)
    tabnew
    call termopen(a:brwsr . " " . a:url)
    startinsert
endfunction

function RSourceDirectory(...)
    if has("win32")
        let dir = substitute(a:1, '\\', '/', "g")
    else
        let dir = a:1
    endif
    if dir == ""
        call g:SendCmdToR("nvim.srcdir()")
    else
        call g:SendCmdToR("nvim.srcdir('" . dir . "')")
    endif
endfunction

function PrintRObject(rkeyword)
    if bufname("%") =~ "Object_Browser"
        let firstobj = ""
    else
        let firstobj = RGetFirstObj(a:rkeyword)[0]
    endif
    if firstobj == ""
        call g:SendCmdToR("print(" . a:rkeyword . ")")
    else
        call g:SendCmdToR('nvim.print("' . a:rkeyword . '", "' . firstobj . '")')
    endif
endfunction

function OpenRExample()
    if bufloaded(g:rplugin.tmpdir . "/example.R")
        exe "bunload! " . substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g')
    endif
    if g:Rcfg.nvimpager == "tabnew" || g:Rcfg.nvimpager == "tab"
        exe "tabnew " . substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') . "/example.R"
    else
        let nvimpager = g:Rcfg.nvimpager
        if g:Rcfg.nvimpager == "vertical"
            let wwidth = winwidth(0)
            let min_e = (g:Rcfg.editor_w > 78) ? g:Rcfg.editor_w : 78
            let min_h = (g:Rcfg.help_w > 78) ? g:Rcfg.help_w : 78
            if wwidth < (min_e + min_h)
                let nvimpager = "horizontal"
            endif
        endif
        if nvimpager == "vertical"
            exe "belowright vsplit " . substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') . "/example.R"
        else
            exe "belowright split " . substitute(g:rplugin.tmpdir, ' ', '\\ ', 'g') . "/example.R"
        endif
    endif
    nnoremap <buffer><silent> q :q<CR>
    setlocal bufhidden=wipe
    setlocal noswapfile
    set buftype=nofile
    call delete(g:rplugin.tmpdir . "/example.R")
endfunction

" Call R functions for the word under cursor
function RAction(rcmd, ...)
    if &filetype == "rdoc"
        let rkeyword = expand('<cword>')
    elseif &filetype == "rbrowser"
        let rkeyword = RBrowserGetName()
    elseif a:0 == 1 && a:1 == "v" && line("'<") == line("'>")
        let rkeyword = strpart(getline("'>"), col("'<") - 1, col("'>") - col("'<") + 1)
    elseif a:0 == 1 && a:1 != "v" && a:1 !~ '^,'
        let rkeyword = RGetKeyword()
    else
        let rkeyword = RGetKeyword()
    endif
    if strlen(rkeyword) > 0
        if a:rcmd == "help"
            if rkeyword =~ "::"
                let rhelplist = split(rkeyword, "::")
                let rhelppkg = rhelplist[0]
                let rhelptopic = rhelplist[1]
            else
                let rhelppkg = ""
                let rhelptopic = rkeyword
            endif
            let s:running_rhelp = 1
            if g:Rcfg.nvimpager == "no"
                call g:SendCmdToR("help(" . rkeyword . ")")
            else
                if bufname("%") =~ "Object_Browser"
                    if g:rplugin.curview == "libraries"
                        let pkg = RBGetPkgName()
                    else
                        let pkg = ""
                    endif
                endif
                call AskRDoc(rhelptopic, rhelppkg, 1)
            endif
            return
        endif
        if a:rcmd == "print"
            call PrintRObject(rkeyword)
            return
        endif
        let rfun = a:rcmd
        if a:rcmd == "args"
            if g:Rcfg.listmethods && rkeyword !~ '::'
                call g:SendCmdToR('nvim.list.args("' . rkeyword . '")')
            else
                call g:SendCmdToR('args(' . rkeyword . ')')
            endif
            return
        endif
        if a:rcmd == "plot" && g:Rcfg.specialplot
            let rfun = "nvim.plot"
        endif
        if a:rcmd == "plotsumm"
            if g:Rcfg.specialplot
                let raction = "nvim.plot(" . rkeyword . "); summary(" . rkeyword . ")"
            else
                let raction = "plot(" . rkeyword . "); summary(" . rkeyword . ")"
            endif
            call g:SendCmdToR(raction)
            return
        endif

        if g:Rcfg.open_example && a:rcmd == "example"
            call SendToNvimcom("E", 'nvimcom:::nvim.example("' . rkeyword . '")')
            return
        endif

        if a:0 == 1 && a:1 =~ '^,'
            let argmnts = a:1
        elseif a:0 == 2 && a:2 =~ '^,'
            let argmnts = a:2
        else
            let argmnts = ''
        endif

        if a:rcmd == "viewobj" || a:rcmd == "dputtab"
            if a:rcmd == "viewobj"
                if has_key(g:Rcfg, "df_viewer")
                    let argmnts .= ', R_df_viewer = "' . g:Rcfg.df_viewer . '"'
                endif
                if rkeyword =~ '::'
                    call SendToNvimcom("E",
                                \'nvimcom:::nvim_viewobj(' . rkeyword . argmnts . ')')
                else
                    if has("win32") && &encoding == "utf-8"
                        call SendToNvimcom("E",
                                    \'nvimcom:::nvim_viewobj("' . rkeyword . '"' . argmnts .
                                    \', fenc="UTF-8"' . ')')
                    else
                        call SendToNvimcom("E",
                                    \'nvimcom:::nvim_viewobj("' . rkeyword . '"' . argmnts . ')')
                    endif
                endif
            else
                call SendToNvimcom("E",
                            \'nvimcom:::nvim_dput("' . rkeyword . '"' . argmnts . ')')
            endif
            return
        endif

        let raction = rfun . '(' . rkeyword . argmnts . ')'
        call g:SendCmdToR(raction)
    endif
endfunction

function RLoadHTML(fullpath, browser)
    if g:Rcfg.openhtml == v:false
        return
    endif

    if a:browser == ''
        if has('win32') || g:rplugin.is_darwin
            let cmd = ['open', a:fullpath]
        else
            let cmd = ['xdg-open', a:fullpath]
        endif
    else
        let cmd = split(a:browser) + [a:fullpath]
    endif

    call jobstart(cmd, {'detach': 1})
endfunction

function ROpenDoc(fullpath, browser)
    if a:fullpath == ""
        return
    endif
    if !filereadable(a:fullpath)
        call RWarningMsg('The file "' . a:fullpath . '" does not exist.')
        return
    endif
    if a:fullpath =~ '.odt$' || a:fullpath =~ '.docx$'
        call system('lowriter ' . a:fullpath . ' &')
    elseif a:fullpath =~ '.pdf$'
        call ROpenPDF(a:fullpath)
    elseif a:fullpath =~ '.html$'
        call RLoadHTML(a:fullpath, a:browser)
    else
        call RWarningMsg("Unknown file type from nvim.interlace: " . a:fullpath)
    endif
endfunction

" render a document with rmarkdown
function RMakeRmd(t)
    update

    let rmddir = s:RGetBufDir()
    if a:t == "default"
        let rcmd = 'nvim.interlace.rmd("' . expand("%:t") . '", rmddir = "' . rmddir . '"'
    else
        let rcmd = 'nvim.interlace.rmd("' . expand("%:t") . '", outform = "' . a:t .'", rmddir = "' . rmddir . '"'
    endif

    if g:Rcfg.rmarkdown_args == ''
        let rcmd = rcmd . ', envir = ' . g:Rcfg.rmd_environment . ')'
    else
        let rcmd = rcmd . ', envir = ' . g:Rcfg.rmd_environment . ', ' . substitute(g:Rcfg.rmarkdown_args, "'", '"', 'g') . ')'
    endif
    call g:SendCmdToR(rcmd)
endfunction
