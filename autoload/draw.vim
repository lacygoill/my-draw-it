vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# TODO: allow moving visual selection beyond first/last line

# Init {{{1

import {
    MapSave,
    MapRestore,
} from 'lg/map.vim'

# We initialize the state of the plugin to 'disabled'.
# But only if it hasn't already been initialized.
# Why?
# Because if  we edit the  code, while the  drawing mappings are  installed, and
# source it,  then the next  time we  will toggle the  state of the  plugin with
# `m_`,  `m<Space>`,  `draw#changeState()` will  save  the  drawing mappings  in
# `original_mappings_{normal|visual}`.  From  then, we  won't be able  to remove
# the mappings with `m|`, because the plugin will consider them as default.
#
# This issue is not limited to this particular case.
# It's a fundamental issue.
# When a plugin relies on some information which is initialized before its
# execution, and this information can change, we must make sure it's always
# correct.
# We must *not lie* to the plugin.  Feeding it with wrong info will ALWAYS cause
# unexpected behavior.  Remember,  we faced the same issue when  we were working
# on mucomplete, with the `auto` flag.
#
# So, here, we use `get()` to make sure we don't accidentally alter the info
# after it has been initialized.
#
# Another way of putting it: only initialize a variable ONCE.
# Sourcing a file, again and again, should NOT RE-initialize a variable.

var state: string = 'disabled'

const KEY2CHAR: dict<string> = {
    '<Left>': '-',
    '<Right>': '-',
    '<Down>': '|',
    '<Up>': '|',
    '<PageDown>': '\',
    '<PageUp>': '/',
    '<Home>': '\',
    '<End>': '/',
    '<': '<',
    '>': '>',
    'v': 'v',
    '^': '^',
}

const KEY2MOTION: dict<string> = {
    '<Left>': 'h',
    '<Right>': 'l',
    '<Down>': 'j',
    '<Up>': 'k',
    '<PageDown>': 'lj',
    '<PageUp>': 'lk',
    '<End>': 'hj',
    '<Home>': 'hk',
    '<': 'h',
    '>': 'l',
    'v': 'j',
    '^': 'k',
    '<S-Left>': 'h',
    '<S-Right>': 'l',
    '<S-Down>': 'j',
    '<S-Up>': 'k',
}

const CROSSING_KEYS: dict<string> = {
    '<Left>': '[-|+]',
    '<Right>': '[-|+]',
    '<Down>': '[-|+]',
    '<Up>': '[-|+]',
    '<PageDown>': '[\/X]',
    '<PageUp>': '[\/X]',
    '<End>': '[\/X]',
    '<Home>': '[\/X]',
}

const INTERSECTION: dict<string> = {
    '<Left>': '+',
    '<Right>': '+',
    '<Down>': '+',
    '<Up>': '+',
    '<PageDown>': 'X',
    '<PageUp>': 'X',
    '<End>': 'X',
    '<Home>': 'X',
}

# Interface {{{1
def draw#boxPrettify(line1: number, line2: number) #{{{2
    var range: string = ':' .. line1 .. ',' .. line2
    execute 'silent ' .. range .. 'substitute/\%(-\@1<=-\|-\ze-\)\l\@!/─/ge'
    #                                                            ^---^
    #                                                            ignore names of optional arguments:
    #                                                                --some-optional-argument
    #                                                            (frequently found in linux utilities)

    RepBar = (): string => GetCharsAround('below') =~ '[+|]' ? '│' : '|'
    execute 'silent ' .. range .. 'substitute/|/\=RepBar()/ge'

    RepPlus = (): string =>
        GetCharsAround('before') =~ '─'
     && GetCharsAround('after') == '─'
     && GetCharsAround('above') == '│'
     && GetCharsAround('below') == '│'
        ?    '┼'

   :    GetCharsAround('before') =~ '─'
     && GetCharsAround('after') == '─'
     && GetCharsAround('below') == '│'
        ?    '┬'

   :    GetCharsAround('before') =~ '─'
     && GetCharsAround('after') == '─'
     && GetCharsAround('above') == '│'
        ?    '┴'

   :    GetCharsAround('above') =~ '│'
     && GetCharsAround('below') == '│'
     && GetCharsAround('after') == '─'
        ?    '├'

   :    GetCharsAround('above') =~ '│'
     && GetCharsAround('below') == '│'
     && GetCharsAround('before') == '─'
        ?    '┤'

   :    GetCharsAround('below') =~ '│'
     && GetCharsAround('after') == '─'
        ?    '┌'

   :    GetCharsAround('below') =~ '│'
     && GetCharsAround('before') == '─'
        ?    '┐'

   :    GetCharsAround('above') =~ '│'
     && GetCharsAround('after') == '─'
        ?    '└'

   :    GetCharsAround('above') =~ '│'
     && GetCharsAround('before') == '─'
        ?    '┘'
   :         '+'

    execute 'silent ' .. range .. 'substitute/+/\=RepPlus()/ge'
