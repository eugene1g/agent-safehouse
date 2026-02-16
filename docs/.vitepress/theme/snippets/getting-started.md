```bash
# 1. Download safehouse (single self-contained script)
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/safehouse.sh \
  -o ~/.local/bin/safehouse
chmod +x ~/.local/bin/safehouse

# 2. Run any agent inside Safehouse
cd ~/projects/my-app
safehouse claude --dangerously-skip-permissions
```
