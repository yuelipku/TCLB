include conf.mk
ADJOINT=0        # calculate adjoint: 1-on, 0-off
GRAPHICS=1       # GLUT graphics: 1-on, 0-off
GRID3D=0         # use 3D block grid (only avaliable on capability 2.x): 1-on, 0-off
ARCH=sm_11       # CUDA architecture: sm_10 for capability 1.0, sm_13 for capability 1.3 etc.
DOUBLE=0         # precision: 1-double, 0-float


#######################################################################################################################

ifeq '$(strip $(STANDALONE))' '1'
 total : sa
else
total : Rpackage
	R CMD INSTALL CLB_0.00.tar.gz
endif

makefile:src/makefile.main.Rt
	RT -f $< -o $@

thor : Rpackage
	scp CLB_0.00.tar.gz tachion:cuwork

Rpackage : source package/configure
	R CMD build package
	
package/configure:package/configure.ac
	@echo "AUTOCONF     $@"
	@cd package; autoconf

sa : source
	@cd standalone; $(MAKE)

MPI_INCLUDES = /usr/include/mpi/
MPI_LIBS     = /usr/lib/mpich/lib/
MPI_OPT      = -L$(MPI_LIBS) -I$(MPI_INCLUDES) -lmpi #-Xptxas -v
RT = tools/RT
ADMOD = tools/ADmod.R
MAKEHEADERS = tools/makeheaders

SRC=src

ifeq '$(strip $(STANDALONE))' '1'
 DEST=standalone
 ADDITIONALS=makefile model README.md
 SOURCE_CU+=main.cu
 HEADERS_H+=DataLine.h
else
 DEST=package/src
 ADDITIONALS=Makefile.in ../data/LB.RData
endif

SOURCE_CU+=Global.cu Lattice.cu vtkLattice.cu vtkOutput.cu cross.cu cuda.cu LatticeContainer.cu Dynamics.c inter.cpp Solver.cpp pugixml.cpp Geometry.cu def.cpp
SOURCE_R=conf.R Dynamics.R
SOURCE=$(addprefix $(DEST)/,$(SOURCE_CU))
HEADERS_H+=Global.h gpu_anim.h LatticeContainer.h Lattice.h Node.h Region.h vtkLattice.h vtkOutput.h cross.h gl_helper.h Dynamics.h Dynamics.hp types.h Node_types.h Solver.h pugixml.hpp pugiconfig.hpp Geometry.h def.h utils.h
HEADERS=$(addprefix $(DEST)/,$(HEADERS_H))

ALL_FILES=$(SOURCE_CU) $(HEADERS_H) $(ADDITIONALS)
DEST_FILES=$(addprefix $(DEST)/,$(ALL_FILES))

AOUT=main

CC=nvcc
CCTXT=NVCC

RTOPT=

OPT=$(MPI_OPT)

ifdef MODEL
 RTOPT+=MODEL=\"$(strip $(MODEL))\"
endif

ifdef ADJOINT
 RTOPT+=ADJOINT=$(strip $(ADJOINT))
endif

ifdef DOUBLE
 RTOPT+=DOUBLE=$(strip $(DOUBLE))
endif

ifdef GRAPHICS
 RTOPT+=GRAPHICS=$(strip $(GRAPHICS))
endif

ifeq '$(strip $(ADJOINT))' '1'
 OPT+=-D ADJOINT
 SOURCE_CU+=Dynamics_b.c ADTools.cu Dynamics_adj.c
 HEADERS_H+=Dynamics_b.hp Dynamics_b.h types_b.h ADpre_.h Dynamics_adj.hp ADpre__b.h
endif

ifeq '$(strip $(GRAPHICS))' '1'
 OPT+=-D GRAPHICS -lglut
endif

ifeq '$(strip $(DIRECT_MEM))' '1'
 OPT+=-D DIRECT_MEM
endif

ifdef ARCH
 OPT+=-arch $(strip $(ARCH))
endif

ifeq '$(strip $(GRID3D))' '1'
 OPT+=-D GRID_3D
endif

ifeq '$(strip $(DOUBLE))' '1'
 OPT+=-D CALC_DOUBLE_PRECISION
endif

MODELPATH=$(strip $(MODEL))
all:$(AOUT)
	@echo "DONE         $^"

.PRECIOUS:$(DEST_FILES)

source:Dynamics.R conf.R $(DEST_FILES)
	@cd $(DEST); git add $(ALL_FILES)


conf.R:$(SRC)/conf.R
	@cp $< $@

Dynamics.R:$(SRC)/$(MODELPATH)/Dynamics.R
	@cp $< $@
	

package/data/LB.RData: conf.R Dynamics.R
	@echo "MAKEDATA     $@"
	@Rscript tools/makeData.R


$(DEST)/%:$(SRC)/%.Rt Dynamics.R conf.R
	@echo "  RT         $@"
	@$(RT) -q -f $< -o $@ $(RTOPT) || rm $@


$(DEST)/%:$(SRC)/$(MODELPATH)/%.Rt Dynamics.R conf.R
	@echo "  RT         $@ (model)"
	@$(RT) -q -f $< -o $@ $(RTOPT) || rm $@

$(DEST)/%:$(SRC)/$(MODELPATH)/%
	@echo "  CP         $@ (model)"
	@cp $< $@

$(DEST)/%:$(SRC)/%
	@echo "  CP         $@"
	@cp $< $@

%.hpp:%.cpp
	@echo "MAKEHEADERS  $<"
	@$(MAKEHEADERS) $< && mv $@ $@. && sed 's/extern//' $@. > $@
	@rm $@.

%.hp:%.c
	@echo "MAKEHEADERS  $<"
	@cp $< $<.cpp; $(MAKEHEADERS) $<.cpp && sed 's/extern//' $<.hpp > $@
	@rm $<.cpp $<.hpp

clear:
	@echo "  RM         ALL"
	@rm `ls | grep -v -e ^makefile$$ -e .mk$$` 2>/dev/null; true

$(DEST)/Dynamics_b.c $(DEST)/Dynamics_b.h $(DEST)/types_b.h $(DEST)/ADpre_.h $(DEST)/ADpre__b.h : tapenade.run

.INTERMEDIATE : tapenade.run

tapenade.run : $(DEST)/Dynamics.c $(DEST)/ADpre.h $(DEST)/ADpre_b.h $(DEST)/Dynamics.h $(DEST)/Node_types.h $(DEST)/types.h $(DEST)/ADset.sh
	@echo "  TAPENADE   $<"
	@(cd standalone; ../tools/makeAD)
