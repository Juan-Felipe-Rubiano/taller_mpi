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
# * Descripción: Lanza el binary juntos con los argumentos desde argumentos.txt
#********************************************************************/


if (@ARGV[0]) {
   $FInput = "$ARGV[0]";
} else {
   usage();
}

#use Switch;

$path0 = `pwd`;
chomp($path0);
$T = index($path0,"T")-2;
$Path = substr($path0,0,$T);

$mpi = "mpirun -hostfile singleHost -np";

##### Captura de Argumentos
@BenchMark= ("v3ompMPI");
###Workers: 1, 2, 4, 10 
@Workers = (2,11,21,41,51);
@N = (1000,2000,4000,8000);
@TH = (1,2);
$Rep = 30;

foreach $Nombre (@BenchMark) {
	foreach $w (@Workers) {
		foreach $n (@N) {
			foreach $t (@TH) {
				$file = "$Path/mm/Soluciones/$Nombre-".$n."-workers-".$w."-Th-".$t.".dat";
				for ($k=0; $k<$Rep; $k++) {
					system("$mpi $w ./$Nombre $n $t >> $file");
					printf("$mpi $w ./$Nombre $n $t \n");
				}	
				close($file);
			}
		}
	$h=$h+1;
	}
}

sub Argument {
	$lab = $_[0];
	$pos = $_[1]; # pos: 1 2 3 4 5 
	$arg = `cat $FInput | grep $lab: | cut -f2 -d: |cut -f$pos -d" "`;
	chomp($arg);
}

sub Search {
	my($label) = @_;
	foreach (@ {$label}) {
		$name = `grep $_ $FInput | cut -f1`;
		chomp($name);
		push(@Inputs, $name);
	}
}

sub Formato {
	$in = $_[0];
	if ($in < 1000) {
		$Id = $in;
	} elsif($in < 10000) {
		$ddk = $in/10000;
		$Id = $ddk."K";
	} elsif($in < 1000000){
		$ddk = $in/1000000;
		$Id = $ddk."M";
	}
}

sub usage() {
	print "\n test.pl: Error incorrect usage \n\n";
	print "\t <directory> Is directory start point to check \n\n\n";
	exit(1);
}

