#!/bin/zsh
# AgentPass Demo Recording Script

set -e

ECHO_PK=$(cat ~/.openclaw/evm-wallet.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('privateKey') or d.get('private_key') or d.get('key') or list(d.values())[0])")

echo "Launching Terminal..."
open -a Terminal
sleep 2

echo "Launching Safari..."
open -a Safari "https://www.useagentpass.com"
sleep 2

# Position windows
peekaboo window set-bounds --app "Terminal" --x 0 --y 25 --width 1240 --height 900
sleep 0.5
peekaboo window set-bounds --app "Safari" --x 1260 --y 25 --width 1280 --height 900
sleep 0.5

# Focus Terminal
peekaboo window focus --app "Terminal"
sleep 1

echo "Starting recording..."
peekaboo capture live \
  --mode screen \
  --screen-index 0 \
  --duration 120 \
  --active-fps 12 \
  --idle-fps 3 \
  --path "/tmp/agentpass-demo/frames" \
  --video-out "/tmp/agentpass-demo.mp4" &
CAPTURE_PID=$!
sleep 2

# Type into Terminal
peekaboo type "# AgentPass Demo" --app "Terminal" --delay 40
peekaboo press return --app "Terminal"
sleep 0.8

peekaboo type "# Echo (agentId: 32176) authenticating via ERC-8004 on Base" --app "Terminal" --delay 35
peekaboo press return --app "Terminal"
sleep 0.8

peekaboo type "# No API keys — just a signed challenge verified on-chain" --app "Terminal" --delay 35
peekaboo press return --app "Terminal"
sleep 1.5

peekaboo type "cd ~/dev/agentpass/demo" --app "Terminal" --delay 30
peekaboo press return --app "Terminal"
sleep 0.5

# Type the demo command (without the actual private key visible)
peekaboo type 'SERVER_URL=https://www.useagentpass.com SERVICE=useagentpass ECHO_PRIVATE_KEY="[echo-wallet]" npx tsx src/demo-client.ts' --app "Terminal" --delay 20
sleep 1

# Clear that line — write key to temp file, source it so it never appears on screen
peekaboo hotkey --keys "ctrl,u" --app "Terminal"
sleep 0.3
echo "export ECHO_PRIVATE_KEY=$ECHO_PK" > /tmp/.agentpass_env
peekaboo type "source /tmp/.agentpass_env && SERVER_URL=https://www.useagentpass.com SERVICE=useagentpass npx tsx src/demo-client.ts" --app "Terminal" --delay 20
peekaboo press return --app "Terminal"
sleep 18

# Navigate to Basescan
peekaboo window focus --app "Safari"
sleep 0.5
open -a Safari "https://basescan.org/address/0x159E776Dc47C745a4a78857C3ca37CdEEbbb8C84#readContract"
sleep 4

# Navigate to GitHub
open -a Safari "https://github.com/echointheopen/agentpass"
sleep 4

# Back to Terminal — run tests
peekaboo window focus --app "Terminal"
sleep 0.5
peekaboo type "cd ~/dev/agentpass/contracts && forge test --summary" --app "Terminal" --delay 25
peekaboo press return --app "Terminal"
sleep 15

echo "Demo complete. Stopping recording..."
kill $CAPTURE_PID 2>/dev/null || true
wait $CAPTURE_PID 2>/dev/null || true

sleep 2
echo ""
echo "✅ Video saved to: /tmp/agentpass-demo.mp4"
ls -lh /tmp/agentpass-demo.mp4 2>/dev/null && open /tmp/agentpass-demo.mp4 || echo "Check /tmp/agentpass-demo/frames/"
