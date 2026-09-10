#!/usr/bin/env bash

_brewstore_completions() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="adopt switch audit mas health clean devclean blueprint completions install-cli launch version help"

    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
        return 0
    fi

    case "${prev}" in
        adopt)
            COMPREPLY=( $(compgen -W "--all" -- ${cur}) )
            ;;
        mas)
            COMPREPLY=( $(compgen -W "list upgrade outdated" -- ${cur}) )
            ;;
        blueprint)
            COMPREPLY=( $(compgen -W "export restore" -- ${cur}) )
            ;;
        completions)
            COMPREPLY=( $(compgen -W "zsh bash fish" -- ${cur}) )
            ;;
    esac
}

complete -F _brewstore_completions brewstore
