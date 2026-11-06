#!/bin/bash

# Formato da base de dados (BD), separador ';':
# #PASTAS;/pasta1;/pasta2
# #EXCLUIR;padrao
# caminho;dono;grupo;tamanho;permissões;data;SHA-256

export LC_ALL=C   # garante que o sort e o comm usam a mesma ordem

BD="/tmp/.pdb"     # -f
EXCLUIR=""         # -e
ALERTAS=0          # -s
PASTAS=()          # preenchido a partir da BD
MODO_P=0
MODO_V=0

TOTAL_VERIFICADOS=0
TOTAL_MODIFICADOS=0
TOTAL_APAGADOS=0
TOTAL_NOVOS=0
TOTAL_ILEGIVEIS=0
TOTAL_PASTAS_ILEGIVEIS=0

# Ajuda e erros
ajuda() {
    echo "Uso: ./vp [{-p <dir1> [<dir2>...] | -v}] [-f <ficheiro>] [-e <padrao>] [-s]" >&2
    echo "  -p : Protege e guarda informação acerca de um ou mais diretórios" >&2
    echo "  -v : Verifica alterações em ficheiros desde que foram protegidos" >&2
    echo "       (é o modo por defeito: sem -p nem -v o programa verifica)" >&2
    echo "  -f : indicação do nome do ficheiro onde a base de dados será guardada" >&2
    echo "       (por defeito será /tmp/.pdb)" >&2
    echo "  -e : Permite a exclusão de ficheiros voláteis (ex. *.temp, *.log, /tmp/*)" >&2
    echo "       da proteção e verificação. O padrão é comparado com o nome do" >&2
    echo "       ficheiro e com o caminho completo. Usar sempre com aspas." >&2
    echo "  -s : Emite alertas de alta prioridade para o sistema de logging usando o logger" >&2
}

# erro imprime a mensagem
erro() {
    echo "Erro: $1" >&2
    ajuda
    exit 1
}

