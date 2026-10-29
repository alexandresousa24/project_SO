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

export LC_ALL=C   # garante que o sort e comm têm a mesma ordem

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
    if [ -n "$exclusao" ]; then
        find "$1" -type f -not -name "$exclusao"
    else
        find "$1" -type f
    fi
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
        done < <(listar_ficheiros "$pasta") >> "$bd"
    done
    chmod 444 "$bd"
    echo "Base de dados de proteção $bd criada com sucesso."
    echo "Ficheiros processados: $n | Diretórios protegidas: $lista"
}

comparar_campo() {
    if [ "$2" != "$3" ]; then
        echo "  $1: $2 -> $3"
    fi
}

comparar_ficheiro() {
    comparar_campo "Dono"                "$1" "$7"
    comparar_campo "Grupo"               "$2" "$8"
    comparar_campo "Tamanho"             "$3" "$9"
    comparar_campo "Permissões"          "$4" "${10}"
    comparar_campo "Data de modificação" "$5" "${11}"
    if [ "$6" != "${12}" ]; then
        echo "  Conteúdo: SHA-256 diferente"
    fi
}

alertar() {
    echo "$1"
    [ -n "$2" ] && echo "$2"
    if (( modo_s )); then
        logger -p user.crit -t vp "$1"
    fi
}

obter_estado_atual() {
    atual_dono=$(stat -c '%U' "$1")
    atual_grupo=$(stat -c '%G' "$1")
    atual_tam=$(stat -c '%s' "$1")
    atual_perm=$(stat -c '%a' "$1")
    atual_data=$(stat -c '%Y' "$1")
    atual_sha=$(sha256sum < "$1" | cut -d' ' -f1)
}

esta_excluido() {
    [ -n "$exclusao" ] && [[ "$(basename "$1")" == $exclusao ]]
}

verificar_existentes() {
    local caminho dono grupo tamanho perm data sha detalhes
    while IFS=";" read -r caminho dono grupo tamanho perm data sha; do
        [[ "$caminho" =~ ^# ]] && continue
        [ -z "$caminho" ] && continue
        esta_excluido "$caminho" && continue

        total_verificados=$((total_verificados + 1))

        if [ ! -f "$caminho" ]; then
            alertar "APAGADO: $caminho"
            total_apagados=$((total_apagados + 1))
            continue
        fi

        obter_estado_atual "$caminho"
        detalhes=$(comparar_ficheiro "$dono" "$grupo" "$tamanho" "$perm" "$data" "$sha" \
                   "$atual_dono" "$atual_grupo" "$atual_tam" "$atual_perm" "$atual_data" "$atual_sha")
        if [ -n "$detalhes" ]; then
            alertar "MODIFICADO: $caminho" "$detalhes"
            total_modificados=$((total_modificados + 1))
        fi
    done < "$bd"
}

ler_cabecalho_bd() {
    local campos
    while IFS=";" read -r -a campos; do
        case "${campos[0]}" in
            "#PASTAS")  pastas=(${campos[@]:1}) ;;
            "#EXCLUIR") [ -z "$exclusao" ] && exclusao="${campos[1]}" ;;
        esac
    done < "$bd"
    if [ "${#pastas[@]}" -eq 0 ]; then
        erro "a base de dados '$bd' não tem pastas protegidas (linha #PASTAS;...)."
    fi
}

caminhos_da_bd() {
    grep -v -e '^#' -e '^$' "$bd" | cut -d';' -f1 | sort
}

caminhos_atuais() {
    local pasta
    for pasta in "${pastas[@]}"; do
        listar_ficheiros "$pasta"
    done | sort
}

verificar_novos() {
    local caminho
    while IFS= read -r caminho; do
        alertar "NOVO: $caminho"
        total_novos=$((total_novos + 1))
    done < <(comm -13 <(caminhos_da_bd) <(caminhos_atuais))
}

verificar_bd_existe() {
    if [ ! -f "$bd" ] || [ ! -r "$bd" ]; then
        erro "base de dados '$bd' não encontrada ou sem permissão de leitura."
    fi
}

mostrar_resumo() {
    echo "-------------------------------------------------"
    echo "Verificados: $total_verificados | Modificados: $total_modificados | Apagados: $total_apagados | Novos: $total_novos"
}

modo_verificar() {
    verificar_bd_existe
    ler_cabecalho_bd
    verificar_existentes
    verificar_novos
    mostrar_resumo
}

modo_p=0
modo_v=0
modo_s=0
bd="/tmp/.pdb"
exclusao=""
pastas=()
total_verificados=0
total_modificados=0
total_apagados=0
total_novos=0

while (( $# > 0 )); do
    OPTIND=1
    while getopts ":pve:f:s" flag; do
        case "${flag}" in
            p) modo_p=1 ;;
            v) modo_v=1 ;;
            e) exclusao="$OPTARG" ;;
            f) bd="$OPTARG" ;;
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

if (( modo_p )); then
    proteger
fi

if (( modo_v )); then
    modo_verificar
fi
