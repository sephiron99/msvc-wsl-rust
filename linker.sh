#!/bin/bash

# script_path="$(dirname "${BASH_SOURCE[0]}")"
script_path="$(realpath "${BASH_SOURCE[0]}")"
script_path="$(dirname "${script_path}")"

source "$script_path/config.sh"

host=x64
target=${TARGET_ARCH:=x64}

msvc_path="C:\\Program Files (x86)\\Microsoft Visual Studio\\$vs_version\\BuildTools\\VC\\Tools\\MSVC"
kits_path="C:\\Program Files (x86)\\Windows Kits"

linker_exec="$msvc_path\\$tools_version\\bin\\Host$host\\$target\\link.exe"

sdk_libs="$kits_path\\10\\Lib\\$sdk_version\\um\\$target\\"
ucrt_libs="$kits_path\\10\\Lib\\$sdk_version\\ucrt\\$target\\"
crt_libs="$msvc_path\\$tools_version\\lib\\$target\\"

# 실행마다 작업 directory를 따로 쓴다. cargo는 여러 binary를 동시에 link하므로, 고정된 이름의
# 파일을 쓰면 서로의 명령과 인자를 덮어쓴다. 끝나면 last-linking.* 로 옮겨 마지막 기록을 남긴다.
work_dir="$(mktemp -d "$script_path/linking.XXXXXX")" || exit 1
script_file="$work_dir/linking.ps1"
args_file="$work_dir/linking-args.txt"
log_file_local="$work_dir/linking.log"

echo "\$env:LIB=\"$sdk_libs;$ucrt_libs;$crt_libs\"" > "$script_file"

path_l2w()
{
        echo "\\\\wsl\$\\$wsl_distro$(echo "$1" | sed "s/\//\\\\/g")"
}

args=""
# rustc가 /OUT: 으로 넘긴 결과물의 Linux 경로. link 뒤에 실행 권한을 주는 데 쓴다.
output_file=""

for v in "$@"; do
        case "$v" in
                /OUT:*) output_file="${v#/OUT:}" ;;
        esac
        num_of_slash=`tr -dc '/' <<< "$v" | wc -c`
        num_of_colon=`tr -dc ':' <<< "$v" | wc -c`
        if [ "$num_of_slash" -gt "1" ] && [ "$num_of_colon" -eq "0" ]; then
                v="$(path_l2w "$v")"
        fi
        if [ "$num_of_slash" -gt "1" ] && [ "$num_of_colon" -eq "1" ]; then
                v1="$(echo "$v" | cut -d ':' -f 1)"
                v2="$(echo "$v" | cut -d ':' -f 2)"
                v2="$(path_l2w "$v2")"
                v="$v1:$v2"
        fi
        args="$args $v"
done

log_file="$(path_l2w "$log_file_local")"

commands_file="$(path_l2w "$args_file")"
echo "$args" > "$args_file"

echo "& \"$linker_exec\" \"@$commands_file\" | Out-file \"$log_file\"" >> "$script_file"
# link.exe 종료코드를 powershell 프로세스 종료코드로 전파한다.
# (네이티브 명령을 Out-File로 파이프해도 $LASTEXITCODE 에는 link.exe 의 종료코드가 남는다.)
echo 'exit $LASTEXITCODE' >> "$script_file"

powershell.exe -ExecutionPolicy Bypass -Command "$script_file"
status=$?

# link.exe는 Windows 쪽에서 파일을 만들어 Linux 실행 권한 bit가 없다. WSL에서 결과물을 바로
# 실행할 수 있도록 권한을 준다. 실패해도 link 결과는 바꾸지 않는다.
if [ "$status" -eq 0 ] && [ -n "$output_file" ] && [ -f "$output_file" ]; then
        chmod +x "$output_file" 2>/dev/null
fi

# 마지막 link의 기록을 고정된 이름으로 남기고 작업 directory를 치운다.
mv -f "$script_file" "$script_path/last-linking.ps1" 2>/dev/null
mv -f "$args_file" "$script_path/last-linking-args.txt" 2>/dev/null
[ -f "$log_file_local" ] && mv -f "$log_file_local" "$script_path/last-linking.log" 2>/dev/null
rmdir "$work_dir" 2>/dev/null

# powershell(=link.exe)의 종료코드를 래퍼의 종료코드로 전파 → 링크 실패 시 rustc/cargo 가 인지한다.
exit $status
