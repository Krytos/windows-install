# ~/.config/fish/config.fish

# ==============================================================================
# 1. GLOBAL ENVIRONMENT & PATH
#    (Runs for ALL sessions: Interactive, Scripts, VS Code Tasks)
# ==============================================================================

# Path Management
fish_add_path $HOME/.local/bin
fish_add_path $HOME/.cargo/bin

# Default Editor
set -gx EDITOR nano

# ==============================================================================
# 2. FUNCTIONS
# ==============================================================================

function vscode --description 'Launch VS Code correctly on WSL'
    if type -q code
        set -l output (code --version 2>&1)
        if not string match -q "*Command is only available*" "$output"
            return 0
        end
    end

    # Use 'command ls' to avoid alias loops
    set -l latest_server_dir (command ls -td $HOME/.vscode-server/cli/servers/Stable-* 2>/dev/null | head -n 1)

    if test -z "$latest_server_dir"
        echo "VS Code server not installed."
        return 1
    end

    set -l code_binary "$latest_server_dir/server/bin/remote-cli/code"

    if test -f "$code_binary"
        ln -sf "$code_binary" "$HOME/.local/bin/code"
    else
        echo "VS Code binary missing."
        return 1
    end
end

function killcode --description 'Kill VS Code Server processes'
    ps aux | grep .vscode-server | grep -v grep | awk '{print $2}' | sudo xargs -r kill
end

function check_sudo_nopasswd
    set -l user (whoami)
    if sudo -n true 2>/dev/null
        return 0
    end

    echo "$user doesn't have passwordless sudo access. Attempting to configure..."

    if not groups $user | grep -q '\bsudo\b'
        echo "$user is not in the sudo group."
        return 1
    end

    sudo cp /etc/sudoers /etc/sudoers.bak
    echo "$user ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$user > /dev/null

    if sudo -n true 2>/dev/null
        echo "Successfully configured."
        return 0
    else
        echo "Failed. Reverting..."
        sudo mv /etc/sudoers.bak /etc/sudoers
        sudo rm -f /etc/sudoers.d/$user
        return 1
    end
end

function activate_python_venv
    if set -q VIRTUAL_ENV
        echo "Virtual environment already active."
        return
    end

    if test -d ".venv"
        source .venv/bin/activate.fish
    else if test -d "venv"
        source venv/bin/activate.fish
    else
        echo "No venv found. Creating one..."
        if type -q uv
            uv venv -p 3.14
            source .venv/bin/activate.fish
        else
            echo "Error: uv is not installed. Cannot create venv."
        end
    end
end

# --- Install Checkers ---

function check_nvm_plugin
    if not type -q nvm
        echo "nvm not found. Installing Fisher and nvm.fish..."

        # 1. Install Fisher (Plugin Manager) if missing
        if not type -q fisher
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher
        end

        # 2. Install nvm.fish
        fisher install jorgebucaran/nvm.fish

        # 3. Install latest Node version immediately so it's usable
        echo "Installing latest Node.js version..."
        nvm install latest
        set --universal nvm_default_version latest
    end
end

function check_nala_installed
    if not type -q nala
        echo "nala not installed, installing..."
        sudo apt-get update && sudo apt-get upgrade -y
        sudo apt-get install nala -y
    end
end

function check_fastfetch_installed
    if not type -q fastfetch
        echo "fastfetch not installed, installing..."
        sudo apt-get install fastfetch -y
    end
end

function check_posh_installed
    if not type -q oh-my-posh
        if not type -q unzip; sudo apt-get install unzip -y; end
        if not type -q curl; sudo apt-get install curl -y; end
        echo "oh-my-posh not installed, installing..."
        curl -s https://ohmyposh.dev/install.sh | bash -s
        oh-my-posh font install FiraCode
        mkdir -p ~/.posh-themes
        curl -o ~/.posh-themes/krytos.omp.json https://raw.githubusercontent.com/Krytos/windows-install/refs/heads/main/krytos.omp.json
    end
end

function check_uv_installed
    if not type -q uv
        if not type -q cargo; sudo apt-get install cargo -y; end
        echo "uv not installed, installing..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    end
end

function check_lsd_installed
    if not type -q lsd
        if not type -q cargo; sudo apt-get install cargo -y; end
        echo "lsd not installed, installing..."
        cargo install lsd
        mkdir -p ~/.config/lsd
    end
end

function check_docker_installed
    if type -q docker; return 0; end

    set -l flag_file "$HOME/.config/suppress-docker-prompt"
    if test -f "$flag_file"; and test "$argv[1]" != "force"
        return 0
    end

    echo "Docker is not installed."
    read -P "Would you like to install Docker now? (y/n): " choice

    if string match -ri "^y" "$choice"
        echo "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        rm get-docker.sh
        sudo systemctl enable --now docker
        sudo usermod -aG docker $USER
        rm -f "$flag_file" 2>/dev/null
        newgrp docker
    else
        echo "Skipping Docker installation."
        mkdir -p (dirname "$flag_file")
        touch "$flag_file"
        echo "Run 'check_docker_installed force' to install later."
    end
end

# SSH Agent Helper (Fish specific file)
set -gx SSH_ENV "$HOME/.ssh/agent-environment.fish"

function start_agent
    echo "Initialising new SSH agent..."
    mkdir -p ~/.ssh
    ssh-agent -c | sed 's/^echo/#echo/' > "$SSH_ENV"
    chmod 600 "$SSH_ENV"
    source "$SSH_ENV" > /dev/null
    ssh-add
end


# ==============================================================================
# 3. INTERACTIVE SESSIONS ONLY
# ==============================================================================

if status is-interactive

    # A. Aliases
    alias alert='notify-send --urgency=low -i "$([ $status = 0 ] && echo terminal || echo error)" "$(history|tail -n1)"'

    # B. Run Installation/Config Checks
    check_sudo_nopasswd
    check_nala_installed
    check_fastfetch_installed
    check_posh_installed
    check_lsd_installed
    check_uv_installed
    check_docker_installed
    check_nvm_plugin   # <--- Installs Fisher & NVM automatically

    # C. Safe Aliases
    alias sudo='sudo '
    alias venv='activate_python_venv'
    alias denv='deactivate'

    if type -q nala
        alias apt='nala'
        alias dapt='apt'
    end

    if type -q lsd
        alias ls='lsd'
        alias lsls='command ls'
        alias ll='ls -alF'
        alias l='ls -lF'
        alias la='ls -A'
        alias lt='ls --tree'
    else
        alias ll='ls -alF'
        alias la='ls -A'
        alias l='ls -CF'
    end

    if type -q oh-my-posh
        alias omp='oh-my-posh'
    end

    # D. SSH Agent Setup
    if test -f "$SSH_ENV"
        source "$SSH_ENV" > /dev/null
        if not ps -ef | grep -q "$SSH_AGENT_PID.*ssh-agent\$"
            start_agent
        end
    else
        start_agent
    end

    # E. Visuals
    if type -q fastfetch
        fastfetch
    end

    # F. Prompt Init
    if type -q oh-my-posh
        oh-my-posh init fish --config ~/.posh-themes/krytos.omp.json | source
    end

end
