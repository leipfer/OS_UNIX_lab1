#!/bin/sh
E_USAGE=1
E_NOSRC=2
E_TYPE=3
E_NOOUT=4
E_NOTOOL=5
E_TMP=6
E_BUILD=7
E_COPY=8

PROG=${0##*/}
TMPD=
CHILD=

err() {
    printf '%s: ошибка: %s\n' "$PROG" "$*" >&2
}

die() {
    code=$1
    shift
    err "$@"
    exit "$code"
}

cleanup() {
    rc=$?
    trap - EXIT
    if [ -n "$CHILD" ]; then
        kill -TERM "$CHILD" 2>/dev/null
        wait "$CHILD" 2>/dev/null
    fi
    if [ -n "$TMPD" ] && [ -d "$TMPD" ]; then
        rm -rf -- "$TMPD"
    fi
    exit "$rc"
}

on_signal() {
    err "получен сигнал $1, сборка прервана"
    exit $((128 + $2))
}

run() {
    "$@" &
    CHILD=$!
    wait "$CHILD"
    rc=$?
    CHILD=
    return "$rc"
}

trap cleanup EXIT
trap 'on_signal HUP 1'   HUP
trap 'on_signal INT 2'   INT
trap 'on_signal QUIT 3'  QUIT
trap 'on_signal PIPE 13' PIPE
trap 'on_signal TERM 15' TERM

if [ $# -ne 1 ]; then
    printf 'Использование: %s ФАЙЛ\n' "$PROG" >&2
    exit "$E_USAGE"
fi

SRC=$1
[ -e "$SRC" ] || die "$E_NOSRC" "файл '$SRC' не существует"
[ -f "$SRC" ] || die "$E_NOSRC" "'$SRC' не является обычным файлом"
[ -r "$SRC" ] || die "$E_NOSRC" "файл '$SRC' недоступен для чтения"

case $SRC in
    */*) SRCDIR=${SRC%/*} ;;
    *)   SRCDIR=. ;;
esac
[ -n "$SRCDIR" ] || SRCDIR=/
SRCDIR=$(cd -- "$SRCDIR" && pwd) || die "$E_NOSRC" "не удалось перейти в каталог '$SRCDIR'"
SRCNAME=${SRC##*/}
SRCABS=$SRCDIR/$SRCNAME

case $SRCNAME in
    *.c)                             TYPE=c   ;;
    *.cc|*.cpp|*.cxx|*.c++|*.C)      TYPE=cxx ;;
    *.tex)                           TYPE=tex ;;
    *) die "$E_TYPE" "неподдерживаемый тип файла '$SRCNAME' (ожидается .c, .cpp, .cc, .cxx или .tex)" ;;
esac

case $TYPE in
    c|cxx) RE='^[[:space:]]*(//|/\*|\*)[[:space:]]*Output:' ;;
    tex)   RE='^[[:space:]]*%+[[:space:]]*Output:' ;;
esac

OUT=$(grep -E -- "$RE" "$SRCABS" | sed -n '1{
s/^.*Output:[[:space:]]*//
s/\*\/.*$//
s/[[:space:]].*$//
p
}')

[ -n "$OUT" ] || die "$E_NOOUT" "в файле '$SRCNAME' не найден комментарий 'Output: <имя>'"
case $OUT in
    */*)   die "$E_NOOUT" "имя конечного файла '$OUT' не должно содержать '/'" ;;
    .|..)  die "$E_NOOUT" "недопустимое имя конечного файла '$OUT'" ;;
esac
[ "$OUT" != "$SRCNAME" ] || die "$E_NOOUT" "имя конечного файла совпадает с именем исходного"

case $TYPE in
    c)   TOOL=${CC:-cc} ;;
    cxx) TOOL=${CXX:-c++} ;;
    tex) TOOL=${TEX:-pdflatex} ;;
esac
command -v "$TOOL" >/dev/null 2>&1 || die "$E_NOTOOL" "компилятор '$TOOL' не найден"

TMPD=$(mktemp -d "${TMPDIR:-/tmp}/build.XXXXXXXX") || {
    TMPD=
    die "$E_TMP" "не удалось создать временный каталог"
}

cd -- "$TMPD" || die "$E_TMP" "не удалось перейти во временный каталог"

printf '%s: %s -> %s (каталог сборки %s)\n' "$PROG" "$SRCNAME" "$OUT" "$TMPD"

case $TYPE in
    c)
        run "$TOOL" $CFLAGS -o "$TMPD/result" "$SRCABS" $LDFLAGS \
            || die "$E_BUILD" "ошибка компиляции '$SRCNAME'"
        ;;
    cxx)
        run "$TOOL" $CXXFLAGS -o "$TMPD/result" "$SRCABS" $LDFLAGS \
            || die "$E_BUILD" "ошибка компиляции '$SRCNAME'"
        ;;
    tex)
        TEXINPUTS=$SRCDIR:${TEXINPUTS:-}
        export TEXINPUTS
        for pass in 1 2; do
            run "$TOOL" -interaction=nonstopmode -halt-on-error \
                    -output-directory="$TMPD" -jobname=result "$SRCABS" \
                    >"$TMPD/build.out" 2>&1 || {
                tail -n 20 "$TMPD/build.out" >&2
                die "$E_BUILD" "ошибка компиляции '$SRCNAME' (проход $pass)"
            }
        done
        mv -f -- "$TMPD/result.pdf" "$TMPD/result" \
            || die "$E_BUILD" "pdflatex не создал PDF-файл"
        ;;
esac

[ -f "$TMPD/result" ] || die "$E_BUILD" "компилятор не создал конечный файл"

DEST=$SRCDIR/$OUT
PART=$SRCDIR/.$OUT.part.$$
if ! { cp -p -- "$TMPD/result" "$PART" && mv -f -- "$PART" "$DEST"; }; then
    rm -f -- "$PART"
    die "$E_COPY" "не удалось записать '$DEST'"
fi

printf '%s: готово: %s\n' "$PROG" "$DEST"
exit 0
