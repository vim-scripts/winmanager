"=============================================================================
"        File: wintagexplorer.vim
"      Author: Srinath Avadhanula (srinath@eecs.berkeley.edu)
" Last Change: Fri Jan 18 04:00 PM 2002 PST
"        Help: This file provides a simple interface to a tags file. The tags
"              are grouped according to the file they belong to and the user can
"              press <enter> while on a tag to open the tag in an adjacent
"              window.
"
"              This file shows the implementation of an explorer plugin add-in
"              to winmanager.vim. As explained in |winmanager-adding|, this
"              function basically has to expose various functions which
"              winmanager calls during its refresh-diplay cycle. In turn, it
"              uses the function WinManagerRileEdit() supplied by
"              winmanager.vim.

" See ":help winmanager" for additional details.
" ============================================================================


" "TagsExplorer" is the "name" under which this plugin "registers" itself.
" Registration means including a line like:
"    RegisterExplorers "TagsExplorer"
" in the .vimrc. Registration provides a way to let the user customize the
" layout of the various windows. When a explorer is released, the user needs
" to know this "name" to register the plugin. 
"
" The first thing this plugin does is decide upon a "title" for itself. This is
" the name of the buffer which winmanager will open for displaying the
" contents of this plugin. Note that this variable has to be of the form:
"    g:<ExplorerName>_title
" where <ExplorerName> = "TagsExplorer" for this plugin.
let g:TagsExplorer_title = "[Tag List]"

" variables to remember the last position of the user within the file.
let s:savedCursorRow = 1
let s:savedCursorCol = 1

" skip display the error message if no tags file in current directory.
if !exists('g:TagsExplorerSkipError')
	let g:TagsExplorerSkipError = 0
end

function! TagsExplorer_IsPossible()
	if glob('tags') == '' && g:TagsExplorerSkipError && !exists('s:tagDisplay')
		return 0
	end
	return 1
endfunction


" This is the function which winmanager calls the first time this plugin is
" displayed. Again, the rule for the name of this function is:
" <ExplorerName>_Start()
"
function! TagsExplorer_Start()
	let _showcmd = &showcmd

	setlocal bufhidden=delete
	setlocal buftype=nofile
	setlocal modifiable
	setlocal noswapfile
	setlocal nowrap
	setlocal nobuflisted

	set noshowcmd

	" set up some _really_ elementary syntax highlighting.
	if has("syntax") && !has("syntax_items") && exists("g:syntax_on")
		syn match TagsExplorerFileName	'^\S*$'   
		syn match TagsExplorerTagName	'^  \S*' 
		syn match TagsExplorerError   '^"\s\+Error:'
		syn match TagsExplorerVariable 'g:TagsExplorerSkipError'
		syn match TagsExplorerIgnore '"$'

		hi def link TagsExplorerFileName Special
		hi def link TagsExplorerTagName String
		hi def link TagsExplorerError Error
		hi def link TagsExplorerVariable Comment
		hi def link TagsExplorerIgnore Ignore
	end

	" if the tags were previously displayed, then they would have been saved
	" in this script variable. Therefore, just paste the contents of that
	" variable and quit.
	if exists("s:tagDisplay")
		put=s:tagDisplay
		1d_
		set nomodified
		call s:FoldTags()
		exe s:savedCursorRow
		exe 'normal! '.s:savedCursorCol.'|'
		return
	end

	1,$d_
	" if a file called "tags" exists in the current directory, then read in
	" the contents of that file.
	if glob('tags') != ""
		let s:TagsDirectory = getcwd()
		read tags
		" remove the leading comment lines.
		% g/^!_/de
	else
		let message = "
