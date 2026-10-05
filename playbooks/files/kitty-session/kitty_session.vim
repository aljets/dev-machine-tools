" Per-window vim session for kitty restore (see kitty_session.yml).
" vim-obsession keeps ~/.vim/sessions/kitty-*.vim current, and the kitty window
" gets a vim_session user var so the fish vim wrapper can `vim -S` it on restore.
" Files are not deleted on exit: when kitty quits, vim can exit like a normal
" quit after kitty already saved a reference to the file. Old ones are pruned.
if empty($KITTY_WINDOW_ID) || exists('g:loaded_kitty_session')
  finish
endif
let g:loaded_kitty_session = 1

let s:dir = expand('~/.vim/sessions')
let s:max_age_days = 7

function! s:SetUserVar(value) abort
  let l:assignment = empty(a:value) ? '' : '=' . base64_encode(str2blob([a:value]))
  call echoraw("\e]1337;SetUserVar=vim_session" . l:assignment . "\x07")
endfunction

function! s:Prune() abort
  let l:cutoff = localtime() - s:max_age_days * 86400
  for l:file in glob(s:dir . '/kitty-*.vim', 0, 1)
    if getftime(l:file) < l:cutoff
      call delete(l:file)
    endif
  endfor
endfunction

function! s:IsGitEditor() abort
  return len(filter(argv(), 'v:val =~# "\\.git/"')) > 0
endfunction

function! s:Start() abort
  if !exists(':Obsess') || &diff || s:IsGitEditor()
    return
  endif
  call mkdir(s:dir, 'p')
  call s:Prune()
  if get(g:, 'this_obsession', '') !~# '^' . s:dir . '/'
    execute 'Obsess' fnameescape(s:dir . '/kitty-' . getpid() . '-' . localtime() . '.vim')
  endif
  call s:SetUserVar(g:this_obsession)
endfunction

augroup kitty_session
  autocmd!
  autocmd VimEnter * nested call s:Start()
  autocmd VimLeavePre * if exists('g:this_obsession') | call s:SetUserVar('') | endif
augroup END
