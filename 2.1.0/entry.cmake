# Set the policies for the range of supported CMake versions
cmake_policy(PUSH)
cmake_minimum_required(VERSION 3.13.0...3.21.4)

if(NOT DEFINED _PMM_BOOTSTRAP_VERSION OR _PMM_BOOTSTRAP_VERSION LESS 4)
    message(FATAL_ERROR
            "Using PMM ${PMM_VERSION} requires updating the pmm.cmake bootstrap script. "
            "Visit the PMM repository to obtain a new copy of pmm.cmake for your project.")
endif()

# Unset variables that may be affected by a version change
if(NOT PMM_VERSION STREQUAL PMM_PRIOR_VERSION)
    foreach(var IN ITEMS PMM_CONAN_EXECUTABLE)
        unset(${var} CACHE)
    endforeach()
endif()
set(PMM_PRIOR_VERSION "${PMM_VERSION}" CACHE STRING "Previous version of PMM in the source tree" FORCE)

function(_pmm_log arg)
    string(REPLACE ";" " " msg "${ARGN}")
    if(arg STREQUAL DEBUG)
        if(PMM_DEBUG)
            message(STATUS "[pmm] [debug  ] ${ARGN}")
        endif()
    elseif(arg STREQUAL VERBOSE)
        if(PMM_DEBUG OR PMM_VERBOSE)
            message(STATUS "[pmm] [verbose] ${ARGN}")
        endif()
    elseif(arg STREQUAL WARNING)
        message(STATUS "[pmm] [warn   ] ${ARGN}")
    else()
        message(STATUS "[pmm] ${ARGV}")
    endif()
endfunction()

function(_pmm_download url dest)
    cmake_parse_arguments(ARG "NO_CHECK" "RESULT_VARIABLE" "" "${ARGN}")
    set(tmp "${dest}.tmp")
    _pmm_log(DEBUG "Downloading ${url}")
    _pmm_log(DEBUG "File will be written to ${dest}")
    file(
        DOWNLOAD "${url}"
        "${tmp}"
        STATUS st
        )
    list(GET st 0 rc)
    list(GET st 1 msg)
    _pmm_log(DEBUG "Download status [${rc}]: ${msg}")
    if(rc)
        file(REMOVE "${tmp}")
        if(NOT ARG_NO_CHECK)
            message(FATAL_ERROR "Error while downloading file from '${url}' to '${dest}' [${rc}]: ${msg}")
        endif()
        _pmm_log(VERBOSE "Failed to download file ${url}: [${rc}]: ${msg}")
        if(ARG_RESULT_VARIABLE)
            set("${ARG_RESULT_VARIABLE}" FALSE PARENT_SCOPE)
        endif()
    else()
        file(RENAME "${tmp}" "${dest}")
        _pmm_log(VERBOSE "Downloaded file ${url} to ${dest}")
        if(ARG_RESULT_VARIABLE)
            set("${ARG_RESULT_VARIABLE}" TRUE PARENT_SCOPE)
        endif()
    endif()
endfunction()

macro(_pmm_check_and_include_file filename)
    get_filename_component(_dest "${PMM_DIR}/${filename}" ABSOLUTE)
    if(NOT EXISTS "${_dest}" OR PMM_ALWAYS_DOWNLOAD)
        _pmm_download("${PMM_URL}/${filename}" "${_dest}")
    endif()
    include("${_dest}")
endmacro()

# Download the required modules
_pmm_check_and_include_file(util.cmake)
_pmm_check_and_include_file(main.cmake)

# Do the update check.
function(_pmm_check_updates)
    set(_latest_info_url "${PMM_URL_BASE}/latest-info.cmake")
    set(_latest_info_file "${PMM_DIR}/latest-info.cmake")
    file(DOWNLOAD "${_latest_info_url}" "${_latest_info_file}" STATUS did_download TIMEOUT 5)
    list(GET did_download 0 rc)
    if(rc EQUAL 0)
        include("${_latest_info_file}")
        _pmm_lift(PMM_LATEST_VERSION)
    else()
        if(NOT PMM_IGNORE_NEW_VERSION)
            _pmm_log("Failed to check for updates (Couldn't download ${_latest_info_url})")
        endif()
    endif()
endfunction()

_pmm_check_updates()

if(CMAKE_SCRIPT_MODE_FILE)
    _pmm_script_main()
endif()

# Restore prior policy settings before returning to our includer
cmake_policy(POP)
