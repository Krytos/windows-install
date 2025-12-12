# ~/.bashrc: executed by bash(1) for non-login shells.

# ==============================================================================
# 1. GLOBAL ENVIRONMENT & PATH (Runs for ALL sessions: Interactive, Scripts, SSH)
#    Crucial: This MUST remain at the top for MCP, VS Code, and scripts to work.
# ==============================================================================

# Path Management
# Add local bins and cargo bins to path
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# NVM (Node Version Manager)
# Loads NVM environment so 'npm' and 'node' work in non-interactive shells
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# History Settings
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

# ==============================================================================
# 2. FUNCTIONS (Defined globally, but not executed yet)
# ==============================================================================

# VSCode Helper
function vscode {
    if command -v code &> /dev/null; then
        local output
        output=$(code --version 2>&1)
        if [[ "$output" != *"Command is only available"* ]]; then
            return 0
        fi
    fi
    # Use 'command ls' to avoid alias interference
    local latest_server_dir=$(command ls -td "$HOME/.vscode-server/cli/servers/Stable-"* 2>/dev/null | head -n 1)
    if [[ -z "$latest_server_dir" ]]; then
        echo "VS Code server not installed."
        return 1
    fi
    local code_binary="${latest_server_dir}/server/bin/remote-cli/code"
    if [[ -f "$code_binary" ]]; then
        ln -sf "$code_binary" "$HOME/.local/bin/code"
    else
        echo "VS Code binary missing."
        return 1
    fi
}
export -f vscode

# Kill VSCode Server
function killcode() {
    # Added grep -v grep to avoid killing the search process
    ps aux | grep .vscode-server | grep -v grep | awk '{print $2}' | sudo xargs -r kill
}
export -f killcode

# Sudo Nopasswd Check
check_sudo_nopasswd() {
    local user=$(whoami)
    if sudo -n true 2>/dev/null; then return 0; fi
    echo "$user doesn't have passwordless sudo access. Attempting to configure..."
    if ! groups $user | grep -q '\bsudo\b'; then
        echo "$user is not in the sudo group."
        return 1
    fi
    sudo cp /etc/sudoers /etc/sudoers.bak
    echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$user > /dev/null
    if sudo -n true 2>/dev/null; then
        echo "Successfully configured."
        return 0
    else
        echo "Failed. Reverting..."
        sudo mv /etc/sudoers.bak /etc/sudoers
        sudo rm -f /etc/sudoers.d/$user
        return 1
    fi
}

# Python Venv Logic
function activate_python_venv {
    if [ -n "$VIRTUAL_ENV" ]; then
        echo "Virtual environment already active."
    else
        if [ -d ".venv" ]; then source .venv/bin/activate
        elif [ -d "venv" ]; then source venv/bin/activate
        else
            echo "No venv found. Creating one..."
            if command -v uv &> /dev/null; then
                uv venv -p >=3.13
                source .venv/bin/activate
            else
                echo "Error: uv is not installed. Cannot create venv."
            fi
        fi
    fi
}

deactivate () {
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
        unset -f deactivate
    fi
}

# Install Checkers
function check_nala_installed {
  if ! command -v nala &> /dev/null; then
    echo "nala not installed, installing..."
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install nala -y
  fi
}

function check_fastfetch_installed {
  if ! command -v fastfetch &> /dev/null; then
    echo "fastfetch not installed, installing..."
    sudo add-apt-repository ppa:zhangsongcui3371/fastfetch -y
    sudo apt update
    sudo apt-get install fastfetch -y
  fi
}

function check_posh_installed {
  if ! command -v oh-my-posh &> /dev/null; then
    ! command -v unzip &> /dev/null && sudo apt-get install unzip -y
    ! command -v curl &> /dev/null && sudo apt-get install curl -y
    echo "oh-my-posh not installed, installing..."
    curl -s https://ohmyposh.dev/install.sh | bash -s
    oh-my-posh font install FiraCode
    mkdir -p ~/.posh-themes
    curl -o ~/.posh-themes/krytos.omp.json https://raw.githubusercontent.com/Krytos/windows-install/refs/heads/main/krytos.omp.json
  fi
}

