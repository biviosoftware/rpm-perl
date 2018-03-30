#!/bin/bash

rpm_perl_build() {
    local root=$1 exe_prefix=$2 app_root=$3 facade_uri=$4
    umask 022
    cd "$build_guest_conf"
    local build_d=$PWD
    local facades_d=/var/www/facades
    local javascript_d=/usr/share/Bivio-bOP-javascript
    local flags=()
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
        flags=( --branch robnagler --single-branch )
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
        install_download perl-Bivio.rpm
        fpm_args+=(
            --rpm-auto-add-exclude-directories "$facades_d"
            --rpm-auto-add-exclude-directories "$bop_d"
        )
    fi
    local app_d=${app_root//::/\/}
    local files_d=$app_d/files
    git clone "${flags[@]}" https://github.com/biviosoftware/perl-"$root" --depth 1
    mv perl-"$root" "$root"
    # POSTIT: radiasoft/rsconf/rsconf/component/btest.py
    local bop_d="/usr/src/bop"
    mkdir -p "$bop_d"
    cp -a "$root" "$bop_d"
    chmod -R a+rX "$bop_d"
    if [[ $root == Bivio ]]; then
        # POSIT: radiasoft/rsconf/rsconf/component/bop.py
        local src_d=/usr/share/Bivio-bOP-src
        mkdir -m 755 -p "$src_d"
        cp -a "$bop_d/$root" "$src_d"
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
    if [[ $facade_uri == bivio.org ]]; then
        (
            cd "$facades_d"
            ln -s -r bivio.org via.rob
        )
    fi
    if [[ $root == Bivio ]]; then
        # fpm is fickle if the directory is in the exclude list so need to be very explicit here
        # "Cannot copy file, the destination path is probably a directory and I attempted to write a file."
        fpm_args+=( "$facades_d" )
    else
        fpm_args+=( "$facades_d"/* )
    fi
    cd /rpm-perl
    # fpm should not add the /usr/share or /var/www dirs to the %files of the rpm
    fpm -t rpm -s dir -n "perl-$root" -v "$version" --rpm-auto-add-directories \
        --rpm-auto-add-exclude-directories /usr/share/perl5 \
        --rpm-auto-add-exclude-directories /usr/share/perl5/vendor_perl \
        --rpm-auto-add-exclude-directories /var/www \
        --rpm-use-file-permissions "${fpm_args[@]}"

}

rpm_perl_create_bivio_perl() {
    umask 077
    install_tmp_dir
    docker run -i --network=host --rm -v $PWD:/rpm-perl biviosoftware/perl <<'EOF'
set -euo pipefail
cd /rpm-perl
v=$(python -c 'import json; print json.load(open("/rsmanifest.json"))["image"]["version"]')
x=(
    /usr/java
    /usr/local/share/catdoc
    /usr/local/lib64/perl5
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
fpm -t rpm -s dir -n bivio-perl -v "$v" --rpm-auto-add-directories --rpm-use-file-permissions "${x[@]}"
EOF
    rpm_perl_install_rpm bivio-perl
}

rpm_perl_install_rpm() {
    local base=$1
    if [[ ! $rpm_perl_install_dir ]]; then
        return
    fi
    local f="$(ls -t "$base"*rpm | head -1)"
    install -m 444 "$f" "$rpm_perl_install_dir/"
    local l="$rpm_perl_install_dir/$base.rpm"
    rm -f "$l"
    ln -s "$f" "$l"
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
    case $1 in
        _build)
            shift
            rpm_perl_build "$@"
            return
            ;;
        bivio-perl)
            rpm_perl_create_bivio_perl
            return
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
    install_tmp_dir
    cp ~/.netrc netrc
    docker run -i --network=host --rm -v $PWD:/rpm-perl biviosoftware/perl <<EOF
. ~/.bashrc
cd /rpm-perl
install -m 400 netrc ~/.netrc
export install_server='$install_server' install_channel='$install_channel' install_debug='$install_debug'
curl radia.run | bash -s biviosoftware/rpm-perl _build '$root' '$exe_prefix' '$app_root' '$facade_uri'
EOF
    rpm_perl_install_rpm "perl-$root"
}


rpm_perl_main "${install_extra_args[@]}"
