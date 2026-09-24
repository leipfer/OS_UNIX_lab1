# Демонстрация работы build.sh на примерах. Запуск: sh test.sh
cd "$(dirname "$0")/examples" || exit 1
B=../build.sh

check() {
    exp=$1; shift
    sh "$B" "$@" >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq "$exp" ]; then r=OK; else r=FAIL; fi
    printf '%-4s  %-12s ожидалось %3s, получено %3s\n' "$r" "${1:-<нет>}" "$exp" "$rc"
}

check 0 hello.c
check 0 hello.cpp
check 0 report.tex
check 7 broken.c
check 4 nooutput.c
check 2 missing.c
check 1

echo " проверка сигнала: SIGTERM во время «долгой» компиляции"
CC=$PWD/slowcc sh "$B" hello.c & P=$!
sleep 1
echo "временный каталог во время сборки: $(ls -d "${TMPDIR:-/tmp}"/build.* 2>/dev/null)"
kill -TERM "$P"; wait "$P"; echo "код выхода: $? (ожидалось 143)"
echo "осталось временных каталогов: $(ls -d "${TMPDIR:-/tmp}"/build.* 2>/dev/null | wc -l)"
echo " результаты рядом с исходниками:"
ls -l hello hello_cpp report.pdf
