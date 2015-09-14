"""
A command-line interface script for poseviewconvert.py, which is a module
to for creating or converting pose viewer files.  The module can convert a
'pose viewer' type files into a series of complexes, and convert complexes
into ligand-only, receptor-only, or pose viewer files.


$Revision: 3.1 $
$Date: 2009/09/30 22:35:50 $

Copyright Schrodinger, LLC. All rights reserved.
"""
# Contributors: K. Shawn Watts, Jeff Saunders

# Note to maintainers: The poseviewconvert.py module does the actual
# splitting/merging of the pv file, this script handles the command-line
# parsing and option logic.  

# TODO: Add support for ct-level property copying from the command
# line interface.

# TODO: add -o or -b to control output name/basename

################################################################################
# Globals
################################################################################
_version = "$Revision: 3.1 $"


################################################################################
# Packages 
################################################################################
import schrodinger.application.glide.poseviewconvert as poseviewconvert
import schrodinger.utils.cmdline as cmdline


################################################################################
# Functions 
################################################################################
def get_parser():
    """
    @return:
        a command-line parser configured for this application.
    @rtype:
        cmdline.SingleDashOptionParser 

    """

    # Get a dinger option parser, and populate it 
    script_usage = "\n$SCHRODINGER/run %prog -m <pose_viewer_file> [-M <radius>]... \n$SCHRODINGER/run %prog -p|-l|-r <structure_file> ..."

    script_desc = \
        """A script to create or convert pose viewer files.  The -merge_pv mode takes an input pose viewer file and creates a file with a series of receptor-ligand complexes.  The other modes take a file with one or more receptor-ligand complexes and extracts the receptor and ligand into a pose viewer format maestro file, or extracts the ligands into a file, or extracts the receptors into a file.  The last molecule in the complex is assumed to be the ligand by default."""

    parser = cmdline.SingleDashOptionParser(
        usage=script_usage,
        description=script_desc,
        version_source=_version
    ) 
    parser.add_option(
        "-m",
        "-merge_pv",
        action="store_true",
        dest="merge_pv",
        help='Combine pose viewer receptor and poses into a series of complexes.'
    )
    parser.add_option(
        "-M",
        "-merge_pv_radius",
        type="float",
        dest="merge_pv_radius",
        default=None,
        help='When combining pose viewer receptor and poses into a series of complexes, only include receptor residues within this distance, in angstroms, from the ligand.'
    )
    parser.add_option(
        "-p",
        "-split_pv",
        action="store_true",
        dest="split_pv",
        help='Extract receptor and ligand from complexes, write as pose viewer format file(s).'
    )
    parser.add_option(
        "-l",
        "-split_ligand",
        action="store_true",
        dest="split_ligand",
        help='Extract ligand from complexes, write ligand(s) to output file(s).'
    )
    parser.add_option(
        "-r",
        "-split_receptor",
        action="store_true",
        dest="split_receptor",
        help='Extract receptor from complexes, write receptor(s) to output file(s).'
    )
    parser.add_option(
        "-a",
        "-asl",
        dest="asl",
        help="""Optional ASL expression to identify the ligand molecule from a receptor-ligand complex.  The entire string must be quoted, and internal quotes must be escaped.  e.g. -asl "res.ptype \\'UNK \\'".""" 
    )
    parser.add_option(
        "-q",
        "-quiet",
        dest="quiet",
        action="store_true",
        help="Run tasks without intermediate reporting."
    )
    # ev109052 py_convert.py - add option -asl_file.
    parser.add_option(
        '-asl_file',
        type='string',
        default='',
        dest='asl_file',
        help="Optional file containing the ASL expression.  The expression in the file supersedes -asl expression." 
    )

    # ev113640 return ligands as single file.
    parser.add_option(
        '-s',
        '-separate_files',
        action='store_true',
        dest='separate_files',
        help="When splitting ligands/receptors from complexes put each ligand/receptor into a unique file name (old default mode)." 
    )

    # Assign default values to some args
    parser.set_defaults(
        asl='',
    )
    return parser


################################################################################
# Main 
################################################################################

