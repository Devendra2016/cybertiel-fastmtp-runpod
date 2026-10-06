IMAGE ?= cybertiel-fastmtp-runpod
PORT ?= 8000

build:
	docker build -t $(IMAGE) .

run:
	docker run --rm --gpus all \
		-p $(PORT):8000 \
		-v $(PWD)/models:/workspace/models \
		-e MTP=false \
		$(IMAGE)

run-mtp:
	docker run --rm --gpus all \
		-p $(PORT):8000 \
		-v $(PWD)/models:/workspace/models \
		-e MTP=true \
		$(IMAGE)

health:
	curl -fsS http://localhost:$(PORT)/health

models:
	curl -fsS http://localhost:$(PORT)/v1/models

stop:
	@true