# Leitura e validação de argumentos
processar_argumentos() {
    local flag
    while (( $# > 0 )); do
        OPTIND=1
        while getopts ":pve:f:s" flag; do
            case "${flag}" in
                p) MODO_P=1 ;;
                v) MODO_V=1 ;;
                e) EXCLUIR="$OPTARG" ;;
                f) BD="$OPTARG" ;;
                s) ALERTAS=1 ;;
                :) erro "A opção -$OPTARG precisa de argumento" ;;
                \?) erro "Opção Inválida: a flag -$OPTARG não existe" ;;
            esac
        done
        shift $((OPTIND - 1))

        if (( $# > 0 )); then
            PASTAS+=("$1")
            shift
        fi
    done
}

validar_argumentos() {
    if (( MODO_P && MODO_V )); then
        erro "As opções -p e -v não podem ser usadas em simultâneo"
    fi
    if (( MODO_P && ${#PASTAS[@]} == 0 )); then
        erro "A opção -p precisa de pelo menos uma pasta"
    fi
    if (( !MODO_P && ${#PASTAS[@]} > 0 )); then
        erro "Foram indicadas pastas sem a opção -p"
    fi
}

#  Modo -p proteger
info_ficheiro() {
    local ficheiro="$1"
    local meta hash

    meta=$(stat --format="%U;%G;%s;%a;%Y" "$ficheiro")

    hash=""
    [ -r "$ficheiro" ] && hash=$(sha256sum < "$ficheiro" | cut -d' ' -f1)

    echo "$ficheiro;$meta;$hash"
}

# Lista os ficheiros de uma pasta e subpastas
listar_ficheiros() {
    [ -d "$1" ] || return   # pasta apagada: não há ficheiros
    if [ -n "$EXCLUIR" ]; then
        find "$1" -type f ! -path "$BD" ! \( -name "$EXCLUIR" -o -path "$EXCLUIR" \) 2>/dev/null
    else
        find "$1" -type f ! -path "$BD" 2>/dev/null
    fi
}

# Avisa (stderr) das subpastas sem permissão de leitura/travessia: o conteúdo não pode ser listado.
# Devolve em ILEGIVEIS_PASTAS o número de pastas encontradas.
avisar_pastas_ilegiveis() {
    local d
    ILEGIVEIS_PASTAS=0
    while IFS= read -r d; do
        echo "Aviso: sem permissão para ler a pasta '$d': o seu conteúdo não é protegido/verificado." >&2
        ILEGIVEIS_PASTAS=$((ILEGIVEIS_PASTAS + 1))
    done < <(find "$1" -type d \( ! -readable -o ! -executable \) 2>/dev/null)
}

proteger() {
    local pasta lista f
    local n=0
    local avisos=0                       # ficheiros/pastas que não puderam ser lidos
    local absolutas=()
    local -A vistos=()                   # evita ficheiros repetidos (pastas sobrepostas)

    # Valida e guarda todas as pastas antes de mexer na BD antiga
    for pasta in "${PASTAS[@]}"; do
        [ -d "$pasta" ] || erro "A pasta '$pasta' não existe ou não é uma pasta"
        absolutas+=("$(readlink -f "$pasta")")
    done
    PASTAS=("${absolutas[@]}")

    # Se a BD já existe apaga-se para a poder recriar
    rm -f "$BD"
    lista=$(IFS=';'; echo "${PASTAS[*]}")
    echo "#PASTAS;$lista" > "$BD" || erro "Não foi possível criar a base de dados '$BD'"
    echo "#EXCLUIR;$EXCLUIR" >> "$BD"

    for pasta in "${PASTAS[@]}"; do
        echo "a proteger a pasta: $pasta"

        avisar_pastas_ilegiveis "$pasta"
        avisos=$((avisos + ILEGIVEIS_PASTAS))

        while IFS= read -r f; do
            [ -n "${vistos[$f]}" ] && continue
            vistos["$f"]=1
            if [ ! -r "$f" ]; then
                echo "Aviso: sem permissão de leitura em '$f': guardado sem SHA-256 (conteúdo não será verificado)." >&2
                avisos=$((avisos + 1))
            fi
            info_ficheiro "$f"
            n=$((n+1))
        done < <(listar_ficheiros "$pasta") >> "$BD"
    done

    chmod 444 "$BD"
    echo "Ficheiros processados: $n | Diretórios protegidos: ${PASTAS[*]}"
    if (( avisos > 0 )); then
        echo "Base de dados de proteção $BD criada COM AVISOS: $avisos item(ns) ilegível(eis) (ver mensagens acima)." >&2
        exit 2
    fi
    echo "Base de dados de proteção $BD criada com sucesso."
}

# Modo -v verificar
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
    if [ -n "$6" ] && [ -n "${12}" ] && [ "$6" != "${12}" ]; then
        echo "  Conteúdo: SHA-256 diferente"
    fi
}

# Mostra o alerta no ecrã e, com -s, também no registo do sistema
alertar() {
    echo "$1"
    [ -n "$2" ] && echo "$2"          # $2 = detalhes (só no ecrã)
    if [ "$ALERTAS" -eq 1 ]; then
        logger -p user.crit -t vp "$1"
    fi
}

# Apagados e modificados
obter_estado_atual() {
    atual_dono=$(stat -c '%U' "$1")
    atual_grupo=$(stat -c '%G' "$1")
    atual_tam=$(stat -c '%s' "$1")
    atual_perm=$(stat -c '%a' "$1")
    atual_data=$(stat -c '%Y' "$1")
    atual_sha=""
    [ -r "$1" ] && atual_sha=$(sha256sum < "$1" | cut -d' ' -f1)
}


esta_excluido() {
    # Verifica se o ficheiro está excluído pelo padrão -e
    [ -n "$EXCLUIR" ] && { [[ "$(basename "$1")" == $EXCLUIR ]] || [[ "$1" == $EXCLUIR ]]; }
}

# Verificação dos ficheiros que estão na BD
verificar_existentes() {
    local linha caminho dono grupo tamanho perm data sha detalhes
    while IFS= read -r linha; do
        [[ "$linha" =~ ^# ]] && continue                # ignora linhas começadas com #
        [ -z "$linha" ] && continue                     # ignora linhas vazias
        # o caminho pode conter ';': os 6 últimos campos são fixos
        caminho=${linha%;*;*;*;*;*;*}
        IFS=";" read -r dono grupo tamanho perm data sha <<< "${linha#"$caminho;"}"
        esta_excluido "$caminho" && continue            # ignora ficheiros que batem com o padrão de exclusão

        if [ ! -f "$caminho" ]; then
            TOTAL_VERIFICADOS=$((TOTAL_VERIFICADOS + 1))
            alertar "APAGADO: $caminho"
            TOTAL_APAGADOS=$((TOTAL_APAGADOS + 1))
            continue
        fi

        # Sem hash na BD ou sem leitura agora: o conteúdo não pode ser verificado.
        # Não conta como "Verificado"; os metadados continuam a ser comparados.
        if [ -z "$sha" ]; then
            alertar "ILEGÍVEL: $caminho" "  Conteúdo não verificável: ficheiro guardado sem SHA-256 (sem permissão de leitura no -p)"
            TOTAL_ILEGIVEIS=$((TOTAL_ILEGIVEIS + 1))
        elif [ ! -r "$caminho" ]; then
            alertar "ILEGÍVEL: $caminho" "  Conteúdo não verificável: sem permissão de leitura"
            TOTAL_ILEGIVEIS=$((TOTAL_ILEGIVEIS + 1))
        else
            TOTAL_VERIFICADOS=$((TOTAL_VERIFICADOS + 1))
        fi

        obter_estado_atual "$caminho"
        detalhes=$(comparar_ficheiro "$dono" "$grupo" "$tamanho" "$perm" "$data" "$sha" \
                   "$atual_dono" "$atual_grupo" "$atual_tam" "$atual_perm" "$atual_data" "$atual_sha")
        if [ -n "$detalhes" ]; then
            alertar "MODIFICADO: $caminho" "$detalhes"
            TOTAL_MODIFICADOS=$((TOTAL_MODIFICADOS + 1))
        fi
    done < "$BD"
}

# Novos
# Lê o cabeçalho da BD e preenche PASTAS com as pastas protegidas. O -e tem prioridade
ler_cabecalho_bd() {
    local campos
    while IFS=";" read -r -a campos; do
        case "${campos[0]}" in
            "#PASTAS")  PASTAS=("${campos[@]:1}") ;;
            "#EXCLUIR") [ -z "$EXCLUIR" ] && EXCLUIR="${campos[1]}" ;;
        esac
    done < "$BD"
    if [ "${#PASTAS[@]}" -eq 0 ]; then
        erro "a base de dados '$BD' não tem pastas protegidas (linha #PASTAS;...)."
    fi
}

# Uma lista para o que está na BD e outra para o que existe agora no disco
caminhos_da_bd() {
    grep -v -e '^#' -e '^$' "$BD" | sed 's/\(;[^;]*\)\{6\}$//' | sort -u
}
caminhos_atuais() {
    local pasta
    for pasta in "${PASTAS[@]}"; do
        listar_ficheiros "$pasta"
    done | sort -u
}

# Ficheiros que existem agora e não estão na BD
verificar_novos() {
    local caminho
    while IFS= read -r caminho; do
        alertar "NOVO: $caminho"
        TOTAL_NOVOS=$((TOTAL_NOVOS + 1))
    done < <(comm -13 <(caminhos_da_bd) <(caminhos_atuais))
}

# Erro, resumo e função principal do modo -v
verificar_bd_existe() {
    if [ ! -f "$BD" ] || [ ! -r "$BD" ]; then
        erro "base de dados '$BD' não encontrada ou sem permissão de leitura."
    fi
}

mostrar_resumo() {
    echo "-------------------------------------------------"
    echo "Verificados: $TOTAL_VERIFICADOS | Modificados: $TOTAL_MODIFICADOS | Apagados: $TOTAL_APAGADOS | Novos: $TOTAL_NOVOS | Ilegíveis: $TOTAL_ILEGIVEIS | Pastas ilegíveis: $TOTAL_PASTAS_ILEGIVEIS"
}

modo_verificar() {
    local pasta
    verificar_bd_existe
    ler_cabecalho_bd
    for pasta in "${PASTAS[@]}"; do
        avisar_pastas_ilegiveis "$pasta"
        TOTAL_PASTAS_ILEGIVEIS=$((TOTAL_PASTAS_ILEGIVEIS + ILEGIVEIS_PASTAS))
    done
    verificar_existentes
    verificar_novos
    mostrar_resumo
}

main() {
    processar_argumentos "$@"
    validar_argumentos

    # Caminho absoluto da BD
    BD=$(readlink -m "$BD")

    if (( MODO_P )); then
        proteger
    else
        modo_verificar
    fi
}

main "$@"
