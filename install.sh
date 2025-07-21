#!/bin/bash

set -euo pipefail

BLUE="\033[1;34m"
GREEN="\033[1;32m"
RED="\033[1;31m"
RESET="\033[0m"

# Set the WINEPREFIX_DIRECTORY to the user's home directory
WINEPREFIX_DIRECTORY="${HOME}/.wine"
GITHUB_REPOSITORY_API_URL="https://api.github.com/repos"

function check_bash_version() {
    local major=5
    local minor=3

    ((BASH_VERSINFO[0] >= "${major}" && BASH_VERSINFO[1] >= "${minor}")) && return 0
}

function check_program() {
    type -P "${1}" 2>/dev/null
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

function install_powershell() {
    local repository="${GITHUB_REPOSITORY_API_URL}/PowerShell/PowerShell/releases/latest"
    local response=$(curl -s "${repository}")
    local pattern="\"browser_download_url\":\ *\"([^\"]+)\"(.*)"
    local installer=""
    local artifacts=""

    function setup_wineprefix() {
        if [[ ! -d "${WINEPREFIX_DIRECTORY}" ]]
        then
            info "Creating a WINEPREFIX directory in '${WINEPREFIX_DIRECTORY}'"
            mkdir "${WINEPREFIX_DIRECTORY}"
        fi

        if [[ "${HOSTTYPE}" == "x86_64" ]]
        then
            info "Configuring wine directory with the latest version of Windows..."
            eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' winecfg /v win11 &>/dev/null"

            info "Initializing wine directory..."
            eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' wineboot -u &>/dev/null"
        else
            error "x86_64 (64-bit) architecture is only supported!"
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
        if [[ "${url}" == *"${filename}"* ]]
        then
            installer=$(basename "${url}")
            [[ -f "${installer}" ]] && rm -f "${installer}"
            invoke_as "curl -sLo '${installer}' '${url}'"
            break
        fi
    done

    if [[ -f "${installer}" ]]
    then
        info "Installing PowerShell..."
        eval "WINEDEBUG=-all WINEARCH=win64 WINEPREFIX='${WINEPREFIX_DIRECTORY}' wine msiexec.exe /package '${installer}' /quiet ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 USE_MU=1 ENABLE_MU=1 ADD_PATH=1 &>/dev/null"
        rm -f "${installer}"
        fin "PowerShell Installed!"
    else
        error "PowerShell installer not found! Please try again."
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

        info "Debian-based distro detected! Checking if i386 (32-bit) architecture is enabled..."
        while read -r line
        do
            if [[ "${line}" == "i386" ]]
            then
                info "i386 (32-bit) architecture is already enabled! Skipping..."
                break
            else
                info "i386 (32-bit) architecture has been disabled! Enabling..."
                invoke_as "dpkg --add-architecture i386"
            fi
        done < "${file}"
    }

    source -p "/etc/" "os-release"
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
        info "Creating directory: ${WINEPREFIX_DIRECTORY}."
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
                    packages+=("wine-mono")
                else
                    packages+=("${program}")
                    packages+=("wine-mono")
                fi
            elif [[ -f "/etc/NIXOS" ]]
            then
                packages+=("nixpkgs.${program}")
                packages+=("nixpkgs.${program}Mono")
            else
                packages+=("${program}")
                packages+=("wine-mono")
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

function main() {
    local program="shortcutgen"
    local source="/usr/local/src/${program}.sh"
    local destination="/usr/local/bin/${program}"
    local filename="${program}.sh"
    local repository="${GITHUB_REPOSITORY_API_URL}/U53RW4R3/ShortcutGen/releases/latest"
    local response=$(curl -s "${repository}")
    local pattern="\"browser_download_url\":\ *\"([^\"]+)\"(.*)"
    local artifacts=""

    if [[ ! $(check_bash_version) ]]
    then
        error "The program requires GNU Bash version 5.3 or later!"
        quit 1
    fi

    check_dependencies

    info "Installing ShortcutGen..."
    [[ -f "${source}" ]] && sudo rm -f "${source}" 2>/dev/null

    while [[ "${response}" =~ ${pattern} ]]
    do
        artifacts+="${BASH_REMATCH[1]}"$'\n'
        response="${BASH_REMATCH[2]}"
    done

    artifacts=${artifacts%$'\n'}

    local -a urls=(${artifacts})

    for url in "${urls[@]}"
    do
        if [[ "${url}" == *"${filename}"* ]]
        then
            file=$(basename "${url}")
            [[ -f ${source} ]] && rm -f "${source}"
            invoke_as "curl -sLo '${source}' '${url}'"
            break
        fi
    done

    invoke_as "chmod 755 '${source}'"

    if [[ -f "${destination}" || ! -f "${destination}" ]]
    then
        invoke_as "ln -sf '${source}' '${destination}'"
        invoke_as "chmod 755 '${destination}'"
    fi

    if [[ -f "${source}" && -f "${destination}" ]]
    then
        fin "The installation is a success!"
    else
        error "The installation has failed! Please try again."
    fi
}

main
