ROOT_DIR = $(shell pwd)
OS = $(shell uname)

BUILD_DIR = ./bin
APP_NAME = build
C_FILES = ./src/*.cpp
IMGUI_FILES = ./include/imgui/*.cpp
GLAD_FILE = ./include/glad.c

CXX := clang++
APP_INCLUDES:= -I./include/
APP_LINKERS:= -L./lib/

# OS specific settings
ifeq ($(OS), Darwin)
	CXXFLAGS := -std=c++20 -lglfw3 -lassimp -framework Cocoa -framework OpenGL -framework IOKit
else ifeq ($(OS), Linux)
	CXXFLAGS = -std=c++20 -lglfw -lGL -lX11 -lpthread -lXrandr -lXi -ldl -lXcursor -lassimp
endif

# Define targets
all: $(BUILD_DIR)/$(APP_NAME)

$(BUILD_DIR)/$(APP_NAME): $(C_FILES) $(GLAD_FILE) $(IMGUI_FILES)
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(APP_INCLUDES) $(APP_LINKERS)

run: $(BUILD_DIR)/$(APP_NAME)
	@./$<

clean:
	@rm -rf $(BUILD_DIR)

log:
	@echo $(ROOT_DIR)

.PHONY: all run clean log