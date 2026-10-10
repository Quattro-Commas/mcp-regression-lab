.PHONY: install build test lint format run demo clean

install:
	npm ci

build:
	npm run build

test:
	npm test

lint:
	npm run lint

format:
	npm run format

run:
	npx tsx src/cli.ts

demo:
	npx tsx examples/demo-server.ts

clean:
	rm -rf dist node_modules *.tsbuildinfo