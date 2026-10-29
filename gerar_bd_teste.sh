#!/bin/bash
# SÓ PARA TESTES (não entra no vp): gera base_real.txt com valores reais.
# Uso: ./gerar_bd_teste.sh [pasta1 pasta2 ...]   (por defeito ./testes_vp)
[ $# -eq 0 ] && set -- "$PWD/testes_vp"
LINHA="#PASTAS"
for p in "$@"; do LINHA="$LINHA;$(realpath "$p")"; done
{
    echo "$LINHA"
    for p in "$@"; do find "$(realpath "$p")" -type f; done | while IFS= read -r f; do
        echo "$f;$(stat -c '%U;%G;%s;%a;%Y' "$f");$(sha256sum < "$f" | cut -d' ' -f1)"
    done
} > base_real.txt
echo "base_real.txt criada: $LINHA"
