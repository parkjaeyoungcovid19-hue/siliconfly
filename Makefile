.PHONY: build run fly

APP := ThongpariFlyNeuronSim

build:
	@./build.sh

# Launch the fly; quit from the menu-bar 🪰.
run: build
	@./$(APP)

# Same as `make run`.
fly: run
