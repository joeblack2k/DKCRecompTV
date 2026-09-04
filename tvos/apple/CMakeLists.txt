cmake_minimum_required(VERSION 3.20)

set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING
    "tvOS architecture" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0" CACHE STRING
    "Minimum tvOS version" FORCE)

project(DKCRecompTV LANGUAGES OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "tvOS")
    message(FATAL_ERROR
        "The isolated Apple app project requires CMAKE_SYSTEM_NAME=tvOS")
endif()

set(DKC2_TVOS_SDK "appletvos" CACHE STRING
    "Apple SDK used for the app and Metal library")
set(DKC2_TVOS_SDK_PATH "" CACHE PATH
    "Absolute path to the selected Apple SDK")
set(DKC2_TVOS_CORE_ARCHIVE "" CACHE FILEPATH
    "Absolute path to the separately built dkc2_tvos_core archive")
set(DKC2_SOURCE_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." CACHE PATH
    "DKC2 source root used for include paths and compiler path maps")
set(DKC2_BUNDLE_ID "tv.nijssen.DKC2RecompTV")
set(DKC2_PRODUCT_NAME "DKC2 Recomp TV")
set(DKC2_EXECUTABLE_NAME "DKCRecompTV")
set(DKC2_MARKETING_VERSION "0.1.0")
set(DKC2_BUILD_VERSION "1")

if(NOT DKC2_TVOS_SDK STREQUAL "appletvos" AND
   NOT DKC2_TVOS_SDK STREQUAL "appletvsimulator")
    message(FATAL_ERROR
        "DKC2_TVOS_SDK must be appletvos or appletvsimulator")
endif()
if(NOT DKC2_TVOS_CORE_ARCHIVE)
    message(FATAL_ERROR "DKC2_TVOS_CORE_ARCHIVE is required")
endif()
if(NOT IS_ABSOLUTE "${DKC2_TVOS_CORE_ARCHIVE}" OR
   NOT EXISTS "${DKC2_TVOS_CORE_ARCHIVE}")
    message(FATAL_ERROR
        "DKC2_TVOS_CORE_ARCHIVE must be an existing absolute path")
endif()
if(NOT DKC2_TVOS_SDK_PATH)
    execute_process(
        COMMAND xcrun --sdk "${DKC2_TVOS_SDK}" --show-sdk-path
        OUTPUT_VARIABLE DKC2_TVOS_SDK_PATH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE DKC2_SDK_PATH_RESULT
        ERROR_VARIABLE DKC2_SDK_PATH_ERROR)
    if(NOT DKC2_SDK_PATH_RESULT EQUAL 0)
        message(FATAL_ERROR
            "Could not resolve ${DKC2_TVOS_SDK}: ${DKC2_SDK_PATH_ERROR}")
    endif()
endif()
if(NOT IS_DIRECTORY "${DKC2_TVOS_SDK_PATH}")
    message(FATAL_ERROR
        "DKC2_TVOS_SDK_PATH does not exist: ${DKC2_TVOS_SDK_PATH}")
endif()
if(DKC2_TVOS_SDK STREQUAL "appletvos")
    set(DKC2_METAL_TARGET "air64-apple-tvos17.0")
else()
    set(DKC2_METAL_TARGET "air64-apple-tvos17.0-simulator")
endif()

get_filename_component(DKC2_SOURCE_ROOT "${DKC2_SOURCE_ROOT}" REALPATH)
get_filename_component(DKC2_TVOS_CORE_ARCHIVE
    "${DKC2_TVOS_CORE_ARCHIVE}" REALPATH)

