#!/bin/bash
##################################
# Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
# Uso: scripts/sistema_info.sh salida
# Escribe <directorio_salida>/info_<hostname>.txt (default directorio actual) con información del sistema, incluyendo:
# 1. Sistema operativo y kernel
# 2. Virtualización
# 3. CPU (arquitectura, cores, hilos, frecuencia, etc)
# 4. RAM
# 5. Cachés por núcleo y N máximo para que una matriz de doubles (N*N*8 bytes) quepa en caché L1, L2 y L3 (jerarquía de memoria)
# 6. Compilador y MPI
##################################
mkdir -p "$1" || exit 1
{
    echo "1. Sistema";  . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME"; uname -srm
    echo "2. Virtualización"; systemd-detect-virt 2>/dev/null || echo "no determinada"
    echo "3. CPU"; lscpu
    echo "4. Memoria"; free -h
    echo "5. Cachés por core y N máximo para que una matriz de doubles (N*N*8 bytes) quepa en caché L1, L2 y L3 (jerarquía de memoria)"
    for d in /sys/devices/system/cpu/cpu0/cache/index*; do
        [ "$(cat $d/type 2>/dev/null)" = Instruction ] && continue
        awk -v n="L$(cat $d/level)" -v s="$(cat $d/size)" 'BEGIN{
            b=s+0; if (s ~ /K$/) b*=1024; else if (s ~ /M$/) b*=1048576;
            printf "%s %s  N max = %d\n", n, s, int(sqrt(b/8)) }'
    done
    echo "6. Compilador y MPI"; gcc --version | head -1; mpirun --version | head -1
} > "$1/info_$(hostname -s).txt" 2>&1
echo "$1/info_$(hostname -s).txt"