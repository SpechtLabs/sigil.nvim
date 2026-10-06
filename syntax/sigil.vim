" Regex highlighting for sigil files, used until the tree-sitter parser is
" installed. vim.treesitter.start() turns it off in buffers it highlights.
" Mirrors the TextMate grammar the Sigil docs site highlights with.

if exists('b:current_syntax')
  finish
endif

syn case match

" A keyword after `.` is a field name, as in service.type, so every keyword
" group refuses a preceding dot.
syn match sigilDocSeparator '^\s*---\s*$'
syn match sigilComment '//.*$' contains=sigilTodo,@Spell
syn keyword sigilTodo contained TODO FIXME XXX NOTE

syn match sigilEscape contained '\\\%([abfnrtv\\"'']\|x\x\{2}\|u\x\{4}\|U\x\{8}\|\o\{3}\)'
syn region sigilString start='"' skip='\\\\\|\\"' end='"' oneline contains=sigilEscape,@Spell
syn region sigilRawString start='`' end='`'

syn match sigilDuration '\<\%(\d\+\%(ms\|s\|m\|h\|d\)\)\+\>'
syn match sigilNumber '\<\d\+\%(\.\d\+\)\=\>'

syn match sigilConditional '\.\@1<!\<\%(when\|assert\)\>'
syn match sigilKeyword '\.\@1<!\<\%(as\|param\|let\|pub\|version\|enum\|input\|precedence\|collect\|default\|conflict\)\>'
syn match sigilWordOperator '\.\@1<!\<\%(and\|or\|xor\|not\|in\|all\|any\|filter\|one\|exclusive\|has\|like\|matches\|present\)\>'
syn match sigilBoolean '\.\@1<!\<\%(true\|false\)\>'
syn match sigilConstant '\.\@1<!\<outcome\>'
syn match sigilBuiltinType '\.\@1<!\<\%(bool\|int\|float\|string\|duration\|timestamp\|list\|map\)\>'

syn match sigilCall '\<\h\w*\ze\s*('

" Declarations: the keyword, then the name it declares.
syn match sigilImport '\.\@1<!\<\%(policy\|module\|use\)\>' nextgroup=sigilNamespace skipwhite
syn match sigilNamespace contained '\h\w*\%(\.\h\w*\)*'
syn match sigilTypeDecl '\.\@1<!\<\%(kind\|type\)\>' nextgroup=sigilTypeName skipwhite
syn match sigilTypeName contained '\h\w*'
syn match sigilFuncDecl '\.\@1<!\<\%(fn\|decision\)\>' nextgroup=sigilFuncName skipwhite
syn match sigilFuncName contained '\h\w*'

syn match sigilOperator '??\|==\|!=\|<=\|>=\|->\|[<>+\-?|]'

hi def link sigilDocSeparator Delimiter
hi def link sigilComment Comment
hi def link sigilTodo Todo
hi def link sigilEscape SpecialChar
hi def link sigilString String
hi def link sigilRawString String
hi def link sigilDuration Number
hi def link sigilNumber Number
hi def link sigilConditional Conditional
hi def link sigilKeyword Keyword
hi def link sigilWordOperator Operator
hi def link sigilBoolean Boolean
hi def link sigilConstant Constant
hi def link sigilBuiltinType Type
hi def link sigilCall Function
hi def link sigilImport Include
hi def link sigilNamespace Identifier
hi def link sigilTypeDecl Keyword
hi def link sigilTypeName Type
hi def link sigilFuncDecl Keyword
hi def link sigilFuncName Function
hi def link sigilOperator Operator

let b:current_syntax = 'sigil'
