```bash
# Try to read your SSH private key — denied by the kernel
safehouse cat ~/.ssh/id_ed25519
# cat: /Users/you/.ssh/id_ed25519: Operation not permitted

# Try to list another repo — invisible
safehouse ls ~/other-project
# ls: /Users/you/other-project: Operation not permitted

# But your current project works fine
safehouse ls .
# README.md  src/  package.json  ...
```
