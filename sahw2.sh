#!/usr/local/bin/bash

usage() {
    echo -n -e "\nUsage: sahw2.sh {--sha256 hashes ... | --md5 hashes ...} -i files ...\n\n--sha256: SHA256 hashes to validate input files.\n--md5: MD5 hashes to validate input files.\n-i: Input files.\n"
}

hash_type=""
hashes=()
input_files=()
usernames=()
password=()
shells=()
groups=()

while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
        --sha256)
            if [[ ! -z "$hash_type" ]]; then
                echo -n "Error: Only one type of hash function is allowed." >&2
                exit 1
            fi
            hash_type="sha256"
            shift
            while [[ $# -gt 0 && ! $1 == -* ]]; do
                hashes+=("$1")
                shift
            done
            ;;
        --md5)
            if [[ ! -z "$hash_type" ]]; then
                echo -n "Error: Only one type of hash function is allowed." >&2
                exit 1
            fi
            hash_type="md5"
            shift
            while [[ $# -gt 0 && ! $1 == -* ]]; do
                hashes+=("$1")
                shift
            done
            ;;
        -i)
            shift
            while [[ $# -gt 0 && ! $1 == -* ]]; do
		        if jq '.[] | has("username") and has("password") and has("shell") and has("groups")' "$1" > /dev/null 2>&1; then
                    usernames+=($(jq -r '.[].username' "$1"))
                    passwords+=($(jq -r '.[].password' "$1"))
                    shells+=($(jq -r '.[].shell' "$1"))
		            while read object; do
		                groups+=("$object")
		            done <<< $(jq -c '.[].groups' "$1")
	            elif [[ "$(head -n 1 "$1")" == "username,password,shell,groups" ]]; then
		            exec 3< "$1"
		            read header <&3
		            while read line; do
			            usernames+=($(echo "$line" | awk -F ',' '{print $1}'))
			            passwords+=($(echo "$line" | awk -F ',' '{print $2}'))
			            shells+=($(echo "$line" | awk -F ',' '{print $3}'))
			            groups+=("[$(echo "$line" | awk -F ', *' '{print $4}' | sed 's/\([a-zA-Z]\{1,\}\)/"\1"/g;s/ /,/g')]")
                    done <&3
		            exec 3<&-
		        else
		            echo -n "Error: Invalid file format." >&2
		            exit 1
		        fi
		        input_files+=("$1")
                shift
            done
            ;;
        -h)
            usage
            exit 0
            ;;
        *)
            echo -n "Error: Invalid arguments." >&2
            usage
            exit 1
            ;;
    esac
done

if [[ ${#hashes[@]} -ne ${#input_files[@]} ]]; then
    echo -n "Error: Invalid values." >&2
    exit 1
fi

amount=`expr ${#hashes[@]} - 1`

if [[ "$hash_type" == "sha256" ]]; then
    for i in $(seq 0 $amount); do
	if ! sha256 -c "${hashes[i]}" "${input_files[i]}" > /dev/null 2>&1; then
	    echo -n "Error: Invalid checksum." >&2
	    exit 1
	fi
    done
else
    for i in $(seq 0 $amount); do
	if ! md5 -c "${hashes[i]}" "${input_files[i]}" > /dev/null 2>&1; then
	    echo -n "Error: Invalid checksum." >&2
	    exit 1
	fi
    done
fi

echo -n "This script will create the following user(s): ${usernames[*]} Do you want to continue? [y/n]:"

read answer

if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    exit 0
fi

for (( i=0; i<${#usernames[@]}; i++ )); do
    if id "${usernames[i]}" >/dev/null 2>&1; then
        echo -n -e "\nWarning: user ${usernames[i]} already exists."
    else
        pw useradd -n "${usernames[i]}" -s "${shells[i]}" -m
        echo "${passwords[i]}" | pw mod user "${usernames[i]}" -h 0
        arr=($(echo "${groups[i]}" | awk -F ',' '{for(i=1;i<=NF;i++) print $i}' | sed 's/"//g; s/\[//g; s/\]//g'))
        if [[ ${#arr[@]} -gt 0 ]]; then
            for group in "${arr[@]}"; do
                if ! getent group $group >/dev/null 2>&1; then
                    pw groupadd $group
                fi
                pw groupmod "${group}" -m "${usernames[i]}"
            done
        fi
    fi
done

exit 0