# Verify caching of GCC C++20 named modules, selected with -fmodules.
#
# The same option name means Clang header modules, where the module files are
# rebuilt on demand and the compilation is cacheable under "modules"
# sloppiness. On GCC it means named modules: an import resolves to a BMI in
# gcm.cache that the consumer reads, and that BMI is named only in the
# dependency information. A consumer cached without that information runs stale
# code after the module interface changes.

SUITE_gcc_modules_PROBE() {
    if ! $COMPILER_TYPE_GCC || $COMPILER_USES_MSVC; then
        echo "GCC named modules not supported by compiler"
    else
        echo 'export module probe_module;' >probe_module.cppm
        $COMPILER -std=c++20 -fmodules -x c++ -c \
            probe_module.cppm -o probe_module.o 2>/dev/null \
            || echo "compiler does not support GCC named modules"
    fi
}

SUITE_gcc_modules_SETUP() {
    unset CCACHE_NODIRECT
    export CCACHE_DEPEND=1

    cat <<'EOF' >main.cpp
import somemodule;
int main() { return module_value; }
EOF

    generate_module() {
        cat <<EOF >module.cppm
export module somemodule;
export constexpr int module_value = $1;
EOF
        rm -rf gcm.cache
        $COMPILER -std=c++20 -fmodules -x c++ -c module.cppm -o module.o
    }

    generate_module 1
}

SUITE_gcc_modules() {
    # -------------------------------------------------------------------------
    TEST "no dependency output is uncacheable"

    # Depend mode only records the BMI when the compilation writes dependency
    # information, so without it nothing describing the module is hashed.
    CCACHE_SLOPPINESS="$DEFAULT_SLOPPINESS modules" $CCACHE_COMPILE \
        -std=c++20 -fmodules -c main.cpp -o main.o
    expect_stat could_not_use_modules 1

    CCACHE_SLOPPINESS="$DEFAULT_SLOPPINESS modules" $CCACHE_COMPILE \
        -std=c++20 -fmodules -c main.cpp -o main.o
    expect_stat could_not_use_modules 2

    # -------------------------------------------------------------------------
    TEST "changed module interface is not served from the cache"

    CCACHE_SLOPPINESS="$DEFAULT_SLOPPINESS modules" $CCACHE_COMPILE \
        -std=c++20 -fmodules -MD -MF main.d -c main.cpp -o main.o
    $COMPILER main.o module.o -o prog
    ./prog
    expect_equal_text_content <(echo 1) <(echo $?)

    generate_module 42

    CCACHE_SLOPPINESS="$DEFAULT_SLOPPINESS modules" $CCACHE_COMPILE \
        -std=c++20 -fmodules -MD -MF main.d -c main.cpp -o main.o
    $COMPILER main.o module.o -o prog
    ./prog
    expect_equal_text_content <(echo 42) <(echo $?)

    # -------------------------------------------------------------------------
    TEST "cache hit against an unchanged module"

    CCACHE_SLOPPINESS="$DEFAULT_SLOPPINESS modules" $CCACHE_COMPILE \
        -std=c++20 -fmodules -MD -MF main.d -c main.cpp -o main.o
    expect_stat direct_cache_hit 0
    expect_stat cache_miss 1

    CCACHE_SLOPPINESS="$DEFAULT_SLOPPINESS modules" $CCACHE_COMPILE \
        -std=c++20 -fmodules -MD -MF main.d -c main.cpp -o main.o
    expect_stat direct_cache_hit 1
    expect_stat cache_miss 1

    # -------------------------------------------------------------------------
    TEST "no sloppiness is uncacheable"

    $CCACHE_COMPILE -std=c++20 -fmodules -MD -MF main.d -c main.cpp -o main.o
    expect_stat could_not_use_modules 1
}
