function(_pmm_read_script_argv var)
    set(got_p FALSE)
    set(got_script FALSE)
    set(ret)
    foreach(i RANGE "${CMAKE_ARGC}")
        set(arg "${CMAKE_ARGV${i}}")
        if(got_p)
            if(got_script)
                list(APPEND ret "${arg}")
            else()
                set(got_script TRUE)
            endif()
        elseif(arg STREQUAL "-P")
            set(got_p TRUE)
        endif()
    endforeach()
    set("${var}" "${ret}" PARENT_SCOPE)
endfunction()

# Argument parser helper. This may look like magic, but it is pretty simple:
# - Call this at the top of a function
# - It takes three "list" arguments: `.`, `-` and `+`.
# - The `.` arguments specify the "option/boolean" values to parse out.
# - The `-` arguments specify the one-value arguments to parse out.
# - The `+` argumenst specify mult-value arguments to parse out.
# - Specify `-nocheck` to disable warning on unparse arguments.
# - Parse values are prefixed with `ARG`
#
# This macro makes use of some very horrible aspects of CMake macros:
# - Values appear the caller's scope, so no need to set(PARENT_SCOPE)
# - The ${${}ARGN} eldritch horror evaluates to the ARGN *OF THE CALLER*, while
#   ${ARGN} evaluates to the macro's own ARGN value. This is because ${${}ARGN}
#   inhibits macro argument substitution. It is painful, but it makes this magic
#   work.
macro(_pmm_parse_args)
    cmake_parse_arguments(_ "-nocheck;-hardcheck" "" ".;-;+" "${ARGN}")
    set(__arglist "${${}ARGN}")
    _pmm_parse_arglist("${__.}" "${__-}" "${__+}")
endmacro()

macro(_pmm_parse_script_args)
    cmake_parse_arguments(_ "-nocheck;-hardcheck" "" ".;-;+" "${ARGV}")
    _pmm_read_script_argv(__arglist)
    _pmm_parse_arglist("${__.}" "${__-}" "${__+}")
endmacro()

macro(_pmm_parse_arglist opt args list_args)
    cmake_parse_arguments(ARG "${opt}" "${args}" "${list_args}" "${__arglist}")
    if(NOT __-nocheck)
        foreach(arg IN LISTS ARG_UNPARSED_ARGUMENTS)
            message(WARNING "Unknown argument: ${arg}")
        endforeach()
        if(__-hardcheck AND NOT ("${ARG_UNPARSED_ARGUMENTS}" STREQUAL ""))
            message(FATAL_ERROR "Unknown arguments provided.")
        endif()
    endif()
endmacro()

macro(_pmm_lift)
    foreach(varname IN ITEMS ${ARGN})
        set("${varname}" "${${varname}}" PARENT_SCOPE)
    endforeach()
endmacro()

function(_pmm_exec)
    if(PMM_DEBUG)
        set(acc)
        foreach(arg IN LISTS ARGN)
            if(arg MATCHES " |\\\"|\\\\")
                string(REPLACE "\"" "\\\"" arg "${arg}")
                string(REPLACE "\\" "\\\\" arg "${arg}")
                set(arg "\"${arg}\"")
            endif()
            string(APPEND acc "${arg} ")
        endforeach()
        _pmm_log(DEBUG "Executing command: ${acc}")
    endif()
    set(output_args)
    if(NOT NO_EAT_OUTPUT IN_LIST ARGN)
        set(output_args
            OUTPUT_VARIABLE out
            ERROR_VARIABLE out
            )
    endif()
    list(FIND ARGN WORKING_DIRECTORY wd_kw_idx)
    set(wd_arg)
    if(wd_kw_idx GREATER -1)
        math(EXPR wd_idx "${wd_kw_idx} + 1")
        list(GET ARGN "${wd_idx}" wd_dir)
        LIST(REMOVE_AT ARGN "${wd_idx}" "${wd_kw_idx}")
        set(wd_arg WORKING_DIRECTORY "${wd_dir}")
    endif()
    list(REMOVE_ITEM ARGN NO_EAT_OUTPUT)
    execute_process(
        COMMAND ${ARGN}
        ${output_args}
        RESULT_VARIABLE rc
        ${wd_arg}
        )
    set(_PMM_RC "${rc}" PARENT_SCOPE)
    set(_PMM_OUTPUT "${out}" PARENT_SCOPE)
endfunction()


