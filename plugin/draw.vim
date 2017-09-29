if exists('g:loaded_draw')
    finish
endif
let g:loaded_draw = 1

nno <silent> m_        :<C-U>call draw#change_state(0)<CR>
nno <silent> m<space>  :<C-U>call draw#change_state(1)<CR>
nno <silent> m<Bar>    :<C-U>call draw#stop()<CR>