file(READ "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist" DKC2_INFO_PLIST_CONTENT)
string(REPLACE "$(PRODUCT_BUNDLE_IDENTIFIER)" "${DKC2_BUNDLE_ID}"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
string(REPLACE "$(EXECUTABLE_NAME)" "${DKC2_EXECUTABLE_NAME}"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
string(REPLACE "$(PRODUCT_NAME)" "${DKC2_PRODUCT_NAME}"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
string(REPLACE "$(MARKETING_VERSION)" "${DKC2_MARKETING_VERSION}"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
string(REPLACE "$(CURRENT_PROJECT_VERSION)" "${DKC2_BUILD_VERSION}"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
string(REPLACE "<key>CFBundleDisplayName</key>\n  <string>DKCRecompTV</string>"
    "<key>CFBundleDisplayName</key>\n  <string>${DKC2_PRODUCT_NAME}</string>"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
if(DKC2_TVOS_SDK STREQUAL "appletvos")
    set(DKC2_PLIST_PLATFORM "AppleTVOS")
else()
    set(DKC2_PLIST_PLATFORM "AppleTVSimulator")
endif()
string(REPLACE "<plist version=\"1.0\">\n<dict>"
    "<plist version=\"1.0\">\n<dict>\n  <key>CFBundleSupportedPlatforms</key>\n  <array>\n    <string>${DKC2_PLIST_PLATFORM}</string>\n  </array>\n  <key>MinimumOSVersion</key>\n  <string>17.0</string>"
    DKC2_INFO_PLIST_CONTENT "${DKC2_INFO_PLIST_CONTENT}")
file(GENERATE
    OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
    CONTENT "${DKC2_INFO_PLIST_CONTENT}")
set(DKC2_PLATFORM_CONSTANT_SOURCE
    "${CMAKE_CURRENT_BINARY_DIR}/dkc2_platform_constants.mm")
file(GENERATE
    OUTPUT "${DKC2_PLATFORM_CONSTANT_SOURCE}"
    CONTENT [=[#import <CoreGraphics/CoreGraphics.h>
extern "C" const CGRect CGRectZero = {0, 0, 0, 0};
]=])

execute_process(
    COMMAND xcrun --sdk "${DKC2_TVOS_SDK}" --find metal
    OUTPUT_VARIABLE DKC2_METAL_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE DKC2_METAL_RESULT
    ERROR_VARIABLE DKC2_METAL_ERROR)
if(NOT DKC2_METAL_RESULT EQUAL 0)
    message(FATAL_ERROR "Could not find metal: ${DKC2_METAL_ERROR}")
endif()

execute_process(
    COMMAND xcrun --sdk "${DKC2_TVOS_SDK}" --find metallib
    OUTPUT_VARIABLE DKC2_METALLIB_COMPILER
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE DKC2_METALLIB_RESULT
    ERROR_VARIABLE DKC2_METALLIB_ERROR)
if(NOT DKC2_METALLIB_RESULT EQUAL 0)
    message(FATAL_ERROR "Could not find metallib: ${DKC2_METALLIB_ERROR}")
endif()

set(DKC2_METAL_AIR "${CMAKE_CURRENT_BINARY_DIR}/DKCTVShaders.air")
set(DKC2_METALLIB "${CMAKE_CURRENT_BINARY_DIR}/default.metallib")

add_custom_command(
    OUTPUT "${DKC2_METAL_AIR}"
    COMMAND "${DKC2_METAL_COMPILER}"
        -c "${CMAKE_CURRENT_SOURCE_DIR}/DKCTVShaders.metal"
        -o "${DKC2_METAL_AIR}"
        -target "${DKC2_METAL_TARGET}"
        -isysroot "${DKC2_TVOS_SDK_PATH}"
    DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/DKCTVShaders.metal"
    COMMENT "Compiling the tvOS Metal shader"
    VERBATIM)

add_custom_command(
    OUTPUT "${DKC2_METALLIB}"
    COMMAND "${DKC2_METALLIB_COMPILER}"
        "${DKC2_METAL_AIR}"
        -o "${DKC2_METALLIB}"
    DEPENDS "${DKC2_METAL_AIR}"
    COMMENT "Linking the tvOS Metal library"
    VERBATIM)

add_custom_target(dkc2_default_metallib
    DEPENDS "${DKC2_METALLIB}")

add_library(dkc2_tvos_core STATIC IMPORTED GLOBAL)
set_target_properties(dkc2_tvos_core PROPERTIES
    IMPORTED_LOCATION "${DKC2_TVOS_CORE_ARCHIVE}"
    INTERFACE_INCLUDE_DIRECTORIES
        "${DKC2_SOURCE_ROOT}/tvos/include")

add_executable(DKCRecompTV MACOSX_BUNDLE
    "${CMAKE_CURRENT_SOURCE_DIR}/DKCTVApp.mm"
    "${DKC2_PLATFORM_CONSTANT_SOURCE}")
add_dependencies(DKCRecompTV dkc2_default_metallib)

target_include_directories(DKCRecompTV PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${DKC2_SOURCE_ROOT}/tvos/include")
target_compile_definitions(DKCRecompTV PRIVATE
    DKC_CORE_FUNCTION=dkc2_game_core)
target_compile_options(DKCRecompTV PRIVATE
    "-fobjc-arc"
    "-ffile-prefix-map=${DKC2_SOURCE_ROOT}=."
    "-fdebug-prefix-map=${DKC2_SOURCE_ROOT}=."
    "-fmacro-prefix-map=${DKC2_SOURCE_ROOT}=.")
target_link_libraries(DKCRecompTV PRIVATE
    dkc2_tvos_core
    "-framework UIKit"
    "-framework Metal"
    "-framework MetalKit"
    "-framework QuartzCore"
    "-framework AVFAudio"
    "-framework GameController"
    "-framework Foundation")
target_link_options(DKCRecompTV PRIVATE
    "-Wl,-force_load,${DKC2_TVOS_CORE_ARCHIVE}")

set_target_properties(DKCRecompTV PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_BINARY_DIR}/Info.plist"
    MACOSX_BUNDLE_BUNDLE_NAME "${DKC2_PRODUCT_NAME}"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${DKC2_BUNDLE_ID}"
    MACOSX_BUNDLE_BUNDLE_VERSION "${DKC2_BUILD_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${DKC2_MARKETING_VERSION}"
    OUTPUT_NAME "${DKC2_EXECUTABLE_NAME}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${DKC2_BUNDLE_ID}"
    XCODE_ATTRIBUTE_PRODUCT_NAME "${DKC2_PRODUCT_NAME}"
    XCODE_ATTRIBUTE_EXECUTABLE_NAME "${DKC2_EXECUTABLE_NAME}"
    XCODE_ATTRIBUTE_MARKETING_VERSION "${DKC2_MARKETING_VERSION}"
    XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION "${DKC2_BUILD_VERSION}"
    XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "17.0"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "3"
    XCODE_ATTRIBUTE_INFOPLIST_KEY_CFBundleDisplayName "${DKC2_PRODUCT_NAME}"
    XCODE_ATTRIBUTE_INFOPLIST_KEY_CFBundleName "${DKC2_PRODUCT_NAME}"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    XCODE_ATTRIBUTE_AD_HOC_CODE_SIGNING_ALLOWED "NO"
    XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY ""
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "")

add_custom_command(TARGET DKCRecompTV POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${DKC2_METALLIB}"
        "$<TARGET_BUNDLE_DIR:DKCRecompTV>/default.metallib"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_SOURCE_DIR}/PrivacyInfo.xcprivacy"
        "$<TARGET_BUNDLE_DIR:DKCRecompTV>/PrivacyInfo.xcprivacy"
    VERBATIM)
