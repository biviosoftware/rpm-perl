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
    local module=$1
    local -A w=()
    w['provides']=$2
    w['requires']=$3
    w['list']=$4
    local y=
    if [[ $module =~ ^[A-Z] ]]; then
        y=perl-
    fi
    local x=$rpm_perl_install_dir/$y$module-dev.rpm
    radia_run biviosoftware/rpm-perl "$module"
    local p=$(find "$x"  -mmin -1)
    if [[ ! $p ]]; then
        _err "$x is not recent"
    fi
    local c
    for i in "${!w[@]}"; do
        c=( rpm -qp --"$i" "$p" )
        if (( $( "${c[@]}" | wc -l) != ${w[$i]} )); then
            _err "${c[*]} != ${w[$i]}"
        fi
    done
    echo "$module: PASSED"
}

_t bivio-perl 2 3 151
_t bivio-named 2 3 7
_t Artisans 2 3 1414
# the last number might change
_t Bivio 2 3 7086
