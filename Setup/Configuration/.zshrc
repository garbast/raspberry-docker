export ZSH="/home/ubuntu/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(command-not-found common-aliases composer docker git git-extras git-flow-avh npm rsync ssh-agent)

source $ZSH/oh-my-zsh.sh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

alias composer='[ -d ~/.composer ] || mkdir ~/.composer; docker run --rm --interactive --tty --user 1000:33 -v `pwd`:/app -v ~/.composer:/tmp/.composer -e COMPOSER_HOME=/tmp/.composer composer --ignore-platform-reqs'
