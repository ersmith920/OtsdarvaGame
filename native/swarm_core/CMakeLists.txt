cmake_minimum_required(VERSION 3.17)
project(swarm_core LANGUAGES CXX)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp godot-cpp)

add_library(swarm_core SHARED src/swarm_core.cpp src/gold_core.cpp src/register_types.cpp)
target_link_libraries(swarm_core PRIVATE godot-cpp)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set_target_properties(swarm_core PROPERTIES
    CXX_STANDARD 17
    CXX_EXTENSIONS OFF
    CXX_VISIBILITY_PRESET hidden
    POSITION_INDEPENDENT_CODE ON
    PREFIX "lib"
    OUTPUT_NAME "swarm_core${GODOTCPP_SUFFIX}"
)
if(MINGW)
    target_link_options(swarm_core PRIVATE -static -static-libgcc -static-libstdc++)
endif()
