#!/usr/bin/perl

#*********************************************************************
# * 			Pontificia Universidad Javeriana
# * 						----=----
# * 	Taller Evaluación de Rendimiento de Sistemas de Cómputo
# *
# * Autor: Ing. John Corredor Franco, PhD.
# * Revision para taller: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
# * Fecha:
# * Objetivo:
# * Descripción: Ejecuta experimentos donde un experimento es una combinación de entorno, hilos y dimensiones de entrada.
# * Salida: resultados/sistema/: <binario>-<N>-w<W>-h<H>.dat, bitacora.csv, info_<nodo>.txt, errores.log
# * Uso:
# * perl lanzador.pl --sistema cluster --ver    	listar experimentos disponibles
# * perl lanzador.pl --sistema cluster --probar    	3 repeticiones y proyección de tiempo
# * perl lanzador.pl --sistema cluster 		    	experimentos completos
#********************************************************************/

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use List::Util qw(shuffle);
use POSIX qw(strftime);
use Time::HiRes qw(time);
use File::Path qw(make_path);
use FindBin qw($Bin);

$| = 1;

# Params
my @BINARIOS = qw(mxmMPI_FxC mxmMPI_FxT mxmMPIompFxC mxmMPIompFxT mxmMPIpthFxC mxmMPIpthFxT);
my @Ns       = (256, 512, 1024, 2048);
my @Ws       = (1, 2, 4);              # workers
my @Hs       = (1, 2, 4);              # hilos por worker
my $REPS     = 30;
my $TIMEOUT  = 1800;                   # segundos máximos por ejecución
my $INTENTOS = 3;                      # intentos por ejecución antes de darla por fallida
my $NUCLEOS_CLUSTER = 4;               # cores por nodo
my $HOSTFILE = "$Bin/nodos";           # solo para --sistema cluster
my $MPI_CLUSTER = "mpirun --hostfile '$HOSTFILE' --map-by node --bind-to none";
my $MPI_LOCAL   = "mpirun --oversubscribe --bind-to none";

# Opciones
my %opt;
GetOptions(\%opt, 'sistema=s', 'rep=i', 'probar', 'ver') or die "Opciones inválidas\n";
die "Uso: perl lanzador.pl --sistema <cluster|nombre> [--ver] [--probar] [--rep N]\n"
    unless $opt{sistema};
