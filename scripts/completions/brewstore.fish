# fish completion for brewstore

set -l commands adopt switch audit mas health clean devclean blueprint completions install-cli launch version help

complete -c brewstore -f
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a adopt -d "Scan and adopt unmanaged macOS apps"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a switch -d "Switch active version symlinks"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a audit -d "Run CVE security scan"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a mas -d "Manage Mac App Store apps"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a health -d "Evaluate Homebrew health"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a clean -d "Clean package download caches"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a devclean -d "Purge developer caches"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a blueprint -d "Export or restore Mac blueprint"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a completions -d "Print shell completion script"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a install-cli -d "Install brewstore CLI symlink"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a launch -d "Launch the BrewStore GUI app"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a version -d "Show version"
complete -c brewstore -n "not __fish_seen_subcommand_from $commands" -a help -d "Show usage help"
