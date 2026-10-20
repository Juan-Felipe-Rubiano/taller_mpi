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
# * 			 Si se detiene, se puede reanudar desde donde quedó con el mismo comando.
# * Salida: almacena el resultado de cada ejecución en una fila de resultados/<sistema>.csv
# * Uso:
# * perl lanzador.pl cluster    			usando el archivo "nodos" que contiene los nodos del cluster de nuestro equipo
# * perl lanzador.pl <nombre_maquina>    	para correr en la máquina actual
#********************************************************************/

use strict; use warnings;
use List::Util qw(shuffle);
use FindBin qw($Bin);
 
my $sistema = shift or die "Uso: perl lanzador.pl <cluster|nombre>\n";
my @BIN = qw(mxmMPI_FxC mxmMPI_FxT mxmMPIompFxC mxmMPIompFxT mxmMPIpthFxC mxmMPIpthFxT);
my @N = (256, 512, 1024, 2048);
my @W = (1, 2, 4);      # workers
my @H = (1, 2, 4);      # hilos por worker (para openmp y pthread, todas las máquinas tienen 4 cores)
my $REPS = 30;
 
my $cluster = $sistema eq 'cluster';
my $nucleos = $cluster ? 4 : `nproc`;
chomp $nucleos;
my $mpi = $cluster ? "mpirun --hostfile $Bin/nodos --map-by node --bind-to none"
                   : "mpirun --oversubscribe --bind-to none";
 
# Configuraciones válidas
my @cfg;
for my $b (@BIN) { for my $n (@N) { for my $w (@W) { for my $h ($b =~ /omp|pth/ ? @H : (1)) {
    next if $n % $w || ($n / $w) % $h; # tamaños divisibles
    next if $h > $nucleos || (!$cluster && $w * $h > $nucleos);
    push @cfg, [$b, $n, $w, $h];
}}}}
 
# Reanudar ejecuciones ya guardadas
my $csv = "$Bin/resultados/$sistema.csv";
mkdir "$Bin/resultados";
my %hechas;
if (open my $f, '<', $csv) { <$f>; while (<$f>) { my @c = split /,/; $hechas{"$c[0],$c[1],$c[2],$c[3]"}++ } close $f }
open my $out, '>>', $csv or die "$csv: $!\n";
select((select($out), $| = 1)[0]);
print $out "binario,N,workers,hilos,ronda,t_us,t_seg\n" unless -s $csv;

print scalar(@cfg), " configuraciones x $REPS repeticiones\n";
for my $ronda (1 .. $REPS) {
    for my $c (shuffle grep { ($hechas{join ',', @$_} // 0) < $ronda } @cfg) {
        my ($b, $n, $w, $h) = @$c;
        my $salida = `timeout 1800 $mpi -np ${\($w + 1)} $Bin/bin/$b $n $h 2>&1 < /dev/null`;
        my ($t) = $salida =~ /Tiempo(?: por)? MPI\s*[=:]\s*([0-9.]+)/;
		my @us = $salida =~ /^[ \t]*(\d+)[ \t]*$/mg;
		if ($? != 0 || !defined $t || !@us) { warn "FALLO: $b N=$n W=$w H=$h\n"; next }
        print $out "$b,$n,$w,$h,$ronda,$us[-1],$t\n";
        print "ronda $ronda/$REPS  $b N=$n W=$w H=$h  $t s\n";
    }
}