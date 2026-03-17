.PHONY: deploy check sync restart status logs

VPS_HOST ?= openclaw2
OPENCLAW_HOME ?= /root/.openclaw

check:
	@echo "==> Checking local state..."
	@test -f .env || (echo "ERROR: .env file missing. Copy .env.example and fill in values." && exit 1)
	@test -f configs/openclaw.json || (echo "ERROR: configs/openclaw.json missing." && exit 1)
	@echo "==> Local checks passed."

sync: check
	@echo "==> Syncing config to VPS..."
	scp configs/openclaw.json $(VPS_HOST):$(OPENCLAW_HOME)/openclaw.json
	scp .env $(VPS_HOST):$(OPENCLAW_HOME)/.env
	ssh $(VPS_HOST) "mkdir -p $(OPENCLAW_HOME)/agents/main $(OPENCLAW_HOME)/memory"
	scp configs/agent/BOOTSTRAP.md $(VPS_HOST):$(OPENCLAW_HOME)/agents/main/BOOTSTRAP.md
	scp configs/agent/memory-safety-rules.md $(VPS_HOST):$(OPENCLAW_HOME)/memory/safety-rules.md
	scp configs/agent/memory-identity.md $(VPS_HOST):$(OPENCLAW_HOME)/memory/identity.md
	ssh $(VPS_HOST) "chmod 600 $(OPENCLAW_HOME)/openclaw.json $(OPENCLAW_HOME)/.env"
	@echo "==> Config synced."

restart:
	@echo "==> Restarting OpenClaw on VPS..."
	ssh $(VPS_HOST) "systemctl restart openclaw"
	@sleep 3
	ssh $(VPS_HOST) "systemctl status openclaw --no-pager"
	@echo "==> Restart complete."

deploy: check sync restart
	@echo "==> Deploy complete."

status:
	ssh $(VPS_HOST) "systemctl status openclaw --no-pager"

logs:
	ssh $(VPS_HOST) "journalctl -u openclaw -f --no-pager -n 50"

setup-vps:
	@echo "==> Setting up VPS environment..."
	ssh $(VPS_HOST) "bash -s" < scripts/setup-vps.sh
	@echo "==> VPS setup complete."