function check_uv_installed {
    if ! command -v uv &> /dev/null; then
        ! command -v cargo &> /dev/null && sudo apt-get install cargo -y
        echo "uv not installed, installing..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
}

function check_docker_installed {
    if command -v docker &> /dev/null; then return 0; fi
    local flag_file="$HOME/.config/suppress-docker-prompt"
    if [[ -f "$flag_file" && "$1" != "force" ]]; then return 0; fi

    echo "Docker is not installed."
    read -p "Would you like to install Docker now? (y/n): " -r choice
    echo
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo systemctl enable --now docker
        sudo usermod -aG docker "$USER"
        rm -f "$flag_file" 2>/dev/null
        newgrp docker
    else
        echo "Skipping Docker installation."
        mkdir -p "$(dirname "$flag_file")"
        touch "$flag_file"
        echo "Run 'check_docker_installed force' to install later."
    fi
}

function update_lsd_config {
    mkdir -p ~/.config/lsd
    cat <<-EOF >~/.config/lsd/colors.yaml
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
    cat <<-EOF > ~/.config/lsd/config.yaml
	color:
	  theme: custom
	EOF
}

function check_lsd_installed {
  if ! command -v lsd &> /dev/null; then
    ! command -v cargo &> /dev/null && sudo apt-get install cargo -y
    echo "lsd not installed, installing..."
    cargo install lsd
    update_lsd_config
  fi
}

SSH_ENV="$HOME/.ssh/agent-environment"
function start_agent {
    echo "Initialising new SSH agent..."
    mkdir -p ~/.ssh
    /usr/bin/ssh-agent | sed 's/^echo/#echo/' > "${SSH_ENV}"
    echo succeeded
    chmod 600 "${SSH_ENV}"
    . "${SSH_ENV}" > /dev/null
    /usr/bin/ssh-add;
}


# ==============================================================================
# 3. INTERACTIVE SESSIONS ONLY (Visuals, Prompts, Autostart Tools)
# ==============================================================================

# If not running interactively, STOP HERE.
# This protects scripts/SCP from noisy output.
case $- in
    *i*) ;;
      *) return;;
esac

# --- Everything below this line runs ONLY when you open a terminal ---

# A. Standard Ubuntu Aliases (Safe to define always)
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# B. Run Installation/Config Checks (Ensure tools exist)
check_sudo_nopasswd
check_nala_installed
check_fastfetch_installed
check_posh_installed
check_lsd_installed
check_uv_installed
check_docker_installed

# C. SAFE ALIASES (Defined ONLY if the tool exists)

alias sudo='sudo '
alias venv='activate_python_venv'
alias denv='deactivate'

if command -v nala &> /dev/null; then
    alias apt='\nala'
    alias dapt='\apt'
fi

if command -v lsd &> /dev/null; then
    alias ls='lsd'
    alias lsls='\ls'        # Raw ls
    alias ll='ls -alF'
    alias l='ls -lF'
    alias la='ls -A'
    alias lt='ls --tree'
else
    # Fallback if lsd failed to install
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
fi

if command -v oh-my-posh &> /dev/null; then
    alias omp='oh-my-posh'
fi

# D. SSH Agent Setup
if [ -f "${SSH_ENV}" ]; then
    . "${SSH_ENV}" > /dev/null
    ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ > /dev/null || {
        start_agent;
    }
else
    start_agent;
fi

# E. Visuals
if command -v fastfetch &> /dev/null; then
    fastfetch
fi

# F. Prompt Init
if command -v oh-my-posh &> /dev/null; then
    eval "$(oh-my-posh init bash --config ~/.posh-themes/krytos.omp.json)"
fi
