" data "{{{

" We initialize the state of the plugin to 'disabled'.
" But only if it hasn't already been initialized.
" Why?
" Because if we edit the code, while the drawing mappings are installed, and
" source it, then the next time we will toggle the state of the plugin with
" `m_`, `m<space>`, `draw_it#change_state()` will save the drawing mappings in
" `s:original_mappings`. From then, we won't be able to remove the
" mappings with `m|`, because the plugin will consider them as default.
"
" This issue is not limited to this particular case.
" It's a fundamental issue.
" When a plugin relies on some information which is initialized before its
" execution, and this information can change, we must make sure it's always
" correct.
" We must NOT LIE to the plugin. Feeding it with wrong info will ALWAYS cause
" unexpected behavior. Remember, we faced the same issue when we were working
" on mucomplete, with the `s:auto` flag.
"
" So, here, we use `get()` to make sure we don't accidentally alter the info
" after it has been initialized.
"
" Another way of putting it: only initialize a variable ONCE.
" Sourcing a file, again and again, should NOT RE-initialize a variable.

let s:state = get(s:, 'state', 'disabled')

let s:key2char = {
                 \ '<Left>'     : '-',
                 \ '<Right>'    : '-',
                 \ '<Down>'     : '|',
                 \ '<Up>'       : '|',
                 \ '<PageDown>' : '\',
                 \ '<PageUp>'   : '/',
                 \ '<Home>'     : '\',
                 \ '<End>'      : '/',
                 \ '<'          : '<',
                 \ '>'          : '>',
                 \ 'v'          : 'v',
                 \ '^'          : '^',
                 \ }

let s:key2motion = {
                   \ '<Left>'     : 'h',
                   \ '<Right>'    : 'l',
                   \ '<Down>'     : 'j',
                   \ '<Up>'       : 'k',
                   \ '<PageDown>' : 'lj',
                   \ '<PageUp>'   : 'lk',
                   \ '<End>'      : 'hj',
                   \ '<Home>'     : 'hk',
                   \ '<'          : 'h',
                   \ '>'          : 'l',
                   \ 'v'          : 'j',
                   \ '^'          : 'k',
                   \ '<S-Left>'   : 'h',
                   \ '<S-Right>'  : 'l',
                   \ '<S-Down>'   : 'j',
                   \ '<S-Up>'     : 'k',
                   \ }

let s:crossing_keys = {
                      \ '<Left>'     : '[-|+]',
                      \ '<Right>'    : '[-|+]',
                      \ '<Down>'     : '[-|+]',
                      \ '<Up>'       : '[-|+]',
                      \ '<PageDown>' : '[\/X]',
                      \ '<PageUp>'   : '[\/X]',
                      \ '<End>'      : '[\/X]',
                      \ '<Home>'     : '[\/X]',
                      \ }

let s:intersection = {
                     \ '<Left>'     : '+',
                     \ '<Right>'    : '+',
                     \ '<Down>'     : '+',
                     \ '<Up>'       : '+',
                     \ '<PageDown>' : 'X',
                     \ '<PageUp>'   : 'X',
                     \ '<End>'      : 'X',
                     \ '<Home>'     : 'X',
                     \ }

"}}}
" above_first_line "{{{

fu! s:above_first_line(key) abort
    return count(['<Up>', '<PageUp>', '<Home>', '^'], a:key)
            \ && s:state ==# 'drawing' && line('.') == 1
endfu

"}}}
" beyond_last_line"{{{

fu! s:beyond_last_line(key) abort
    return count(['<Down>', '<PageDown>', '<End>', 'v'], a:key)
            \ && s:state ==# 'drawing' && line('.') == line('$')
endfu

"}}}
" arrow "{{{

fu! s:arrow() abort
    " let x0 = virtcol("'<")
    " let y0 = line("'<")
    " let x1 = virtcol("'>")
    " let y1 = line("'>")

    " exe 'norm! '.y0.'G'.x0.'|v'.x1.'|r-'
    " exe 'norm! '.y1.'G'.x0.'|v'.x1.'|r-'

    " exe 'norm! '.y0.'G'.x0."|\<C-v>".y1.'Gr|'
    " exe 'norm! '.y1.'G'.x1."|\<C-v>".y0.'Gr|'

    " call s:set_char_at('+', x0, y0)
    " call s:set_char_at('+', x0, y1)
    " call s:set_char_at('+', x1, y0)
    " call s:set_char_at('+', x1, y1)
endfu

"}}}
" box "{{{

fu! s:box() abort
    let x0 = virtcol("'<")
    let y0 = line("'<")
    let x1 = virtcol("'>")
    let y1 = line("'>")

    " draw the horizontal sides of the box
    exe 'norm! '.y0.'G'.x0.'|v'.x1.'|r-'
    exe 'norm! '.y1.'G'.x0.'|v'.x1.'|r-'

    " draw the vertical sides of the box
    exe 'norm! '.y0.'G'.x0."|\<C-v>".y1.'Gr|'
    exe 'norm! '.y1.'G'.x1."|\<C-v>".y0.'Gr|'

    " draw the corners of the box
    call s:set_char_at('+', x0, y0)
    call s:set_char_at('+', x0, y1)
    call s:set_char_at('+', x1, y0)
    call s:set_char_at('+', x1, y1)
endfu

"}}}
" change_state "{{{

fu! draw_it#change_state(erasing_mode) abort

    if s:state ==# 'disabled'
        let s:ve_save  = &ve
        let s:ww_save  = &ww
        let s:sol_save = &sol
        let s:original_mappings = extend(s:save_mappings(['mdb', 'mde'], 'x', 1),
                                \        s:save_mappings([
                                \                               '<Left>',
                                \                               '<Right>',
                                \                               '<Down>',
                                \                               '<Up>',
                                \                               '<S-Left>',
                                \                               '<S-Right>',
                                \                               '<S-Down>',
                                \                               '<S-Up>',
                                \                               '<PageDown>',
                                \                               '<PageUp>',
                                \                               '<End>',
                                \                               '<Home>',
                                \                               '<',
                                \                               '>',
                                \                               'v',
                                \                               '^',
                                \                              ],
                                \
                                \                                 'n',
                                \                                      1)
                                \       )

        " The last argument passed to `s:save_mappings()` is 1. "{{{
        " This is very important. It means that we save global mappings.
        " We aren't interested in buffer-local ones.
        " Why?
        " It would be difficult to restore them, we would need to first restore
        " the focus to the buffer where they were initially saved.
        " And they could only be used in the current buffer, not in others.
        "
        " I prefer to not bother.
        " If the user mapped the keys locally, our global mapping will work
        " everywhere except in the current buffer and buffers where they
        " installed similar buffer-local mappings.
        "
        " Trying to support this case would create too much complexity.
        " We would need to override the buffer-local mappings from the user in
        " every buffer where they exist. It would probably require an autocmd,
        " watching some event, like `BufEnter,BufNewFile`.
        " It would have to check whether the user did install a buffer-local
        " mapping using the keys we're interested in, and in that case,
        " save the info about the mapping as well as the position of the buffer
        " in the buffer list.
        "
        " Once the user stops drawing, we would then need to parse all this
        " info, to give the focus to various buffers and restore the mappings
        " in them.
        " Then, we would need to restore the layout… FUBAR
        "
        " }}}
    endif

    let s:state = {
                       \ 'disabled' : a:erasing_mode ? 'erasing'  : 'drawing' ,
                       \ 'drawing'  : a:erasing_mode ? 'erasing'  : 'disabled',
                       \ 'erasing'  : a:erasing_mode ? 'disabled' : 'drawing' ,
                       \ }[s:state]

    call s:toggle_mappings()
endfu

"}}}
" ellipse "{{{

fu! s:ellipse() abort
    let x0    = virtcol("'<")
    let y0    = line("'<")
    let x1    = virtcol("'>")
    let y1    = line("'>")

    let xoff  = (x0+x1)/2
    let yoff  = (y0+y1)/2
    let a     = abs(x1-x0)/2
    let b     = abs(y1-y0)/2
    let a2    = a*a
    let b2    = b*b
    let twoa2 = a2 + a2
    let twob2 = b2 + b2

    let xi = 0
    let yi = b
    let ei = 0
    call s:four(xi,yi,xoff,yoff,a,b)
    while xi <= a && yi >= 0

        let dy = a2 - twoa2*yi
        let ca = ei + twob2*xi + b2
        let cb = ca + dy
        let cc = ei + dy

        let aca = abs(ca)
        let acb = abs(cb)
        let acc = abs(cc)

        " pick case: (xi+1,yi) (xi,yi-1) (xi+1,yi-1)
        if aca <= acb && aca <= acc
            let xi = xi + 1
            let ei = ca
        elseif acb <= aca && acb <= acc
            let ei = cb
            let xi = xi + 1
            let yi = yi - 1
        else
            let ei = cc
            let yi = yi - 1
        endif
        if xi > x1
            break
        endif
        call s:four(xi, yi, xoff, yoff, a, b)
    endwhile
endfu

fu! s:four(x, y, xoff, yoff, a, b) abort
    let x  = a:xoff + a:x
    let y  = a:yoff + a:y
    let lx = a:xoff - a:x
    let by = a:yoff - a:y

    call s:set_char_at('*',  x, y)
    call s:set_char_at('*', lx, y)
    call s:set_char_at('*', lx, by)
    call s:set_char_at('*',  x, by)
endfu

"}}}
" install_mappings "{{{

fu! s:install_mappings() abort
    let args = ' <nowait> <silent> '

    for l:key in [
                 \ '<Left>',
                 \ '<Right>',
                 \ '<Down>',
                 \ '<Up>',
                 \ '<PageDown>',
                 \ '<PageUp>',
                 \ '<Home>',
                 \ '<End>',
                 \ ]
        exe 'nno '.args.' '.l:key
                    \.' :<C-U>call <SID>draw_it('.string('<lt>'.l:key[1:]).')<CR>'
    endfor

    for l:key in ['<', '>', 'v', '^']
        exe 'nno '.args.' '.l:key
                    \.' :<C-U>call <SID>draw_it('.string(l:key).')<CR>'
    endfor

    for l:key in [
                 \ '<S-Left>',
                 \ '<S-Right>',
                 \ '<S-Down>',
                 \ '<S-Up>',
                 \ ]
        exe 'nno '.args.' '.l:key
                        \ .' :<C-U>call <SID>shift_arrow('
                        \ .string(s:key2motion[l:key])
                        \ .')<CR>'
    endfor

    xno <silent> mdb       :<C-U>call <SID>box()<CR>
    xno <silent> mde       :<C-U>call <SID>ellipse()<CR>
endfu

"}}}
" it "{{{

fu! s:draw_it(key) abort

    if s:beyond_last_line(a:key)
        call append('.', '')
    elseif s:above_first_line(a:key)
        call append(0, '')
    endif

    if count([
             \ '<Left>',
             \ '<Right>',
             \ '<Down>',
             \ '<Up>',
             \ '<PageDown>',
             \ '<PageUp>',
             \ '<End>',
             \ '<Home>'
             \ ],
             \     a:key)

        call s:replace_char(a:key)
        exe 'norm! '.s:key2motion[a:key]
        call s:replace_char(a:key)

    elseif count(['^', 'v', '<', '>'], a:key)
        exe 'norm! r'.s:key2char[a:key].s:key2motion[a:key].'r'.s:key2char[a:key]
    endif
endfu

"}}}
" remove_mappings "{{{

fu! s:remove_mappings() abort
    if !exists('s:original_mappings')
        return
    endif

    for l:key in [
                 \ '<Left>',
                 \ '<Right>',
                 \ '<Down>',
                 \ '<Up>',
                 \ '<S-Left>',
                 \ '<S-Right>',
                 \ '<S-Down>',
                 \ '<S-Up>',
                 \ '<PageDown>',
                 \ '<PageUp>',
                 \ '^',
                 \ 'v',
                 \ '<',
                 \ '>',
                 \ ]

        " Why unmap silently?
        "
        " Because we could be dumb and ask to disable the drawing mode manually
        " (`m|`), even though it's already disabled.
        " It could raise errors, if the keys are already unmapped (the user didn't
        " map them to anything by default).

        sil! exe 'nunmap '.l:key
    endfor

    for l:key in ['mdb', 'mde']
        sil! exe 'xunmap '.l:key
    endfor

    call s:restore_mappings(s:original_mappings)
endfu

"}}}
" restore_mappings "{{{

" Warning:
" Don't try to restore a buffer local mapping unless you're sure that, when
" `s:restore_mappings()` is called, you're in the same buffer where
" `s:save_mappings()` was originally called.
"
" If you aren't in the same buffer, you could install a buffer-local mapping
" inside a buffer where this mapping didn't exist before.
" It could cause unexpected behavior on the user's system.
"
" Usage:
" call s:restore_mappings(my_saved_mappings)
"
" `my_saved_mappings` is a dictionary obtained earlier by calling
" `s:save_mappings()`.
" Its keys are the keys used in the mappings.
" Its values are the info about those mappings stored in sub-dictionaries.
"
" There's nothing special to pass to `s:restore_mappings()`, no other
" argument, no wrapping inside a 3rd dictionary, or anything. Just this dictionary.

fu! s:restore_mappings(mappings) abort

    for mapping in values(a:mappings)
        if !empty(mapping)
            exe     mapping.mode
               \ . (mapping.noremap ? 'noremap ' : 'map ')
               \ . (mapping.buffer  ? ' <buffer> ' : '')
               \ . (mapping.expr    ? ' <expr>   ' : '')
               \ . (mapping.nowait  ? ' <nowait> ' : '')
               \ . (mapping.silent  ? ' <silent> ' : '')
               \ .  mapping.lhs
               \ . ' '
               \ . substitute(mapping.rhs, '<SID>', '<SNR>'.mapping.sid.'_', 'g')
        endif
    endfor

endfu

"}}}
" replace_char"{{{

fu! s:replace_char(key) abort

    " This function is called before and then after a motion (left, up, …).
    " It must return the character to draw.
    "
    " When it's called AFTER a motion, and we're erasing, the character HAS TO
    " be a space.
    " When it's called BEFORE a motion, and we're erasing, we COULD (should?)
    " return nothing.
    "
    " Nevertheless, we let the function return a space.
    " It doesn't seem to cause an issue.
    " This way, we don't have to pass a 2nd argument to know when it's called
    " (before or after a motion).

    let cchar = getline('.')[col('.')-1]

    exe 'norm! r'
               \ .(
               \   s:state ==# 'erasing'
               \   ? ' '
               \   : cchar =~# s:crossing_keys[a:key] && cchar !=# s:key2char[a:key]
               \         ? s:intersection[a:key]
               \         : s:key2char[a:key]
               \  )
endfu

"}}}
" save_mappings "{{{

" Usage:
"
"     let my_global_mappings = s:save_mappings(['key1', 'key2', …], 'n', 1)
"     let my_local_mappings  = s:save_mappings(['key1', 'key2', …], 'n', 0)
"

" Output example: "{{{
"
"     { '<left>' :
"                \
"                \ {'silent': 0,
"                \ 'noremap': 1,
"                \ 'lhs': '<Left>',
"                \ 'mode': 'n',
"                \ 'nowait': 0,
"                \ 'expr': 0,
"                \ 'sid': 7,
"                \ 'rhs': ':echo ''foo''<CR>',
"                \ 'buffer': 1},
"                \
"     \ '<right>':
"                \
"                \ { 'silent': 0,
"                \ 'noremap': 1,
"                \ 'lhs': '<Right>',
"                \ 'mode': 'n',
"                \ 'nowait': 0,
"                \ 'expr': 0,
"                \ 'sid': 7,
"                \ 'rhs': ':echo ''bar''<CR>',
"                \ 'buffer': 1,
"                \ },
"                \}
"
" }}}

fu! s:save_mappings(keys, mode, global) abort
    let mappings = {}

    " If a key is used in a global mapping and a local one, by default,
    " `maparg()` only returns information about the local one.
    " We want to be able to get info about a global mapping even if a local
    " one shadows it.
    " To do that, we will temporarily unmap the local mapping.

    if a:global
        for l:key in a:keys
            let buf_local_map = maparg(l:key, a:mode, 0, 1)

            " temporarily unmap the local mapping
            sil! exe a:mode.'unmap <buffer> '.l:key

            " save info about the global one
            let mappings[l:key] = maparg(l:key, a:mode, 0, 1)

            " restore the local one
            call s:restore_mappings({l:key : buf_local_map})
        endfor

    " TRY to return info local mappings.
    " If they exist it will work, otherwise it will return info about global
    " mappings.
    else
        for l:key in a:keys
            let mappings[l:key] = maparg(l:key, a:mode, 0, 1)
        endfor
    endif

    return mappings
endfu


"}}}
" set_char_at "{{{

fu! s:set_char_at(char, x, y) abort
    " move on line whose address is `y`
    exe a:y

    " move cursor on column `x` and replace the character under the cursor
    " with `char`
    if a:x <= 1
        exe 'norm! 0r'.a:char
    else
        exe 'norm! 0'.(a:x-1).'lr'.a:char
    endif
endfu

"}}}
" shift_arrow "{{{

fu! s:shift_arrow(motion) abort
    if a:motion ==# 'j' && line('.') == line('$')
        call append('.', '')
    elseif a:motion ==# 'k' && line('.') == 1
        call append(0, '')
    endif

    call feedkeys(a:motion, 'in')
endfu

"}}}
" stop "{{{

fu! draw_it#stop() abort
    let s:state = 'disabled'
    call s:remove_mappings()
    let &ve  = get(s:, 've_save', &ve)
    let &ww  = get(s:, 'ww_save', &ww)
    let &sol = get(s:, 'sol_save', &sol)
    echom '[Drawing/Erasing] disabled'
endfu

"}}}
" toggle_mappings"{{{

fu! s:toggle_mappings() abort
    if s:state ==# 'disabled'
        call draw_it#stop()

    else
        call s:install_mappings()
        set ve=all

        " We disable `'startofline'`, otherwise we get unintended results when
        " trying to draw a box, hitting `mdb` from visual mode.
        set nostartofline

        " We remove the `h` value from `'whichwrap'`, otherwise we get
        " unintended results when drawing and reaching column 0.
        set whichwrap-=h

        echom '['.substitute(s:state, '.', '\u&', '').'] '.'enabled'
    endif
endfu

"}}}
