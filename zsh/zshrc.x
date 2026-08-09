# Sourced by zsh/zshrc where profiles/manjaro.conf.yaml has deployed it, which
# is the host that has an X server. Anything here that would also make sense
# over ssh belongs in shell/interactive.sh instead.

# Java apps that render blank under a reparenting WM (i3).
alias fixWindows='export _JAVA_AWT_WM_NONREPARENTING=0'

# The WSL equivalent is clip.exe, which is not a package and not an alias worth
# faking: a script wanting the clipboard should test for the command it needs.
alias clip='xclip -selection clipboard'
