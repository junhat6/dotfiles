# 読み込み順: 補完 → 関数・ツール → 端末固有設定 → 候補・ハイライト
_dotfiles_zsh_dir="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
_dotfiles_brew_prefix="${HOMEBREW_PREFIX:-}"
if [[ -z "$_dotfiles_brew_prefix" ]] && command -v brew >/dev/null 2>&1; then
  _dotfiles_brew_prefix="$(brew --prefix)"
fi

source "$_dotfiles_zsh_dir/options.zsh"
source "$_dotfiles_zsh_dir/completion.zsh"
source "$_dotfiles_zsh_dir/navigation.zsh"
source "$_dotfiles_zsh_dir/git.zsh"
source "$_dotfiles_zsh_dir/tools.zsh"

# Git 管理外。会社専用の PATH などはこの端末に保存する。
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

# 全ウィジェットの定義後。fzf-tab より後、syntax-highlighting より前。
ZSH_AUTOSUGGEST_STRATEGY=(history)
if [[ -r "$_dotfiles_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$_dotfiles_brew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi
if [[ -r "$_dotfiles_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$_dotfiles_brew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
unset _dotfiles_zsh_dir _dotfiles_brew_prefix