enddef

var RepBar: func
var RepPlus: func

def draw#changeState(erasing_mode: bool) #{{{2
    if state == 'disabled'
        virtualedit_save = &virtualedit
        whichwrap_save = &whichwrap
        startofline_save = &startofline

        original_mappings_normal = MapSave([
            'm?',
            '<Left>',
            '<Right>',
            '<Down>',
            '<Up>',
            '<S-Left>',
            '<S-Right>',
            '<S-Down>',
            '<S-Up>',
            '<PageDown>',
            '<PageUp>',
            '<End>',
            '<Home>',
            '<',
            '>',
            'v',
            '^',
            'H',
            'J',
            'K',
            'L',
            'j',
            'k',
            ], 'n')

        original_mappings_visual = MapSave([
            'j',
            'k',
            'ma',
            'mb',
            'me',
            'mm',
            'mM',
            ], 'x')

        # What if we have buffer-local mappings?  Will they be saved & restored? {{{
        #
        # No.  We only save global mappings.
        #
        # If the user  mapped these keys locally, our global  mappings will work
        # everywhere  except  in  the  current buffer  and  buffers  where  they
        # installed similar buffer-local mappings.
        #
        # It would be difficult to restore buffer-local mappings; we would need to:
        #
        #    - remove the buffer-local mappings from the user in every buffer where they exist
        #
        #    - parse all this info – once the user stops drawing – to focus various buffers
        #      and restore the mappings in them
        #
        #    - restore the original layout (because focusing various buffers may have changed it)
        #
        # Right now, I prefer to not bother.
        #
        # In the future, if that bothers you, as a partial workaround, you could
        # simply remove the local mappings in the current buffer.
        # It would make sure you can at least draw in the latter.
        # Once you're finished, you could try to restore the original local mappings.
        #}}}
    endif

    state = {
        disabled: erasing_mode ? 'erasing' : 'drawing',
        drawing: erasing_mode ? 'erasing' : 'disabled',
        erasing: erasing_mode ? 'disabled' : 'drawing',
        }[state]

    MappingsToggle()
enddef
var virtualedit_save: string
var whichwrap_save: string
var startofline_save: bool
var original_mappings_visual: list<dict<any>>

var original_mappings_normal: list<dict<any>>

def draw#stop() #{{{2
    state = 'disabled'

    if original_mappings_normal != []
        MapRestore(original_mappings_normal)
    endif
    if original_mappings_visual != []
        MapRestore(original_mappings_visual)
    endif

    &virtualedit = virtualedit_save
    &whichwrap = whichwrap_save
    &startofline = startofline_save
    echomsg '[Drawing/Erasing] disabled'
enddef
#}}}1
# Core {{{1
def AboveFirstLine(key: string): bool #{{{2
    return index(['<Up>', '<PageUp>', '<Home>', '^'], key) >= 0
        && state == 'drawing' && line('.') == 1
enddef

def BeyondLastLine(key: string): bool #{{{2
    return index(['<Down>', '<PageDown>', '<End>', 'v'], key) >= 0
        && state == 'drawing' && line('.') == line('$')
enddef

