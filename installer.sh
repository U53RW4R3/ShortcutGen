#!/usr/bin/env bash

set -euo pipefail

BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
RESET="\033[0m"

# Set the WINEPREFIX_DIRECTORY to the user's home directory
WINEPREFIX_DIRECTORY="${HOME}/.local/share/shortcutgen"
WINE_DEBUG="-all"
WINE_ARCHITECTURE="win64"
WINDOWS_VERSION="win11"

# Set the repository to download the software
GITHUB_DOMAIN="github.com"
GITHUB_URL="https://${GITHUB_DOMAIN}"
GITHUB_API_URL="https://api.${GITHUB_DOMAIN}"
GITHUB_REPOSITORY_API_URI="${GITHUB_API_URL}/repos"

function check_bash_version() {
    local major=5

    ((BASH_VERSINFO[0] >= "${major}")) && return 0
}

function check_program() {
    type -P "${1}" 2>/dev/null
}

function puts() {
    local string="${1}"

    echo -e "${string}"
}

function info() {
    local text="${1}"
    local color="${BLUE}[*]${RESET}"

    puts "${color} ${text}"
}

function fin() {
    local text="${1}"
    local color="${GREEN}[*]${RESET}"

    puts "${color} ${text}"
}

function fail() {
    local text="${1}"
    local color="${RED}[*]${RESET}"

    puts "${color} ${text}"
}

function quit() {
    local code="${1}"

    ((code != 0)) && info "Terminating program..."
    exit "${1}"
}

function get_file_type() {
    file -b --mime-type "${1}" 2>/dev/null
}

function temporary_file() {
    mktemp 2>/dev/null
}

function invoke_as() {
    local commands="${1}"

    if [[ -n $(check_program "sudo") ]]
    then
        eval "sudo ${commands}"
    elif [[ -n $(check_program "doas") ]]
    then
        eval "doas ${commands}"
    fi
}

function delete_file() {
    local file="${1}"

    if [[ -w "${file}" ]]
    then
        if [[ -d "${file}" ]] # Delete the directory
        then
            rm -rf "${file}" 2>/dev/null
        elif [[ -e "${file}" ]] # Delete any kind of file
        then
            rm -f "${file}" 2>/dev/null
        fi
    else
        if [[ -d "${file}" ]] # Delete the directory
        then
            invoke_as "rm -rf '${file}' 2>/dev/null"
        elif [[ -h "${file}" ]] # Delete the symbolic link file
        then
            invoke_as "rm -rf '${file}' 2>/dev/null"
        elif [[ -e "${file}" ]] # Delete any kind of file
        then
            invoke_as "rm -f '${file}' 2>/dev/null"
        fi
    fi
}

function web_request() {
    local url="${1}"
    local output="${2:-}"
    local -a execute=()

    if [[ -n $(check_program "curl") ]]
    then
        execute+=("curl")
        if [[ -z "${output}" ]] # Retrieve web content
        then
            execute+=("-s" "'${url}'")
        else # Download file
            execute+=("-sLo" "'${output}'" "'${url}'")
        fi
    elif [[ -n $(check_program "wget") ]]
    then
        execute+=("wget")
        if [[ -z "${output}" ]] # Retrieve web content
        then
            execute+=("-qO-" "'${url}'")
        else # Download file
            execute+=("-qO-" "'${output}'" "'${url}'")
        fi
    fi

    eval "${execute[*]}"
}
# Download the file and verify it's format
function download_and_verify() {
    local url="${1}"
    local output_file="${2}"
    local file_format="${3}"
    local retries=2
    local file_type

    for ((i = 0; i < retries; i++))
    do
        web_request "${url}" "${output_file}"
        file_type="$(get_file_type "${output_file}")"

        if [[ "${file_type}" == "${file_format}" ]]
        then
            return 0
        fi

        if ((i == retries))
        then
            return 1
        fi
    done
}