my $cluster = $opt{sistema} eq 'cluster';
my $reps    = $opt{probar} ? 3 : ($opt{rep} // $REPS);
 
my $slots = 0;
my $nucleos;
if ($cluster) {
    open(my $hf, '<', $HOSTFILE) or die "No se puede abrir $HOSTFILE: $!\n";
    while (<$hf>) { s/#.*//; next unless /\S/; $slots += (/slots=(\d+)/ ? $1 : 1) }
    close $hf;
    $nucleos = $NUCLEOS_CLUSTER;
} else {
    chomp($nucleos = `nproc`);
}
my $mpi = $cluster ? $MPI_CLUSTER : $MPI_LOCAL;
 
for my $b (@BINARIOS) { die "Falta bin/$b. Ejecutar 'make' primero.\n" unless -x "$Bin/bin/$b" }

# Combinaciones

my (@configs, $descartadas);
for my $b (@BINARIOS) {
    for my $N (@Ns) {
        for my $W (@Ws) {
            for my $H ($b =~ /(omp|pth)/ ? @Hs : (1)) {
                my $ok = $N % $W == 0 && ($N / $W) % $H == 0
                      && ($cluster ? ($W + 1 <= $slots && $H <= $nucleos)
                                   : ($W * $H <= $nucleos));
                if (!$ok) { $descartadas++; next }
                push @configs, { bin => $b, N => $N, W => $W, H => $H,
                                 clave => "$b|$N|$W|$H", dat => "$b-$N-w$W-h$H.dat" };
            }
        }
    }
}
die "Ninguna combinación es válida.\n" unless @configs;

# Reanudar por si se cae pues el experimento completo puede durar muchas horas

my $dir      = "$Bin/resultados/$opt{sistema}";
my $bitacora = "$dir/bitacora.csv";
my %hechas;                              # clave -> ejecuciones válidas ya guardadas
if (-e $bitacora) {
    open(my $bf, '<', $bitacora) or die "No se puede leer $bitacora: $!\n";
    <$bf>;
    while (<$bf>) {
        chomp;
        my @c = split /,/;               # fecha,ronda,orden,binario,alg,modelo,N,W,H,rc,...
        $hechas{"$c[3]|$c[6]|$c[7]|$c[8]"}++ if @c >= 13 && $c[9] == 0;
    }
    close $bf;
}
my $pendientes = 0;
for (@configs) { my $h = $hechas{$_->{clave}} // 0; $pendientes += $reps - $h if $h < $reps }
 
printf "Sistema: %s (%s, %d núcleos por nodo)   repeticiones: %d\n",
       $opt{sistema}, $cluster ? "cluster, $slots slots" : "local", $nucleos, $reps;
printf "Configuraciones válidas: %d   descartadas: %d   ejecuciones pendientes: %d\n",
       scalar(@configs), $descartadas // 0, $pendientes;
if ($opt{ver}) { print "(--ver: no se ejecutó nada)\n"; exit 0 }
if (!$pendientes) { print "Nada que hacer: ya están todas las repeticiones.\n"; exit 0 }
 
make_path($dir);
my $nueva = !-e $bitacora;
open(my $bit, '>>', $bitacora) or die "No se puede escribir $bitacora: $!\n";
select((select($bit), $| = 1)[0]);
print $bit "fecha,ronda,orden,binario,algoritmo,modelo,N,workers,hilos,rc,t_us,t_mpi_s,intento\n" if $nueva;
open(my $err, '>>', "$dir/errores.log") or die $!;
select((select($err), $| = 1)[0]);
 
sub fecha { return strftime('%Y-%m-%dT%H:%M:%S', localtime) }

# Información de la máquina
unless (glob("$dir/info_*.txt")) {
    my $cmd = $cluster ? "$mpi -np $slots '$Bin/scripts/sistema_info.sh' '$dir'"
                       : "'$Bin/scripts/sistema_info.sh' '$dir'";
    system("$cmd > /dev/null 2>> '$dir/errores.log' < /dev/null") == 0
        or warn "AVISO: no se pudo recolectar la información (scripts/sistema_info.sh).\n";
}

# Una ejecución (retorna rc, salida, t_us, t_mpi_s, stderr)
sub ejecutar {
    my ($bin, $N, $W, $H) = @_;
    my $ef  = "$dir/.stderr_tmp";
    my $out = `timeout -k 10 $TIMEOUT $mpi -np ${\($W + 1)} '$Bin/bin/$bin' $N $H 2> '$ef' < /dev/null`;
    my $rc  = $? == -1 ? 127 : ($? & 127) ? 128 + ($? & 127) : $? >> 8;
    my $stderr = '';
    if (open(my $e, '<', $ef)) { local $/; $stderr = <$e> // ''; close $e }
    unlink $ef;
    my @us   = $out =~ /^[ \t]*(\d+)[ \t]*$/mg;                       # línea en microsegundos
    my ($tm) = $out =~ /Tiempo(?: por)? MPI\s*[=:]\s*([0-9.]+)/;     # línea en segundos
    return ($rc, $out, $us[-1], $tm, $stderr);
}
 
$SIG{INT} = $SIG{TERM} = sub {
    print "\nInterrumpido. Vuelva a lanzar el MISMO comando para continuar donde quedó.\n";
    exit 130;
};

# Calentamiento
my $menor = (sort { $a <=> $b } map { $_->{N} } @configs)[0];
for my $b (@BINARIOS) {
    my ($c) = grep { $_->{bin} eq $b && $_->{N} == $menor && $_->{W} == 1 && $_->{H} == 1 } @configs;
    ejecutar($b, $c->{N}, 1, 1) if $c;
}

# rondas
my $t_ini = time;
my ($ok, $fallos, $rondas) = (0, 0, 0);
print "\nEjecutando " . scalar(@configs) . " configuraciones por ronda, hasta $reps rondas.\n";
 
for my $ronda (1 .. $reps) {
    my @lista = shuffle grep { ($hechas{$_->{clave}} // 0) < $ronda } @configs;
    next unless @lista;
    $rondas++;
    my $orden = 0;
    for my $c (@lista) {
        $orden++;
        my ($rc, $out, $us, $tm, $stderr);
        for my $intento (1 .. $INTENTOS) {
            ($rc, $out, $us, $tm, $stderr) = ejecutar($c->{bin}, $c->{N}, $c->{W}, $c->{H});
            my $valida = $rc == 0 && defined $us && defined $tm;
            printf $bit "%s,%d,%d,%s,%s,%s,%d,%d,%d,%d,%s,%s,%d\n",
                   fecha(), $ronda, $orden, $c->{bin},
                   $c->{bin} =~ /FxT$/ ? 'FxT' : 'FxC',
                   $c->{bin} =~ /omp/ ? 'omp' : $c->{bin} =~ /pth/ ? 'pth' : 'mpi',
                   $c->{N}, $c->{W}, $c->{H}, $rc, $us // '', $tm // '', $intento;
            if ($valida) {
                open(my $d, '>>', "$dir/$c->{dat}") or die "No se puede escribir $c->{dat}: $!\n";
                $out .= "\n" unless $out =~ /\n$/;
                print $d $out;
                close $d;
                print $err "[" . fecha() . "] AVISO $c->{bin} N=$c->{N} W=$c->{W} H=$c->{H}: $stderr\n"
                    if $stderr =~ /\S/;
                $hechas{$c->{clave}}++; $ok++;
                last;
            }
            print $err "[" . fecha() . "] FALLO (rc=$rc) intento $intento: $c->{bin} N=$c->{N} W=$c->{W} H=$c->{H}\n$stderr\n";
            $fallos++;
        }
        my $t   = time - $t_ini;
        my $eta = $ok ? $t / $ok * ($pendientes - $ok) : 0;
        printf "[ronda %2d/%d] %4d/%d  %-13s N=%-5d W=%d H=%d  %s  (ETA %s)\n",
               $ronda, $reps, $ok, $pendientes, $c->{bin}, $c->{N}, $c->{W}, $c->{H},
               $rc == 0 && defined $tm ? sprintf("%.3f s", $tm) : "FALLO rc=$rc",
               $eta > 0 ? sprintf("%dh%02dm", $eta / 3600, ($eta % 3600) / 60) : "-";
    }
}

# Final

my $total = time - $t_ini;
printf "\nTerminado: %d ejecuciones válidas, %d intentos fallidos, %.1f min.\n", $ok, $fallos, $total / 60;
printf "Proyección de la batería completa (%d repeticiones): %.1f horas.\n", $REPS, $total / $rondas * $REPS / 3600
    if $opt{piloto} && $rondas;
print "Resultados en $dir\n";
exit($fallos && !$ok ? 1 : 0);
