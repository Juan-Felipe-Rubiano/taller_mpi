######################################################
# Autores: Juan Felipe Rubiano, Salomón Ávila, Sara Cárdenas, Cristian Ortiz, Juan C. 
# Uso:
#        - make				compila los 6 programas
#        - make	verificar	compila y prueba que los resultados sean iguales
#        - make	clean		borrar bin/
#
#####################################################
GCC= mpicc
FLAGS = -O3 -Wall -Wextra -fopenmp -pthread -lm
MODULO= functions
BIN= bin/
SRC= src/

PROGRAMAS=  mxmMPI_FxC mxmMPI_FxT \
			mxmMPIompFxC mxmMPIompFxT \
			mxmMPIpthFxC mxmMPIpthFxT
all: ${PROGRAMAS}

mxmMPI_FxC:
	$(GCC) $(FLAGS) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPI_FxT:
	$(GCC) $(FLAGS) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPIompFxC:
	$(GCC) $(FLAGS) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPIompFxT:
	$(GCC) $(FLAGS) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPIpthFxC:
	$(GCC) $(FLAGS) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

mxmMPIpthFxT:
	$(GCC) $(FLAGS) $(SRC)$@.c $(SRC)$(MODULO).c -o $(BIN)$@ 

verificar: all
	./scripts/verificar.sh

clean:
	$(RM) $(BIN)*

.PHONY: all verificar clean