def main():
    """
    A convenience command-line interface function that takes file names
    from the command line and writes pv format files or splits depending
    on flags.

    """

    parser = get_parser()
    opts, args = parser.parse_args()

    # ev109052 py_convert.py - add option -asl_file
    if opts.asl_file:
        if not poseviewconvert.os.path.isfile(opts.asl_file):
            parser.error('File does not exist: "%s"' % opts.asl_file)
        asl_fh = open(opts.asl_file, 'r')
        asl = " ".join(asl_fh.readlines()).strip()
        if not asl:
            parser.error('File does not contain an ASL expression: "%s"' % opts.asl_file)
        opts.asl = asl

    # Squelch intermediate reporting by turning the log level threshold
    # down.
    if opts.quiet:
        poseviewconvert.logger.setLevel(poseviewconvert.log.logging.CRITICAL)


    # Check for some kind of mode flag 
    split_mode = opts.split_ligand or opts.split_receptor or opts.split_pv
    if not (opts.merge_pv or split_mode):
        parser.error(
            "Missing argument.  Please provide at least one flag: -m|-p|-l|-r"
        )

    # The user interface allows splitting or merging, not both at the same time
    if (opts.merge_pv and split_mode):
        parser.error(
            "Mixed arguments.  Please provide one or more splitter flags (-p|-l|-r) or -m to merge a pv file."
        )

    # Check that filenames exist.
    files = []
    for arg in args:
        if not poseviewconvert.os.path.isfile(arg):
            poseviewconvert.logger.warning("File not found: %s" % arg) 
        else:
            files.append(arg)
            
    # Split or merge all filenames 
    for file in files:
        (root, ext) = poseviewconvert.fileutils.splitext(file)
        if opts.merge_pv:
            if root.endswith('_pv'):
                root = "".join(root[0:-3])
            complex_file_name = "%s_complex%s" % (root, ext)
            radius = opts.merge_pv_radius
            poseviewconvert.merge_pv_file(
                file,
                complex_file_name,
                radius=opts.merge_pv_radius
            ) 

        else:
            if opts.split_ligand:
                lig_file_name = "%s_lig%s" % (root, ext)
                lig_st_writer = poseviewconvert.structure.StructureWriter(lig_file_name)
            if opts.split_receptor:
                recep_file_name = "%s_recep%s" % (root, ext)
                recep_st_writer = poseviewconvert.structure.StructureWriter(recep_file_name)
            # Add to index so it is 1 based
            for index, st in enumerate(poseviewconvert.structure.StructureReader(file)): 
                cmplx = None

                try:
                    cmplx = poseviewconvert.Complex(st, ligand_asl=opts.asl)
                    # ev92027 It will be good to conserve the Glide/IFD
                    # score and energy fields from the pv file to the
                    # output file.
                    cmplx.ligand.property.update(st.property)
                except Exception, e:
                    msg = "Failed to create a complex from %s.\nPlease check that the input structure file is consistent with specified script option(s)." % str(st)
                    print msg
                    print str(e)
                if opts.split_ligand and cmplx:
                    if opts.separate_files:
                        lig_file_name = "%s_%d_lig%s" % (root, index + 1, ext)
                        cmplx.writeLigand(lig_file_name)
                    else:
                        lig_st_writer.append(cmplx.ligand)

                if opts.split_receptor and cmplx:
                    if opts.separate_files:
                        recep_file_name = "%s_%d_recep%s" % (
                            root,
                            index + 1,
                            ext
                        )
                        cmplx.writeReceptor(recep_file_name)
                    else:
                        recep_st_writer.append(cmplx.receptor)

                if opts.split_pv and cmplx:
                    pv_file_name = "%s_%d_pv%s" % (root, index + 1, ext)
                    try:
                        cmplx.writePv(pv_file_name)
                    except:
                        msg = 'Failed to write complex to file: %s' % (
                            pv_file_name
                        )
                        print msg
                        poseviewconvert.sys.exit(1)

            if opts.split_ligand and not opts.separate_files:
                lig_st_writer.close()
            if opts.split_receptor and not opts.separate_files:
                recep_st_writer.close()



if __name__ == '__main__':
    main()

# EOF
