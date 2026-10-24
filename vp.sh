#!/bin/bash

recolher_metadados() {
    local dir="$1"

    # -print0 + read -d '' permitem nomes de ficheiros com espaços
    find "$dir" -type f -print0 | while IFS= read -r -d '' ficheiro; do
        stat -c '%n|%U|%G|%s|%a|%Y' "$ficheiro"
    done
}

recolher_metadados "$1"