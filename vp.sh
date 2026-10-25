#!/bin/bash
#Formato da base de dados caminho;dono;grupo;tamanho;permissões;data;SHA-256

BD="base_exemplo.txt"

# Lê a base de dados e imprime os valores
ler_base() {
    while IFS=";" read -r caminho dono grupo tamanho perm data sha; do       
        [[ "$caminho" =~ ^# ]] && continue    # testa se o caminho começa com #
        [ -z "$caminho" ] && continue         # ignora linhas vazias

        echo "Ficheiro:   $caminho"
        echo "  Dono:       $dono"
        echo "  Grupo:      $grupo"
        echo "  Tamanho:    $tamanho"
        echo "  Permissões: $perm"
        echo "  Data:       $data"
        echo "  SHA-256:    $sha"
    done < "$BD"
}

# Compara os valores antigos com os atuais e diz o que mudou
comparar_ficheiro() {
    local mudou=0

    if [ "$dono" != "$atual_dono" ]; then
        echo "  Dono: $dono -> $atual_dono"
        mudou=1
    fi

    if [ "$grupo" != "$atual_grupo" ]; then
        echo "  Grupo: $grupo -> $atual_grupo"
        mudou=1
    fi

    if [ "$tamanho" != "$atual_tam" ]; then
        echo "  Tamanho: $tamanho -> $atual_tam"
        mudou=1
    fi

    if [ "$perm" != "$atual_perm" ]; then
        echo "  Permissões: $perm -> $atual_perm"
        mudou=1
    fi

    if [ "$data" != "$atual_data" ]; then
        echo "  Data de modificação: $data -> $atual_data"
        mudou=1
    fi

    if [ "$sha" != "$atual_sha" ]; then
        echo "  Conteúdo: SHA-256 diferente"
        mudou=1
    fi

    if [ "$mudou" -eq 0 ]; then
        echo "  Nada mudou."
    fi
}

# Testa a comparação com valores inventados
testar_comparacao() {
    # Valores antigos
    dono="ana"; grupo="ana"; tamanho=10; perm=644; data=1700000000; sha="aaa"

    echo "Teste 1: tudo igual"
    atual_dono="ana"; atual_grupo="ana"; atual_tam=10
    atual_perm=644; atual_data=1700000000; atual_sha="aaa"
    comparar_ficheiro

    echo "Teste 2: dono, permissões e conteúdo diferentes"
    atual_dono="bob"; atual_perm=600; atual_sha="bbb"
    comparar_ficheiro
}

if [ ! -f "$BD" ]; then
    echo "Erro: base de dados $BD não encontrada!" >&2
    exit 1
fi

echo "-> Leitura da base de dados <-"
ler_base
echo ""
echo "-> Comparação <-"
testar_comparacao

# Função principal para verificar a bd e os ficheiros
verificar_pasta() {
    local bd_ficheiro="${1:-$BD}" # Se não for fornecido, usa a base de dados padrão

    # Verifica se a base de dados existe
    if [ ! -f "$bd_ficheiro" ]; then
        echo "Erro: Base de dados '$bd_ficheiro' não encontrada!" >&2
        echo "Uso correto: ./vp [-v] [-f base_de_dados] [-s]" >&2
        exit 1
    fi

    echo "A iniciar a verificação com base em: $bd_ficheiro"
    echo "-------------------------------------------------"
    
    # Inicializar contadores para o resumo final
    local total_verificados=0
    local total_modificados=0
    local total_apagados=0

    # Ler a base de dados linha a linha
    while IFS=";" read -r caminho dono grupo tamanho perm data sha; do
        # Ignorar linhas de comentário ou vazias
        [[ "$caminho" =~ ^# ]] && continue
        [ -z "$caminho" ] && continue

        total_verificados=$((total_verificados + 1))

        # Verificar se o ficheiro foi apagado
        if [ ! -f "$caminho" ]; then
            echo "Ficheiro APAGADO: $caminho"
            total_apagados=$((total_apagados + 1))
            echo "-------------------------------------------------"
            continue # Passa logo para a próxima linha
        fi

        # Obter os valores atuais do ficheiro
        atual_dono=$(stat -c '%U' "$caminho")
        atual_grupo=$(stat -c '%G' "$caminho")
        atual_tam=$(stat -c '%s' "$caminho")
        atual_perm=$(stat -c '%a' "$caminho")
        atual_data=$(stat -c '%Y' "$caminho")
        atual_sha=$(sha256sum "$caminho" | cut -d' ' -f1)

        echo "A verificar ficheiro: $caminho"
        
        # Comparar usando a tua função de comparação existente
        comparar_ficheiro
        echo "-------------------------------------------------"

    done < "$bd_ficheiro"

    echo "Verificação concluída."
    echo "Total verificados: $total_verificados | Apagados: $total_apagados"
}
