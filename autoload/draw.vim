" TODO:
"
" - allow moving visual selection beyond first/last line

" guard {{{1

if exists('g:auto_loaded_draw')
    finish
endif
let g:auto_loaded_draw = 1

" data {{{1

" We initialize the state of the plugin to 'disabled'.
" But only if it hasn't already been initialized.
" Why?
" Because if we edit the code, while the drawing mappings are installed, and
" source it, then the next time we will toggle the state of the plugin with
" `m_`, `m<space>`, `draw_it#change_state()` will save the drawing mappings in
" `s:original_mappings_{normal|visual}`. From then, we won't be able to remove
" the mappings with `m|`, because the plugin will consider them as default.
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

fu! s:above_first_line(key) abort "{{{1
    return index(['<Up>', '<PageUp>', '<Home>', '^'], a:key) != -1
            \ && s:state ==# 'drawing' && line('.') == 1
endfu

fu! s:beyond_last_line(key) abort "{{{1
    return index(['<Down>', '<PageDown>', '<End>', 'v'], a:key) != -1
            \ && s:state ==# 'drawing' && line('.') == line('$')
endfu

fu! s:arrow(...) abort "{{{1

    " We initialize the coordinates of the beginning and end of the arrow,
    " as well as its tip.
    if a:0
    " We're cycling.

        let [x0, y0, x1, y1, xb, yb] = a:1
        let tip = a:2
    else
    " We're creating a first arrow.

        " normalize in case we hit `O`???
        " I don't think it would be a good idea to normalize.
        " Why?
        " normalization would prevent us from having the choice between
        " 2 different arrows depending on whether we switched the visual marks
        " hitting `O`.

        let [x0, y0] = [virtcol("'<"), line("'<")]
        let [x1, y1] = [virtcol("'>"), line("'>")]

        " if the height is too big, the first segment of the arrow can't be
        " oblique (it would go too far), it must be vertical
        let [height, width] = [abs(y1 - y0), abs(x1 - x0)]
        let xb              = height > width ? x0 : x0 + (x0 < x1 ? height : -height)
        let yb              = y1

        let tip = x0 < x1 ? '>' : '<'
    endif

    if x0 == x1 || y0 == y1
    " vertical/horizontal arrow
        call s:segment([x0, y0, x1, y1])
        call s:set_char_at(x0 == x1 ? 'v' : '>', x1 , y1)

    else
        " diagonal arrow

        " draw 1st segment of the arrow
        call s:segment([x0, y0, xb, yb])

        " draw 2nd segment of the arrow
        call s:segment([xb, yb, x1, y1])

        " draw a `+` character where the 2 segments of the arrow break at
        call s:set_char_at('+', xb, yb)

        " draw the tip of the arrow
        " This line must be adapted so that `s:arrow()` can draw the tip of any
        " arrow. It should be able to deduce it from the segments.
        " If it can't, pass the tip as an argument when `s:arrow()` is called by
        " `s:arrow_cycle()`.
        call s:set_char_at(tip, x1, y1)
    endif

    call s:restore_selection(x0, y0, x1, y1)

    " trim ending whitespace
    '<,'>TW
endfu

