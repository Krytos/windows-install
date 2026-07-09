# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

####### PATH STUFF #######

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export PATH="/snap/bin:$PATH"


###### ENV VARS ######

LOGURU_LEVEL='INFO'


shopt -s expand_aliases

#########################################################
# EVERYTHING BELOW THIS ONLY RUNS IN INTERACTIVE SHELLS #
#########################################################

case $- in
    *i*) ;;
      *) return;;
esac


# Antigravity Agent fix - clean the terminal
if [[ -n "$ANTIGRAVITY_AGENT" ]]; then
    # Force the shell to behave as a simple pipe
    export TERM=dumb
    export DEBIAN_FRONTEND=noninteractive

    # Disable aliases that might wait for terminal polling
    unalias -a

    # Clean prompt
    export PS1='$ '
    unset PROMPT_COMMAND

    # exit early, without running the rest of .bashrc, e.g. bypassing oh-my-bash
    return
fi


# Function to check and configure sudo access without password

check_sudo_nopasswd() {
    local user=$(whoami)

    # Check if user can run sudo without password
    if sudo -n true 2>/dev/null; then
        return 0
    fi

    echo "$user doesn't have passwordless sudo access. Attempting to configure..."

    # Check if user is in sudo group
    if ! groups $user | grep -q '\bsudo\b'; then
        echo "$user is not in the sudo group. Please add the user to the sudo group first."
        return 1
    fi

    # Backup sudoers file
    sudo cp /etc/sudoers /etc/sudoers.bak

    # Add user to sudoers file with NOPASSWD
    echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$user > /dev/null

    # Verify the changes
    if sudo -n true 2>/dev/null; then
        echo "Successfully configured passwordless sudo access for $user."
        return 0
    else
        echo "Failed to configure passwordless sudo access. Reverting changes..."
        sudo mv /etc/sudoers.bak /etc/sudoers
        sudo rm -f /etc/sudoers.d/$user
        return 1
    fi
}

check_sudo_nopasswd

####### Nala #######

check_nala_installed() {
  if ! command -v nala &> /dev/null; then
    echo "nala not installed, installing..."
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install nala -y
  fi
}

check_nala_installed

####### OH MY POSH #######

check_posh_installed() {
  if ! command -v oh-my-posh &> /dev/null; then
    if ! command -v unzip &> /dev/null; then
        sudo apt-get install unzip -y
    fi
	if ! command -v curl &> /dev/null; then
        sudo apt-get install curl -y
    fi
    echo "oh-my-posh not installed, installing..."
    curl -s https://ohmyposh.dev/install.sh | bash -s
    oh-my-posh font install FiraCode
    mkdir -p ~/.posh-themes
    curl -o ~/.posh-themes/krytos.omp.json https://raw.githubusercontent.com/Krytos/windows-install/refs/heads/main/config/krytos.omp.json
  fi
}

update_omp_theme() {
    curl -o ~/.posh-themes/krytos.omp.json https://raw.githubusercontent.com/Krytos/windows-install/refs/heads/main/config/krytos.omp.json
}
export update_omp_theme

export PATH="$PATH:$HOME/.local/bin"
check_posh_installed

# Initialize oh-my-posh if installed
if command -v oh-my-posh &> /dev/null; then
  eval "$(oh-my-posh init bash --config ~/.posh-themes/krytos.omp.json)"
fi

####### LSD #######

update_lsd_config() {
# write config to ~/.config/lsd/colors.yaml
mkdir -p ~/.config/lsd
echo "Writing lsd colors..."
cat <<"EOF"> ~/.config/lsd/colors.yaml
user: "#cba6f7"
group: "#b4befe"
permission:
    read: "#a6e3a1"
    write: "#f9e2af"
    exec: "#eba0ac"
    exec-sticky: "#cba6f7"
    no-access: "#a6adc8"
    octal: "#94e2d5"
    acl: "#94e2d5"
    context: "#89dceb"
date:
    hour-old: "#94e2d5"
    day-old: "#89dceb"
    older: "#74c7ec"
size:
    none: "#a6adc8"
    small: "#a6e3a1"
    medium: "#f9e2af"
    large: "#fab387"
inode:
    valid: "#f5c2e7"
    invalid: "#a6adc8"
links:
    valid: "#f5c2e7"
    invalid: "#a6adc8"
tree-edge: "#bac2de"
git-status:
    default: "#cdd6f4"
    unmodified: "#a6adc8"
    ignored: "#a6adc8"
    new-in-index: "#a6e3a1"
    new-in-workdir: "#a6e3a1"
    typechange: "#f9e2af"
    deleted: "#f38ba8"
    renamed: "#a6e3a1"
    modified: "#f9e2af"
    conflicted: "#f38ba8"
EOF
# write config to ~/.config/lsd/config.yaml
echo "Writing lsd config..."
cat <<"EOF"> ~/.config/lsd/config.yaml
color:
    theme: custom
EOF
}


