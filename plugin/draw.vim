if exists('g:loaded_draw')
    finish
endif
let g:loaded_draw = 1

nno  <silent><unique>  m_        :<c-u>call draw#change_state(0)<cr>
nno  <silent><unique>  m<space>  :<c-u>call draw#change_state(1)<cr>
nno  <silent><unique>  m<bar>    :<c-u>call draw#stop()<cr>

" Usage:
" Visually select a box whose borders are drawn in ascii-art (- + |),
" then execute this command. The borders will now use `│─┌┐└┘`.
com -bar -range=% BoxPrettify call draw#box_prettify(<line1>,<line2>)