def Arrow(coords: list<number> = [], arg_tip = '') #{{{2
    # We initialize the coordinates of the beginning and end of the arrow,
    # as well as its tip.
    var tip: string
    var x0: number
    var y0: number
    var x1: number
    var y1: number
    var xb: number
    var yb: number
    if arg_tip != ''
    # We're cycling.
        [x0, y0, x1, y1, xb, yb] = coords
        tip = arg_tip
    else
    # We're creating a first arrow.

        # normalize in case we hit `O`???
        # I don't think it would be a good idea to normalize.
        # Why?
        # normalization would prevent us from having the choice between
        # 2 different arrows depending on whether we switched the visual marks
        # hitting `O`.

        x0 = virtcol("'<")
        y0 = line("'<")
        x1 = virtcol("'>")
        y1 = line("'>")

        # if the height is too big, the first segment of the arrow can't be
        # oblique (it would go too far), it must be vertical
        var height: number = abs(y1 - y0)
        var width: number = abs(x1 - x0)
        xb = height > width ? x0 : x0 + (x0 < x1 ? height : -height)
        yb = y1

        tip = x0 < x1 ? '>' : '<'
    endif

    var visual_marks_pos = [getpos("'<"), getpos("'>")]

    if x0 == x1 || y0 == y1
    # vertical/horizontal arrow
        Segment([x0, y0, x1, y1])
        SetCharAt(x0 == x1 ? 'v' : '>', x1, y1)

    else
        # diagonal arrow

        # draw 1st segment of the arrow
        Segment([x0, y0, xb, yb])

        # draw 2nd segment of the arrow
        Segment([xb, yb, x1, y1])

        # draw a `+` character where the 2 segments of the arrow break at
        SetCharAt('+', xb, yb)

        # draw the tip of the arrow
        # This line must  be adapted so that  `Arrow()` can draw the  tip of any
        # arrow.  It should be able to deduce it from the segments.
        # If it can't, pass  the tip as an argument when  `Arrow()` is called by
        # `ArrowCycle()`.
        SetCharAt(tip, x1, y1)
    endif

    RestoreSelection(visual_marks_pos)

    # trim ending whitespace
    if exists(':TW') == 2
        :* TW
    endif
enddef

