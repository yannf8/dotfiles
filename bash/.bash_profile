# .bash_profile

# Get the aliases and functions
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# User specific environment and startup programs
. "$HOME/.cargo/env"

export QSYS_ROOTDIR="$HOME/intelFPGA_lite/18.1/quartus/sopc_builder/bin"
