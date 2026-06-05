# =============================================================================
# Makefile for rest-db-api
#
# Builds the restdblib library (com/fourjs/restdblib) and the example REST
# service programs (bin/), mirroring the build rules in GeneroRest.4pw.
#
# Prerequisite: put the Genero toolchain on PATH first, e.g.
#     eval "$(fglpkg env)"
#
# Common targets:
#     make            # build everything (library + services)
#     make lib        # build only the restdblib library
#     make services   # build only the example services
#     make clean      # remove all compiled .42m artifacts
#     make run-northwind PORT=8090   # build then run the Northwind service
# =============================================================================

PROJECT_DIR := $(CURDIR)
SRC_DIR     := src
PKG_DIR     := com/fourjs/restdblib
BIN_DIR     := bin

FGLCOMP      := fglcomp
FGLRUN       := fglrun
FGLCOMPFLAGS := -M

# The library modules use PACKAGE com.fourjs.restdblib and import each other;
# the service programs import the library and the in-memory *Create modules.
# Both resolutions go through FGLLDPATH, which must include the project root
# (for com/fourjs/restdblib/*.42m) and bin/ (for the *Create modules).
export FGLLDPATH := $(PROJECT_DIR):$(PROJECT_DIR)/$(BIN_DIR):$(FGLLDPATH)

# ---- restdblib library ------------------------------------------------------
LIB_MODULES := UserScopes JsonParser SQLHelper WriteDelegates ServiceHelper
LIB_OBJ     := $(addprefix $(PKG_DIR)/,$(addsuffix .42m,$(LIB_MODULES)))

# ---- example service programs ----------------------------------------------
SERVICES    := NorthwindService CustdemoService OfficestoreService
# Companion modules linked into a service program (DB create scripts, write
# delegates) that must be compiled into bin/ before the service that imports them.
EXTRA_MODS  := CustdemoCreate OfficestoreCreate NorthwindWrites
SERVICE_OBJ := $(addprefix $(BIN_DIR)/,$(addsuffix .42m,$(SERVICES) $(EXTRA_MODS)))

PORT ?= 8090

.PHONY: all lib services clean run-northwind run-custdemo run-officestore

all: lib services

lib: $(LIB_OBJ)

services: $(SERVICE_OBJ)

# Package modules: output root is the project dir, so a module declaring
# PACKAGE com.fourjs.restdblib lands its .42m under com/fourjs/restdblib/.
$(PKG_DIR)/%.42m: $(SRC_DIR)/%.4gl
	$(FGLCOMP) $(FGLCOMPFLAGS) -o . $<

# ServiceHelper imports the other library modules, so they must exist first
# (FGLLDPATH resolves them from the package tree).
$(PKG_DIR)/ServiceHelper.42m: $(PKG_DIR)/SQLHelper.42m $(PKG_DIR)/UserScopes.42m $(PKG_DIR)/JsonParser.42m $(PKG_DIR)/WriteDelegates.42m

# Service / Create programs: plain modules, output goes into bin/. They depend
# on the library (order-only: built first, but a lib rebuild alone need not
# relink every service).
$(BIN_DIR)/%.42m: $(SRC_DIR)/%.4gl | $(LIB_OBJ)
	$(FGLCOMP) $(FGLCOMPFLAGS) -o $(BIN_DIR) $<

# These services IMPORT FGL their *Create companion module, which must be
# compiled into bin/ first so fglcomp can resolve the import.
$(BIN_DIR)/CustdemoService.42m:    $(BIN_DIR)/CustdemoCreate.42m
$(BIN_DIR)/OfficestoreService.42m: $(BIN_DIR)/OfficestoreCreate.42m
$(BIN_DIR)/NorthwindService.42m:   $(BIN_DIR)/NorthwindWrites.42m

# ---- run helpers ------------------------------------------------------------
# A UTF-8 locale is required: without it the engine returns serialization
# error -32 on multibyte data. PORT must be a free TCP port to bind to.
run-northwind: all
	cd $(BIN_DIR) && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 FGLAPPSERVER=$(PORT) \
		$(FGLRUN) NorthwindService.42m --debug

run-custdemo: all
	cd $(BIN_DIR) && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 FGLAPPSERVER=$(PORT) \
		$(FGLRUN) CustdemoService.42m --debug

run-officestore: all
	cd $(BIN_DIR) && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 FGLAPPSERVER=$(PORT) \
		$(FGLRUN) OfficestoreService.42m --debug

clean:
	rm -f $(LIB_OBJ) $(SERVICE_OBJ) $(SRC_DIR)/*.42m
