##################################
# Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
# Uso: scripts/sistema_info.sh salida
# Escribe <directorio_salida>/info_<hostname>.txt (default directorio actual). Ejecutado por lanzador.

SALIDA=${1:-.}
mkdir -p "$SALIDA" || exit 1
ARCHIVO="$SALIDA/info_$(hostname -s).txt"
 
{
    echo "# Información del sistema: $(hostname) - $(date -Is)"
    echo
    echo "## Sistema operativo"
    ( . /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" )
    uname -srm
    echo
    echo "## Virtualización"
    systemd-detect-virt 2>/dev/null || echo "no se pudo determinar (systemd-detect-virt no disponible)"
    echo
    echo "## CPU (lscpu)"
    lscpu
    echo
    echo "## Núcleos lógicos disponibles (nproc)"
    nproc
    echo
    echo "## Memoria"
    free -h
    echo
    echo "## Cachés por núcleo (sysfs) y N máximo para el que una matriz cabe"
    printf '%-6s %-12s %10s   %s\n' nivel tipo tamaño "N máx (una matriz N*N doubles)"
    for d in /sys/devices/system/cpu/cpu0/cache/index*; do
        [ -r "$d/size" ] || continue
        nivel=$(cat "$d/level"); tipo=$(cat "$d/type"); tam=$(cat "$d/size")
        [ "$tipo" = Instruction ] && continue
        awk -v n="L$nivel" -v t="$tipo" -v s="$tam" 'BEGIN{
            b=s+0; if (s ~ /[Kk]$/) b*=1024; else if (s ~ /[Mm]$/) b*=1048576;
            printf "%-6s %-12s %10s   %d\n", n, t, s, int(sqrt(b/8)) }'
    done
    echo "(el L3 suele compartirse entre núcleos y, en una VM, con otras máquinas del host)"
    echo
    echo "## Gobernador de frecuencia de CPU"
    cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "no disponible (típico en VM o WSL)"
    echo
    echo "## Compilador y MPI"
    gcc --version 2>/dev/null | head -1
    mpicc --version 2>/dev/null | head -1
    mpirun --version 2>/dev/null | head -1
    echo
    echo "## Variables OpenMP"
    echo "OMP_NUM_THREADS=${OMP_NUM_THREADS:-no definida}  OMP_PROC_BIND=${OMP_PROC_BIND:-no definida}"
    echo
    echo "## Carga al iniciar"
    uptime
} > "$ARCHIVO" 2>&1
 
echo "$ARCHIVO"