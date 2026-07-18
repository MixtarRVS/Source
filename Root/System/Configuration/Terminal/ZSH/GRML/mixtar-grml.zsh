# Native Mixtar profile derived from the earlier grml-zsh-config adapter.
# It deliberately uses no public FHS paths.

export HISTFILE=$ZSH_MIXTAR_STATE/history
export SAVEHIST=5000
export HISTSIZE=5000
export ZSH_COMPDUMP=$ZSH_MIXTAR_STATE/cache/zcompdump

setopt prompt_subst
unsetopt beep
PROMPT='%F{green}${USER}@${MIXTAR_SYSTEM_NAME}%f:%F{blue}%~%f> '

if autoload -Uz +X compinit compdump 2>/System/Devices/null; then
  compinit -u -d "$ZSH_COMPDUMP"
fi
zmodload zsh/complist 2>/System/Devices/null || true

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

bindkey -e
bindkey '^?' backward-delete-char
bindkey '^H' backward-delete-char
bindkey '^[[3~' delete-char
bindkey '^[[A' history-beginning-search-backward
bindkey '^[[B' history-beginning-search-forward
bindkey '^[[C' forward-char
bindkey '^[[D' backward-char
bindkey '^[OA' history-beginning-search-backward
bindkey '^[OB' history-beginning-search-forward
bindkey '^[OC' forward-char
bindkey '^[OD' backward-char
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[OH' beginning-of-line
bindkey '^[OF' end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line

mixtar_ignore_function_key() { return 0 }
zle -N mixtar-ignore-function-key mixtar_ignore_function_key
for key_sequence in \
  '^[[[A' '^[[[B' '^[[[C' '^[[[D' '^[[[E' \
  '^[OP' '^[OQ' '^[OR' '^[OS' '^[[15~' \
  '^[[17~' '^[[18~' '^[[19~' '^[[20~' '^[[21~' '^[[23~' '^[[24~'
do
  bindkey "$key_sequence" mixtar-ignore-function-key
done
unset key_sequence

setopt auto_cd
setopt auto_list
setopt auto_menu
setopt auto_param_slash
setopt complete_in_word
setopt extended_glob
setopt hist_ignore_dups
setopt hist_reduce_blanks
setopt inc_append_history
setopt interactive_comments
setopt no_beep
