#!/bin/bash
erro() {
    echo "Erro: $1" >&2
    echo "Uso: ./vp [{-p <dir1> [<dir2>...] | -v}] [-f <ficheiro>] [-e <padrao>] [-s]" >&2
    echo "  -p : Protege e guarda informação acerca de um ou mais diretórios" >&2
    echo "  -v : Percorre os ficheiros nos diretórios protegidos e determina se existiram modificações desde a criação da base de dados de proteção" >&2
    echo "  -f : Especifica o ficheiro que irá guardar a base de dados" >&2
    echo "  -e : Exclui os ficheiros especificados da verificação e proteção" >&2
    echo "  -s : Emite alertas de alta prioridade para o sistema de logging usando o logger" >&2
    exit 1
}

modo_p=0
modo_v=0
modo_s=0
ficheiro="/tmp/.pdb"
exclusao=""
pastas=()
while (( $# > 0 )); do
    OPTIND=1
    while getopts ":pve:f:s" flag; do
        case "${flag}" in
            p) modo_p=1 ;;
            v) modo_v=1 ;;
            e) exclusao="$OPTARG" ;;
            f) ficheiro="$OPTARG" ;;
            s) modo_s=1 ;;
            :) erro "A opção -$OPTARG precisa de argumento" ;;
            \?) erro "Opção Inválida: a flag -$OPTARG não existe" ;;
        esac
    done
    shift $((OPTIND - 1))

    if (( $# > 0 )); then
        pastas+=("$1")
        shift
    fi
done

if (( modo_p && modo_v )); then
    erro "As opções -p e -v não podem ser usadas em simultâneo"
fi

if (( modo_p && ${#pastas[@]} == 0 )); then
    erro "A opção -p precisa de pelo menos uma pasta"
fi

if (( !modo_p && ${#pastas[@]} > 0 )); then
    erro "Foram indicadas pastas sem a opção -p"
fi

echo "-p: $modo_p | -v: $modo_v | -s: $modo_s"
echo "-f: $ficheiro"
echo "-e: ${exclusao:-<não dado>}"
echo "pastas (${#pastas[@]}):"
for pasta in "${pastas[@]}"; do
    echo "  $pasta"
done