check_lsd_installed() {
  if ! command -v lsd &> /dev/null; then
    echo "lsd not installed, installing..."
    sudo apt-get install lsd -y
    update_lsd_config
  fi
}

check_lsd_installed

####### SSH AGENT #######

SSH_ENV="$HOME/.ssh/agent-environment"

start_agent() {
    echo "Initialising new SSH agent..."
    mkdir -p ~/.ssh
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    echo succeeded
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    /usr/bin/ssh-add;
}

# Source SSH settings, if applicable

if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    #ps ${SSH_AGENT_PID} doesn't work under cywgin
    ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || {
        start_agent;
    }
else
    start_agent;
fi


####### BLE.SH #######

check_ble_installed() {
    if [ ! -f ~/.local/share/blesh/ble.sh ]; then
        echo "ble.sh not installed, installing..."
        git clone --recursive --depth 1 --shallow-submodules https://github.com/akinomyoga/ble.sh.git

        if ! command -v make &> /dev/null; then
            echo "make not installed, installing..."
            sudo apt-get install make -y
        fi
        make -C ble.sh install PREFIX=~/.local
    else
        source -- ~/.local/share/blesh/ble.sh
    fi
}
check_ble_installed

####### PYTHON #######

check_uv_installed() {
    if ! command -v uv &> /dev/null; then
        if ! command -v cargo &> /dev/null; then
            sudo apt-get install cargo -y
            reboot
        fi
        export PATH="$PATH:$HOME/.cargo/bin"
        echo "uv not installed, installing..."
        # On macOS and Linux.
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
}
check_uv_installed

activate_python_venv() {
    # check if .venv or venv dir exists and activate it
    # check first if a virtual environment is activated
    # if not, check if .venv or venv dir exists and activate it

    if [ -n "$VIRTUAL_ENV" ]; then
        echo "A virtual environment is already activated."
    else
        if [ -d ".venv" ]; then
            echo "Activating .venv..."
            source .venv/bin/activate
        elif [ -d "venv" ]; then
            echo "Activating venv..."
            source venv/bin/activate
        else
            echo "No virtual environment found. Creating one..."
            uv venv -p >=3.13
            source .venv/bin/activate
        fi
    fi
}


deactivate() {
    # reset old environment variables
    if [ -n "${_OLD_VIRTUAL_PATH:-}" ] ; then
        PATH="${_OLD_VIRTUAL_PATH:-}"
        export PATH
        unset _OLD_VIRTUAL_PATH
    fi
    if [ -n "${_OLD_VIRTUAL_PYTHONHOME:-}" ] ; then
        PYTHONHOME="${_OLD_VIRTUAL_PYTHONHOME:-}"
        export PYTHONHOME
        unset _OLD_VIRTUAL_PYTHONHOME
    fi

    # This should detect bash and zsh, which have a hash command that must
    # be called to get it to forget past commands.  Without forgetting
    # past commands the $PATH changes we made may not be respected
    if [ -n "${BASH:-}" -o -n "${ZSH_VERSION:-}" ] ; then
        hash -r 2> /dev/null
    fi

    if [ -n "${_OLD_VIRTUAL_PS1:-}" ] ; then
        PS1="${_OLD_VIRTUAL_PS1:-}"
        export PS1
        unset _OLD_VIRTUAL_PS1
    fi

    unset VIRTUAL_ENV
    unset VIRTUAL_ENV_PROMPT
    if [ ! "${1:-}" = "nondestructive" ] ; then
    # Self destruct!
        unset -f deactivate
    fi
}




####### ALIASES #######

# Oh my posh
alias omp='oh-my-posh'

# Sudos
alias sudo='sudo '

# Apt and Nala
alias apt='\nala'
alias dapt='\apt'

# ls and cd
alias ls='lsd'
alias lsls='\ls'
alias ll='ls -alF'
alias l='ls -lF'
alias la='ls -A'
alias lt='ls --tree'

# Python
alias venv='activate_python_venv'
alias denv='deactivate'



####### VSCODE #######
vscode() {
    if ! command -v code &> /dev/null; then
        echo "code not installed"
        if test -e ~/.local/bin/code &> /dev/null; then
            echo ""
        elif ! test -e ~/.vscode-server/cli/servers/Stable-*/server/bin/remote-cli/code &> /dev/null; then
            echo "vscode not installed"
            exit 1
        else
            echo "linking vscode"
            ln -sf ~/.vscode-server/cli/servers/Stable-*/server/bin/remote-cli/code ~/.local/bin/code
        fi
    fi
}

killcode() {
    ps aux | grep .vscode-server | awk '{print $2}' | sudo xargs kill
}
export vscode
export killcode
