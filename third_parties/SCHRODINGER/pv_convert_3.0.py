"""
A wrapper script for poseviewconvert.py, a module to create or convert
pose viewer files.  The module can convert a 'pose viewer' type files
into a series of complexes, and convert complexes into ligand-only,
receptor-only, or pose viewer files.


$Revision: 3.0 $
$Date: 2009/09/30 22:35:50 $

Copyright Schrodinger, LLC. All rights reserved.
"""
# Contributors: K. Shawn Watts, Jeff Saunders

# TODO: Add support for ct-level property copying from the command
# line interface.

# TODO: add -o or -b to control output name/basename

################################################################################
# Globals
################################################################################
_version = "$Revision: 3.0 $"


################################################################################
# Packages 
################################################################################
import schrodinger.application.glide.poseviewconvert as poseviewconvert


################################################################################
# Main 
################################################################################

# ev109052 py_convert.py - add option -asl_file
# To implement this request I made a local, modified version of the
# poseviewconvert parser.  The new feature will be pushed back into the
# poseviewconvert.py module (trunk) after the branch.  
#
# Convenience command line interface that takes file names from the
# command line and writes pv format files or splits depending on flags.
#if __name__ == '__main__':
#    poseviewconvert.main(version=_version)

def main(version=None):
    """
    A convenience command-line interface function that takes file names from
    the command line and writes pv format files or splits depending on flags.
    If a version string isn't passed in, this module's '_version' string is
    used by the parser.
    """
    parser = poseviewconvert.get_parser()

    # ev109052 py_convert.py - add option -asl_file
    parser.add_option(
        '-asl_file',
        type='string',
        default='',
        dest='asl_file',
        help="Optional file containing the ASL expression.  The expression in the file supersedes -asl expression." 
    )

    if version:
        # Override the parser so it prints a different version than that
        # of this module; e.g., the version of the calling script.
        parser.version = poseviewconvert.cmdline.version_string(version)
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
            poseviewconvert.merge_pv_file(file, complex_file_name, radius=opts.merge_pv_radius) 

        else:
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
                    lig_file_name = "%s_%d_lig%s" % (root, index + 1, ext)
                    cmplx.writeLigand(lig_file_name)

                if opts.split_receptor and cmplx:
                    recep_file_name = "%s_%d_recep%s" % (root, index + 1, ext)
                    cmplx.writeReceptor(recep_file_name)

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



if __name__ == '__main__':
    main(version=_version)

# EOF