function install_powershell() {
    local repository="${GITHUB_REPOSITORY_API_URI}/PowerShell/PowerShell/releases/latest"
    local response=$(web_request "${repository}")
    local pattern="\"browser_download_url\":\ *\"([^\"]+)\"(.*)"
    local installer="$(temporary_file)"
    local artifacts
    local file_type

    function setup_wineprefix() {
        if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
        then
            info "Creating a WINEPREFIX directory in '${WINEPREFIX_DIRECTORY}'"
            mkdir "${WINEPREFIX_DIRECTORY}"
        fi

        if [[ "${HOSTTYPE}" == "x86_64" ]]
        then
            info "Configuring wine directory with the latest version of Windows..."
            eval "WINEDEBUG=${WINE_DEBUG} WINEARCH=${WINE_ARCHITECTURE} WINEPREFIX='${WINEPREFIX_DIRECTORY}' winecfg /v ${WINDOWS_VERSION} &>/dev/null"

            info "Initializing wine directory..."
            eval "WINEDEBUG=${WINE_DEBUG} WINEARCH=${WINE_ARCHITECTURE} WINEPREFIX='${WINEPREFIX_DIRECTORY}' wineboot -u &>/dev/null"
        else
            fail "x86_64 (64-bit) architecture is only supported!"
            quit 1
        fi
    }

    setup_wineprefix

    info "Fetching latest PowerShell release..."
    while [[ "${response}" =~ ${pattern} ]]
    do
        artifacts+="${BASH_REMATCH[1]}"$'\n'
        response="${BASH_REMATCH[2]}"
    done

    # Remove trailing newline
    artifacts=${artifacts%$'\n'}

    # Extract version from URL path and remove the 'v' prefix
    local latest_version=$(cut -d '/' -f 8 <<< "${artifacts}" | head -n 1)
    latest_version=${latest_version#v}

    local filename="PowerShell-${latest_version}-win-x64.msi"

    # Convert artifacts to array for proper iteration
    local -a urls=(${artifacts})

    for url in "${urls[@]}"
    do
        for ((i = 0; i < 2; i++))
        do
            if [[ "${url}" == *"${filename}"* ]]
            then
                download_and_verify "${url}" "${installer}" "application/x-msi"
                if ((${?} == 0))
                then
                    break
                else
                    fail "PowerShell installer not found! Please try again."
                    quit 1
                fi
            fi
        done
    done

    if [[ -f "${installer}" ]]
    then
        info "Installing PowerShell..."
        eval "WINEDEBUG=${WINE_DEBUG} WINEARCH=${WINE_ARCHITECTURE} WINEPREFIX='${WINEPREFIX_DIRECTORY}' wine msiexec.exe /package '${installer}' /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1 &>/dev/null"
        delete_file "${installer}"
        fin "PowerShell Installed!"
    else
        fail "PowerShell installer not found! Please try again."
        quit 1
    fi
}

function install_packages() {
    local -a programs=("${@}")

    if [[ -f "/etc/debian_version" ]]
    then
        invoke_as "DEBIAN_FRONTEND=noninteractive apt update -qq"
        invoke_as "DEBIAN_FRONTEND=noninteractive apt install -yqq ${programs[*]}"
    elif [[ -f "/etc/fedora-release" || -f "/etc/openmandriva-release" ]]
    then
        invoke_as "dnf update"
        invoke_as "dnf install -y ${programs[*]}"
    elif [[ -f "/etc/SuSE-release" ]]
    then
        invoke_as "zypper refresh"
        invoke_as "zypper install -y ${programs[*]}"
    elif [[ -f "/etc/redhat-release" ]]
    then
        if [[ -n $(check_program "yum") ]]
        then
            invoke_as "yum update"
            invoke_as "yum install -y ${programs[*]}"
        elif [[ -n $(check_program "dnf") ]]
        then
            invoke_as "dnf update"
            invoke_as "dnf install -y ${programs[*]}"
        fi
    elif [[ -f "/etc/void-release" ]]
    then
        invoke_as "xbps-install -S"
        invoke_as "xbps-install -y ${programs[*]}"
    elif [[ -f "/etc/arch-release" ]]
    then
        invoke_as "pacman -Sy"
        invoke_as "pacman -S --noconfirm ${programs[*]}"
    elif [[ -f "/etc/NIXOS" ]]
    then
        invoke_as "nix-channel --update"
        invoke_as "nix-env -iA ${program[*]}"
    elif [[ -f "/etc/gentoo-release" ]]
    then
        invoke_as "emerge --sync"
        invoke_as "emerge --quiet --ask=0 ${programs[*]}"
    elif [[ -f "/etc/alpine-release" ]]
    then
        invoke_as "apk update"
        invoke_as "apk add --no-cache --quiet ${program[*]}"
    fi
}

function check_distro() {
    function check_i386() {
        local file="/var/lib/dpkg/arch"
        local is_enabled="false"

        info "Debian-based distro detected! Checking if i386 (32-bit) architecture is enabled..."
        if [[ -f "${file}" ]]
        then
            while read -r line
            do
                if [[ "${line}" == "i386" ]]
                then
                    info "i386 (32-bit) architecture is already enabled! Skipping..."
                    is_enabled="true"
                    break
                fi
            done < "${file}"
        fi

        if [[ "${is_enabled}" == "false" ]]
        then
            info "i386 (32-bit) architecture has been disabled! Enabling..."
            invoke_as "dpkg --add-architecture i386"
        fi
    }

    source "/etc/os-release"
    if [[ -f "/etc/debian_version" ]]
    then
        if [[ "${ID}" == "debian" || "${ID_LIKE}" == "debian" ]]
        then
            check_i386
        fi
    fi
}

function check_dependencies() {
    local -a programs=("desktop-file-edit" "wine")
    local -a powershell=("${WINEPREFIX_DIRECTORY}/drive_c/Program Files/PowerShell/"*/pwsh.exe)
    local -a packages=()

    if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
    then
        info "Creating directory: ${WINEPREFIX_DIRECTORY}"
        mkdir "${WINEPREFIX_DIRECTORY}"
    fi

    check_distro

    for program in "${programs[@]}"
    do
        if [[ "${program}" == "wine" ]]
        then
            if [[ -f "/etc/debian_version" ]]
            then
                if [[ "${ID}" == "debian" || "${ID_LIKE}" == "debian" ]]
                then
                    packages+=("${program}")
                    packages+=("wine32")
                    packages+=("wine64")
                else
                    packages+=("${program}")
                fi
            elif [[ -f "/etc/NIXOS" ]]
            then
                packages+=("nixpkgs.${program}")
            else
                packages+=("${program}")
            fi
        elif [[ "${program}" == "desktop-file-edit" ]]
        then
            packages+=("desktop-file-utils")
        else
            packages+=("${program}")
        fi
    done

    if ((${#packages[@]} > 0))
    then
        info "Installing necessary packages..."
        install_packages "${packages[@]}"
    fi

    shopt -s nullglob
    [[ ! -f "${powershell[0]}" ]] && install_powershell
    shopt -u nullglob
}

function install_software() {
    local program="shortcutgen"
    local source="/usr/local/src/${program}.sh"
    local destination="/usr/local/bin/${program}"
    local repository="U53RW4R3/ShortcutGen"
    local url="${GITHUB_URL}/${repository}/releases/latest/download/${program}.sh"
    local file="$(temporary_file)"
    local file_type

    info "Installing ShortcutGen..."

    download_and_verify "${url}" "${file}" "text/x-shellscript"
    if ((${?} != 0))
    then
        fail "ShortcutGen is not installed! Please try again."
        quit 1
    fi

    invoke_as "install -m 755 '${file}' '${source}'"
    delete_file "${file}"
    invoke_as "ln -sf '${source}' '${destination}'"
    invoke_as "chmod 755 '${destination}'"

    if [[ -f "${source}" && -f "${destination}" ]]
    then
        fin "The installation is a success!"
    else
        fail "The installation has failed! Please try again."
    fi
}

function uninstall_software() {
    local program="shortcutgen"
    local source_file="/usr/local/src/${program}.sh"
    local symlink_file="/usr/local/bin/${program}"

    info "Uninstalling ShortcutGen..."

    if [[ -e "${source_file}" ]]
    then
        delete_file "${source_file}"
    fi

    if [[ -h "${symlink_file}" ]]
    then
        delete_file "${symlink_file}"
    fi

    if [[ -d "${WINEPREFIX_DIRECTORY}" ]]
    then
        delete_file "${WINEPREFIX_DIRECTORY}"
    fi

    fin "ShortcutGen has been uninstalled!"
}

function usage() {
    puts "Usage: installer.sh <flag>
    --install                           Install the software (can also be used to reinstall).
    --remove                            Uninstall the software.
    -h, --help                          Display the help menu."
    quit 0
}

function main() {
    check_bash_version
    if ((${?} != 0))
    then
        fail "The program requires GNU Bash version 5 or later!"
        quit 0
    fi

    ((${#} == 0)) && usage

    while ((${#} > 0))
    do
        case "${1}" in
            --install)
                check_dependencies
                install_software
                shift
                ;;
            --remove)
                uninstall_software
                shift
                ;;
            -h | --help)
                usage
                ;;
            *)
                fail "Invalid option: ${1}" >&2
                quit 1
                ;;
        esac
    done
}

main "${@}"
