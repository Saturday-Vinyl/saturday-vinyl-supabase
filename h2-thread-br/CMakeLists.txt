# Saturday Vinyl Hub - ESP32-H2 Thread Border Router Firmware
# ESP-IDF Project CMakeLists.txt

cmake_minimum_required(VERSION 3.16)

# Include component directories
set(EXTRA_COMPONENT_DIRS
    ${CMAKE_CURRENT_SOURCE_DIR}/components
    ${CMAKE_CURRENT_SOURCE_DIR}/../shared
)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)

project(sv-hub-h2-thread-br)
