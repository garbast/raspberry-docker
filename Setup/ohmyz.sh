#!/bin/bash

readonly BASE_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." > /dev/null 2>&1 && pwd )"

function main() {
  local user=$(who am i | awk '{print $1}')
  local home_dir=$( getent passwd "${user}" | cut -d: -f6 )

  curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | zsh
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${home_dir}/.oh-my-zsh/themes/powerlevel10k
  rm "${home_dir}/.zshrc"
  ln -s "${BASE_DIR}/Setup/Configuration/.zshrc" "${home_dir}/.zshrc"
  rm "${home_dir}/.p10k.zsh"
  ln -s "${BASE_DIR}/Setup/Configuration/.p10k.zsh" "${home_dir}/.p10k.zsh"
}
main
