#!/bin/bash
set -euo pipefail

rpm_perl_build() {
    install -m 400 .netrc ~
    case $1 in
        bivio-named)
            rpm_perl_build_named "$@"
            ;;
        bivio-perl)
            rpm_perl_build_perl "$@"
            ;;
        perl-*)
            rpm_perl_build_app "$@"
            ;;
        *)
            install_err "bad args: $*"
            ;;
    esac
}

rpm_perl_build_app() {
    local rpm_base=$1 root=$2 exe_prefix=$3 app_root=$4 facade_uri=$5
    umask 022
    local build_d=$PWD
    local facades_d=/var/www/facades
    local javascript_d=/usr/share/Bivio-bOP-javascript
    local bop_d=/usr/src/bop
    local version=$(date -u +%Y%m%d.%H%M%S)
    local fpm_args=()
    if [[ $root == Bivio ]]; then
        mkdir "$javascript_d"
        # No channels here, because the image gets the channel tag
        git clone --recursive --depth 1 https://github.com/biviosoftware/javascript-Bivio
        cd javascript-Bivio
        bash build.sh "$javascript_d"
        cd ..
        rm -rf javascript-Bivio
        #TODO(robnagler) move this to master when in production
        cat > /etc/bivio.bconf <<'EOF'
use Bivio::DefaultBConf;
Bivio::DefaultBConf->merge_dir({
    'Bivio::UI::Facade' => {
        http_host => 'www.bivio.biz',
        mail_host => 'bivio.biz',
    },
});
EOF
        chmod 444 /etc/bivio.bconf
        fpm_args+=( "$javascript_d" )
    else
        install_yum_install $(install_foss_server)/perl-Bivio-dev.rpm
    fi
    local app_d=${app_root//::/\/}
    local files_d=$app_d/files
    git clone https://github.com/biviosoftware/"$rpm_base" --depth 1
    mv "$rpm_base" "$root"
    # POSTIT: radiasoft/rsconf/rsconf/component/btest.py
    mkdir -p "$bop_d"
    rsync -a --exclude .git "$root" "$bop_d/"
    chmod -R a+rX "$bop_d"
    if [[ $root == Bivio ]]; then
        # POSIT: radiasoft/rsconf/rsconf/component/bop.py
        local src_d=/usr/share/Bivio-bOP-src
        mkdir -m 755 -p "$src_d"
        rsync -a --exclude .git "$bop_d/$root" "$src_d/"
        # perl-Bivio installs directory
        fpm_args+=( "$bop_d" "$src_d" )
    else
        fpm_args+=( "$bop_d/$root" )
    fi
    perl -p -e "s{EXE_PREFIX}{$exe_prefix}g;s{ROOT}{$root}g" <<'EOF' > Makefile.PL
use strict;
require 5.005;
use ExtUtils::MakeMaker ();
use File::Find ();
my($_EXE_FILES) = [];
my($_PM) = {};
File::Find::find(sub {
    if (-d $_ && $_ =~ m#((^|/)(\.git|old|t)|-|\.old)$#) {
	$File::Find::prune = 1;
	return;
    }
    my($file) = $File::Find::name;
    $file =~ s#^\./##;
    push(@$_EXE_FILES, $file)
	if $file =~ m{(?:^|/)(?:EXE_PREFIX-[-\w]+$)$|Bivio/Util/bivio$};
    # $(INST_LIBDIR) is where MakeMaker copies packages during
    # the build process.  The variable is interpolated by make.
    $_PM->{$file} = '$(INST_LIBDIR)/' . $file
	if $file =~ /\.pm$/;
    return;
}, 'ROOT');
ExtUtils::MakeMaker::WriteMakefile(
	 NAME => 'ROOT',
     ABSTRACT => 'ROOT',
      VERSION => '1.0',
    EXE_FILES => $_EXE_FILES,
	 'PM' => $_PM,
       AUTHOR => 'Bivio',
    PREREQ_PM => {},
);
EOF
    perl Makefile.PL DESTDIR=/ INSTALLDIRS=vendor < /dev/null
    make POD2MAN=true
    fpm_args+=(
        $( make POD2MAN=true pure_install 2>&1 | perl -n -e 'm{Installing (/usr/bin/\S+)} && print("$1\n")' )
        "/usr/share/perl5/vendor_perl/$root"
    )
    rm -rf "$facades_d"
    local tgt=$facades_d
    mkdir -p "$(dirname "$tgt")" "$tgt"
    cd "$files_d"
    local dirs
    if [[ -d ddl || -d plain ]]; then
	tgt=$tgt/$facade_uri
        # view is historical for Artisans (slideshow and extremeperl)
        # so no need here.
	dirs=( plain ddl )
        mkdir -p "$tgt"
    else
	dirs=( $(find * -type d -prune -print) )
    fi
    find "${dirs[@]}" -type l -print -o -type f -print \
	| tar Tcf - - | (cd "$tgt"; tar xpf -)
    (
        set -e
	set -x
        export BCONF=$build_d/build.bconf
        cat > "$BCONF" <<EOF
use strict;
use $app_root::BConf;
$app_root::BConf->merge_dir({
    'Bivio::UI::Facade' => {
        local_file_root => '$facades_d',
    },
    'Bivio::Ext::DBI' => {
        connection => 'Bivio::SQL::Connection::None',
    },
});
EOF
        bivio project link_facade_files
    )
    for facade in "$facades_d"/*; do
        if [[ ! -L $facade ]]; then
            mkdir -p "$facade/plain"
            ln -s -r "$javascript_d" "$facade/plain/b"
        fi
    done
    case $root in
        Societas)
            (
                cd "$build_d"/Societas/files/java
                javac *.java
                jar -cf /usr/java/societas.jar *.class
            )
            fpm_args+=( /usr/java/societas.jar )
            ;;
        BivioOrg)
            (
                cd "$facades_d"
                ln -s -r bivio.org viarob.com
            )
            ;;
        *)
            ;;
    esac
    if [[ $root == Bivio ]]; then
        fpm_args+=( "$facades_d" )
    else
        fpm_args+=( "$facades_d"/* )
    fi
    find "${fpm_args[@]}" | sort > "$rpm_build_include_f"
    echo perl-Bivio > "$rpm_build_depends_f"
}

rpm_perl_build_perl() {
    local x=(
        /usr/java
        /usr/local/share/catdoc
        /usr/local/lib64/perl5
        /usr/local/share/perl5
        /usr/local/bin/catdoc
        /usr/local/bin/catppt
        /usr/local/bin/docx2txt
        /usr/local/bin/html2ps
        /usr/local/bin/ldat
        /usr/local/bin/perl2html
        /usr/local/bin/trgrep
        /usr/local/bin/unixtime
        /usr/local/bin/xls2csv
        /usr/local/awstats
        /etc/postgrey
        /usr/sbin/postgrey
        /usr/share/postgrey
    )
    find "${x[@]}" | sort > "$rpm_build_include_f"
    echo perl > "$rpm_build_depends_f"
}

rpm_perl_build_named() {
    local rpm_base=$1
    # named config is not world readable
    umask 027
    local build_d=$PWD
    local version=$(date -u +%Y%m%d.%H%M%S)
    local fpm_args=()
    install_yum_install "$(install_foss_server)"/perl-Bivio-dev.rpm
    (cat bivio-named.pl && echo '->{NamedConf};') | bivio NamedConf generate
    local db_d=/srv/bivio_named/db
    mkdir -p "$db_d"
    tail -n +11 etc/named.conf > "$db_d/zones.conf"
    # We expect something like: zone .*.in-addr.arpa" in {
    # if that's not there, we have a problem. Better to break now
    # than later.
    if [[ ! $(head -1 "$db_d/zones.conf") = 'zone "." in {' ]]; then
        install_err "$db_d/zones.conf: expecting zone "." in {: got $(head -5 $db_d/zones.conf)"
    fi
    mv var/named/* "$db_d"
    local tmp_conf=$build_d/tmp.conf
    perl -pe "s{/var/named}{$db_d}" etc/named.conf > "$tmp_conf"
    local res=$(
        named-checkconf -z "$tmp_conf" \
        | grep -v 'zone.*loaded.serial' \
        | grep -v '_sip.*/SRV.*is a CNAME .illegal.'
    )
    if [[ $res ]]; then
        install_err "named-checkconf failed with: $res"
    fi
    chgrp -R named "$db_d"
    find "$db_d"/* | sort > "$rpm_build_include_f"
    echo bind > "$rpm_build_depends_f"
}

rpm_perl_install_rpm() {
    local base=$1
    if [[ ! ${rpm_perl_install_dir:-} ]]; then
        return
    fi
    # Y2100
    local f="$(ls -t "$base"-20[0-9][0-9]*rpm | head -1)"
    # Contains multiple directories separated by spaces
    local c d l
    for d in $rpm_perl_install_dir; do
        install -m 444 "$f" "$d/"
        for c in dev alpha; do
            l="$d/$base-$c.rpm"
            rm -f "$l"
            ln -s "$f" "$l"
        done
    done
}

rpm_perl_main() {
    if (( $# < 1 )); then
        install_err 'must supply bivio-perl or Root (for perl-Root)'
    fi
    local root=$1
    local root_lc=${root,,}
    local exe_prefix
    local app_root=$root
    local facade_uri=$root_lc
    local rpm_base build_args
    local extra_conf=
    case $1 in
        rpm_build_do)
            install_repo_eval rpm-build "$@"
            return
            ;;
        bivio-named)
            local extra_conf=$PWD/bivio-named.pl
            if [[ ! -r  $extra_conf ]]; then
                install_err "$extra_conf: must exist"
            fi
            rpm_base=bivio-named
            build_args=$rpm_base
            ;;
        bivio-perl)
            rpm_base=bivio-perl
            build_args=$rpm_base
            ;;
        Artisans)
            exe_prefix=a
            ;;
        Bivio)
            app_root=Bivio::PetShop
            exe_prefix=b
            facade_uri=petshop
            ;;
        BivioOrg)
            exe_prefix=bo
            facade_uri=bivio.org
            ;;
        Sensorimotor)
            exe_prefix=sp
            ;;
        Societas)
            exe_prefix=s
            ;;
        Zoe)
            exe_prefix=zoe
            facade_uri=zoescore
            ;;
        *)
            install_err "$1: unknown Perl app"
            ;;
    esac
    umask 077
    local p=$PWD
    install_tmp_dir
    local t=$PWD
    if [[ $extra_conf ]]; then
        cp "$extra_conf" .
    fi
    cp ~/.netrc .
    : ${rpm_base:=perl-$root}
    export rpm_build_user=root
    : ${build_args:="$rpm_base $root $exe_prefix $app_root $facade_uri"}
    install_repo_eval rpm-build "$rpm_base" "biviosoftware/perl" biviosoftware/rpm-perl rpm_perl_build $build_args
    rpm_perl_install_rpm "$rpm_base"
    # only necessary for testing; the files are owned by root, and run as vagrant
    cd "$p"
    install_sudo rm -rf "$t"
}

rpm_perl_main "${install_extra_args[@]}"
