vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

nno <unique> m_ <cmd>call draw#changeState(v:false)<cr>
nno <unique> m<space> <cmd>call draw#changeState(v:true)<cr>
nno <unique> m<bar> <cmd>call draw#stop()<cr>

# Usage:
# Visually select a box whose borders are drawn in ascii-art (- + |),
# then execute this command.  The borders will now use `│─┌┐└┘`.
com -bar -range=% BoxPrettify draw#boxPrettify(<line1>, <line2>)

# TODO: Implement a mapping  to select the current box (i.e.  the one around the
# current cursor position), so that we can move it quickly with `vim-movesel`.

# TODO: Implement a mapping to select a box around the current paragraph.
# It  would be  useful to  write some  text *first*,  then press  `m_` to  enter
# drawing mode, then press our mapping to draw a box around the text.

