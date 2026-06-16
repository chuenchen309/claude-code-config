# shell/aliases.sh — sourced from ~/.bashrc via $CLAUDE_CONFIG_DIR (set by bootstrap.sh)
# Claude Code helpers

# cch: open Claude via headroom token-compression wrapper, skip rtk layer
alias cch='headroom wrap claude --no-rtk'
