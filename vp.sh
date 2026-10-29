#!/bin/bash
erro() {
    echo "Erro: $1" >&2
    echo "Uso: ./vp [{-p <dir1> [<dir2>...] | -v}] [-f <ficheiro>] [-e <padrao>] [-s]" >&2
    echo "  -p : Protege e guarda informação acerca de um ou mais diretórios" >&2
    echo "  -v : Verifica alterações em ficheiros desde que foram protegidos" >&2
    echo "  -f : indicação do nome do ficheiro onde a base de dados será guardada" >&2 
    echo "(Por defeito será /tmp/.pdb)" >&2
    echo "  -e : Permite a exclusão de ficheiros voláteis (ex. *.temp, *.log, /tmp/*) da proteção e verificação" >&2
    echo "  -s : Emite alertas de alta prioridade para o sistema de logging usando o logger" >&2
    exit 1
}

# Recebe o caminho de UM ficheiro em $1 e imprime uma linha com a sua informação
info_ficheiro() {
    local ficheiro="$1"
    local meta hash

    # 1. Metadados com o stat: dono, grupo, tamanho, permissões (octal), data de modificação
    meta=$(stat --format="%U;%G;%s;%a;%Y" "$ficheiro")

    # 2. Hash com o sha256sum: só o hash, sem o nome do ficheiro
    hash=$(sha256sum "$ficheiro" | cut -d' ' -f1)

    # 3. Imprimir tudo numa linha, com o separador que combinaram no contrato da base de dados
    echo "$ficheiro;$meta;$hash"
}

listar_ficheiros() {
    find "$1" -type f -not -name "$2"
}   

proteger() {
    rm -f "$bd"
    n=0
    lista=$(IFS=';'; echo "${pastas[*]}")
    echo "#PASTAS;$lista" > "$bd"
    echo "#EXCLUIR;$exclusao" >> "$bd"
    for pasta in "${pastas[@]}"; do
        if [ ! -d "$pasta" ]; then
        erro "A pasta $pasta não existe"
        fi

        echo "a proteger a pasta: $pasta"

        while IFS= read -r f; do
            info_ficheiro "$f"
            n=$((n+1))
            done < <(listar_ficheiros "$pasta" "$exclusao") >> "$bd"
    done
    chmod 444 "$bd"
    echo "Base de dados de proteção $bd criada com sucesso."
    echo "Ficheiros processados: $n | Diretórios protegidas: $lista"
}

modo_p=0
modo_v=0
modo_s=0
bd="/tmp/.pdb"
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

if ((modo_p));
then proteger;
fi