function(_pmm_write_if_different filepath content)
    set(do_write FALSE)
    if(NOT EXISTS "${filepath}")
        set(do_write TRUE)
    else()
        file(READ "${filepath}" cur_content)
        if(NOT cur_content STREQUAL content)
            set(do_write TRUE)
        endif()
    endif()
    if(do_write)
        _pmm_log(DEBUG "Updating contents of file: ${filepath}")
        get_filename_component(pardir "${filepath}" DIRECTORY)
        file(MAKE_DIRECTORY "${pardir}")
        file(WRITE "${filepath}" "${content}")
    else()
        _pmm_log(DEBUG "Contents of ${filepath} are up-to-date")
    endif()
    set(_PMM_DID_WRITE "${do_write}" PARENT_SCOPE)
endfunction()


function(_pmm_get_var_from_file filepath varname)
    include(${filepath})
    get_property(propt VARIABLE PROPERTY ${varname})
    set(${varname} ${propt} PARENT_SCOPE)
endfunction()


function(_pmm_generate_cli_scripts force)
    # The sh scipt
    if(NOT EXISTS "${CMAKE_BINARY_DIR}/pmm-cli.sh" OR ${force})
        file(WRITE "${_PMM_USER_DATA_DIR}/pmm-cli.sh" "#!/bin/sh\n${CMAKE_COMMAND} -P ${PMM_MODULE} \"$@\"")
        # Fix to make the sh executable
        file(COPY "${_PMM_USER_DATA_DIR}/pmm-cli.sh"
             DESTINATION ${CMAKE_BINARY_DIR}
             FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
        )
    endif()
    # The bat scipt
    if(NOT EXISTS "${CMAKE_BINARY_DIR}/pmm-cli.bat" OR ${force})
        file(WRITE "${CMAKE_BINARY_DIR}/pmm-cli.bat" "@echo off\n\"${CMAKE_COMMAND}\" -P \"${PMM_MODULE}\" %*")
    endif()
endfunction()


function(_pmm_generate_shim name executable)
    # The sh scipt
    if (NOT EXISTS "${CMAKE_BINARY_DIR}/${name}.sh")
        file(WRITE "${_PMM_USER_DATA_DIR}/${name}.sh" "#!/bin/sh\n\"${executable}\" \"$@\"")
        # Fix to make the sh executable
        file(COPY "${_PMM_USER_DATA_DIR}/${name}.sh"
                DESTINATION ${CMAKE_BINARY_DIR}
                FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
                )
    endif ()
    # The bat scipt
    if (NOT EXISTS "${CMAKE_BINARY_DIR}/${name}.bat")
        file(WRITE "${CMAKE_BINARY_DIR}/${name}.bat" "@echo off\n\"${executable}\" %*")
    endif ()
endfunction()


function(_pmm_verbose_lock fpath)
    _pmm_parse_args(
        . DIRECTORY
        - FIRST_MESSAGE FAIL_MESSAGE RESULT_VARIABLE LAST_WAIT_DURATION
        )
    set(arg_dir)
    if(ARG_DIRECTORY)
        set(arg_dir "DIRECTORY")
    endif()
    if(NOT ARG_LAST_WAIT_DURATION)
        set(ARG_LAST_WAIT_DURATION 60)
    endif()
    set("${ARG_RESULT_VARIABLE}" TRUE PARENT_SCOPE)
    file(
        LOCK "${fpath}" ${arg_dir}
        GUARD PROCESS
        TIMEOUT 3
        RESULT_VARIABLE lock_res
        )
    if(NOT lock_res)
        return()
    endif()
    # Couldn't get the lock
    _pmm_log("${ARG_FIRST_MESSAGE}")
    file(
        LOCK "${fpath}" ${arg_dir}
        GUARD PROCESS
        TIMEOUT 60
        RESULT_VARIABLE lock_res
        )
    if(NOT lock_res)
        return()
    endif()
    _pmm_log("Unable to obtain lock after 60 seconds. We'll try for ${ARG_LAST_WAIT_DURATION} more seconds...")
    file(
        LOCK "${fpath}" ${arg_dir}
        GUARD PROCESS
        TIMEOUT "${ARG_LAST_WAIT_DURATION}"
        RESULT_VARIABLE lock_res
        )
    if(lock_res)
        message(WARNING "${ARG_FAIL_MESSAGE}")
        set("${ARG_RESULT_VARIABLE}" FALSE PARENT_SCOPE)
    endif()
endfunction()