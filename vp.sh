#!/bin/bash
#Formato da base de dados caminho;dono;grupo;tamanho;permissões;data;SHA-256

BD="base_exemplo.txt"

# Lê a base de dados e imprime os valores
ler_base() {
    while IFS=";" read -r caminho dono grupo tamanho perm data sha; do       
        [[ "$dono" =~ ^# ]] && continue    # ignora linhas de comentário
        [ -z "$dono" ] && continue         # ignora linhas vazias

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

# ---- Testes da Fase 1 ----
if [ ! -f "$BD" ]; then
    echo "Erro: base de dados $BD não encontrada!" >&2
    exit 1
fi

echo "=== Leitura da base de dados ==="
ler_base
echo ""
echo "=== Comparação ==="
testar_comparacao