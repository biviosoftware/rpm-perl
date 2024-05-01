#!/bin/bash
source ~/.bashrc
set -euo pipefail
source ~/src/radiasoft/download/installers/rpm-code/dev-env.sh
cd - &> /dev/null

_err() {
    echo ERROR: "$@"
    return 1
}

_t() {
    declare module=$1
    declare -A w=()
    w['provides']=$2
    w['requires']=$3
    w['list']=$4
    declare y=
    if [[ $module =~ ^[A-Z] ]]; then
        y=perl-
    fi
    declare x=$rpm_perl_install_dir/$y$module-dev.rpm
    radia_run biviosoftware/rpm-perl "$module"
    declare p=$(find "$x"  -mmin -1)
    if [[ ! $p ]]; then
        _err "$x is not recent"
    fi
    declare c
    for i in "${!w[@]}"; do
        c=( rpm -qp --"$i" "$p" )
        x=$( "${c[@]}" | wc -l)
        if (( $x != ${w[$i]} )); then
            _err "${c[*]} $x != ${w[$i]}"
        fi
    done
    echo "$module: PASSED"
}

_main() {
    declare -a args=( "$@" )
    if [[ ! ${!args[@]} ]]; then
        args=( bivio-perl bivio-named Artisans Bivio )
    fi
    declare c
    for c in "${args[@]}"; do
        case $c in
            bivio-perl)
                _t bivio-perl 2 3 150
                ;;
            bivio-named)
                _t bivio-named 2 3 7
                ;;
            Artisans)
                _t Artisans 2 3 1414
                ;;
            Bivio)
                # the last number will likely change
                _t Bivio 2 3 7120
                ;;
            *.rpm)
                echo Extracting files from: "$c"
                rpm2cpio "$c" | cpio -idv --no-absolute-filenames
                ;;
            *)
                _err "unknown case=$c"
                ;;
        esac
    done
}

_main "$@"
