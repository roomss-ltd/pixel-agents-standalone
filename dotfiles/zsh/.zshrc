export PATH="$HOME/.local/bin:$PATH"

# ── Oh My Zsh ────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(git zsh-autosuggestions fast-syntax-highlighting you-should-use zsh-bat)

source $ZSH/oh-my-zsh.sh

# ── Powerlevel10k prompt ─────────────────────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ── direnv ───────────────────────────────────────────────────────────
eval "$(direnv hook zsh)"

# ── Claude Code (Bedrock) ────────────────────────────────────────────
# Set these environment variables for your AWS/Bedrock setup:
#   export CLAUDE_CODE_USE_BEDROCK=1
#   export AWS_REGION=eu-west-1
#   export AWS_BEARER_TOKEN_BEDROCK=<your-token>
#
# Model aliases — replace __BEDROCK_TOKEN__ with your actual token:
#
# alias claude-opus='
#   export CLAUDE_CODE_USE_BEDROCK=1;
#   export AWS_REGION=eu-west-1;
#   export ANTHROPIC_MODEL=eu.anthropic.claude-opus-4-6-v1;
#   export AWS_BEARER_TOKEN_BEDROCK=__BEDROCK_TOKEN__;
#   claude
# '
#
# alias claude-sonnet='
#   export CLAUDE_CODE_USE_BEDROCK=1;
#   export AWS_REGION=eu-west-1;
#   export ANTHROPIC_MODEL=global.anthropic.claude-sonnet-4-6;
#   export AWS_BEARER_TOKEN_BEDROCK=__BEDROCK_TOKEN__;
#   claude
# '
#
# alias claude-haiku='
#   export CLAUDE_CODE_USE_BEDROCK=1;
#   export AWS_REGION=eu-west-1;
#   export ANTHROPIC_MODEL=eu.anthropic.claude-haiku-4-5-20251001-v1:0;
#   claude
# '
