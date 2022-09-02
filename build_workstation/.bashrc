# Remove the old PS1 under the $color_prompt conditional and replace with the following to add the git branch name when in a git directory
PS1="\[\e]0;\u@\h: \w\a\]${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[1;35m\]\$(__git_ps1)\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
