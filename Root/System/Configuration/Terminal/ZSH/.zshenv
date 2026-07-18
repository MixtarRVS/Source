export PATH=/System/Commands:/System/Terminal/ZSH
export MIXTAR_SYSTEM_NAME=${MIXTAR_SYSTEM_NAME:-MixtarRVS}
export ZSH_MIXTAR_STATE=${HOME}/.Mixtar/ZSH

module_path=(
  /System/Terminal/ZSH/Modules
  $module_path
)

fpath=(
  /System/Terminal/ZSH/Functions
  /System/Terminal/ZSH/Functions/Completion
  /System/Terminal/ZSH/Functions/Completion/Base
  /System/Terminal/ZSH/Functions/Completion/Linux
  /System/Terminal/ZSH/Functions/Completion/Unix
  /System/Terminal/ZSH/Functions/Completion/Zsh
  /System/Terminal/ZSH/Functions/Misc
  /System/Terminal/ZSH/Functions/Prompts
  $fpath
)