fu! s:arrow_cycle(back) abort "{{{1
    " Why `min()`, `max()`?
    "
    " We could have hit `O` in visual mode, which would have switch the
    " position of the marks.
    "
    "     '<    upper-left    →    upper-right corner
    "     '>    lower-right   →    lower-left  "
    "
    " We need to normalize the x0, y0, x1, y1 coordinates.
    " Indeed, we'll use them inside a dictionary (`s:state2coords`) to deduce
    " the coordinates of 3 points necessary to erase the current arrow and draw the next one.
    " The dictionary was written expecting (x0, y0) to be the coordinates of
    " the upper-left corner, while (x1, y1) are the coordinates of the
    " bottom-right corner.

    let [x0, y0] = [min([virtcol("'<"), virtcol("'>")]), min([line("'<"), line("'>")])]
    let [x1, y1] = [max([virtcol("'<"), virtcol("'>")]), max([line("'<"), line("'>")])]

    " A B
    " D C
    let corners = {
                  \ 'A' : matchstr(getline("'<"), '\v%'.x0.'v.'),
                  \ 'B' : matchstr(getline("'<"), '\v%'.x1.'v.'),
                  \ 'C' : matchstr(getline("'>"), '\v%'.x1.'v.'),
                  \ 'D' : matchstr(getline("'>"), '\v%'.x0.'v.'),
                  \ }

    let cur_arrow = filter(corners, 'v:val =~ ''[<>v^]''')
    if empty(cur_arrow)
        return
    endif

    if y0 ==# y1
    " horizontal arrow
        exe 'norm! '.(values(cur_arrow)[0] ==# '<' ? x1.'|r>'.x0 : x0.'|r<'.x1).'|r_'
        return

    elseif x0 ==# x1
    " vertical arrow
        exe 'norm! '.(values(cur_arrow)[0] ==# 'v' ? y0.'Gr^'.y1 : y1.'Grv'.y0).'Gr|'
        return

    else
    " diagonal arrow

        " Ex: B>, Cv, A^, …
        let cur_state = keys(cur_arrow)[0].values(cur_arrow)[0]
        let states    = ['A<', 'A^', 'B^', 'B>', 'C>', 'Cv', 'Dv', 'D<']
        let new_state = states[(index(states, cur_state) + (a:back ? -1 : 1)) % len(states)]
        let tip       = new_state[1]

        let [height, width] = [abs(y1 - y0), x1 - x0]
        let offset          = height > width ? 0 : height

        let state2coords = {
                           \ 'A<' : { 'beg' : [x1, y1], 'end' : [x0, y0], 'break' : [x1 - offset, y0]},
                           \ 'A^' : { 'beg' : [x1, y1], 'end' : [x0, y0], 'break' : [x0 + offset, y1]},
                           \ 'B^' : { 'beg' : [x0, y1], 'end' : [x1, y0], 'break' : [x1 - offset, y1]},
                           \ 'B>' : { 'beg' : [x0, y1], 'end' : [x1, y0], 'break' : [x0 + offset, y0]},
                           \ 'C>' : { 'beg' : [x0, y0], 'end' : [x1, y1], 'break' : [x0 + offset, y1]},
                           \ 'Cv' : { 'beg' : [x0, y0], 'end' : [x1, y1], 'break' : [x1 - offset, y0]},
                           \ 'Dv' : { 'beg' : [x1, y0], 'end' : [x0, y1], 'break' : [x0 + offset, y0]},
                           \ 'D<' : { 'beg' : [x1, y0], 'end' : [x0, y1], 'break' : [x1 - offset, y1]},
                           \ }

        " we erase the current arrow
        let point1 = state2coords[cur_state]['beg']
        let point2 = state2coords[cur_state]['end']
        let point3 = state2coords[cur_state]['break']
        call s:segment(extend(copy(point1), point3), 1)
        call s:segment(extend(copy(point3), point2), 1)

        " we draw a new one
        let point1 = state2coords[new_state]['beg']
        let point2 = state2coords[new_state]['end']
        let point3 = state2coords[new_state]['break']
        call s:arrow(extend(extend(copy(point1), point2), point3), tip)
    endif
endfu

fu! s:box() abort "{{{1
    let [x0, x1] = [virtcol("'<"), virtcol("'>")]
    let [y0, y1] = [line("'<"),    line("'>")]

    " draw the horizontal sides of the box
    exe 'norm! '.y0.'G'.(x0+1).'|v'.(x1-1).'|r_'
    exe 'norm! '.y1.'G'.x0.'|v'.x1.'|r_'

    " draw the vertical sides of the box
    exe 'norm! '.(y0+1).'G'.x0."|\<C-v>".y1.'Gr|'
    exe 'norm! '.y1.'G'.x1."|\<C-v>".(y0+1).'Gr|'

    call s:restore_selection(x0, y0, x1, y1)
endfu

fu! draw#change_state(erasing_mode) abort "{{{1

    if s:state ==# 'disabled'
        let s:ve_save  = &ve
        let s:ww_save  = &ww
        let s:sol_save = &sol

        let s:original_mappings_normal = s:mappings_save([
                                       \                   'm?',
                                       \                   '<Left>',
                                       \                   '<Right>',
                                       \                   '<Down>',
                                       \                   '<Up>',
                                       \                   '<S-Left>',
                                       \                   '<S-Right>',
                                       \                   '<S-Down>',
                                       \                   '<S-Up>',
                                       \                   '<PageDown>',
                                       \                   '<PageUp>',
                                       \                   '<End>',
                                       \                   '<Home>',
                                       \                   '<',
                                       \                   '>',
                                       \                   'v',
                                       \                   '^',
                                       \                   'H',
                                       \                   'J',
                                       \                   'K',
                                       \                   'L',
                                       \                   'j',
                                       \                   'k',
                                       \                  ],
                                       \                     'n',
                                       \                          1)

        let s:original_mappings_visual = s:mappings_save([
                                       \                   'j',
                                       \                   'k',
                                       \                   'ma',
                                       \                   'mb',
                                       \                   'me',
                                       \                   'mm',
                                       \                   'mM',
                                       \                 ],
                                       \                    'x',
                                       \                         1)

        " The last argument passed to `s:mappings_save()` is 1. {{{
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

    call s:mappings_toggle()
endfu

fu! s:draw(key) abort "{{{1

    if s:beyond_last_line(a:key)
        call append('.', '')
    elseif s:above_first_line(a:key)
        call append(0, '')
    endif

    if index([
             \ '<Left>',
             \ '<Right>',
             \ '<Down>',
             \ '<Up>',
             \ '<PageDown>',
             \ '<PageUp>',
             \ '<End>',
             \ '<Home>'
             \ ],
             \     a:key) != -1

        call s:replace_char(a:key)
        exe 'norm! '.s:key2motion[a:key]
        call s:replace_char(a:key)

    elseif index(['^', 'v', '<', '>'], a:key) != -1
        exe 'norm! r'.s:key2char[a:key].s:key2motion[a:key].'r'.s:key2char[a:key]
    endif
endfu

fu! s:ellipse() abort "{{{1
    let [x0, x1] = [virtcol("'<"), virtcol("'>")]
    let [y0, y1] = [line("'<"),    line("'>")]

    let xoff  = (x0+x1)/2
    let yoff  = (y0+y1)/2
    let a     = abs(x1-x0)/2
    let b     = abs(y1-y0)/2

    let xi = 0
    let yi = b
    let ei = 0
    call s:four(xi,yi,xoff,yoff,a,b)
    while xi <= a && yi >= 0

        let dy = a*a - 2*a*a*yi
        let ca = ei + 2*b*b*xi + b*b
        let cb = ca + dy
        let cc = ei + dy

        let aca = abs(ca)
        let acb = abs(cb)
        let acc = abs(cc)

        " pick case: (xi+1,yi) (xi,yi-1) (xi+1,yi-1)
        if aca <= acb && aca <= acc
            let xi += 1
            let ei  = ca
        elseif acb <= aca && acb <= acc
            let ei  = cb
            let xi += 1
            let yi -= 1
        else
            let ei  = cc
            let yi -= 1
        endif
        if xi > x1
            break
        endif
        call s:four(xi, yi, xoff, yoff, a, b)
    endwhile

    call s:restore_selection(x0, y0, x1, y1)
endfu

fu! s:four(x, y, xoff, yoff, a, b) abort "{{{1
    let x  = a:xoff + a:x
    let y  = a:yoff + a:y
    let lx = a:xoff - a:x
    let by = a:yoff - a:y

    call s:set_char_at('*',  x, y)
    call s:set_char_at('*', lx, y)
    call s:set_char_at('*', lx, by)
    call s:set_char_at('*',  x, by)
endfu

fu! s:mappings_install() abort "{{{1
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
                          \.' :<C-U>call <SID>draw('.string('<lt>'.l:key[1:]).')<CR>'
    endfor

    for l:key in [
                 \ '<',
                 \ '>',
                 \ 'v',
                 \ '^',
                 \ ]
        exe 'nno '.args.' '.l:key
                    \.' :<C-U>call <SID>draw('.string(l:key).')<CR>'
    endfor

    for l:key in [
                 \ '<S-Left>',
                 \ '<S-Right>',
                 \ '<S-Down>',
                 \ '<S-Up>',
                 \ ]
        exe 'nno '.args.' '.l:key
                         \ .' :<C-U>call <SID>unbounded_vertical_motion('
                         \ .string(s:key2motion[l:key])
                         \ .')<CR>'
    endfor

    for l:key in [
                 \ 'H',
                 \ 'L',
                 \ ]
        exe 'nno '.args.' '.l:key.' 3'.tolower(l:key)
    endfor

    for l:key in [
                 \ 'j',
                 \ 'k',
                 \ 'J',
                 \ 'K',
                 \ ]
        exe 'nno '.args.' '.l:key.' :<C-U>call <SID>unbounded_vertical_motion('.string(tolower(l:key)).')<CR>'
    endfor

    xno <nowait> <silent> ma    :<C-U>call <SID>arrow()<CR>
    xno <nowait> <silent> mb    :<C-U>call <SID>box()<CR>
    xno <nowait> <silent> me    :<C-U>call <SID>ellipse()<CR>
    xno <nowait> <silent> mm    :<C-U>call <SID>arrow_cycle(0)<CR>
    xno <nowait> <silent> mM    :<C-U>call <SID>arrow_cycle(1)<CR>

    nno <nowait> <silent> m?    :<C-U>call draw_it#stop() <bar> h my-draw-it<CR>
endfu

" mappings_restore {{{1

" Warning:
" Don't try to restore a buffer local mapping unless you're sure that, when
" `s:mappings_restore()` is called, you're in the same buffer where
" `s:mappings_save()` was originally called.
"
" If you aren't in the same buffer, you could install a buffer-local mapping
" inside a buffer where this mapping didn't exist before.
" It could cause unexpected behavior on the user's system.
"
" Usage:
"
"     call s:mappings_restore(my_saved_mappings)
"
" `my_saved_mappings` is a dictionary obtained earlier by calling
" `s:mappings_save()`.
" Its keys are the keys used in the mappings.
" Its values are the info about those mappings stored in sub-dictionaries.
"
" There's nothing special to pass to `s:mappings_restore()`, no other
" argument, no wrapping inside a 3rd dictionary, or anything. Just this dictionary.

fu! s:mappings_restore(mappings) abort

    for mapping in values(a:mappings)
        if !has_key(mapping, 'unmapped') && !empty(mapping)
            exe     mapping.mode
               \ . (mapping.noremap ? 'noremap   ' : 'map ')
               \ . (mapping.buffer  ? ' <buffer> ' : '')
               \ . (mapping.expr    ? ' <expr>   ' : '')
               \ . (mapping.nowait  ? ' <nowait> ' : '')
               \ . (mapping.silent  ? ' <silent> ' : '')
               \ .  mapping.lhs
               \ . ' '
               \ . substitute(mapping.rhs, '<SID>', '<SNR>'.mapping.sid.'_', 'g')

        elseif has_key(mapping, 'unmapped')
            sil! exe mapping.mode.'unmap '
                                \ .(mapping.buffer ? ' <buffer> ' : '')
                                \ . mapping.lhs
        endif
    endfor

endfu

" mappings_save {{{1

" Usage:
"
"     let my_global_mappings = s:mappings_save(['key1', 'key2', …], 'n', 1)
"     let my_local_mappings  = s:mappings_save(['key1', 'key2', …], 'n', 0)
"

" Output example: {{{
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

fu! s:mappings_save(keys, mode, global) abort
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
            let map_info        = maparg(l:key, a:mode, 0, 1)
            let mappings[l:key] = !empty(map_info)
                               \?     map_info
                               \:     {
                               \       'unmapped' : 1,
                               \       'buffer'   : 0,
                               \       'lhs'      : l:key,
                               \       'mode'     : a:mode,
                               \      }

            " If there's no mapping, why do we still save this dictionary: {{{

            "     {
            "     \ 'unmapped' : 1,
            "     \ 'buffer'   : 0,
            "     \ 'lhs'      : l:key,
            "     \ 'mode'     : a:mode,
            "     \ }

            " …?
            " Suppose we have a key which is mapped to nothing.
            " We save it (with an empty dictionary).
            " It's possible that after the saving, the key is mapped to something.
            " Restoring this key means deleting whatever mapping may now exist.
            " But to be able to unmap the key, we need 3 information:
            "
            "     - is the mapping global or buffer-local (<buffer> argument)?
            "     - the lhs
            "     - the mode (normal, visual, …)
            "
            " The `'unmapped'` key is not necessary. I just find it can make
            " the code a little more readable inside `s:mappings_restore()`.
            " Indeed, one can write:

            "     if has_key(mapping, 'unmapped') && !empty(mapping)
            "         …
            "     endif
            "
"}}}

            " restore the local one
            call s:mappings_restore({l:key : buf_local_map})
        endfor

    " TRY to return info local mappings.
    " If they exist it will work, otherwise it will return info about global
    " mappings.
    else
        for l:key in a:keys
            let map_info        = maparg(l:key, a:mode, 0, 1)
            let mappings[l:key] = !empty(map_info)
                               \?     map_info
                               \:     {
                               \        'unmapped' : 1,
                               \        'buffer'   : 1,
                               \        'lhs'      : l:key,
                               \        'mode'     : a:mode,
                               \      }
        endfor
    endif

    return mappings
endfu

fu! s:mappings_toggle() abort "{{{1
    if s:state ==# 'disabled'
        call draw#stop()

    else
        call s:mappings_install()
        set ve=all

        " We disable `'startofline'`, otherwise we get unintended results when
        " trying to draw a box, hitting `mb` from visual mode.
        set nostartofline

        " We remove the `h` value from `'whichwrap'`, otherwise we get
        " unintended results when drawing and reaching column 0.
        set whichwrap-=h

        echom '['.substitute(s:state, '.', '\u&', '').'] '.'enabled'
    endif
endfu

fu! s:replace_char(key) abort "{{{1

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
               \?      ' '
               \:  cchar =~# s:crossing_keys[a:key] && cchar !=# s:key2char[a:key]
               \?      s:intersection[a:key]
               \:      s:key2char[a:key]
               \  )
endfu

fu! s:restore_selection(x0, y0, x1, y1) abort "{{{1
    call setpos("'>", [0, a:y0, a:x0, 0])
    call setpos("'<", [0, a:y1, a:x1, 0])
    norm! gv
endfu

fu! s:segment(coords, ...) abort "{{{1
" if we pass an optional argument to the function, it will draw spaces,
" thus erasing a segment instead of drawing it

    let [x0, y0, x1, y1] = a:coords

    " reorder the coordinates to make sure the first ones describe the point
    " on the left, and the last ones the point on the right
    let [point1, point2] = sort([[x0, y0], [x1, y1]], {a, b -> a[0] - b[0]})
    let [x0, y0, x1, y1] = point1 + point2

    let rchar = a:0
             \?     ' '
             \: x0 == x1
             \?     '|'
             \: y0 == y1
             \?     '_'
             \: y0 > y1
             \?     '/'
             \:     '\'

    if x0 ==# x1
        exe 'norm! '.y0.'G'.x0."|\<C-v>".y1.'Gr'.rchar

    elseif y0 ==# y1
        exe 'norm! '.y0.'G'.x0."|\<C-v>".x1.'|r'.rchar

    else
        for i in range(x0, x0 + abs(y1 - y0))
            " if y0 > y1, we must decrement the line address, otherwise
            " increment
            call s:set_char_at(rchar, i, y0 + (y0 > y1 ? (x0 - i) : (i - x0)))
        endfor
    endif
endfu

fu! s:set_char_at(char, x, y) abort "{{{1
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

fu! draw#stop() abort "{{{1
    let s:state = 'disabled'

    if exists('s:original_mappings_normal')
        call s:mappings_restore(s:original_mappings_normal)
    endif
    if exists('s:original_mappings_visual')
        call s:mappings_restore(s:original_mappings_visual)
    endif

    let &ve  = get(s:, 've_save', &ve)
    let &ww  = get(s:, 'ww_save', &ww)
    let &sol = get(s:, 'sol_save', &sol)
    echom '[Drawing/Erasing] disabled'
endfu

fu! s:unbounded_vertical_motion(motion) abort "{{{1
    if a:motion ==# 'j' && line('.') == line('$')
        call append('.', repeat(' ', virtcol('.')))

    elseif a:motion ==# 'k' && line('.') == 1
        call append(0, repeat(' ', virtcol('.')))
    endif

    exe 'norm! '.a:motion
endfu
