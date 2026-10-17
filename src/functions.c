/************************************************************************************************
								=	Pontificia Universidad Javeriana	=

	Author: John Corredor
	Versión Prototipo "Inicial" MPI Distribución de Matrices en Nodos de Cómputo	

	Descripción:
		Multiplicación de Matrices cuadradas, algoritmo Filas x Columnas
		Square Matrix Multiplication, rowsxcolumns version:
		=> MPI_Init:				- Inicializacíón del entorno MPI 
		=> MPI_Comm_size:			- Obtener cantidad de procesos o workers en ejecución
		=> MPI_Comm_rank:			- Obtener el ID del proceso o worker  
		=> MPI_Get_processor_name:	- Obtener nombre del Nodo de Cómputo 
		=> MPI_Finalize:			- Finalización del entorno MPI

	Ejecución:
		$mpirun -hostfile fileHOSTSMPI -np 3 ./mmMPIv1 8 1
************************************************************************************************/
#include <mpi.h>
#include <omp.h>
#include <stdio.h>
#include <omp.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include "functions.h" 

// Estructura de datos para la toma de tiempos
struct timeval inicio, fin;

//Función inicialización matrices
void iniMatrix(double *mA, double *mB, int D){
	srand(time(NULL));
	for(int i=0; i<D*D; i++, mA++, mB++){
		*mA = (0.1*i + 0.3*i) * (double) rand()/RAND_MAX*(5.1-2.3);
		*mB = (2.3*i - 0.1*i) * (double) rand()/RAND_MAX*(6.1-2.8);
	}
}

//Función impresión para verificación
void impMatrix(double *matrix, int D){
	if(D<14){
		for (int i = 0; i < D*D; i++, matrix++) {
			if(i%D == 0 ) printf("\n"); 
			printf("%9.2f ", *matrix);
		}
		printf("\n\n");
	}
}

//Función matrix Transpuesta
void matrixTRP(double *mB, double *mT, int D){
	for(int i=0; i<D; i++)
		for(int j=0; j<D; j++)
			mT[i*D+j] = mB[j*D+i];
	impMatrix(mT, D);
}

//Función MxM: algoritmo clásico filasxcolumnas
void mxmFxC(double *mA, double *mB, double *mC, int tw, int D){
	for(int i=0; i<tw; i++)
		for(int j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j;
			for(int k=0; k<D; k++, pA++, pB+=D)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
}

//Función MxM: algoritmo filasxfilas
void mxmFxT(double *mA, double *mB, double *mC, int tw, int D){
	for(int i=0; i<tw; i++)
		for(int j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j*D;
			for(int k=0; k<D; k++, pA++, pB++)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
}

//Función MxM: algoritmo clásico con uso de OpenMP
void mxmOmpFxC(double *mA, double *mB, double *mC, int tw, int D, int nH){
	int i,j,k;
	#pragma omp parallel
	{
	#pragma omp parallel for private(i,j,k) 
	for(i=0; i<tw; i++)
		for(j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j;
			for(k=0; k<D; k++, pA++, pB+=D)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
	}
}

//Función MxM: algoritmo  FilasxFilas <matrix transpuesta> con uso de Hilos OpenMP
void mxmOmpFxT(double *mA, double *mB, double *mC, int tw, int D, int nH){
	int i,j,k;
	#pragma omp parallel
	{
	#pragma omp parallel for private(i,j,k) 
	for(i=0; i<tw; i++)
		for(j=0; j<D; j++){
			double Suma = 0.0;
			double *pA = mA+i*D;
			double *pB = mB+j*D;
			for(k=0; k<D; k++, pA++, pB++)
				Suma += *pA * *pB;
			mC[i*D+j] = Suma;
		}
	}
}


void mensajeVerifica(int N, int cantidadW){
	if(N<14){
		printf("\n");
		printf("********************************************************************\n");
		printf("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n");
		printf("++++++ \t\tDimensión de Matrix NxN \t  = %dx%d \t++++\n", N, N);
		printf("++++++ \t\tCantidad de Workers (np - MASTER) = %d \t\t++++\n", cantidadW);
		printf("++++++ \t\tTajada de matriz A para Workers   = %dx%d \t++++\n", N/cantidadW,N);
		printf("++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++\n");
		printf("********************************************************************\n");
		printf("\n");
	}
}

void iniTime(){
		gettimeofday(&inicio, (void *)0);
}

void endTime(){
		gettimeofday(&fin, (void *)0);
		fin.tv_usec -= inicio.tv_usec;
		fin.tv_sec  -= inicio.tv_sec;
		double tiempo = (double) (fin.tv_sec*1000000 + fin.tv_usec);
		printf("%9.0f \n", tiempo);
}

void argumentos(int cantidad){
	if (cantidad != 3){
		printf("Ingreso de Argumentos: \n\n");
		printf("\t\t$mpirun -hostfile file -np p ./ejecutable DimMatriz NumHilos \n\n");
		exit(0);
	}
}

void verificarDiv(int qworkers, int Dim){
	// Se revisa que modulo de Dimensión de Matrix / Workers == 0
	if ((qworkers < 1) || (Dim%qworkers != 0)) {
		printf("Error: NxN (%d) debe ser divisible por cantidad de workers (%d)\n", Dim, qworkers);
		printf("Error: Número de procesos (%d) > 1 \n", qworkers);
		MPI_Abort(MPI_COMM_WORLD, 1);
		exit(0);
	}
	if(Dim<14){
		printf("|================================================================================|\n");
		printf("|\t\t\tMultiplicación de Matrices  << MPI >>             	 |\n");
		printf("|================================================================================|\n");
		printf(" \t= Dimensión Matrix NxN = %dx%d \n", Dim, Dim);
		printf(" \t= Distribución de %d filas 'Matrix A' para %d Workers \n", Dim/qworkers, qworkers);
		printf("|================================================================================|\n");
	}

}

void functionOMP(int nhilos){
   #pragma omp parallel num_threads(nhilos)
   {
      int i = omp_get_thread_num();
      printf("Hello from thread %d\n", i);
   }
}