def ArrowCycle(is_fwd: bool) #{{{2
    # Why `min()`, `max()`?
    #
    # We could have hit `O` in visual mode, which would have switch the
    # position of the marks.
    #
    #     '<    upper-left    →    upper-right corner
    #     '>    lower-right   →    lower-left  "
    #
    # We need to normalize the x0, y0, x1, y1 coordinates.
    # Indeed, we'll use them inside a dictionary (`state2coords`) to deduce
    # the coordinates of 3 points necessary to erase the current arrow and draw the next one.
    # The dictionary was written expecting (x0, y0) to be the coordinates of
    # the upper-left corner, while (x1, y1) are the coordinates of the
    # bottom-right corner.

    var x0: number = min([VirtcolFirstCell("'<"), VirtcolFirstCell("'>")])
    var x1: number = max([VirtcolFirstCell("'<"), VirtcolFirstCell("'>")])
    var y0: number = min([line("'<"), line("'>")])
    var y1: number = max([line("'<"), line("'>")])

    # A B
    # D C
    var corners: dict<string> = {
        A: getline("'<")->matchstr('\%' .. x0 .. 'v.'),
        B: getline("'<")->matchstr('\%' .. x1 .. 'v.'),
        C: getline("'>")->matchstr('\%' .. x1 .. 'v.'),
        D: getline("'>")->matchstr('\%' .. x0 .. 'v.'),
    }

    var cur_arrow: dict<string> = corners
        ->filter((_, v: string): bool => v =~ '[<>v^]')
    if empty(cur_arrow)
        return
    endif

    if y0 == y1
    # horizontal arrow
        execute 'normal! ' .. (values(cur_arrow)[0] == '<'
            ? x1 .. '|r>' .. x0
            : x0 .. '|r<' .. x1
            ) .. '|r_'
        return

    elseif x0 == x1
    # vertical arrow
        execute 'normal! ' .. (values(cur_arrow)[0] == 'v'
            ? y0 .. 'Gr^' .. y1
            : y1 .. 'Grv' .. y0
            ) .. 'Gr|'
        return

    else
    # diagonal arrow

        # Ex: B>, Cv, A^, ...
        var cur_state: string = keys(cur_arrow)[0] .. values(cur_arrow)[0]
        var states: list<string> =<< trim END
            A<
            A^
            B^
            B>
            C>
            Cv
            Dv
            D<
        END
        var new_state: string = states[
            (index(states, cur_state) + (is_fwd ? 1 : -1)) % len(states)
        ]
        var tip: string = new_state[1]

        var height: number = abs(y1 - y0)
        var width: number = x1 - x0
        var offset: number = height > width ? 0 : height

        var state2coords: dict<dict<list<number>>> = {
            'A<': {beg: [x1, y1], end: [x0, y0], break: [x1 - offset, y0]},
            'A^': {beg: [x1, y1], end: [x0, y0], break: [x0 + offset, y1]},
            'B^': {beg: [x0, y1], end: [x1, y0], break: [x1 - offset, y1]},
            'B>': {beg: [x0, y1], end: [x1, y0], break: [x0 + offset, y0]},
            'C>': {beg: [x0, y0], end: [x1, y1], break: [x0 + offset, y1]},
            'Cv': {beg: [x0, y0], end: [x1, y1], break: [x1 - offset, y0]},
            'Dv': {beg: [x1, y0], end: [x0, y1], break: [x0 + offset, y0]},
            'D<': {beg: [x1, y0], end: [x0, y1], break: [x1 - offset, y1]},
        }

        # we erase the current arrow
        var point1: list<number> = state2coords[cur_state]['beg']
        var point2: list<number> = state2coords[cur_state]['end']
        var point3: list<number> = state2coords[cur_state]['break']
        copy(point1)->extend(point3)->Segment(true)
        copy(point3)->extend(point2)->Segment(true)

        # we draw a new one
        point1 = state2coords[new_state]['beg']
        point2 = state2coords[new_state]['end']
        point3 = state2coords[new_state]['break']
        copy(point1)->extend(point2)->extend(point3)->Arrow(tip)
    endif
enddef

def Box() #{{{2
    var x0: number = virtcol("'<")
    var x1: number = virtcol("'>")
    var y0: number = line("'<")
    var y1: number = line("'>")

    var visual_marks_pos = [getpos("'<"), getpos("'>")]

    # draw the horizontal sides of the box
    execute 'normal! ' .. y0 .. 'G' .. x0 .. '|v' .. x1 .. '|r-'
    execute 'normal! ' .. y1 .. 'G' .. x0 .. '|v' .. x1 .. '|r-'

    # draw the vertical sides of the box
    execute 'normal! ' .. y0 .. 'G' .. x0 .. "|\<C-v>" .. y1 .. 'Gr|'
    execute 'normal! ' .. y1 .. 'G' .. x1 .. "|\<C-v>" .. y0 .. 'Gr|'

    # draw the corners of the box
    SetCharAt('+', x0, y0)
    SetCharAt('+', x0, y1)
    SetCharAt('+', x1, y0)
    SetCharAt('+', x1, y1)

    RestoreSelection(visual_marks_pos)
enddef

def Draw(key: string) #{{{2
    if BeyondLastLine(key)
        ''->append('.')
    elseif AboveFirstLine(key)
        ''->append(0)
    endif

    var keys: list<string> =<< trim END
        <Left>
        <Right>
        <Down>
        <Up>
        <PageDown>
        <PageUp>
        <End>
    END
    if index(keys, key) >= 0
        ReplaceChar(key)
        execute 'normal! ' .. KEY2MOTION[key]
        ReplaceChar(key)

    elseif key =~ "[v^<>]"
        execute 'normal! r' .. KEY2CHAR[key] .. KEY2MOTION[key] .. 'r' .. KEY2CHAR[key]
    endif
enddef

