vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

nnoremap <unique> m_ <Cmd>call draw#changeState(v:false)<CR>
nnoremap <unique> m<Space> <Cmd>call draw#changeState(v:true)<CR>
nnoremap <unique> m<Bar> <Cmd>call draw#stop()<CR>

# Usage:
# Visually select a box whose borders are drawn in ascii-art (- + |),
# then execute this command.  The borders will now use `│─┌┐└┘`.
command -bar -range=% BoxPrettify draw#boxPrettify(<line1>, <line2>)

# TODO: Implement a mapping  to select the current box (i.e.  the one around the
# current cursor position), so that we can move it quickly with `vim-movesel`.

# TODO: Implement a mapping to select a box around the current paragraph.
# It  would be  useful to  write some  text *first*,  then press  `m_` to  enter
# drawing mode, then press our mapping to draw a box around the text.

