.PHONY: test lint up up-mon down image-size dashboards kind-up kind-deploy
test: ; pytest --cov=app
lint: ; ruff check . && shellcheck scripts/system_health.sh
up: ; docker compose up -d --build
up-mon: ; docker compose --profile monitoring up -d --build
down: ; docker compose --profile monitoring down
image-size: ; docker images devops-task:local --format '{{.Size}}'
dashboards: ; python scripts/gen_dashboards.py
kind-up: ; kind create cluster --name devops
kind-deploy:
	docker build -t devops-task:1.0.0 . && kind load docker-image devops-task:1.0.0 --name devops
	kubectl apply -k k8s