def Ellipse() #{{{2
    var x0: number = virtcol("'<")
    var x1: number = virtcol("'>")
    var y0: number = line("'<")
    var y1: number = line("'>")

    var xoff: number = (x0 + x1) / 2
    var yoff: number = (y0 + y1) / 2
    var a: number = abs(x1 - x0) / 2
    var b: number = abs(y1 - y0) / 2

    var visual_marks_pos = [getpos("'<"), getpos("'>")]

    var xi: number = 0
    var yi: number = b
    var ei: number = 0
    Four(xi, yi, xoff, yoff)
    while xi <= a && yi >= 0

        var dy: number = a * a - 2 * a * a * yi
        var ca: number = ei + 2 * b * b * xi + b * b
        var cb: number = ca + dy
        var cc: number = ei + dy

        var aca: number = abs(ca)
        var acb: number = abs(cb)
        var acc: number = abs(cc)

        # pick case: (xi + 1, yi) (xi, yi - 1) (xi + 1, yi - 1)
        if aca <= acb && aca <= acc
            ++xi
            ei = ca
        elseif acb <= aca && acb <= acc
            ei = cb
            ++xi
            --yi
        else
            ei = cc
            --yi
        endif
        if xi > x1
            break
        endif
        Four(xi, yi, xoff, yoff)
    endwhile

    RestoreSelection(visual_marks_pos)
enddef

def Four( #{{{2
    arg_x: number,
    arg_y: number,
    xoff: number,
    yoff: number
)
    var x: number = xoff + arg_x
    var y: number = yoff + arg_y
    var lx: number = xoff - arg_x
    var by: number = yoff - arg_y

    SetCharAt('*', x, y)
    SetCharAt('*', lx, y)
    SetCharAt('*', lx, by)
    SetCharAt('*', x, by)
enddef

def GetCharsAround(where: string): string #{{{2
    var charcol: number = charcol('.')
    return where == 'before'
        ?     (charcol == 1 ? '' : getline('.')[charcol - 2])
        : where == 'after'
        ?     getline('.')[charcol]
        : where == 'above'
        ?     (line('.') - 1)->getline()->matchstr('\%' .. VirtcolFirstCell('.') .. 'v.')
        # character below
        :     (line('.') + 1)->getline()->matchstr('\%' .. VirtcolFirstCell('.') .. 'v.')
enddef

def MappingsInstall() #{{{2
    var args: string = ' <nowait> '

    for key in [
        '<Left>',
        '<Right>',
        '<Down>',
        '<Up>',
        '<PageDown>',
        '<PageUp>',
        '<Home>',
        '<End>',
    ]

        execute printf('nnoremap %s %s <Cmd>call <SID>Draw(%s)<CR>', args, key, string('<lt>' .. key[1 :]))
    endfor

    for key in [
        '<',
        '>',
        'v',
        '^',
    ]

        execute printf('nnoremap %s %s <Cmd>call <SID>Draw(%s)<CR>', args, key, string(key))
    endfor

    for key in [
        '<S-Left>',
        '<S-Right>',
        '<S-Down>',
        '<S-Up>',
    ]

        execute printf('nnoremap %s %s <Cmd>call <SID>UnboundedVerticalMotion(%s)<CR>',
            args, key, string(KEY2MOTION[key]))
    endfor

    for key in ['H', 'L']
        execute printf('nnoremap %s %s 3%s', args, key, tolower(key))
    endfor

    for key in [
        'j',
        'k',
        'J',
        'K',
    ]
        execute printf('nnoremap %s %s <Cmd>call <SID>UnboundedVerticalMotion(%s)<CR>',
            args, key, tolower(key)->string())
    endfor

    xnoremap <nowait> ma <C-\><C-N><Cmd>call <SID>Arrow()<CR>
    xnoremap <nowait> mb <C-\><C-N><Cmd>call <SID>Box()<CR>
    xnoremap <nowait> me <C-\><C-N><Cmd>call <SID>Ellipse()<CR>
    xnoremap <nowait> mm <C-\><C-N><Cmd>call <SID>ArrowCycle(v:true)<CR>
    xnoremap <nowait> mM <C-\><C-N><Cmd>call <SID>ArrowCycle(v:false)<CR>

    nnoremap <nowait> m? <Cmd>call draw#stop() <Bar> help my-draw-it<CR>
