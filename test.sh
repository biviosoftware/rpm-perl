#!/bin/bash
source ~/.bashrc
set -euo pipefail
source ~/src/radiasoft/download/installers/rpm-code/dev-env.sh
cd -
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

_t bivio-perl 2 3 150
_t bivio-named 2 3 7
_t Artisans 2 3 1414
# the last number might change
_t Bivio 2 3 7114
