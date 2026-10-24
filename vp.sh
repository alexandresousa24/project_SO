#!/bin/bash

# Função para comparar os atributos de um ficheiro antigo com os atuais
comparar_ficheiro() {
    local antigo_dono="$1" local atual_dono="$2"
    local antigo_tam="$3"  local atual_tam="$4"
    local antigo_perm="$5" local atual_perm="$6"
    local antigo_data="$7" local atual_data="$8"
    local antigo_sha="$9"  local atual_sha="${10}"

    local mudou=0

    if [ "$antigo_dono" != "$atual_dono" ]; then
        echo "  -> Alterações: Dono alterado (antigo: $antigo_dono -> atual: $atual_dono)"
        mudou=1
    fi

    if [ "$antigo_tam" != "$atual_tam" ]; then
        echo "  -> Alterações: Tamanho alterado (antigo: $antigo_tam -> atual: $atual_tam)"
        mudou=1
    fi

    if [ "$antigo_perm" != "$atual_perm" ]; then
        echo "  -> Alterações: Permissões alteradas (antigas: $antigo_perm -> atuais: $atual_perm)"
        mudou=1
    fi

    if [ "$antigo_data" != "$atual_data" ]; then
        echo "  -> Alterações: Data de modificação alterada"
        mudou=1
    fi

    if [ "$antigo_sha" != "$atual_sha" ]; then
        echo "  -> Alterações: Conteúdo alterado (SHA-256 diferente)"
        mudou=1
    fi

    if [ "$mudou" -eq 0 ]; then
        echo "  -> Nada mudou neste ficheiro."
    fi
}

# Leitura da base de dados
# Substituir 'testes_vp/base_exemplo.txt' pelo caminho real BD no projeto
BD="testes_vp/base_exemplo.txt"

if [ ! -f "$BD" ]; then
    echo "Erro: Base de dados $BD não encontrada!"
    exit 1
fi

echo "A processar a base de dados: $BD"
echo ""

while IFS=";" read -r caminho dono grupo tamanho perm data sha; do
    # Ignora linhas que começam com #
    [[ "$caminho" =~ ^# ]] && continue

    echo "A verificar o ficheiro: $caminho"

    # Verifica se o ficheiro existe
    if [ ! -e "$caminho" ]; then
        echo "  -> ALERTA: O ficheiro foi apagado do disco!"
        continue
    fi

    # Recolher os atributos atuais do ficheiro
    atual_dono=$(stat -c "%U" "$caminho")
    atual_grupo=$(stat -c "%G" "$caminho")
    atual_tam=$(stat -c "%s" "$caminho")
    atual_perm=$(stat -c "%a" "$caminho")
    atual_data=$(stat -c "%Y" "$caminho")
    atual_sha=$(sha256sum "$caminho" | awk '{print $1}')

    comparar_ficheiro "$dono" "$atual_dono" "$tamanho" "$atual_tam" "$perm" "$atual_perm" "$data" "$atual_data" "$sha" "$atual_sha"

done < "$BD"