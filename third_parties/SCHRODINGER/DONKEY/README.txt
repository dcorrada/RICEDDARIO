DONKEY (DO Not use KnimE Yet) is a script to perform a full docking workflow, using the software tool offered from the Schrodinger suite (the current version has been tested on Schrodinger suite 2014).


## REQUIREMENTS

* [Schrodinger suite](http://www.schrodinger.com/)
* [R v2.10.0](http://www.r-project.org/) or higher

DONKEY also requires the following Perl libraries:

* [Statistics::Descriptive](http://search.cpan.org/~shlomif/Statistics-Descriptive-3.0607/lib/Statistics/Descriptive.pm)
* [Text::CSV](http://search.cpan.org/~makamaka/Text-CSV-1.32/lib/Text/CSV.pm)


## INPUT FILES

DONKEY needs a list of input files, an example of them could be retrieved from the folder _"DONKEY/input_files/"_. The following files must be present in the current path where the script will launched:

1. A compressed mae file (**maegz**) containing the library of ligands to be docked. DONKEY does not check if the topology of the molecules is correct, so you need to build them properly (also with hydrogens). It is strongly suggested to define unique `title` and `entry_name` properties for each entry of the mae file.

2. One (ore more) **pdb** file containing the receptor molecule. DONKEY is aimed to perform an ensemble docking strategy, so several pdb of the same receptor can be submitted at once (e.g. different snapshots deriving from an MD simulation). The different pdb files must share the same chain id and residue numbering.

3. A **mae** file containing a reference complex structure (receptor + ligand), it could come from an experimentally resolved structure.


### The configuration file

The detailed configuration of the docking protocol is defined in a configuration file (ie specific setting fitting, grid size, minimization, etc.). It can be specified using the `-script` option (otherwise, a default configuration file will be created and stored in your homedir as _".DONKEYrc"_). 

The different sections of the DONKEY configuration file are delimited by the tags `&section_name` and `&end`. The syntax adopted for each section varies, according to the specific syntax used by the different tool of the Schrodinger Suite.

Some specific keywords are tagged as "_[reserved]_". The content of such keywords is ignored, since these keywords are automatically parsed by the DONKEY script.


## THE DOCKING PROTOCOL

The DONKEY workflow is characterized by several sequential steps of calculation. For each step  a dedicated folder will be created: outputs, logs and intermediate files are stored there.

In the following, the settings of the default configuration file will be explained.


### 1. Preparing models

The structure of the receptor molecule (**pdb** input file) is checked through the [Protein Preparation Wizard](http://www.schrodinger.com/Protein-Preparation-Wizard/) tool and hydrogens are replaced accordingly to the best predicted protonation state, by means of the [PROPKA](https://github.com/jensengroup/propka-3.1) method.

Then the receptor molecule is fitted against the reference complex (**mae** input file). The `&fit` section of the configuration file defines the options passed to Protein Structure Alignment (SKA) algorithm:

    &fit
    -cutoff 7.0
    -color
    -jobname SKA    [reserved]
    &end

From the reference complex, the CA atoms of those residues that fall within 7.0 A from the ligand are selected. Then, the SKA algorithm searches this pattern of atoms along the receptor molecule. Once defined the subset of atom pairs between the receptor molecule and the reference complex, the former structure is superposed.

Finally, the atomic coordinates of the ligand molecule are transferred from the reference complex to the receptor structure.


### 2. Pre-docking minimization

The receptor molecule is subjected to a preliminar structure minimization process, in order to relax the overall structure and to remove minor steric clashes. The minimization is preformed by the [MacroModel](http://www.schrodinger.com/MacroModel/) module.

In this step a run input file is written, according to the specifications defined in the configuration file:

    &mini
    INPUT_STRUCTURE_FILE infile.mae         [reserved]
    OUTPUT_STRUCTURE_FILE outfile.maegz     [reserved]
    JOB_TYPE MINIMIZATION                   [reserved]
    USE_SUBSTRUCTURE_FILE True              [reserved]
    FORCE_FIELD OPLS_2005
    SOLVENT Water
    MINI_METHOD TNCG
    MAXIMUM_ITERATION 1500
    CONVERGE_ON Gradient
    &end

The keyword `USE_SUBSTRUCTURE_FILE` is reserved. During minimization steps, the script requires the presence of a substructure (sbc) file. The details of the substructure file are listed as follows:

    &sbc
     ASL1       0 ( ( fillres within 5 ( mol.entry 2 ) ) AND NOT ( backbone ) )
     ASL2 200.000 ( ( fillres within 5 ( mol.entry 2 ) ) AND ( backbone ) )
     ASL2 500.000 ( ( fillres within 7 ( mol.entry 2 ) ) AND NOT ( fillres within 5 ( mol.entry 2 ) ) )
     ASL2  -1.000 ( ( mol.entry 1 ) AND NOT ( fillres within 7 ( mol.entry 2 ) ) )
    &end

By default, a set of nested shells is defined in order to render progressively more constrained the external regions of the receptor. On the other hand, the putative binding site is less constrained and subjected to more relevant structural rearrangements.

**NOTE:** although a sbc file is required, one can perform a fully unrestrained minimization defining only a single shell:

    &sbc
     ASL1       0 ( all )
    &end


### 3. Grid setting

The grid box is built by the Schrodinger module [Glide](http://www.schrodinger.com/Glide/). The shape and sizes are defined in the configuration file, using the following syntax:

    &grid
    INNERBOX 10, 10, 10
    ACTXRANGE 22.0
    ACTYRANGE 22.0
    ACTZRANGE 22.0
    GRID_CENTER 3.0, -4.0, 1.1    [reserved]
    OUTERBOX 22.0, 22.0, 22.0
    GRIDFILE grid.zip             [reserved]
    RECEP_FILE receptor.maegz     [reserved]
    &end

The keyword `GRID_CENTER` is reserved. The atomic coordinates of the ligand (transferred into the receptor during the step 1) are used by DONKEY to define the center of the grid box (ie the centroid from the atomic coordinates).

After this step the atomic coordinates of the ligand previously introduced are removed.


### 4. Docking

The effective docking job is performed using the [Glide](http://www.schrodinger.com/Glide/) module.

    &glide
    POSES_PER_LIG 1
    POSTDOCK NO
    WRITE_RES_INTERACTION YES
    WRITE_XP_DESC YES
    MAXREF 800
    RINGCONFCUT 2.500000
    PRECISION XP
    GRIDFILE grid.zip       [reserved]
    LIGANDFILE ligs.maegz   [reserved]
    &end

As well, `GRIDFILE` and `LIGANDFILE` are reserved keywords. The former specify the grid box generated in the previous step, the latter specify the library of ligands to be docked (**maegz** input file). The approach proposed by default is based on a GlideXP run, where only the best ranked poses  will be selected.


### 5. Post-docking minimization

The pose viewer file produced from the docking is converted in order to get a complex structure for each pose proposed. Then, the complexes are structurally minimized.

The minimization procedure is analogous to the one followed in the step 2. In this specific step the run input file is written in com format:

    &post
    infile.mae      [reserved]
    outfile.maegz   [reserved]
     DEBG       0      0      0      0     0.0000     0.0000     0.0000     0.0000
     SOLV       3      1      0      0     0.0000     0.0000     0.0000     0.0000
     BDCO       0      0      0      0     0.0000 99999.0000     0.0000     0.0000
     FFLD      14      1      0      0     1.0000     0.0000     1.0000     0.0000
     BGIN       0      0      0      0     0.0000     0.0000     0.0000     0.0000
     SUBS       0      0      0      0     0.0000     0.0000     0.0000     0.0000
     READ       0      0      0      0     0.0000     0.0000     0.0000     0.0000
     CONV       2      0      0      0     0.0500     0.0000     0.0000     0.0000
     MINI       9      0   1500      0     0.0000     0.0010     0.0000     0.0000
     END        0      0      0      0     0.0000     0.0000     0.0000     0.0000
    &end

This specific syntax (instead of the in format adopted in step 2) is less user friendly, but it allows to enforce the planarity of aromatic rings, recommended for complexes where ligands show extended coniugated aromatic systems.

The same substructure defined in the step 2 (ie the sbc file) is herein adopted.


### 6. Rescoring the poses

The complexes are rescored on the basis of the dG bind calculated by the means of the MM-GBSA approach, using the [Prime](http://www.schrodinger.com/Prime/) module:

    &prime
    STRUCT_FILE  complex_pv.maegz   [reserved]
    JOB_TYPE     REAL_MIN
    OUT_TYPE     COMPLEX
    RFLEXDIST    7
    RFLEXGROUP   side
    RCONS        ((fillres within 7 (atom.i_psp_Prime_MMGBSA_Ligand 1)) AND NOT (fillres within 5 (atom.i_psp_Prime_MMGBSA_Ligand 1)))
    STR_CONS     120
    PRIME_OPT    MINIM_NITER         = 50
    PRIME_OPT    MINIM_NSTEP         = 200
    PRIME_OPT    MINIM_RMSG          = 0.01
    PRIME_OPT    MINIM_METHOD        = tn
    PRIME_OPT    PLANARITY_RESTRAINT = 10
    &end

By default, a preliminar structural refinement is expected according to the [VSGB 2.0](http://www.ncbi.nlm.nih.gov/pubmed/21905107) model. Only the Truncated Newton minimization approach is used, and a nested shell strategy is adopted.


### 7. Energy decomposition analysis

The free energy of binding calculated from each complex is decomposed in per-residue energy contribution. Each energy contribution is furtherly decomposed in solvation, electrostatic and VdW terms, respectively.

    &deco
    shell 7.01
    ratio 0.75
    &end

The keywords specified in the configuration file define the subset of residues for which the results of decomposition analysis is performed.

By default only the residues that in the 75% of the poses (`ratio`) fall within 7 A from the ligand molecule (`shell`) are considered.