enddef

def MappingsToggle() #{{{2
    if state == 'disabled'
        draw#stop()

    else
        MappingsInstall()
        &virtualedit = 'all'

        # We disable `'startofline'`, otherwise we get unintended results when
        # trying to draw a box, hitting `mb` from visual mode.
        &startofline = false

        # We remove the `h` value from `'whichwrap'`, otherwise we get
        # unintended results when drawing and reaching column 0.
        set whichwrap-=h

        echomsg '[' .. state->substitute('.', '\u&', '') .. '] ' .. 'enabled'
    endif
enddef

def ReplaceChar(key: string) #{{{2
# This function is called before and then after a motion (left, up, ...).
# It must return the character to draw.
#
# When it's called AFTER a motion, and  we're erasing, the character HAS TO be a
# space.   When  it's called  BEFORE  a  motion,  and  we're erasing,  we  COULD
# (should?) return nothing.
#
# Nevertheless, we let the function return a space.
# It doesn't seem to cause an issue.
# This  way, we  don't have  to pass  a 2nd  argument to  know when  it's called
# (before or after a motion).

    var cchar: string = getline('.')[charcol('.') - 1]

    execute 'normal! r'
        .. (state == 'erasing'
           ?    ' '
           : cchar =~ CROSSING_KEYS[key] && cchar != KEY2CHAR[key]
           ?      INTERSECTION[key]
           :      KEY2CHAR[key]
    )
enddef

def RestoreSelection(pos: list<list<number>>) #{{{2
    setpos("'<", pos[0])
    setpos("'>", pos[1])
    normal! gv
enddef

def Segment(coords: list<number>, erase = false) #{{{2
# if we pass an optional argument to the function, it will draw spaces,
# thus erasing a segment instead of drawing it

    var x0: number
    var y0: number
    var x1: number
    var y1: number
    [x0, y0, x1, y1] = coords

    # reorder the coordinates to make sure the first ones describe the point
    # on the left, and the last ones the point on the right
    var point1: list<number>
    var point2: list<number>
    [point1, point2] = [[x0, y0], [x1, y1]]
        ->sort((a: list<number>, b: list<number>): number => a[0] - b[0])
    [x0, y0, x1, y1] = point1 + point2

    var rchar: string = erase
        ?     ' '
        : x0 == x1
        ?     '|'
        : y0 == y1
        ?     '_'
        : y0 > y1
        ?     '/'
        :     '\'

    if x0 == x1
        execute 'normal! ' .. y0 .. 'G' .. x0 .. "|\<C-v>" .. y1 .. 'Gr' .. rchar

    elseif y0 == y1
        execute 'normal! ' .. y0 .. 'G' .. x0 .. "|\<C-v>" .. x1 .. '|r' .. rchar

    else
        for i in range(x0, x0 + abs(y1 - y0))
            # if y0 > y1, we must decrement the line address, otherwise
            # increment
            SetCharAt(rchar, i, y0 + (y0 > y1 ? (x0 - i) : (i - x0)))
        endfor
    endif
enddef

def SetCharAt( #{{{2
    char: string,
    x: number,
    y: number
)
    cursor(y, 1)

    # move cursor on column `x` and replace the character under the cursor
    # with `char`
    if x <= 1
        execute 'normal! 0r' .. char
    else
        execute 'normal! ' .. x .. '|r' .. char
    endif
enddef

def UnboundedVerticalMotion(motion: string) #{{{2
    if motion == 'j' && line('.') == line('$')
        repeat(' ', virtcol('.'))->append('.')

    elseif motion == 'k' && line('.') == 1
        repeat(' ', virtcol('.'))->append(0)
    endif

    execute 'normal! ' .. motion
enddef
#}}}1
# Util {{{1
def VirtcolFirstCell(filepos: string): number #{{{3
    return virtcol([line(filepos), col(filepos) - 1]) + 1
enddef

