#!/bin/bash
# Formato da BD:
# #PASTAS;/pasta1;/pasta2         
# caminho;dono;grupo;tamanho;permissões;data;SHA-256

export LC_ALL=C   # garante que o sort e comm têm a mesma ordem

BD="base_real.txt"   # TEMPORÁRIO para testes; no vp final vem do -f
EXCLUIR=""           # -e
ALERTAS=0            # -s
PASTAS=()            # preenchido a partir da BD

TOTAL_VERIFICADOS=0
TOTAL_MODIFICADOS=0
TOTAL_APAGADOS=0
TOTAL_NOVOS=0

# Placeholder para testes isolados: a verdadeira `ajuda` é do Alexandre
ajuda() { echo "Uso: ./vp [-p pasta...] [-v] [-f bd] [-e padrao] [-s]" >&2; }

# 1 Comparação
# Escreve uma linha só se o valor antigo for diferente do atual
comparar_campo() {
    if [ "$2" != "$3" ]; then
        echo "  $1: $2 -> $3"
    fi
}

# Recebe 6 valores antigos e 6 atuais, pela mesma ordem e escreve só o que mudou.
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

# 2 Alertas
# Mostra o alerta no ecrã e, com -s, também no registo do sistema
alertar() {
    echo "$1"
    [ -n "$2" ] && echo "$2"          # $2 = detalhes (só no ecrã)
    if [ "$ALERTAS" -eq 1 ]; then
        logger -p user.crit -t vp "$1"
    fi
}

# 3 Apagados e Modificados
# Preenche as variáveis atual_* com os valores do ficheiro no disco
obter_estado_atual() {
    atual_dono=$(stat -c '%U' "$1")
    atual_grupo=$(stat -c '%G' "$1")
    atual_tam=$(stat -c '%s' "$1")
    atual_perm=$(stat -c '%a' "$1")
    atual_data=$(stat -c '%Y' "$1")
    atual_sha=$(sha256sum < "$1" | cut -d' ' -f1)
}

# Verdadeiro se o nome do ficheiro for igual ao do -e
esta_excluido() {
    [ -n "$EXCLUIR" ] && [[ "$(basename "$1")" == $EXCLUIR ]]
}

# Verificação de existentes
verificar_existentes() {
    local caminho dono grupo tamanho perm data sha detalhes
    while IFS=";" read -r caminho dono grupo tamanho perm data sha; do
        [[ "$caminho" =~ ^# ]] && continue              # ignora linhas começadas com #
        [ -z "$caminho" ] && continue                   # ignora linhas vazias
        esta_excluido "$caminho" && continue            # ignora ficheiros que batem com o padrão de exclusão

        TOTAL_VERIFICADOS=$((TOTAL_VERIFICADOS + 1))    

        if [ ! -f "$caminho" ]; then                    
            alertar "APAGADO: $caminho"
            TOTAL_APAGADOS=$((TOTAL_APAGADOS + 1))
            continue 
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

# 4 Novos
# Lê o cabeçalho da BD e preenche a variável PASTAS com as pastas protegidas.
ler_cabecalho_bd() {
    local campos
    while IFS=";" read -r -a campos; do
        case "${campos[0]}" in
            "#PASTAS")  PASTAS=("${campos[@]:1}") ;;
            "#EXCLUIR") [ -z "$EXCLUIR" ] && EXCLUIR="${campos[1]}" ;;
        esac
    done < "$BD"
    if [ "${#PASTAS[@]}" -eq 0 ]; then
        echo "Erro: a base de dados '$BD' não tem pastas protegidas (linha #PASTAS;...)." >&2
        ajuda
        exit 1
    fi
}

# ----------------------------------- Deve ser a MESMA função que o -p do Alexandre usa
listar_ficheiros() {
    if [ -n "$EXCLUIR" ]; then
        find "$1" -type f -not -name "$EXCLUIR"
    else
        find "$1" -type f
    fi
}

# Uma lista para o que está na BD e outra para o que existe agora no disco
caminhos_da_bd() {
    grep -v -e '^#' -e '^$' "$BD" | cut -d';' -f1 | sort
}
caminhos_atuais() {
    local pasta
    for pasta in "${PASTAS[@]}"; do
        listar_ficheiros "$pasta"
    done | sort
}

# Verifica se existem ficheiros novos que não estão na BD e alerta para eles.
verificar_novos() {
    local caminho
    while IFS= read -r caminho; do
        alertar "NOVO: $caminho"
        TOTAL_NOVOS=$((TOTAL_NOVOS + 1))
    done < <(comm -13 <(caminhos_da_bd) <(caminhos_atuais))
}

# 5 Erro, resumo e modo de uso
verificar_bd_existe() {
    if [ ! -f "$BD" ] || [ ! -r "$BD" ]; then
        echo "Erro: base de dados '$BD' não encontrada ou sem permissão de leitura." >&2
        ajuda        # função do Alexandre: modo de uso correto
        exit 1
    fi
}

mostrar_resumo() {
    echo "-------------------------------------------------"
    echo "Verificados: $TOTAL_VERIFICADOS | Modificados: $TOTAL_MODIFICADOS | Apagados: $TOTAL_APAGADOS | Novos: $TOTAL_NOVOS"
}

modo_verificar() {
    verificar_bd_existe
    ler_cabecalho_bd
    verificar_existentes
    verificar_novos
    mostrar_resumo
}

modo_verificar