\Error:
\\n\n
\No Tags File Found in the current directory. Try reopening WManager in a 
\directory which contains a tags file.
\\n\n
\An easy way to do this is to switch to the file explorer plugin (using <c-n>), 
\navigate to that directory, press 'c' while there in order to set the pwd, and 
\then switch back to this view using <c-n>.
\\n\n
\This error message will not be shown for the remainder of this vim session. 
\To have it not appear at all, set g:TagsExplorerSkipError to 1 in your .vimrc
\"
		put=message
		1d
		let s:nothing = 1
		let _tw= &tw
		let &tw = g:winManagerWidth - 2
		normal! ggVGgq
		% s/$/"/g
		let &tw = _tw
		set nomodified
		let g:TagsExplorerSkipError = 1
		return
	end

	" interchange the order of the tag description. the standard tags format
	" is:
	" tagName     tagFile    tagRegExp
	" change this to:
	" tagFile     tagName
	"
	% s/\(\S*\)\s*\(\S*\)\s\+.*/\2\t\1/g

	" delete the first blank line which happens because of read
	0 d
	
	" group the contents according to file name. note that this is not a sort
	" operation. it merely groups each set of tags belonging to the same file
	" in a consecutive set of lines.
	let startTime = localtime()
	% call s:SortTags()
	let sortEndTime = localtime()
	
	0
	let lastfname="highly improbable file name"
	while 1
		" goto first column of this line ...
		normal! 0
		" ... and extract the file name.
		let fname = expand('<cWORD>')
		" then if this is a new filename, write this as a little title above
		" the present line...
		if fname != lastfname
			let _a = @a
			let @a = fname
			normal! O"aPj
			" ... and remember that this is the file name for the next set of
			" tags.
			let lastfname = fname
			let @a = _a
		end
		let curLine = line('.')
		" then modify every tag entry which starts with this file name.
		exe '% s/^'.escape(fname, '\').'\t/  /g'
		exe curLine
		" goto the next line which has a tag entry
		let nextTagLineNum = search('\S\+\t\S\+', 'W')
		if nextTagLineNum > 0
			exe nextTagLineNum
		else
			break
		end
	endwhile
	let indentEndTime = localtime()

	" set up the maps.
	map <buffer> <silent> <c-]> :call <SID>OpenTag(0)<cr>
	map <buffer> <silent> <cr> :call <SID>OpenTag(0)<cr>
	map <buffer> <silent> <tab> :call <SID>OpenTag(1)<cr>
  	nnoremap <buffer> <silent> <2-leftmouse> :call <SID>OpenTag(0)<cr>
	nnoremap <buffer> <silent> <space> za
	map <buffer> <silent> <c-^> <Nop>
	setlocal foldmethod=manual
	call s:FoldTags()
	let foldEndTime = localtime()

	call PrintError('sort time: '.(sortEndTime - startTime))
	call PrintError('indent time: '.(indentEndTime - sortEndTime))
	call PrintError('folding time: '.(foldEndTime - indentEndTime))
	call PrintError('total time: '.(foldEndTime - startTime))

	" for fast redraw if this plugin is closed and reopened...
	let _a = @a
	normal! ggVG"ay
	let s:tagDisplay = @a
	let @a = _a
	
	" clean up.
	setlocal nomodified
	let &showcmd = _showcmd
	unlet! _showcmd
endfunction

function! TagsExplorer_WrapUp()
	let s:savedCursorRow = line('.')
	let s:savedCursorCol = virtcol('.')
endfunction

function! TagsExplorer_IsValid()
	return 1
endfunction

function! <SID>OpenTag(split)
	let line = getline('.')
	if match(line, '"$') == '"'
		return
	end

	normal! 0
	" this is a tag, because it starts with a space.
	let tag = ''
	if line =~ '^\s'
		let tag = matchstr(getline('.'), '  \zs.*\ze')
		" go back and extract the file name
		let num = line('.')
		?^\S
		normal! 0
		let fname = expand('<cfile>')
		exe num
	else
		let fname = expand('<cfile>')
	end
	let _pwd = getcwd()
	exe 'cd '.s:TagsDirectory
	call WinManagerFileEdit(fname, 0)
	exe 'cd '._pwd

	if tag != '' 
		exe 'silent! tag '.tag
	end
endfunction

" function to group various tags according to which file they belong to.
function! <SID>SortTags() range
	" get the file which the first tag belongs to.
	0
	let line = getline('.')
	let fname = matchstr(line, '^[^\t]*\t\@=')
	let firstfname = fname
	" then move all tags belonging to that file to the end.
	exe '% g/^'.escape(fname, '\').'/m$'

	" then proceed to the file containing the next tag.
	0
	let line = getline('.')
	let fname = matchstr(line, '^[^\t]*\t\@=')
	" if we are done with all the files, then quit.
	while fname != firstfname
		" ... otherwise move the tags belonging to that file to the end as
		" well.
		exe '% g/^'.escape(fname, '\').'/m$'
		0
		let line = getline('.')
		let fname = matchstr(line, '^[^\t]*\t\@=')
	endwhile
endfunction

function! <SID>FoldTags()
	1
	let lastLine = 1
	while 1
		if search('^\S', 'W')
			normal! k
			let presLine = line('.')
		else
			break
		end
		exe lastLine.','.presLine.' fold'
		normal! j
		let lastLine = line('.')
	endwhile
	exe lastLine.',$ fold'
endfunction

